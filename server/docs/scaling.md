# Sarthi — Scaling & Capacity Design

> **Audience:** backend developers joining the project.
> **Purpose:** explain *why* Sarthi is "just Go + PostgreSQL + Flutter on (basically)
> one server, no Redis" and where the real limits are. Read this before proposing
> a distributed cache, a message broker, or a sharded database. The math says we
> don't need them yet — for the whole of India.

## TL;DR

For India-scale ride-hailing, the only part of the system under real pressure is
**high-frequency GPS ingestion from drivers**. Everything else (user app traffic,
ride creation) is comfortably handled by a single well-written Go process. So the
architecture is deliberately boring:

- **Go** for the backend (REST + WebSockets).
- **PostgreSQL** as the source of truth.
- **In-memory state** (`internal/memstore`) for hot, rebuildable data.
- **Uber H3** (`pkg/geo`) for geospatial bucketing instead of Redis `GEORADIUS`.
- **No Redis, no Kafka, no service mesh.** Not "not yet" — *not needed at this scale.*

The sections below show the back-of-the-envelope numbers that justify this.

---

## Market sizing (the denominator)

| Quantity                         | Estimate          |
| -------------------------------- | ----------------- |
| Cars in India (total addressable)| ~5 crore (50 M)   |
| Peak app users (vs. competitors) | ~1 million        |
| Daily *riding* users (take a trip)| ~1 lakh (100 k)  |
| Max concurrent drivers online    | ~20 k             |

These are generous upper bounds — "if we became the #1 player in India." We size
to them so we don't have to re-architect on the way up.

---

## Workload 1 — App traffic (browsing users)

**Assume the worst case: all 1 M users open the app on the same day.**

- 1,000,000 sessions / 86,400 s ≈ **~12 sessions/sec average**.
- Allowing for peak-hour bursting (commute windows), budget **~30 req/sec**.
- A REST handler that does its work in **~30 ms** (an eternity for in-memory +
  indexed Postgres reads) means one core clears ~33 req/sec; the process clears
  far more across cores.

**Conclusion:** a single Go instance handles all browsing traffic with headroom.
This is not the bottleneck. Don't optimize it prematurely.

---

## Workload 2 — Ride creation (matchmaking requests)

**Assume 1 lakh rides booked per day.**

- 100,000 rides / 86,400 s ≈ **~1.2 rides/sec average**.
- With peaking, budget **~3 rides/sec**.
- Even at **~300 ms per match** (find nearby drivers via H3, offer, confirm),
  3/sec is trivially served by one process.

**Conclusion:** ride creation is also not the bottleneck. The matchmaking *latency*
matters for UX, but the *throughput* is tiny. H3 bucketing keeps the "find nearby
drivers" step touching only the relevant cells, so it stays cheap.

---

## Workload 3 — GPS ingestion (the ONLY real bottleneck)

This is where the volume is, and the one number worth obsessing over.

**Assume 20 k drivers online, each reporting GPS every 5 seconds.**

- 20,000 / 5 = **4,000 coordinate updates/sec**.

### Raw data volume

At a naive ~8 bytes per coordinate sample (see "Encoding" below):

| Window | Volume     |
| ------ | ---------- |
| /sec   | ~32 KB/s   |
| /hour  | **~115 MB**|
| /day   | **~2.8 GB**|

That is the entire GPS firehose for all of India, per day, in a few GB. It fits.

### Design decisions for GPS

1. **WebSockets, not REST, for GPS.** 4,000 updates/sec over fresh HTTP requests
   would waste handshakes/headers. Drivers hold a persistent WS connection and
   stream location frames. (REST stays for CRUD/auth.)

2. **Live location lives in memory, not the DB.** Current driver positions go into
   `internal/memstore` (RWMutex-guarded maps), bucketed by **H3 cell** via
   `pkg/geo`. "Find nearby drivers" reads only the relevant cells — this is the
   Redis-`GEORADIUS` replacement. memstore is hot, **rebuildable** state: if the
   process restarts, drivers re-report within 5 s and the index refills.

3. **Do NOT write every GPS sample to Postgres synchronously.** 4,000 INSERTs/sec
   of disposable breadcrumbs would be the one thing that *could* tip us into
   needing more infrastructure — and it buys nothing, because live position is a
   memstore concern. Instead:
   - **Batch**: accumulate samples and flush periodically (e.g. `COPY` every few
     seconds) only for trails we actually need to persist (e.g. the active ride's
     path for receipts/disputes).
   - **Compress / delta-encode**: store deltas from the previous fix, not absolute
     lat/lng each time, to approach the ~8-bytes-per-sample figure above.
   - **Drop what's disposable**: an idle driver's breadcrumb between rides does not
     need to survive a restart. Persist ride trails, not the firehose.

**Conclusion:** the bottleneck is I/O volume, and it's defused by keeping live
state in memory (H3 + memstore) and treating Postgres as a *batched, selective*
sink — never the per-sample write path.

---

## Why no Redis (or Kafka, etc.)

Redis would normally show up for two jobs in a ride-hailing backend:

1. **Geospatial radius queries** (`GEORADIUS`) → replaced by **H3 cell bucketing**
   in `pkg/geo` + `memstore`. Same idea (spatial index in memory), one fewer
   moving part, and the index lives in the same process as the matchmaker.
2. **Shared hot state across instances** → we don't have multiple instances at this
   scale. One Go process with in-memory maps *is* the cache. No network hop, no
   serialization, no cache-invalidation class of bugs.

Adding Redis here would add an operational dependency and a failure mode to solve
a problem we don't have. The numbers above show a single server clears every
workload with headroom. **The cost of distributed infrastructure is justified by
scale we have not reached** — so we don't pay it.

This is a *deliberate* constraint, encoded in `CLAUDE.md` ("No Redis"). If a future
developer believes we've outgrown it, the bar is: show the workload number that no
longer fits a single process, not the discomfort of in-memory state.

---

## Where this design *does* break (future signposts)

Be honest about the edges so the next person knows the real triggers:

- **Vertical limit on one process.** memstore is bounded by one machine's RAM and
  the GC. 20 k drivers is fine; if "concurrent drivers" grows 10×, revisit.
- **Single point of failure.** One process means a restart drops live WS
  connections. Mitigation today: memstore is rebuildable (drivers re-report in
  ~5 s) and Postgres holds everything durable. If we need HA before we need
  horizontal *scale*, the first step is a warm standby, **not** a distributed
  cache.
- **The day memstore must be shared across instances** is the day to reconsider
  H3-in-Redis or a purpose-built in-memory grid — and only then.

## Architectural ground rules this implies

(See `CLAUDE.md` for the full list; these are the load-bearing ones.)

- PostgreSQL is the **source of truth**; memstore is hot, rebuildable state — never
  the system of record.
- H3 stays inside `pkg/geo`; other packages use the `geo.Cell` alias.
- Money is integer minor units (cents), never floats.
- Layering talks inward only:
  `domain` ← `memstore`/`repository` ← `service` ← `api`/`websocket`.
