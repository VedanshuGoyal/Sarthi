#!/usr/bin/env bash
#
# Native (non-Docker) VPS setup for the Sarthi backend on Ubuntu 24.04.
#
# Brings a fresh box to a running, TLS-terminated API:
#
#   Caddy (:80/:443, Let's Encrypt)  ->  sarthi-server (:8080)  ->  PostgreSQL 17
#
# Every phase is idempotent: re-running is safe, and is the intended way to
# apply a change (edit server/.env.prod, re-run, done).
#
# Usage:
#   sudo ./setup-vps.sh                    # run every phase, in order
#   sudo ./setup-vps.sh build service      # run only the named phases
#   sudo SKIP_DNS_CHECK=1 ./setup-vps.sh   # skip the pre-flight DNS check
#
# Phases: go postgres database migrations build service caddy firewall verify
#
# Prerequisites:
#   - Ubuntu 24.04, run as root
#   - server/.env.prod filled in (see .env.prod.example) — never commit it
#   - a DNS A record for $DOMAIN pointing at this box's public IP

set -euo pipefail

# --- Pinned versions ---------------------------------------------------------
# Go must satisfy the `go` directive in go.mod; Ubuntu's apt ships an older one,
# so it is installed from the official tarball instead.
GO_VERSION="1.26.5"
# Matches the postgres:17 image pinned in docker-compose.prod.yml, so the two
# deployment paths do not drift apart.
PG_VERSION="17"

# --- Paths -------------------------------------------------------------------
DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(dirname "$DEPLOY_DIR")"
ENV_PROD="$SERVER_DIR/.env.prod"

INSTALL_DIR="/opt/sarthi/bin"
BINARY="$INSTALL_DIR/sarthi-server"
ETC_DIR="/etc/sarthi"
SERVER_ENV="$ETC_DIR/sarthi.env"   # read by sarthi.service
CADDY_ENV="$ETC_DIR/caddy.env"     # read by caddy.service (supplies $DOMAIN)
SERVICE_USER="sarthi"
DB_NAME="sarthi"
DB_USER="sarthi"

