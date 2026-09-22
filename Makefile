# OLS — OVERLORD × SABLE in one image, next to the lab it heals.
#
#     make up          build the image and start everything (lab + console)
#     make down        stop everything (lab containers, network, volumes)
#     make logs        follow the console container's log
#     make status      containers + the console's /api/state
#     make fault F=stop_service     break the lab and watch the loop fix it
#     make test        the console's test suite (needs python3 + deps on this box)
#     make sync        refresh overlord/ and sable/ from their repos (tools/sync.sh)
#
# OLS_DIR is this checkout's absolute HOST path (the console container mounts it
# at the same path so the lab's bind mounts resolve host-side). Keep the checkout
# on the Linux filesystem (~/…), not /mnt/c.
ROOT   := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
COMPOSE := OLS_DIR=$(ROOT) docker compose -f $(ROOT)/docker-compose.yml
FAULTS := stop_service corrupt_config kill_primary poison_dns heal_all

.PHONY: help up down build logs status fault test sync config

help:
	@sed -n '3,11p' $(ROOT)/Makefile | sed 's/^#     //'

build:
	$(COMPOSE) build console

up:
	$(COMPOSE) up -d --build --wait --wait-timeout 300
	@echo; echo "Up.  console: http://127.0.0.1:7780   SABLE: http://127.0.0.1:8080   (make fault F=stop_service)"

down:
	$(COMPOSE) down -v --remove-orphans

logs:
	$(COMPOSE) logs -f --tail 100 console

status:
	$(COMPOSE) ps
	@curl -fsS http://127.0.0.1:7780/api/state 2>/dev/null | python3 -m json.tool | head -40 || echo "console not answering on :7780"

fault:
	@test -n "$(F)" || { echo "usage: make fault F=<$(FAULTS)> [ARGS=dns]"; exit 2; }
	bash $(ROOT)/sable/console/lab/faults/$(F).sh $(ARGS)

config:
	$(COMPOSE) config --quiet && echo "compose config ok"

test:
	cd $(ROOT)/sable && python3 -m pytest console/tests -q

sync:
	bash $(ROOT)/tools/sync.sh
