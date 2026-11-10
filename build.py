#!/usr/bin/env python3
"""Merge upstream Caelestia + niri overlay + patches into run/.

  ./build.py           rebuild run/ from upstream/ (clones it if missing)
  ./build.py --pull    git pull upstream first
  ./build.py --accept  accept upstream changes to overridden files (after porting them)

Overlay files replace upstream files wholesale; overlay.lock remembers which
upstream version each replaced file was ported from and warns when it moves.
Patches are exact/regex edits that must match, so upstream drift fails loudly.
"""
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
UP, OVL, RUN, LOCK = ROOT / "upstream", ROOT / "overlay", ROOT / "run", ROOT / "overlay.lock"
REPO = "https://github.com/caelestia-dots/shell.git"

# (glob, regex, replacement, minimum matches across all files)
REGEX_PATCHES = [
    ("**/*.qml", r"\bproperty (?:HyprlandMonitor|HyprlandToplevel|HyprlandWorkspace) ", "property var ", 6),
    ("**/*.qml", r"\bproperty list<HyprlandToplevel> ", "property var ", 1),
    ("**/*.qml", r"\bHyprlandFocusGrab \{", "NiriFocusGrab {", 2),
]

# (file, old, new): old must occur exactly once
EXACT_PATCHES = [
    ("modules/drawers/ContentWindow.qml",
     "    mask: hasFullscreen ? emptyRegion : regions\n",
     "    mask: hasFullscreen ? emptyRegion : (focusGrab.active || panels.popouts.isDetached) ? null : regions\n"),
    ("modules/drawers/ContentWindow.qml",
     "    NiriFocusGrab {\n        id: focusGrab\n",
     "    NiriFocusGrab {\n        id: focusGrab\n\n        hitRegion: regions\n"),
    ("modules/bar/popouts/Wrapper.qml",
     "    NiriFocusGrab {\n        active: root.isDetached\n",
     "    NiriFocusGrab {\n        hitItems: [root]\n        active: root.isDetached\n"),
    # niri hands OnDemand focus to a layer surface only on click; Hyprland's focus grab gave it on open
    ("modules/drawers/ContentWindow.qml",
     "screenState.launcher || screenState.session ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None\n",
     "screenState.launcher || screenState.session ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None\n"),
    # niri has no per-window capture protocol: window previews come from components/NiriWindowShot
    ("modules/windowinfo/Preview.qml",
     "        ScreencopyView {\n            id: view\n\n            anchors.centerIn: parent\n\n            captureSource: root.client?.wayland ?? null\n",
     "        NiriWindowShot {\n            id: view\n\n            anchors.centerIn: parent\n\n            captureSource: root.client ?? null\n"),
    ("modules/bar/popouts/ActiveWindow.qml",
     "            ScreencopyView {\n                id: preview\n\n                captureSource: Hypr.activeToplevel?.wayland ?? null\n",
     "            NiriWindowShot {\n                id: preview\n\n                captureSource: Hypr.activeToplevel ?? null\n"),
    # Claude usage bar entry + popout (overlay-only files, enabled via bar.entries id "claudeUsage"); same hover branch opens the sysUsage (dashboard Performance) and clock (calendar) popouts
    ("modules/bar/Bar.qml",
     "            DelegateChoice {\n                roleValue: \"statusIcons\"\n",
     "            DelegateChoice {\n                roleValue: \"claudeUsage\"\n                delegate: EntryWrapper {\n                    ClaudeUsage {}\n                }\n            }\n"
     + "            DelegateChoice {\n                roleValue: \"statusIcons\"\n"),
    ("modules/bar/Bar.qml",
     "        } else if (id === \"activeWindow\" && ",
     "        } else if (id === \"claudeUsage\" || id === \"sysUsage\" || id === \"clock\") {\n"
     + "            popouts.currentName = id.toLowerCase();\n"
     + "            popouts.currentCenter = (ch.item as Item).mapToItem(root, 0, (ch.item as Item).implicitHeight / 2).y ?? 0;\n"
     + "            popouts.hasCurrent = true;\n"
     + "        } else if (id === \"activeWindow\" && "),
    ("modules/bar/popouts/Content.qml",
     "        Popout {\n            name: \"lockstatus\"\n",
     "        Popout {\n            name: \"claudeusage\"\n            sourceComponent: ClaudeUsage {}\n        }\n\n"
     + "        Popout {\n            name: \"sysusage\"\n            sourceComponent: Dashboard.Performance {}\n        }\n\n"
     + "        Popout {\n            name: \"clock\"\n            sourceComponent: Calendar {}\n        }\n\n"
     + "        Popout {\n            name: \"lockstatus\"\n"),
    ("modules/bar/popouts/Content.qml", "import qs.components\n", "import qs.components\nimport qs.modules.dashboard as Dashboard\n"),
    # Network + system usage bar entry (overlay-only file, enabled via bar.entries id "sysUsage")
    ("modules/bar/Bar.qml",
     "            DelegateChoice {\n                roleValue: \"claudeUsage\"\n",
     "            DelegateChoice {\n                roleValue: \"sysUsage\"\n                delegate: EntryWrapper {\n                    SysUsage {}\n                }\n            }\n"
     + "            DelegateChoice {\n                roleValue: \"claudeUsage\"\n"),
    # Alt/Super+Tab switcher (modules/switcher, overlay-only)
    ("shell.qml", "import qs.modules.lock\n", "import qs.modules.lock\nimport qs.modules.switcher\n"),
    ("shell.qml", "    AreaPicker {}\n", "    AreaPicker {}\n    Switcher {}\n"),
    # Overview workspace grips: reorder/delete (modules/wshandles + scripts/niri-ws, overlay-only)
    ("shell.qml", "import qs.modules.switcher\n", "import qs.modules.switcher\nimport qs.modules.wshandles\n"),
    ("shell.qml", "    Switcher {}\n", "    Switcher {}\n    WsHandles {}\n"),
    # niri workspaces are dynamic: the bar shows the ones that exist instead of a fixed bar.workspaces.shown
    ("modules/bar/components/workspaces/Workspaces.qml",
     "    readonly property int shown: Math.max(1, Config.bar.workspaces.shown)\n",
     "    readonly property int shown: Math.max(1, Hypr.workspaces.values.filter(w => w.monitor === monitor).length)\n"),
    # Keep awake toggle: niri only honours idle inhibitors on visible surfaces, Caelestia's is a 0x0 window, so gate the idle timers directly
    ("daemons/IdleMonitors.qml", "import Caelestia.Services\n", "import Caelestia.Services\nimport Caelestia.State\n"),
    ("daemons/IdleMonitors.qml",
     "    readonly property bool enabled: {\n",
     "    readonly property bool enabled: {\n        if (RuntimeState.inhibitIdle)\n            return false;\n"),
]


