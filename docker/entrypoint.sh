#!/usr/bin/env bash
# Runs the four processes of the loop inside one container and dies if any
# of them dies (so `docker compose` restarts the whole unit):
#   overlord daemon → SABLE (real engine if weights, else the stub)
#   → live monitor (Prometheus → SABLE) → console server
#
# Env (see docker-compose.yml at the OLS root):
#   SABLE_DIR        $OLS_DIR/sable as bind-mounted at its HOST path (lab dir = $SABLE_DIR/console/lab)
#   PROMETHEUS_URL   default http://prometheus:9090 (the lab network)
#   SABLE_MODE       auto | real | stub (auto: real when docker/checkpoints/fusion.pt exists)
#   ANTHROPIC_API_KEY  → SABLE_LLM=claude
set -uo pipefail
APP=/app/sable
SABLE_DIR="${SABLE_DIR:-/app/sable}"                       # host-path mount, or the image copy
LAB_DIR="${LAB_DIR:-$SABLE_DIR/console/lab}"
export LAB_DIR PROMETHEUS_URL="${PROMETHEUS_URL:-http://prometheus:9090}" SABLE_URL="${SABLE_URL:-http://127.0.0.1:8080}"
export OVERLORD_HOME="${OVERLORD_HOME:-/data}"
mkdir -p "$OVERLORD_HOME"
[[ -n "${ANTHROPIC_API_KEY:-}" ]] && export SABLE_LLM=claude

# the code that runs is the mounted checkout when present (so edits on the
# host are live), else the image's copy
cd "$SABLE_DIR" 2>/dev/null || cd "$APP"
export PYTHONPATH="$PWD:$PWD/docker${PYTHONPATH:+:$PYTHONPATH}"

mode="${SABLE_MODE:-auto}"
if [[ "$mode" == "auto" ]]; then
    if [[ -f "$PWD/docker/checkpoints/fusion.pt" && -f "$PWD/docker/checkpoints/temporal.pt" ]]; then mode=real; else mode=stub; fi
fi
cp -f console/lab/topology.yaml adapters/topologies/00-lab.yaml 2>/dev/null || true
# a fresh checkout has no built UI (dist is gitignored); use the image's build
if [[ ! -f console/ui/dist/index.html && -f "$APP/console/ui/dist/index.html" ]]; then
    mkdir -p console/ui/dist && cp -r "$APP/console/ui/dist/." console/ui/dist/
    echo "== UI: using the image's build (no console/ui/dist in the checkout)"
fi

pids=()
run() { echo "== $1"; shift; "$@" & pids+=($!); }

run "overlord daemon (fuse backend in-container)" overlord daemon
sleep 1
if [[ "$mode" == "real" ]]; then
    run "SABLE engine (real weights)" python3 docker/server.py
else
    echo "!! no trained weights under docker/checkpoints — running the SABLE STAND-IN (console/lab/sable_stub.py)"
    run "SABLE stub" python3 -m console.lab.sable_stub --config console/lab/sable_prometheus.yaml
fi
for _ in $(seq 1 90); do curl -fsS "$SABLE_URL/api/status" > /dev/null 2>&1 && break; sleep 1; done
if [[ "$mode" == "real" ]]; then
    run "live monitor (Prometheus → SABLE)" python3 -m console.lab.live_monitor_lab --config console/lab/sable_prometheus.yaml
fi
run "console" python3 -m console.server --bind "${CONSOLE_BIND:-0.0.0.0}" --port 7780

# first one to exit takes the container down with it
wait -n "${pids[@]}"
code=$?
echo "!! a loop process exited ($code); stopping the rest"
kill "${pids[@]}" 2>/dev/null
exit "$code"