# --- Helpers -----------------------------------------------------------------
log()  { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '\033[1;33m    warning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\n\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# --- Pre-flight --------------------------------------------------------------
preflight() {
	[[ $EUID -eq 0 ]] || die "must run as root (try: sudo $0)"
	[[ -f "$ENV_PROD" ]] || die "missing $ENV_PROD — copy .env.prod.example and fill it in"

	# Load secrets. `set -a` exports everything the file defines.
	set -a; # shellcheck disable=SC1090
	. "$ENV_PROD"; set +a

	local missing=()
	for var in DOMAIN POSTGRES_PASSWORD FAST2SMS_API_KEY FAST2SMS_OTP_ID; do
		[[ -n "${!var:-}" ]] || missing+=("$var")
	done
	[[ ${#missing[@]} -eq 0 ]] || die "$ENV_PROD is missing values for: ${missing[*]}"

	# Caddy cannot get a certificate unless $DOMAIN already resolves here, and
	# each failed ACME attempt counts against a Let's Encrypt rate limit
	# (5 failed validations per hostname per hour). Fail early instead.
	if [[ -z "${SKIP_DNS_CHECK:-}" ]]; then
		local public_ip resolved
		public_ip="$(curl -fsS -4 https://ifconfig.me 2>/dev/null || true)"
		resolved="$(getent ahostsv4 "$DOMAIN" 2>/dev/null | awk 'NR==1{print $1}')"

		[[ -n "$resolved" ]] || die "$DOMAIN does not resolve. Create an A record -> $public_ip, wait for propagation, then re-run."
		if [[ -n "$public_ip" && "$resolved" != "$public_ip" ]]; then
			die "$DOMAIN resolves to $resolved but this box is $public_ip.
       Fix the A record, or re-run with SKIP_DNS_CHECK=1 if you are behind a proxy."
		fi
		info "DNS OK: $DOMAIN -> $resolved"
	fi
}

# --- Phases ------------------------------------------------------------------

phase_go() {
	log "Installing Go $GO_VERSION"
	if [[ "$(/usr/local/go/bin/go version 2>/dev/null || true)" == *"go$GO_VERSION "* ]]; then
		info "already installed"
	else
		local tarball="go${GO_VERSION}.linux-amd64.tar.gz"
		curl -fsSLo "/tmp/$tarball" "https://go.dev/dl/$tarball"
		rm -rf /usr/local/go
		tar -C /usr/local -xzf "/tmp/$tarball"
		rm -f "/tmp/$tarball"
		info "$(/usr/local/go/bin/go version)"
	fi
	# Make `go` available in future login shells. Single-quoted on purpose:
	# $PATH must expand at login, not now.
	# shellcheck disable=SC2016
	echo 'export PATH=$PATH:/usr/local/go/bin' > /etc/profile.d/go.sh
	export PATH="$PATH:/usr/local/go/bin"
}

phase_postgres() {
	log "Installing PostgreSQL $PG_VERSION"
	if [[ -x "/usr/lib/postgresql/$PG_VERSION/bin/postgres" ]]; then
		info "already installed"
	else
		# Ubuntu 24.04 ships PG 16, so pull PG 17 from the PGDG repo.
		install -d /usr/share/postgresql-common/pgdg
		curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
			-o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc
		# shellcheck disable=SC1091
		. /etc/os-release
		echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $VERSION_CODENAME-pgdg main" \
			> /etc/apt/sources.list.d/pgdg.list
		apt-get -qq update
		DEBIAN_FRONTEND=noninteractive apt-get -y -qq install "postgresql-$PG_VERSION"
	fi
	systemctl enable --now postgresql
	info "$(psql --version)"
}

phase_database() {
	log "Provisioning the $DB_NAME role and database"
	# Piped over stdin, never argv — the password must not appear in `ps`.
	# ALTER on the else-branch keeps a re-run in sync with a rotated password.
	psql_su <<-SQL
		DO \$\$
		BEGIN
		    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$DB_USER') THEN
		        CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$POSTGRES_PASSWORD';
		    ELSE
		        ALTER ROLE $DB_USER WITH LOGIN PASSWORD '$POSTGRES_PASSWORD';
		    END IF;
		END
		\$\$;
	SQL

	# CREATE DATABASE cannot run inside a DO block, so guard it from the shell.
	if [[ "$(psql_su_query "SELECT 1 FROM pg_database WHERE datname = '$DB_NAME'")" == "1" ]]; then
		info "database $DB_NAME already exists"
	else
		psql_su <<-SQL
			CREATE DATABASE $DB_NAME OWNER $DB_USER;
		SQL
		info "created database $DB_NAME"
	fi

	# Prove the exact DSN the server will use actually authenticates.
	PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -U "$DB_USER" -d "$DB_NAME" \
		-tAc "SELECT 1" >/dev/null || die "cannot connect as $DB_USER over TCP — check pg_hba.conf"
	info "TCP auth as $DB_USER OK"
}

phase_migrations() {
	log "Applying migrations"
	# Every migration uses CREATE TABLE/INDEX IF NOT EXISTS, so replaying the
	# full set is safe and no version-tracking table is needed. If that stops
	# being true, switch to golang-migrate (see deploy/README.md).
	local f
	for f in "$SERVER_DIR"/migrations/*.up.sql; do
		info "applying $(basename "$f")"
		PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -U "$DB_USER" -d "$DB_NAME" \
			-v ON_ERROR_STOP=1 -q -f "$f" || die "migration failed: $f"
	done
	info "tables: $(psql_app_query "SELECT string_agg(tablename, ', ' ORDER BY tablename) FROM pg_tables WHERE schemaname = 'public'")"
}

phase_build() {
	log "Building the server binary"
	install -d "$INSTALL_DIR"
	( cd "$SERVER_DIR" && "/usr/local/go/bin/go" build -o "$BINARY" ./cmd/server ) \
		|| die "go build failed"
	info "$BINARY ($(du -h "$BINARY" | cut -f1))"
}

phase_service() {
	log "Installing the sarthi systemd service"
	id "$SERVICE_USER" &>/dev/null || \
		useradd --system --no-create-home --shell /usr/sbin/nologin "$SERVICE_USER"

	install -d -m 755 "$ETC_DIR"
	# Root-owned 0600: systemd reads EnvironmentFile as root before dropping
	# privileges, so the service user never needs to read it.
	umask 077
	cat > "$SERVER_ENV" <<-EOF
		DATABASE_URL=postgres://$DB_USER:$POSTGRES_PASSWORD@localhost:5432/$DB_NAME?sslmode=disable
		ADDR=:8080
		FAST2SMS_API_KEY=$FAST2SMS_API_KEY
		FAST2SMS_OTP_ID=$FAST2SMS_OTP_ID
	EOF
	umask 022
	chown root:root "$SERVER_ENV"; chmod 600 "$SERVER_ENV"

	install -m 644 "$DEPLOY_DIR/sarthi.service" /etc/systemd/system/sarthi.service
	systemctl daemon-reload
	systemctl enable sarthi.service >/dev/null
	systemctl restart sarthi.service

	sleep 2
	systemctl is-active --quiet sarthi.service \
		|| die "sarthi failed to start — see: journalctl -u sarthi -n 50"
	info "sarthi is active on :8080"
}

phase_caddy() {
	log "Installing and configuring Caddy"
	if ! command -v caddy &>/dev/null; then
		DEBIAN_FRONTEND=noninteractive apt-get -y -qq install \
			debian-keyring debian-archive-keyring apt-transport-https curl
		curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/gpg.key \
			| gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
		curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt \
			> /etc/apt/sources.list.d/caddy-stable.list
		apt-get -qq update
		DEBIAN_FRONTEND=noninteractive apt-get -y -qq install caddy
	fi

	install -m 644 "$DEPLOY_DIR/Caddyfile" /etc/caddy/Caddyfile

	# The Caddyfile reads {$DOMAIN}; supply it via a drop-in so no hostname is
	# ever hard-coded into a tracked file.
	install -d -m 755 /etc/systemd/system/caddy.service.d
	cat > /etc/systemd/system/caddy.service.d/domain.conf <<-EOF
		[Service]
		EnvironmentFile=$CADDY_ENV
	EOF
	echo "DOMAIN=$DOMAIN" > "$CADDY_ENV"
	chmod 644 "$CADDY_ENV"

	# Caddy runs as the `caddy` user and cannot create or reopen a log file that
	# root already owns. Running `caddy validate` (or `caddy run`) as root once
	# is enough to leave a root-owned 0600 file here, after which the service
	# fails to start with a bare "permission denied". Always re-assert ownership.
	install -d -o caddy -g caddy -m 755 /var/log/caddy
	chown -R caddy:caddy /var/log/caddy

	systemctl daemon-reload
	systemctl enable caddy >/dev/null
	systemctl restart caddy
	info "Caddy restarted; certificate issuance happens on first request"
}

phase_firewall() {
	log "Opening the firewall for HTTP/HTTPS"
	if ! command -v ufw &>/dev/null; then
		info "ufw not installed — skipping (check your provider's cloud firewall)"
		return
	fi
	if ! ufw status | grep -q "^Status: active"; then
		info "ufw inactive — nothing to open"
		return
	fi
	# Without these, ACME validation fails with "Timeout during connect
	# (likely firewall problem)" even though Caddy is listening correctly.
	ufw allow 80/tcp  comment 'HTTP - ACME challenge + redirect to HTTPS' >/dev/null
	ufw allow 443/tcp comment 'HTTPS - Sarthi API' >/dev/null
	info "80/tcp and 443/tcp allowed (Postgres stays closed to the internet)"
}

phase_verify() {
	log "Verifying the deployment"
	local code
	code="$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:8080/healthz" || true)"
	[[ "$code" == "200" ]] || die "local healthz returned $code — see: journalctl -u sarthi -n 50"
	info "localhost:8080/healthz -> 200"

	# Cert issuance is triggered by the first TLS handshake and takes a few
	# seconds; poll rather than failing on the first miss.
	local i
	for i in $(seq 1 12); do
		code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "https://$DOMAIN/healthz" || true)"
		[[ "$code" == "200" ]] && break
		info "waiting for TLS ($i/12)..."
		sleep 5
	done
	[[ "$code" == "200" ]] || die "https://$DOMAIN/healthz returned $code — see: journalctl -u caddy -n 50"

	info "https://$DOMAIN/healthz -> 200"
	printf '\n\033[1;32mDeployment healthy.\033[0m API_BASE_URL = https://%s\n\n' "$DOMAIN"
}

# --- psql wrappers -----------------------------------------------------------
# Superuser access goes through the postgres system account (peer auth);
# application access uses the DSN the server itself uses.
psql_su()          { su postgres -c "psql -v ON_ERROR_STOP=1 -q -f -"; }
psql_su_query()    { su postgres -c "psql -tAc \"$1\""; }
psql_app_query()   { PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -U "$DB_USER" -d "$DB_NAME" -tAc "$1"; }

# --- Main --------------------------------------------------------------------
ALL_PHASES=(go postgres database migrations build service caddy firewall verify)

main() {
	preflight
	local phases=("$@")
	[[ ${#phases[@]} -eq 0 ]] && phases=("${ALL_PHASES[@]}")

	local p
	for p in "${phases[@]}"; do
		if [[ ! " ${ALL_PHASES[*]} " == *" $p "* ]]; then
			die "unknown phase '$p' (valid: ${ALL_PHASES[*]})"
		fi
	done
	for p in "${phases[@]}"; do
		"phase_$p"
	done
}

main "$@"
