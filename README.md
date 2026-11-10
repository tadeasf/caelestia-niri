# caelestia-niri

Upstream [Caelestia shell](https://github.com/caelestia-dots/shell) running on niri, switchable with
[niri-gnome](https://github.com/tadeasf/niri-gnome). Upstream stays an untouched clone; niri support is an overlay plus
checked patches, so `git pull` does not undo it.

## Versions

Every merged PR is a [release](https://github.com/tadeasf/caelestia-niri/releases). v1.0.0 is the plain
port; each later minor version adds one custom feature, so pick the newest one that has what you want and
none of what you don't. A release pins the upstream commit it was built against (`upstream.rev`), so an
older tag still builds the same way later:

    git fetch --tags && git checkout v1.0.0 && ./build.py
    systemctl --user restart niri-caelestia.service

`build.py` moves `upstream/` to the pinned commit by itself and says when the C++ plugin needs a rebuild.
Tags before v1.4.2 predate `upstream.rev`: run `git -C upstream checkout b9a15ba9` before `./build.py`.

| Since | Feature |
|---|---|
| 1.0.0 | niri backend for Caelestia's Hyprland service, window previews, Alt/Super+Tab switcher, launcher focus, `niri-shell` mode switch |
| 1.1.0 | Claude plan usage bar entry and popout (bar id `claudeUsage`) |
| 1.1.1 | Keep awake toggle works on niri |
| 1.2.0 | Network and system usage bar entry (bar id `sysUsage`) |
| 1.3.0 | Hover popouts: Performance on `sysUsage`, calendar on the clock |
| 1.4.0 | Overview workspace grips: drag to reorder, close to merge into the neighbour |
| 1.4.1 | Bar shows the workspaces niri has instead of a fixed five |
| 1.4.2 | Pinned upstream, CI and releases (no shell changes) |

PR labels pick the bump: `release:minor` (feature), `release:major` (breaking), `release:skip` (no release), none = patch.

## Switching

One line decides: `~/.config/niri-shell/mode` holds `gnome` or `caelestia`. Saving the file switches
the running session (a systemd path unit watches it) and it is re-applied at every login.

- GUI: launcher entry **Switch desktop shell** (rofi in niri-gnome mode, Caelestia's launcher in Caelestia mode)
- CLI: `niri-shell caelestia`, `niri-shell gnome`, `niri-shell toggle`, `niri-shell` (show mode)

Caelestia mode stops waybar, niri-panels, swayosd, swaybg and mako, starts `niri-caelestia.service`,
and writes `$XDG_RUNTIME_DIR/niri-shell.kdl`, which niri-gnome's config.kdl includes last. It rebinds
only these keys, to the same jobs: Mod+D / Alt+F2 (launcher), Alt/Super+Tab and Alt+` (switcher),
volume, mic mute and brightness keys. Lock screen, media keys, udiskie and the overview backdrop keep running.

## niri stand-ins

- **Window previews** (bar popout, window info): niri has no per-window capture protocol, so
  `components/NiriWindowShot.qml` replaces `ScreencopyView` there and refreshes every 2 s from
  `scripts/niri-window-shot`, which grabs one frame over niri's ScreenCast D-Bus API (never the clipboard;
  `niri msg action screenshot-window` would overwrite it).
- **Switcher** (`modules/switcher`): port of niri-gnome's Python niri-switcher. Apps in MRU order, Down or
  Alt+` for the app's windows, release Alt/Super to switch. `scripts/niri-mods-held` reads evdev (needs the
  `input` group) to catch a quick tap that ends before the switcher gets focus. Debug:
  `qs -p run ipc call switcher setHold true` keeps it open until Enter/click.
- **Launcher focus**: drawers take `Exclusive` keyboard focus while the launcher/session menu is open;
  niri only gives `OnDemand` focus on click.

## Layout

| Path | What |
|---|---|
| `upstream/` | plain clone of caelestia-dots/shell (gitignored) |
| `overlay/` | niri replacements: `services/Hypr.qml` (niri event-stream backend), `components/NiriFocusGrab.qml`, `components/NiriWindowShot.qml`, `modules/switcher/`, `scripts/`, inert `CustomShortcut.qml`, Claude usage (`services/ClaudeLimits.qml` + bar entry/popout `ClaudeUsage.qml`, bar id `claudeUsage`), network + system usage (bar entry `SysUsage.qml`, bar id `sysUsage`, hover opens the dashboard Performance tab as a popout), calendar popout on clock hover (`popouts/Calendar.qml`) |
| `build.py` | builds `run/` = upstream + overlay + patches; patches must match or the build fails |
| `upstream.rev` | upstream commit this version builds against; `build.py` checks `upstream/` out at it |
| `.github/` | CI (shellcheck, build against the pin) and the release workflow |
| `overlay.lock` | upstream version each overlay file was ported from; `build.py` warns when it moves |
| `bin/niri-shell`, `systemd/`, `applications/` | the switcher, installed by `install.sh` |

## Update upstream

    ./build.py --pull    # moves upstream/ to the newest commit and pins it in upstream.rev
    systemctl --user restart niri-caelestia.service
    # WARNING about an overlay file: port the upstream diff it prints, then ./build.py --accept

The C++ plugin lives in `~/.local/opt/caelestia-niri`; rebuild it when upstream changes `plugin/`:

    cmake -S upstream -B .deps/shell-build -G Ninja -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=$HOME/.local/opt/caelestia-niri -DENABLE_MODULES="extras;plugin" \
      -DINSTALL_LIBDIR=$HOME/.local/opt/caelestia-niri/lib/caelestia \
      -DINSTALL_QMLDIR=$HOME/.local/opt/caelestia-niri/qml -DCMAKE_PREFIX_PATH=$HOME/.local/opt/caelestia-niri
    cmake --build .deps/shell-build && cmake --install .deps/shell-build

## Config

`~/.config/caelestia/shell.json` holds your overrides of upstream defaults (weather location, units, bar entries such as `claudeUsage` and `sysUsage`).

## Keep `~/.config/caelestia/cli.json`

It turns off every caelestia-cli theme applier. Without it, Caelestia's first wallpaper/scheme change
rewrites gtk.css, fuzzel, htop, cava, dconf icon theme and recolours every open terminal.

Licence: GPL-3.0 (overlay files are derived from Caelestia).
