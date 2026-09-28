#!/usr/bin/env bash
set -e

HEXLIC_PATH="/home/kasm-user/.idapro/ida.hexlic"

# ── License check ─────────────────────────────────────
if [[ ! -f "$HEXLIC_PATH" ]]; then
    echo "============================================================"
    echo "WARNING: IDA license file not found at $HEXLIC_PATH"
    echo ""
    echo "The whole ~/.idapro dir is bind-mounted for persistence."
    echo "Place your ida.hexlic in the host config directory, e.g.:"
    echo "  ~/IDA-config/ida.hexlic"
    echo ""
    echo "IDA will start in evaluation mode."
    echo "============================================================"
else
    echo "IDA license file detected: $HEXLIC_PATH"
    # Ensure correct permissions (readable, not executable)
    chmod 644 "$HEXLIC_PATH" 2>/dev/null || true
fi

# ── Ensure workspace and config directories exist ─────
mkdir -p /home/kasm-user/workspace
mkdir -p /home/kasm-user/.idapro

# ── Trust the desktop launcher (XFCE requires +x on desktop files) ──
chmod +x /home/kasm-user/Desktop/ida-pro.desktop 2>/dev/null || true

# ── Start ida-pro-mcp server ──────────────────────────
# ida-pro-mcp provides an MCP server for IDA Pro's idalib.
MCP_HOST="${MCP_HOST:-127.0.0.1}"
MCP_PORT="${MCP_PORT:-8745}"
echo "Starting ida-pro-mcp server on ${MCP_HOST}:${MCP_PORT} ..."
# UV_NO_CACHE avoids cache permission issues if $HOME/.cache/uv is not writable.
UV_NO_CACHE=1 nohup uv run --no-project --python python3.11 idalib-mcp \
    --host "${MCP_HOST}" \
    --port "${MCP_PORT}" \
    > /tmp/idalib-mcp.log 2>&1 &

# ── Done. Kasm VNC startup will proceed via vnc_startup.sh ──
# (This script is called by vnc_startup.sh's custom_startup() function)

