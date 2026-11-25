# Small-fixture Overpass benchmark

`benchmark-small-dataset.sh` creates a disposable database from a small OSM XML
fixture already used by the project's tests, then times a handful of query types:
ID lookup, bounding-box lookup, tag lookup, way geometry output, and relation
recursion. The fixture URL is pinned to a Git commit, making the input consistent
across runs. This is a local microbenchmark, not a production-scale or concurrent
load test.

## Requirements

- Bash, `curl`, GNU `time` (`/usr/bin/time`)
- Built Overpass `update_database` and `osm3s_query` executables
- Enough free disk space for the fixture database (the source XML is small; the
  database takes more space than the XML)

## Run

From the repository root, for a typical out-of-tree build:

```sh
./osm-3s_testing/benchmark-small-dataset.sh --bin-dir ./build/bin --repeats 10
```

The script also checks `build/bin`, `build/src/bin`, and `src/bin` automatically.
Use `--bin-dir` if the executables are elsewhere. It builds the database in a
fresh temporary directory and removes it when finished. To inspect the generated
files and CSV results, provide an empty work directory:

```sh
mkdir -p /tmp/overpass-bench
./osm-3s_testing/benchmark-small-dataset.sh \
  --bin-dir ./build/bin --work-dir /tmp/overpass-bench --repeats 10
```

The `results.csv` file reports wall-clock seconds for every query repetition;
`import-time.txt` records the one-time database import duration. Each query's
standard output is discarded so timing focuses on processing rather than writing
results to disk. The first repetition may be affected by a cold OS page cache;
compare repeated runs on the same host and distinguish cold from warm-cache
results. This script does not clear the OS cache, change machine settings, or
send requests to a public Overpass service.
