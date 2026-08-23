# ────────────────────────────────────────────────────────
# IDA Pro 9.4 + KasmVNC Linux Workspace Image
# ────────────────────────────────────────────────────────

# ── Stage 1: Install IDA Pro ─────────────────────────
FROM kasmweb/core-ubuntu-jammy:1.14.0 AS builder

USER root
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libxcb-cursor0 \
        libxcb-icccm4 \
        libxkbcommon-x11-0 \
        libxcb-keysyms1 \
        libxcb-util1 && \
    rm -rf /var/lib/apt/lists/*

COPY downloads/ida-pro_94_x64linux.run /tmp/ida.run

RUN chmod +x /tmp/ida.run && \
    /tmp/ida.run --mode unattended --prefix /opt/ida-pro && \
    rm -f /tmp/ida.run

# ── Stage 2: Final image ──────────────────────────────
FROM kasmweb/core-ubuntu-jammy:1.14.0

LABEL description="IDA Pro 9.4 inside KasmVNC-powered XFCE desktop"

# ── Install runtime dependencies for Qt6 / IDA ────────
USER root
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libxcb-cursor0 \
        libxcb-icccm4 \
        libxkbcommon-x11-0 \
        libxcb-keysyms1 \
        libxcb-util1 && \
    rm -rf /var/lib/apt/lists/*

# ── Copy installed IDA Pro from builder ───────────────
COPY --from=builder /opt/ida-pro /opt/ida-pro
RUN chown -R 1000:1000 /opt/ida-pro

# ── Install Python 3.11+ for ida-pro-mcp ──────────────
USER root
RUN apt-get update && \
    apt-get install -y --no-install-recommends software-properties-common && \
    add-apt-repository -y ppa:deadsnakes/ppa && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        python3.11 \
        python3.11-dev \
        python3.11-venv \
        python3.11-distutils && \
    rm -rf /var/lib/apt/lists/*

# Point IDA Pro / idalib to Python 3.11
RUN /opt/ida-pro/idapyswitch -s /usr/lib/x86_64-linux-gnu/libpython3.11.so.1.0

# ── Install uv and ida-pro-mcp ────────────────────────
USER root
ENV HOME=/root
RUN python3.11 -m ensurepip && \
    python3.11 -m pip install --upgrade pip && \
    python3.11 -m pip install uv && \
    uv pip install --system --python python3.11 \
        git+https://github.com/mrexodia/ida-pro-mcp.git

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
COPY --chown=1000:1000 resources/custom_startup.sh /dockerstartup/
RUN chmod +x /dockerstartup/custom_startup.sh

# ── Ensure workspace and config directories exist ─────
RUN mkdir -p /home/kasm-user/workspace && \
    chown -R 1000:1000 /home/kasm-user/workspace && \
    mkdir -p /opt/ida-license

# ── Final State ────────────────────────────────────────
USER 1000
WORKDIR /home/kasm-user/workspace

EXPOSE 6901 8745

# ── Persistent volumes ─────────────────────────────────
VOLUME ["/home/kasm-user/.idapro"]
VOLUME ["/home/kasm-user/workspace"]
