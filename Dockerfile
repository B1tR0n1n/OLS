# The whole loop in one image: OVERLORD (engine + daemon), the console server
# and UI, SABLE's server (the real engine when docker/checkpoints/*.pt are
# mounted, the stand-in otherwise), and the live monitor. The lab itself
# stays a compose stack next to this container (docker-compose.yml at the OLS
# root includes it) because faults stop and start its containers.
#
#   make up                          # build + start everything
#
# Inside the container OVERLORD runs on the fuse backend (/dev/fuse +
# CAP_SYS_ADMIN from the host); the executor drives the lab through the
# host's Docker socket, so the OLS checkout is bind-mounted at the SAME
# absolute path as on the host (compose resolves bind mounts host-side).
#
# Build from the OLS root:  docker build .

# ---- stage 1: the UI
FROM node:20-bookworm-slim AS ui
WORKDIR /ui
COPY sable/console/ui/package.json sable/console/ui/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY sable/console/ui/ ./
RUN npm run build

# ---- stage 2: the runtime
FROM python:3.12-slim-bookworm

ARG TORCH_INDEX=https://download.pytorch.org/whl/cpu
ENV DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 PIP_DISABLE_PIP_VERSION_CHECK=1

# docker CLI + compose plugin (to drive the lab through the host socket),
# fuse-overlayfs (OVERLORD's in-container backend), gcc (OVERLORD's launcher)
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl gnupg git gcc libc6-dev fuse-overlayfs strace make \
 && install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable" > /etc/apt/sources.list.d/docker.list \
 && apt-get update && apt-get install -y --no-install-recommends docker-ce-cli docker-compose-plugin \
 && rm -rf /var/lib/apt/lists/*

# OVERLORD, installed the way packaging/install.sh installs it on a host
COPY overlord/ /opt/overlord/
RUN bash /opt/overlord/packaging/install.sh && overlord doctor || true

# python deps: console + Claude bridge + SABLE's engine (CPU torch by default)
COPY sable/console/requirements.txt /tmp/console-requirements.txt
COPY sable/docker/requirements.txt /tmp/sable-requirements.txt
RUN pip install --no-cache-dir -r /tmp/console-requirements.txt anthropic \
 && pip install --no-cache-dir torch --index-url "$TORCH_INDEX" \
 && pip install --no-cache-dir -r /tmp/sable-requirements.txt numpy networkx

# the sable tree (console + engine). At run time the OLS checkout is also
# bind-mounted at its host path and the entrypoint prefers that copy, so edits
# on the host are live; this copy makes the image self-contained.
WORKDIR /app/sable
COPY sable/ /app/sable/
COPY docker/entrypoint.sh /app/docker/entrypoint.sh
COPY --from=ui /ui/dist /app/sable/console/ui/dist
RUN cp /app/sable/console/lab/topology.yaml /app/sable/adapters/topologies/00-lab.yaml \
 && chmod +x /app/docker/entrypoint.sh

ENV OVERLORD_HOME=/data SABLE_URL=http://127.0.0.1:8080 CONSOLE_LAB=1 SITE_ID=lab \
    SABLE_BIND=0.0.0.0 CONSOLE_BIND=0.0.0.0
VOLUME ["/data"]
EXPOSE 7780 8080
HEALTHCHECK --interval=15s --timeout=5s --start-period=60s \
  CMD curl -fsS http://127.0.0.1:7780/api/state > /dev/null || exit 1
ENTRYPOINT ["/app/docker/entrypoint.sh"]