def git(*args: str) -> str:
    return subprocess.run(["git", "-C", str(UP), *args], check=True, capture_output=True, text=True).stdout.strip()


def blob(rel: str) -> str | None:
    try:
        return git("rev-parse", f"HEAD:{rel}")
    except subprocess.CalledProcessError:
        return None


def main() -> int:
    if not UP.exists():
        subprocess.run(["git", "clone", REPO, str(UP)], check=True)
    if "--pull" in sys.argv:
        print(git("pull", "--ff-only"))

    lock = json.loads(LOCK.read_text()) if LOCK.exists() else {}
    accept = "--accept" in sys.argv
    drift = []
    overlay_files = sorted(p.relative_to(OVL).as_posix() for p in OVL.rglob("*") if p.is_file())
    for rel in overlay_files:
        cur = blob(rel)
        if cur is None:
            continue  # new file, nothing upstream to track
        old = lock.get(rel)
        if old and old != cur and not accept:
            drift.append((rel, old, cur))
        elif not old or accept:
            lock[rel] = cur
    lock = {k: v for k, v in lock.items() if k in overlay_files}
    LOCK.write_text(json.dumps(lock, indent=2, sort_keys=True) + "\n")

    tmp = RUN.with_name("run.tmp")
    shutil.rmtree(tmp, ignore_errors=True)
    shutil.copytree(UP, tmp, ignore=shutil.ignore_patterns(".git", "build", "nix", "flake.*"))
    shutil.copytree(OVL, tmp, dirs_exist_ok=True)

    errors = []
    for glob, pat, rep, minimum in REGEX_PATCHES:
        total = 0
        for f in tmp.glob(glob):
            if f.relative_to(tmp).as_posix() in overlay_files:
                continue
            s = f.read_text()
            s2, n = re.subn(pat, rep, s)
            if n:
                f.write_text(s2)
                total += n
        if total < minimum:
            errors.append(f"regex patch {pat!r}: {total} matches, expected >= {minimum}")
    for rel, old, new in EXACT_PATCHES:
        f = tmp / rel
        s = f.read_text() if f.exists() else ""
        n = s.count(old)
        if n != 1:
            errors.append(f"patch {rel}: anchor found {n}x, expected 1:\n{old}")
            continue
        f.write_text(s.replace(old, new))

    leftovers = [f.relative_to(tmp).as_posix() for f in tmp.rglob("*.qml")
                 if f.relative_to(tmp).as_posix() not in overlay_files and re.search(r"\bHyprland(?:Monitor|Toplevel|Workspace|FocusGrab)\b", f.read_text())]
    if leftovers:
        errors.append("Hyprland types still used in: " + ", ".join(leftovers))

    if errors:
        shutil.rmtree(tmp)
        print("BUILD FAILED, upstream changed under a patch:\n- " + "\n- ".join(errors), file=sys.stderr)
        return 1

    # swap in one go so a running qs (watchFiles) reloads once, onto a complete tree
    old_run = RUN.with_name("run.old")
    shutil.rmtree(old_run, ignore_errors=True)
    if RUN.exists():
        RUN.rename(old_run)
    tmp.rename(RUN)
    shutil.rmtree(old_run, ignore_errors=True)

    print(f"run/ built from upstream {git('rev-parse', '--short', 'HEAD')} + {len(overlay_files)} overlay files + patches")
    for rel, old, new in drift:
        print(f"\nWARNING: upstream changed {rel}, which the overlay replaces. Port it, then ./build.py --accept")
        print(f"  git -C upstream diff {old[:12]} {new[:12]}")
    return 2 if drift else 0


if __name__ == "__main__":
    sys.exit(main())
