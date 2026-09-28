#!/usr/bin/env bash
# Root entrypoint wrapper. The image starts as root so we can:
#   1. chown host-mounted dirs (bind mounts are often root-owned on the host)
#   2. create the canonical ida.hexlic symlink
#   3. run idapyswitch (writes ~/.idapro/ida.reg)
# Then we drop back to uid 1000 (kasm-user) and hand off to the original
# Kasm startup chain, exactly as the base image intended.
set -u

IDAPRO=/home/kasm-user/.idapro
LIBPYTHON=/usr/lib/x86_64-linux-gnu/libpython3.11.so.1.0

# ── 1. Fix ownership of host-mounted dirs ────────────
if ! chown -R 1000:1000 /home/kasm-user/workspace "$IDAPRO" 2>&1; then
    echo "WARN: chown on mounted dirs failed."
    echo "      Workaround: chown the host dirs to uid 1000 manually."
fi

# ── 2. Ensure canonical license name exists ──────────
# Accept any *.hexlic filename and symlink it to ida.hexlic.
for f in "$IDAPRO"/*.hexlic; do
    [ -f "$f" ] || continue
    if [ ! -e "$IDAPRO/ida.hexlic" ]; then
        ln -s "$(basename "$f")" "$IDAPRO/ida.hexlic" \
            || echo "WARN: could not create ida.hexlic symlink"
    fi
    break
done

# ── 3. Configure IDAPython if needed ─────────────────
# idapyswitch writes ~/.idapro/ida.reg. The persistent mount shadows the
# copy baked into the image, so re-run it on first boot.
if ! grep -q 'Python3TargetDLL' "$IDAPRO/ida.reg" 2>/dev/null; then
    echo "Configuring IDAPython (idapyswitch) ..."
    if HOME=/home/kasm-user /opt/ida-pro/idapyswitch -s "$LIBPYTHON"; then
        # idapyswitch ran as root; make sure uid 1000 can still read/write it
        chown 1000:1000 "$IDAPRO/ida.reg" 2>/dev/null || true
    else
        echo "WARN: idapyswitch failed — IDAPython may not be configured."
    fi
fi

# ── 4. Drop privileges and run the Kasm startup chain ─
# Base image ENTRYPOINT:
#   ["/dockerstartup/kasm_default_profile.sh",
#    "/dockerstartup/vnc_startup.sh",
#    "/dockerstartup/kasm_startup.sh"]
exec setpriv --reuid=1000 --regid=1000 --init-groups --inh-caps=-all \
     /dockerstartup/kasm_default_profile.sh \
     /dockerstartup/vnc_startup.sh \
     /dockerstartup/kasm_startup.sh \
     "$@"
