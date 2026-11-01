#!/usr/bin/env bash
# Install the niri-shell switcher. Idempotent; touches nothing in niri-gnome except
# drop-ins that let its daemons stand aside in Caelestia mode.
set -euo pipefail
ROOT=$(dirname "$(readlink -f "$0")")
U=${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user
mkdir -p "$HOME/.local/bin" "$U" "$HOME/.local/share/applications"
ln -sfn "$ROOT/bin/niri-shell" "$HOME/.local/bin/niri-shell"
for f in niri-caelestia.service niri-shell.service niri-shell.path; do ln -sfn "$ROOT/systemd/$f" "$U/$f"; done
for u in niri-waybar niri-panels niri-swayosd niri-swaybg mako; do
    mkdir -p "$U/$u.service.d"
    ln -sfn "$ROOT/systemd/niri-shell-gate.conf" "$U/$u.service.d/niri-shell-gate.conf"
done
ln -sfn "$ROOT/applications/niri-shell-toggle.desktop" "$HOME/.local/share/applications/niri-shell-toggle.desktop"

systemctl --user daemon-reload
[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/niri-shell/mode" ] || "$HOME/.local/bin/niri-shell" gnome
systemctl --user enable niri-shell.service niri-shell.path
systemctl --user is-active -q niri.service && systemctl --user start niri-shell.path
grep -q 'niri-shell.kdl' "${XDG_CONFIG_HOME:-$HOME/.config}/niri/config.kdl" ||
    echo "add to niri config.kdl (last line): include optional=true \"${XDG_RUNTIME_DIR:-/run/user/$UID}/niri-shell.kdl\""
