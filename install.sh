#!/usr/bin/env bash
# Sets up the tracker behind the CS2 TTD bar widget:
#   - Python venv with curl_cffi in ~/.local/share/cs2-ttd/venv
#   - config with your SteamID in ~/.config/cs2-ttd/config (asked once, never leaves your machine)
#   - systemd user timer cs2-ttd.timer (every 2 hours)
#
#   ./install.sh            install / update
#   ./install.sh --remove   remove timer and venv (config and history stay)
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="$HOME/.local/share/cs2-ttd/venv"
CONFIG="$HOME/.config/cs2-ttd/config"
UNITS="$HOME/.config/systemd/user"

if [[ "${1:-}" == "--remove" ]]; then
  systemctl --user disable --now cs2-ttd.timer 2>/dev/null || true
  rm -f "$UNITS/cs2-ttd.service" "$UNITS/cs2-ttd.timer"
  systemctl --user daemon-reload
  rm -rf "$HOME/.local/share/cs2-ttd"
  echo "Removed. Config ($CONFIG) and history (~/.local/state/cs2-ttd) are still there."
  exit 0
fi

# 1. SteamID
mkdir -p "$(dirname "$CONFIG")"
if ! grep -qE '^STEAMID=[0-9]{17}$' "$CONFIG" 2>/dev/null; then
  echo "Your SteamID64 (17 digits) or Steam profile URL – find it on https://steamid.io"
  read -rp "> " input
  steamid="$(grep -oE '[0-9]{17}' <<<"$input" | head -1 || true)"
  if [[ -z "$steamid" ]]; then
    echo "That doesn't contain a SteamID64. Custom URLs (/id/name) don't work, use steamid.io to look it up." >&2
    exit 1
  fi
  read -rp "Optional: mark a date in the charts, e.g. when you switched to Omarchy (YYYY-MM-DD, empty = none): " since
  {
    echo "STEAMID=$steamid"
    [[ -n "$since" ]] && echo "SINCE=$since" && echo "SINCE_LABEL=Omarchy"
  } >"$CONFIG"
  chmod 600 "$CONFIG"
  echo "Saved to $CONFIG"
fi

# 2. venv
if [[ ! -x "$VENV/bin/python" ]]; then
  python3 -m venv "$VENV"
fi
"$VENV/bin/pip" install -q --upgrade curl_cffi

# 3. timer
mkdir -p "$UNITS"
cat >"$UNITS/cs2-ttd.service" <<EOF
[Unit]
Description=CS2 Time-to-Damage snapshot from cs2tracker.gg
After=network-online.target

[Service]
Type=oneshot
ExecStart=$VENV/bin/python $DIR/tracker/tracker.py
EOF
cat >"$UNITS/cs2-ttd.timer" <<EOF
[Unit]
Description=CS2 Time-to-Damage snapshot every 2 hours

[Timer]
OnBootSec=5min
OnUnitActiveSec=2h
Persistent=true

[Install]
WantedBy=timers.target
EOF
systemctl --user daemon-reload
systemctl --user enable --now cs2-ttd.timer

# 4. first snapshot
systemctl --user start cs2-ttd.service && echo "First snapshot done – check the widget." \
  || echo "First fetch failed: journalctl --user -u cs2-ttd"
