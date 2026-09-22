# OLS — Lord Sable

OVERLORD and SABLE in one repository, one image, one command.

- **`overlord/`** — the agent hypervisor: transactional overlay sessions, provenance, keyed audit chain, policy gate, revert. Copy of [B1tR0n1n/overlord](https://github.com/B1tR0n1n/overlord).
- **`sable/`** — the infrastructure diagnosis engine plus the closed-loop console (`sable/console/`): SABLE finds the fault, the console plans a fix, OVERLORD executes it in a session that can be reverted, SABLE re-checks, a receipt is sealed. Copy of [B1tR0n1n/sable](https://github.com/B1tR0n1n/sable).
- **`Dockerfile` / `docker-compose.yml` / `docker/entrypoint.sh`** — the console image (OVERLORD daemon + SABLE + live monitor + console server) next to the lab stack it heals.
- **`ENGINES.lock`** — the exact engine commits this tree carries. `tools/sync.sh` refreshes both copies and rewrites it.

## Run

Needs Docker with the Compose v2 plugin (`docker compose version` must work on the host too: the fault scripts and `make fault` call it outside the container), and `make`. Keep the checkout on the Linux filesystem, not `/mnt/c`.

```bash
git clone https://github.com/B1tR0n1n/OLS.git ~/projects/OLS
cd ~/projects/OLS
make up            # builds the image, starts the lab and the console
```

Then open <http://127.0.0.1:7780>. Break something and watch the loop close:

```bash
make fault F=stop_service      # also: corrupt_config kill_primary poison_dns heal_all
make logs
make down
```

## SABLE's weights

The trained checkpoints (`sable/docker/checkpoints/fusion.pt`, `temporal.pt`, optional `lora_adapter.pt`) and the Pillar-1 GNN (`sable/pillar1/checkpoints/best_model.pt`, which the live monitor needs to encode telemetry the way the fusion model was trained) are not in any repo. Drop them in those directories and the container runs the real engine (`SABLE_MODE=auto` picks it up at start). Without them the container runs the stand-in (`sable/console/lab/sable_stub.py`): same API, same tick and recommendation shapes, root cause = the node that left healthy first, and every response is labelled `engine: stub` so nothing can be mistaken for a model verdict.

## Knobs (environment, read by `docker compose`)

| variable | effect |
|---|---|
| `ANTHROPIC_API_KEY` | SABLE's analyst runs on Claude; the console's LLM planner becomes available |
| `SABLE_MODE` | `auto` (default), `real`, `stub` |
| `CONSOLE_POLICY` | path to a policy file (default: the shipped default-deny) |
| `CONSOLE_DISABLE_ACTIONS` | comma-separated catalog actions to refuse |
| `CONSOLE_TOKEN` | when set, every mutating console route needs `Authorization: Bearer <token>`; the UI takes it from `#token=` once and keeps it in localStorage |
| `SABLE_TOKEN` | when set, SABLE's own state-changing routes need `X-SABLE-Token`; the live monitor sends it |

## Developing

Edits under `sable/` on the host are live inside the container (the checkout is bind-mounted; the entrypoint runs from the mount). Changes to `overlord/` need `make build`. Tests: `make test` (the console suite) and `python3 overlord/test/*_test.py` for the engine.

To take engine changes from their own repos: `make sync` (or `tools/sync.sh <overlord-ref> <sable-ref>`), then commit the updated tree together with `ENGINES.lock`.
