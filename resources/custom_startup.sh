#!/usr/bin/env bash
set -e

# NOTE: this script runs as uid 1000 (kasm-user), NOT root.
# Ownership fix, license symlink and idapyswitch configuration are all done
# by the root entrypoint wrapper (/dockerstartup/ida-entrypoint.sh).

# ── License check (informational) ─────────────────────
HEXLIC=""
for f in /home/kasm-user/.idapro/*.hexlic /opt/ida-pro/*.hexlic; do
    if [[ -f "$f" ]]; then HEXLIC="$f"; break; fi
done

if [[ -z "$HEXLIC" ]]; then
    echo "============================================================"
    echo "WARNING: no IDA license file (*.hexlic) found in:"
    echo "  /home/kasm-user/.idapro/  or  /opt/ida-pro/"
    echo "IDA will start in evaluation mode."
    echo "============================================================"
else
    echo "IDA license file detected: $HEXLIC"
fi

# ── Ensure workspace dir exists ───────────────────────
mkdir -p /home/kasm-user/workspace 2>/dev/null || true

# ── Trust the desktop launcher (XFCE requires +x) ─────
chmod +x /home/kasm-user/Desktop/ida-pro.desktop 2>/dev/null || true

# ── Start ida-pro-mcp server ──────────────────────────
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
