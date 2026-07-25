/// Shared scheduling policy for trip start times.
library;

/// Booking times are offered in quarter-hour steps: a trip can start at
/// :00, :15, :30, or :45 — never in between. The time picker builds its slot
/// list from this, and [snapToQuarterHour] realigns any drifting value.
const int scheduleIntervalMinutes = 15;

/// [when] snapped to the nearest quarter hour (seconds/millis dropped).
/// Rounding at :52+ carries into the next hour (and day at 23:53+).
DateTime snapToQuarterHour(DateTime when) {
  final steps = (when.minute / scheduleIntervalMinutes).round();
  return DateTime(
    when.year,
    when.month,
    when.day,
    when.hour,
  ).add(Duration(minutes: steps * scheduleIntervalMinutes));
}

/// The pre-filled start time for a new booking: one hour from [now], rounded to
/// the nearest quarter hour (seconds/millis dropped). A sensible "soon, but not
/// right now" default the customer can nudge. [now] is a seam for tests.
DateTime defaultScheduledAt([DateTime? now]) =>
    snapToQuarterHour((now ?? DateTime.now()).add(const Duration(hours: 1)));

/// Departures up to this far ahead count as "leaving about now". Current
/// traffic is a fine drive-time estimate for them, so the cheap Ola directions
/// call is used — the costlier time-aware Google Routes call is reserved for
/// departures beyond this window.
const Duration nearTermDepartureWindow = Duration(hours: 2);

/// Whether [when] falls inside [nearTermDepartureWindow] from [now] (a seam
/// for tests, defaulting to the wall clock).
bool isNearTermDeparture(DateTime when, [DateTime? now]) =>
    !when.isAfter((now ?? DateTime.now()).add(nearTermDepartureWindow));
