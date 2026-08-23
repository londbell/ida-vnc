#!/usr/bin/env bash
set -e

HEXLIC_PATH="/home/kasm-user/.idapro/ida.hexlic"

# ── License check ─────────────────────────────────────
if [[ ! -f "$HEXLIC_PATH" ]]; then
    echo "============================================================"
    echo "WARNING: IDA license file not found at $HEXLIC_PATH"
    echo ""
    echo "Please place your ida.hexlic next to docker-compose.yml"
    echo "and restart the container."
    echo ""
    echo "IDA will start in evaluation mode."
    echo "============================================================"
else
    echo "IDA license file detected: $HEXLIC_PATH"
    chmod 644 "$HEXLIC_PATH" 2>/dev/null || true
fi

# ── Ensure config directory exists ────────────────────
mkdir -p /home/kasm-user/.idapro

# ── Trust the desktop launcher (XFCE requires +x on desktop files) ──
chmod +x /home/kasm-user/Desktop/ida-pro.desktop 2>/dev/null || true

# ── Start ida-pro-mcp server ──────────────────────────
MCP_HOST="${MCP_HOST:-127.0.0.1}"
MCP_PORT="${MCP_PORT:-8745}"
echo "Starting ida-pro-mcp server on ${MCP_HOST}:${MCP_PORT} ..."
UV_NO_CACHE=1 nohup uv run --no-project --python python3.11 idalib-mcp \
    --host "${MCP_HOST}" \
    --port "${MCP_PORT}" \
    > /tmp/idalib-mcp.log 2>&1 &

# ── Done. Kasm VNC startup will proceed via vnc_startup.sh ──
