#!/usr/bin/env bash
# Benchmark a few representative Overpass queries against a pinned, small OSM fixture.
# Run from any directory. Requires bash, curl, GNU time, and built Overpass binaries.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: benchmark-small-dataset.sh [options]

Builds a temporary Overpass database from a small, fixed OSM test fixture and
runs representative queries against it. Results are per-query wall-clock seconds.

Options:
  --bin-dir DIR    Directory containing update_database and osm3s_query.
                   Auto-detected in common build/install locations if omitted.
  --work-dir DIR   Keep benchmark files in DIR instead of a temporary directory.
  --repeats N      Runs per query (default: 5; first run may be cold-cache).
  -h, --help       Show this help.

Example:
  ./osm-3s_testing/benchmark-small-dataset.sh --bin-dir ./build/bin --repeats 10
EOF
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
BIN_DIR="${OVERPASS_BIN_DIR:-}"
WORK_DIR=""
REPEATS="${BENCHMARK_REPEATS:-5}"
KEEP_WORK_DIR=0

while (($#)); do
  case "$1" in
    --bin-dir)
      (($# >= 2)) || { echo "Missing argument for --bin-dir" >&2; exit 2; }
      BIN_DIR=$2; shift 2 ;;
    --work-dir)
      (($# >= 2)) || { echo "Missing argument for --work-dir" >&2; exit 2; }
      WORK_DIR=$2; KEEP_WORK_DIR=1; shift 2 ;;
    --repeats)
      (($# >= 2)) || { echo "Missing argument for --repeats" >&2; exit 2; }
      REPEATS=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$REPEATS" =~ ^[1-9][0-9]*$ ]] || { echo "--repeats must be a positive integer" >&2; exit 2; }

if [[ -z "$BIN_DIR" ]]; then
  for candidate in "$REPO_ROOT/build/bin" "$REPO_ROOT/build/src/bin" "$REPO_ROOT/src/bin"; do
    if [[ -x "$candidate/update_database" && -x "$candidate/osm3s_query" ]]; then
      BIN_DIR=$candidate
      break
    fi
  done
fi
[[ -n "$BIN_DIR" ]] || { echo "Could not find Overpass binaries; pass --bin-dir DIR" >&2; exit 1; }
BIN_DIR="$(cd -- "$BIN_DIR" && pwd)"
UPDATE_DATABASE="$BIN_DIR/update_database"
OSM3S_QUERY="$BIN_DIR/osm3s_query"
[[ -x "$UPDATE_DATABASE" && -x "$OSM3S_QUERY" ]] || {
  echo "Expected executable update_database and osm3s_query in $BIN_DIR" >&2; exit 1;
}
command -v curl >/dev/null || { echo "curl is required to fetch the fixed dataset" >&2; exit 1; }
[[ -x /usr/bin/time ]] || { echo "GNU /usr/bin/time is required for sub-second timings" >&2; exit 1; }

if [[ -z "$WORK_DIR" ]]; then
  WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/overpass-benchmark.XXXXXX")
else
  mkdir -p -- "$WORK_DIR"
  WORK_DIR="$(cd -- "$WORK_DIR" && pwd)"
  if [[ -n "$(find "$WORK_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    echo "Work directory must be empty: $WORK_DIR" >&2
    exit 1
  fi
fi
cleanup() {
  if ((KEEP_WORK_DIR)); then
    echo "Benchmark files retained in: $WORK_DIR"
  else
    rm -rf -- "$WORK_DIR"
  fi
}
trap cleanup EXIT

DB_DIR="$WORK_DIR/db"
DATA_FILE="$WORK_DIR/fixture.osm"
mkdir -p "$DB_DIR"

# Pinned to a repository commit so repeated runs use identical input.
FIXTURE_URL="https://raw.githubusercontent.com/paulklie/Overpass-API/a9d8f157723ecf2eecf63911642fbf248c2d20a0/osm-3s_testing/input/attic_updater/init.osm"
echo "Downloading fixed OSM fixture..."
curl --fail --location --silent --show-error --retry 3 "$FIXTURE_URL" --output "$DATA_FILE"
[[ -s "$DATA_FILE" ]] || { echo "Downloaded fixture is empty" >&2; exit 1; }

echo "Importing fixture into a fresh temporary database..."
/usr/bin/time -f 'database_import_seconds,%e' -o "$WORK_DIR/import-time.txt" \
  "$UPDATE_DATABASE" --db-dir="$DB_DIR/" --version=mock-up-init < "$DATA_FILE"
printf 'database_import_seconds,%s\n' "$(cat "$WORK_DIR/import-time.txt")"

run_query() {
  local name=$1
  local query=$2
  local query_file="$WORK_DIR/$name.ql"
  local stderr_file="$WORK_DIR/$name.stderr"
  local timing_file="$WORK_DIR/$name.time"
  printf '%s\n' "$query" > "$query_file"

  for ((iteration=1; iteration<=REPEATS; iteration++)); do
    if ! /usr/bin/time -f '%e' -o "$timing_file" \
        "$OSM3S_QUERY" --concise --db-dir="$DB_DIR/" \
        < "$query_file" > /dev/null 2> "$stderr_file"; then
      echo "Query '$name' failed (see $stderr_file in the work directory)." >&2
      return 1
    fi
    printf '%s,%d,%s\n' "$name" "$iteration" "$(cat "$timing_file")" | tee -a "$WORK_DIR/results.csv"
  done
}

printf 'query,iteration,wall_seconds\n' > "$WORK_DIR/results.csv"
echo "Running $REPEATS measured repetitions per query (first run may be cold-cache)..."
run_query id_lookup 'node(1101);out ids;'
run_query bbox_lookup 'node(10,1,10.1,1.1);out ids;'
run_query tag_lookup 'node["foo"="bar_1101"];out ids;'
run_query way_geometry 'way(1302);out geom;'
run_query relation_recurse 'rel(1332);>;out ids;'
echo "Results written to: $WORK_DIR/results.csv"
