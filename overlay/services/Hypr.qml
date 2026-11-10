pragma Singleton
pragma ComponentBehavior: Bound

// niri backend for Caelestia's Hyprland service. Same public API as upstream
// services/Hypr.qml, fed by `niri msg -j event-stream`. Objects mimic the
// HyprlandMonitor/Workspace/Toplevel fields Caelestia reads (incl. lastIpcObject).
// niri has no special workspaces, global shortcuts or Hyprland options: those
// parts are inert.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia.I18n

Singleton {
    id: root

    property var toplevels: ({ values: [] })
    property var workspaces: ({ values: [] })
    property var monitors: ({ values: [] })
    readonly property bool usingLua: false

    property var activeToplevel: null
    property var focusedWorkspace: null
    property var focusedMonitor: null
    readonly property int activeWsId: focusedWorkspace?.id ?? 1
    property bool overviewOpen: false

    property bool capsLock: false
    property bool numLock: false
    property var kbNames: []
    property int kbIdx: 0
    readonly property string defaultKbLayout: kbMap.get(kbNames[0] ?? "") ?? "??"
    readonly property string kbLayoutFull: kbNames[kbIdx] ?? Tr.trCtx("Unknown", "keyboard layout")
    readonly property string kbLayout: kbMap.get(kbLayoutFull) ?? "??"
    readonly property var kbMap: new Map()

    readonly property alias extras: extras
    readonly property alias options: extras.options
    readonly property alias devices: extras.devices

    property string lastSpecialWorkspace: ""

    signal configReloaded

    // raw niri state
    property var _ws: []
    property var _win: ({})
    property var _out: ({})
    readonly property var _wsObjs: ({})
    readonly property var _winObjs: ({})
    readonly property var _monObjs: ({})

    function action(...args): void {
        Quickshell.execDetached(["niri", "msg", "action", ...args.map(String)]);
    }

    // Translates the Hyprland dispatch strings Caelestia sends; unknown ones are logged.
    function dispatch(request: string): void {
        let m;
        if ((m = request.match(/^workspace r([+-])1$/)))
            action(m[1] === "+" ? "focus-workspace-down" : "focus-workspace-up");
        else if ((m = request.match(/^workspace (\d+)$/)))
            focusWorkspace(parseInt(m[1]));
        else if (request === "dpms off")
            action("power-off-monitors");
        else if (request === "dpms on")
            action("power-on-monitors");
        else if ((m = request.match(/^killwindow address:0x(\d+)$/)))
            action("close-window", "--id", m[1]);
        else if ((m = request.match(/^togglefloating address:0x(\d+)$/)))
            action("toggle-window-floating", "--id", m[1]);
        else if ((m = request.match(/^movetoworkspace (\d+),address:0x(\d+)$/)))
            action("move-window-to-workspace", "--window-id", m[2], _niriWsRef(parseInt(m[1])));
        else if (!request.startsWith("togglespecialworkspace") && !request.startsWith("pin "))
            console.warn("Hypr(niri): unsupported dispatch:", request);
    }

    function _niriWsRef(id: int): string {
        const w = workspaces.values.find(w => w.id === id);
        return w ? String(w.niriName || w.idx) : String(id);
    }

    function focusWorkspace(ws: var): void {
        action("focus-workspace", _niriWsRef(parseInt(ws)));
    }

    function toggleSpecial(name: string): void {
    }

    function cycleSpecialWorkspace(direction: string): void {
    }

    function monitorNames(): list<string> {
        return monitors.values.map(e => e.name);
    }

    function monitorFor(screen: ShellScreen): var {
        return monitors.values.find(m => m.name === screen?.name) ?? null;
    }

    function trimWsName(name: string): string {
        return name.startsWith("special:") ? name.slice("special:".length) : name;
    }

    function toplevelsForWs(ws: int, ignoredTags = []): var {
        return toplevels.values.filter(t => t.workspace && t.workspace.id === ws && !isToplevelIgnored(t, ignoredTags));
    }

    function isToplevelIgnored(toplevel: var, ignoredTags = []): bool {
        return !toplevel?.lastIpcObject?.class;
    }

    function reloadDynamicConfs(): void {
    }

    function _same(a: var, b: var): bool {
        return JSON.stringify(a) === JSON.stringify(b);
    }

    // Assign only on change so bindings don't churn; plain data objects compare by content.
    function _set(obj: var, prop: string, value: var): void {
        if (obj[prop] !== value)
            obj[prop] = value;
    }

    function _setData(obj: var, prop: string, value: var): void {
        if (!_same(obj[prop], value))
            obj[prop] = value;
    }

    function _sync(store: var, keys: var, comp: Component): void {
        for (const k of Object.keys(store))
            if (!keys.includes(k)) {
                store[k].destroy();
                delete store[k];
            }
        for (const k of keys)
            if (!store[k])
                store[k] = comp.createObject(root);
    }

    // shortcut: workspace ids are niri idx on the first output and idx + 100 * n on others; fine for one or two monitors, revisit if ids collide.
    function _rebuild(): void {
        const outNames = Object.keys(_out);
        for (const w of _ws)
            if (w.output && !outNames.includes(w.output))
                outNames.push(w.output);
        outNames.sort((a, b) => (_out[a]?.logical?.x ?? 0) - (_out[b]?.logical?.x ?? 0));

        _sync(_monObjs, outNames, monComp);
        const wsKeys = _ws.map(w => String(w.id));
        _sync(_wsObjs, wsKeys, wsComp);
        const winKeys = Object.keys(_win);
        _sync(_winObjs, winKeys, winComp);

        const monList = outNames.map((n, i) => {
            const m = _monObjs[n];
            const l = _out[n]?.logical ?? {};
            _set(m, "id", i);
            _set(m, "name", n);
            _set(m, "x", l.x ?? 0);
            _set(m, "y", l.y ?? 0);
            _set(m, "width", l.width ?? 0);
            _set(m, "height", l.height ?? 0);
            _set(m, "scale", l.scale ?? 1);
            return m;
        });

        const wsList = [..._ws].sort((a, b) => outNames.indexOf(a.output) - outNames.indexOf(b.output) || a.idx - b.idx).map(raw => {
            const w = _wsObjs[String(raw.id)];
            const oi = Math.max(0, outNames.indexOf(raw.output));
            const id = raw.idx + 100 * oi;
            _set(w, "niriId", raw.id);
            _set(w, "idx", raw.idx);
            _set(w, "niriName", raw.name ?? "");
            _set(w, "id", id);
            _set(w, "name", raw.name ?? String(id));
            _set(w, "monitor", _monObjs[raw.output] ?? null);
            _set(w, "active", raw.is_active);
            _set(w, "focused", raw.is_focused);
            _set(w, "urgent", raw.is_urgent);
            return w;
        });

        let focusedWin = null;
        const tlList = winKeys.map(k => {
            const raw = _win[k];
            const t = _winObjs[k];
            const ws = _wsObjs[String(raw.workspace_id)] ?? null;
            const mon = ws?.monitor;
            const lay = raw.layout ?? {};
            const size = lay.window_size ?? [0, 0];
            const tp = lay.tile_pos_in_workspace_view;
            const off = lay.window_offset_in_tile ?? [0, 0];
            const fs = !raw.is_floating && mon && size[0] >= mon.width && size[1] >= mon.height;
            _set(t, "address", String(raw.id));
            _set(t, "title", raw.title ?? "");
            _set(t, "workspace", ws);
            _set(t, "monitor", mon ?? null);
            _set(t, "activated", raw.is_focused);
            _setData(t, "lastIpcObject", {
                address: String(raw.id),
                class: raw.app_id ?? "",
                initialClass: raw.app_id ?? "",
                title: raw.title ?? "",
                pid: raw.pid ?? -1,
                mapped: true,
                hidden: false,
                floating: raw.is_floating,
                fullscreen: fs ? 2 : 0,
                urgent: raw.is_urgent,
                tags: [],
                at: tp ? [Math.round(tp[0] + off[0] + (mon?.x ?? 0)), Math.round(tp[1] + off[1] + (mon?.y ?? 0))] : [0, 0],
                size: size,
                workspace: { id: ws?.id ?? -1, name: ws?.name ?? "" },
                monitor: mon?.id ?? -1
            });
            if (raw.is_focused)
                focusedWin = t;
            return t;
        });

        for (const w of wsList) {
            const tl = tlList.filter(t => t.workspace === w);
            if (tl.length !== w.toplevels.values.length || tl.some((t, i) => t !== w.toplevels.values[i]))
                w.toplevels = { values: tl };
            _setData(w, "lastIpcObject", { id: w.id, name: w.name, monitor: w.monitor?.name ?? "", windows: tl.length });
        }

        let focusedWs = wsList.find(w => w.focused) ?? null;
        for (const m of monList) {
            _set(m, "activeWorkspace", wsList.find(w => w.monitor === m && w.active) ?? null);
            _set(m, "focused", focusedWs?.monitor === m);
        }

        const same = (a, b) => a.length === b.length && a.every((x, i) => x === b[i]);
        if (!same(monitors.values, monList))
            monitors = { values: monList };
        if (!same(workspaces.values, wsList))
            workspaces = { values: wsList };
        if (!same(toplevels.values, tlList))
            toplevels = { values: tlList };

        focusedWorkspace = focusedWs;
        focusedMonitor = focusedWs?.monitor ?? monList[0] ?? null;
        activeToplevel = focusedWin && focusedWin.workspace === focusedWs ? focusedWin : null;
    }

    function _schedule(): void {
        Qt.callLater(root._rebuild);
    }

    function _handle(ev: var): void {
        const [name] = Object.keys(ev);
        const e = ev[name];
        switch (name) {
        case "WorkspacesChanged":
            _ws = e.workspaces;
            if (e.workspaces.some(w => w.output && !_out[w.output]))
                outputsProc.running = true;
            break;
        case "WorkspaceActivated": {
            const target = _ws.find(w => w.id === e.id);
            for (const w of _ws) {
                if (target && w.output === target.output)
                    w.is_active = w.id === e.id;
                if (e.focused)
                    w.is_focused = w.id === e.id;
            }
            break;
        }
        case "WorkspaceActiveWindowChanged": {
            const w = _ws.find(w => w.id === e.workspace_id);
            if (w)
                w.active_window_id = e.active_window_id;
            break;
        }
        case "WorkspaceUrgencyChanged": {
            const w = _ws.find(w => w.id === e.id);
            if (w)
                w.is_urgent = e.urgent;
            break;
        }
        case "WindowsChanged":
            _win = {};
            for (const w of e.windows)
                _win[String(w.id)] = w;
            break;
        case "WindowOpenedOrChanged":
            if (e.window.is_focused)
                for (const w of Object.values(_win))
                    w.is_focused = false;
            _win[String(e.window.id)] = e.window;
            break;
        case "WindowClosed":
            delete _win[String(e.id)];
            break;
        case "WindowFocusChanged":
            for (const w of Object.values(_win))
                w.is_focused = w.id === e.id;
            break;
        case "WindowFocusTimestampChanged":
            if (_win[String(e.id)])
                _win[String(e.id)].focus_timestamp = e.focus_timestamp;
            return; // only read by NotifData.activate, no rebuild needed
        case "WindowUrgencyChanged":
            if (_win[String(e.id)])
                _win[String(e.id)].is_urgent = e.urgent;
            break;
        case "WindowLayoutsChanged":
            for (const [id, layout] of e.changes)
                if (_win[String(id)])
                    _win[String(id)].layout = layout;
            break;
        case "KeyboardLayoutsChanged":
            kbNames = e.keyboard_layouts.names;
            kbIdx = e.keyboard_layouts.current_idx;
            return;
        case "KeyboardLayoutSwitched":
            kbIdx = e.idx;
            return;
        case "OverviewOpenedOrClosed":
            overviewOpen = e.is_open;
            return;
        case "ConfigLoaded":
            root.configReloaded();
            outputsProc.running = true;
            return;
        default:
            return;
        }
        _schedule();
    }

    Process {
        id: eventStream

        running: true
        command: ["niri", "msg", "-j", "event-stream"]
        stdout: SplitParser {
            onRead: data => {
                try {
                    root._handle(JSON.parse(data));
                } catch (err) {
                    console.warn("Hypr(niri): bad event:", err, data.slice(0, 200));
                }
            }
        }
        onExited: restartTimer.start()
    }

    Timer {
        id: restartTimer

        interval: 1000
        onTriggered: eventStream.running = true
    }

    Process {
        id: outputsProc

        running: true
        command: ["niri", "msg", "-j", "outputs"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root._out = JSON.parse(text);
                    root._schedule();
                } catch (err) {
                    console.warn("Hypr(niri): bad outputs:", err);
                }
            }
        }
    }

    Component.onCompleted: {
        const out = {};
        for (const s of Quickshell.screens)
            out[s.name] = { logical: { x: s.x, y: s.y, width: s.width, height: s.height, scale: 1 } };
        _out = out;
        _rebuild();
    }

    Connections {
        function onScreensChanged(): void {
            outputsProc.running = true;
        }

        target: Quickshell
    }

    // Lock LEDs: sysfs has no change notifications, so poll the tiny files.
    Process {
        id: ledProc

        command: ["sh", "-c", "for f in /sys/class/leds/*::capslock/brightness; do cat \"$f\"; done | sort -r | head -1; for f in /sys/class/leds/*::numlock/brightness; do cat \"$f\"; done | sort -r | head -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const [c, n] = text.trim().split("\n");
                root.capsLock = c === "1";
                root.numLock = n === "1";
            }
        }
    }

    Timer {
        running: true
        repeat: true
        triggeredOnStart: true
        interval: 500
        onTriggered: ledProc.running = true
    }

    FileView {
        id: kbLayoutFile

        path: Quickshell.env("CAELESTIA_XKB_RULES_PATH") || "/usr/share/X11/xkb/rules/base.lst"
        onLoaded: {
            const layoutMatch = text().match(/! layout\n([\s\S]*?)\n\n/);
            if (layoutMatch) {
                for (const line of layoutMatch[1].split("\n")) {
                    const match = line.match(/^\s*([a-z]{2,})\s+([a-zA-Z() ]+)$/);
                    if (match)
                        root.kbMap.set(match[2], match[1]);
                }
            }

            const variantMatch = text().match(/! variant\n([\s\S]*?)\n\n/);
            if (variantMatch) {
                for (const line of variantMatch[1].split("\n")) {
                    const match = line.match(/^\s*([a-zA-Z0-9_-]+)\s+([a-z]{2,}): (.+)$/);
                    if (match)
                        root.kbMap.set(match[3], match[2]);
                }
            }
            root.kbMapChanged();
        }
    }

    IpcHandler {
        function refreshDevices(): void {
        }

        function cycleSpecialWorkspace(direction: string): void {
        }

        function listSpecialWorkspaces(): string {
            return "";
        }

        function debug(): string {
            return JSON.stringify({
                monitors: root.monitors.values.map(m => ({ id: m.id, name: m.name, focused: m.focused, activeWs: m.activeWorkspace?.id })),
                workspaces: root.workspaces.values.map(w => ({ id: w.id, name: w.name, mon: w.monitor?.name, active: w.active, windows: w.toplevels.values.length })),
                toplevels: root.toplevels.values.map(t => ({ addr: t.address, cls: t.lastIpcObject.class, ws: t.workspace?.id, wayland: !!t.wayland, fs: t.lastIpcObject.fullscreen })),
                focusedWs: root.focusedWorkspace?.id,
                active: root.activeToplevel?.title ?? null,
                kb: root.kbLayout,
                caps: root.capsLock,
                num: root.numLock,
                waylandToplevels: ToplevelManager.toplevels.values.map(t => t.appId + " | " + t.title)
            }, null, 1);
        }

        target: "hypr"
    }

    // Inert stand-in for HyprExtras (Hyprland keywords/options/devices).
    QtObject {
        id: extras

        property var options: ({})
        property var devices: ({ keyboards: [] })

        function message(msg: string): void {
        }

        function batchMessage(msgs: var): void {
        }

        function applyOptions(opts: var): void {
        }

        function refreshOptions(): void {
        }

        function refreshDevices(): void {
        }
    }

    Component {
        id: monComp

        QtObject {
            property int id
            property string name
            property real x
            property real y
            property real width
            property real height
            property real scale: 1
            property bool focused
            property var activeWorkspace: null
            readonly property var lastIpcObject: ({ specialWorkspace: { id: 0, name: "" } })
        }
    }

    Component {
        id: wsComp

        QtObject {
            property int id
            property int niriId
            property int idx
            property string niriName
            property string name
            property var monitor: null
            property bool active
            property bool focused
            property bool urgent
            property var toplevels: ({ values: [] })
            property var lastIpcObject: ({ windows: 0 })
        }
    }

    Component {
        id: winComp

        QtObject {
            id: tl

            property string address
            property string title
            property var workspace: null
            property var monitor: null
            property bool activated
            property var lastIpcObject: ({})
            readonly property var wayland: ToplevelManager.toplevels.values.find(t => t.appId === tl.lastIpcObject.class && t.title === tl.title) ?? null
        }
    }
}
