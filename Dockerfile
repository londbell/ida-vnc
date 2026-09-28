# ────────────────────────────────────────────────────────
# IDA Pro 9.4 + KasmVNC Linux Workspace Image
# ────────────────────────────────────────────────────────
FROM kasmweb/core-ubuntu-jammy:1.14.0

LABEL description="IDA Pro 9.4 inside KasmVNC-powered XFCE desktop"

# ── Install runtime deps for Qt6 / IDA + Python 3.11 (single layer) ──
# ida-pro-mcp requires Python 3.11+. Ubuntu 22.04 ships 3.10.
# Use Tencent mirrors for faster apt downloads from CN hosts.
USER root
RUN sed -i \
        -e 's|http://archive.ubuntu.com/ubuntu/|https://mirrors.tencent.com/ubuntu/|g' \
        -e 's|http://security.ubuntu.com/ubuntu/|https://mirrors.tencent.com/ubuntu/|g' \
        -e 's|http://[a-z]*.archive.ubuntu.com/ubuntu/|https://mirrors.tencent.com/ubuntu/|g' \
        /etc/apt/sources.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        libxcb-cursor0 \
        libxcb-icccm4 \
        libxkbcommon-x11-0 \
        libxcb-keysyms1 \
        libxcb-util1 \
        software-properties-common && \
    add-apt-repository -y ppa:deadsnakes/ppa && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        python3.11 \
        libpython3.11 \
        python3.11-venv \
        python3.11-distutils && \
    rm -rf /var/lib/apt/lists/*

# ── Install IDA Pro ───────────────────────────────────
# Installer must be staged at downloads/ida-pro_94_x64linux.run before docker build.
# Requires BuildKit (Docker 23+ default). The installer is bind-mounted during
# the RUN step only, so it never bloats a persistent image layer (~600MB saved).
#
# Optional: place replacement files (e.g. patched *.so) under downloads/overrides/
# mirroring the /opt/ida-pro layout — they are copied over after installation.
USER root
RUN --mount=type=bind,source=downloads,target=/mnt/downloads \
    set -eux; \
    cp /mnt/downloads/ida-pro_94_x64linux.run /tmp/ida.run; \
    chmod +x /tmp/ida.run; \
    /tmp/ida.run --mode unattended --prefix /opt/ida-pro; \
    if [ -d /mnt/downloads/overrides ]; then \
        cp -a /mnt/downloads/overrides/. /opt/ida-pro/; \
    fi; \
    rm -f /tmp/ida.run; \
    chown -R 1000:1000 /opt/ida-pro

# Point IDA Pro / idalib to Python 3.11
RUN /opt/ida-pro/idapyswitch -s /usr/lib/x86_64-linux-gnu/libpython3.11.so.1.0

# ── Install uv and ida-pro-mcp ────────────────────────
# ida-pro-mcp is installed from a local clone at downloads/ida-pro-mcp
# (gitignored) — the build host may not have access to github.com.
# PyPI traffic goes through the Tsinghua mirror for CN hosts.
USER root
# Use root's HOME for this step only, so pip/uv don't create root-owned files
# under /home/kasm-user (and don't leak HOME=/root into the runtime image).
ARG PYPI_MIRROR=https://pypi.tuna.tsinghua.edu.cn/simple
RUN --mount=type=bind,source=downloads,target=/mnt/downloads \
    set -eux; \
    cp -a /mnt/downloads/ida-pro-mcp /tmp/ida-pro-mcp; \
    HOME=/root python3.11 -m ensurepip && \
    HOME=/root python3.11 -m pip install --no-cache-dir -i ${PYPI_MIRROR} --upgrade pip && \
    HOME=/root python3.11 -m pip install --no-cache-dir -i ${PYPI_MIRROR} uv && \
    HOME=/root uv pip install --system --python python3.11 \
        --index-url ${PYPI_MIRROR} \
        /tmp/ida-pro-mcp; \
    rm -rf /tmp/ida-pro-mcp

# ── Desktop Integration ────────────────────────────────
COPY --chown=1000:1000 resources/ida-pro.desktop \
     /home/kasm-user/Desktop/ida-pro.desktop
RUN chmod +x /home/kasm-user/Desktop/ida-pro.desktop
COPY --chown=1000:1000 resources/ida-pro.desktop \
     /usr/share/applications/ida-pro.desktop

RUN mkdir -p /home/kasm-user/.local/share/applications && \
    cp /usr/share/applications/ida-pro.desktop \
       /home/kasm-user/.local/share/applications/ida-pro.desktop && \
    chown -R 1000:1000 /home/kasm-user/.local/share/applications

# ── Environment ────────────────────────────────────────
ENV PATH="/opt/ida-pro:${PATH}"
ENV QT_QPA_PLATFORM=xcb
ENV DISPLAY=:1

# ── Startup Hook ──────────────────────────────────────
# Root entrypoint wrapper: fixes mount ownership before Kasm startup
# (custom_startup.sh runs as uid 1000 and cannot chown).
COPY --chown=1000:1000 resources/entrypoint.sh /dockerstartup/ida-entrypoint.sh
RUN chmod +x /dockerstartup/ida-entrypoint.sh
COPY --chown=1000:1000 resources/custom_startup.sh /dockerstartup/
RUN chmod +x /dockerstartup/custom_startup.sh

ENTRYPOINT ["/dockerstartup/ida-entrypoint.sh"]

# ── Ensure workspace and config directories exist ─────
RUN mkdir -p /home/kasm-user/.idapro /home/kasm-user/workspace && \
    chown -R 1000:1000 /home/kasm-user/.idapro /home/kasm-user/workspace

# ── Final State ────────────────────────────────────────
# Start as root so the entrypoint can chown mounts / run idapyswitch;
# it drops back to uid 1000 before handing off to the Kasm startup chain.
USER root
WORKDIR /home/kasm-user/workspace

EXPOSE 6901 8745
