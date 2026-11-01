pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services
import qs.utils

// GNOME-style Alt/Super+Tab for niri, a port of niri-gnome's niri-switcher: app icons
// grouped by app_id in MRU order; Down or Alt+` shows the selected app's windows.
// niri binds call `qs ipc call switcher next|prev|window|prevWindow`; while it is open,
// niri's binds are inhibited so Tab, ` and arrows are handled here directly.
Scope {
    id: root

    property var apps: [] // [{ appId, windows: [niri window JSON, MRU first] }]
    property int sel
    property int winSel: -1 // -1 while the window row is closed
    property bool shown
    property var pending: null // step to run once the window list has loaded
    property bool hold: Quickshell.env("NIRI_SWITCHER_HOLD") === "1" // debug: stay open, switch only on Enter/click

    readonly property var selApp: apps[sel] ?? null

    function wrap(i: int, n: int): int {
        return ((i % n) + n) % n;
    }

    function load(then: var): void {
        pending = then;
        listProc.running = true;
    }

    function step(d: int): void {
        if (!shown)
            load(() => sel = wrap(d > 0 && apps.length > 1 ? 1 : d, apps.length));
        else {
            winSel = -1;
            sel = wrap(sel + d, apps.length);
        }
    }

    function stepWindow(d: int): void {
        if (!shown)
            load(() => {
                sel = 0;
                winSel = wrap(d > 0 ? 1 : -1, apps[0].windows.length);
            });
        else if (winSel < 0)
            winSel = 0;
        else
            winSel = wrap(winSel + d, selApp.windows.length);
    }

    function commit(): void {
        if (!shown)
            return;
        const target = selApp.windows[Math.max(0, winSel)];
        shown = false;
        Quickshell.execDetached(["niri", "msg", "action", "focus-window", "--id", String(target.id)]);
    }

    function appName(app: var): string {
        return DesktopEntries.heuristicLookup(app.appId)?.name || app.windows[0].title || app.appId;
    }

    function appIcon(appId: string): string {
        // Steam games: app_id steam_app_<id>, icon steam_icon_<id>
        const steam = appId.startsWith("steam_app_") ? Quickshell.iconPath("steam_icon_" + appId.slice(10), true) : "";
        return steam || Icons.getAppIcon(appId, "application-x-executable");
    }

    Process {
        id: listProc

        command: ["niri", "msg", "-j", "windows"]
        stdout: StdioCollector {
            onStreamFinished: {
                const ts = w => (w.focus_timestamp?.secs ?? 0) * 1e9 + (w.focus_timestamp?.nanos ?? 0);
                const groups = new Map();
                for (const w of JSON.parse(text).sort((a, b) => ts(b) - ts(a))) {
                    const key = w.app_id || `window-${w.id}`;
                    if (!groups.has(key))
                        groups.set(key, []);
                    groups.get(key).push(w);
                }
                root.apps = [...groups].map(([appId, windows]) => ({ appId, windows }));
                if (!root.apps.length)
                    return;
                root.winSel = -1;
                root.pending?.();
                root.shown = true;
            }
        }
    }

    // exit 1 = Alt/Super already up (quick tap): switch right away
    Process {
        id: modsProc

        command: [Quickshell.shellPath("scripts/niri-mods-held")]
        onExited: code => {
            if (code === 1 && !root.hold)
                root.commit();
        }
    }

    StyledWindow {
        id: win

        name: "switcher"
        visible: root.shown
        screen: Quickshell.screens.find(s => s.name === Hypr.focusedMonitor?.name) ?? Quickshell.screens[0]

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        implicitWidth: content.implicitWidth
        implicitHeight: content.implicitHeight

        onVisibleChanged: {
            if (visible) {
                content.opacity = 0;
                reveal.restart();
            }
        }

        ShortcutInhibitor {
            window: win
            enabled: root.shown
        }

        // GNOME-like: a quick tap switches without flashing the switcher
        Timer {
            id: reveal

            interval: 120
            onTriggered: content.opacity = 1
        }

        ColumnLayout {
            id: content

            anchors.fill: parent
            spacing: Tokens.spacing.medium

            focus: true
            onActiveFocusChanged: {
                if (activeFocus)
                    modsProc.running = true;
            }

            Keys.onPressed: event => {
                const back = event.modifiers & Qt.ShiftModifier ? -1 : 1;
                switch (event.key) {
                case Qt.Key_Tab:
                    root.step(1);
                    break;
                case Qt.Key_Backtab:
                    root.step(-1);
                    break;
                case Qt.Key_QuoteLeft:
                case Qt.Key_AsciiTilde:
                case Qt.Key_Dead_Grave:
                    root.stepWindow(back);
                    break;
                case Qt.Key_Escape:
                    root.shown = false;
                    break;
                case Qt.Key_Left:
                case Qt.Key_Right:
                    if (root.winSel < 0)
                        root.step(event.key === Qt.Key_Right ? 1 : -1);
                    else
                        root.winSel = root.wrap(root.winSel + (event.key === Qt.Key_Right ? 1 : -1), root.selApp.windows.length);
                    break;
                case Qt.Key_Down:
                    if (root.winSel < 0)
                        root.winSel = 0;
                    break;
                case Qt.Key_Up:
                    root.winSel = -1;
                    break;
                case Qt.Key_Return:
                case Qt.Key_Enter:
                case Qt.Key_Space:
                    root.commit();
                    break;
                default:
                    return;
                }
                event.accepted = true;
            }

            Keys.onReleased: event => {
                if ([Qt.Key_Alt, Qt.Key_AltGr, Qt.Key_Meta, Qt.Key_Super_L, Qt.Key_Super_R].includes(event.key) && !root.hold)
                    root.commit();
            }

            StyledRect {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: appCol.implicitWidth + Tokens.padding.large * 2
                implicitHeight: appCol.implicitHeight + Tokens.padding.large * 2
                radius: Tokens.rounding.extraLarge
                color: Colours.tPalette.m3surfaceContainer

                ColumnLayout {
                    id: appCol

                    anchors.centerIn: parent
                    spacing: Tokens.spacing.small

                    Row {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: Tokens.spacing.small

                        Repeater {
                            model: root.apps

                            StyledRect {
                                id: appItem

                                required property var modelData
                                required property int index

                                implicitWidth: 96 + Tokens.padding.medium * 2
                                implicitHeight: appIconImg.implicitHeight + arrow.implicitHeight + Tokens.padding.medium * 2
                                radius: Tokens.rounding.large
                                color: index === root.sel ? Colours.palette.m3secondaryContainer : "transparent"

                                IconImage {
                                    id: appIconImg

                                    anchors.top: parent.top
                                    anchors.topMargin: Tokens.padding.medium
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    implicitSize: 96
                                    asynchronous: true
                                    source: root.appIcon(appItem.modelData.appId)
                                }

                                StyledText {
                                    id: arrow

                                    anchors.top: appIconImg.bottom
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: appItem.modelData.windows.length > 1 ? "▾" : " "
                                    color: Colours.palette.m3onSurfaceVariant
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        root.sel = appItem.index;
                                        root.winSel = -1;
                                        root.commit();
                                    }
                                }
                            }
                        }
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.maximumWidth: 480
                        text: root.selApp ? root.appName(root.selApp) : ""
                        font: Tokens.font.title.small
                        elide: Text.ElideRight
                    }
                }
            }

            StyledRect {
                Layout.alignment: Qt.AlignHCenter
                visible: root.winSel >= 0
                implicitWidth: winRow.implicitWidth + Tokens.padding.large * 2
                implicitHeight: winRow.implicitHeight + Tokens.padding.large * 2
                radius: Tokens.rounding.extraLarge
                color: Colours.tPalette.m3surfaceContainer

                Row {
                    id: winRow

                    anchors.centerIn: parent
                    spacing: Tokens.spacing.small

                    Repeater {
                        model: root.winSel >= 0 ? root.selApp.windows : []

                        StyledRect {
                            id: winItem

                            required property var modelData
                            required property int index

                            implicitWidth: 260 + Tokens.padding.medium * 2
                            implicitHeight: 160 + winTitle.implicitHeight + Tokens.spacing.small + Tokens.padding.medium * 2
                            radius: Tokens.rounding.large
                            color: index === root.winSel ? Colours.palette.m3secondaryContainer : "transparent"

                            Item {
                                id: frame

                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.margins: Tokens.padding.medium
                                height: 160

                                IconImage {
                                    anchors.centerIn: parent
                                    visible: !shot.hasContent
                                    implicitSize: 64
                                    source: root.appIcon(root.selApp.appId)
                                }

                                NiriWindowShot {
                                    id: shot

                                    anchors.centerIn: parent
                                    captureSource: ({ address: String(winItem.modelData.id) })
                                    live: false
                                    shotWidth: 520
                                    constraintSize.width: frame.width
                                    constraintSize.height: frame.height
                                }
                            }

                            StyledText {
                                id: winTitle

                                anchors.top: frame.bottom
                                anchors.topMargin: Tokens.spacing.small
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.margins: Tokens.padding.medium
                                horizontalAlignment: Text.AlignHCenter
                                text: winItem.modelData.title ?? ""
                                elide: Text.ElideRight
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    root.winSel = winItem.index;
                                    root.commit();
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "switcher"

        function next(): void {
            root.step(1);
        }

        function prev(): void {
            root.step(-1);
        }

        function window(): void {
            root.stepWindow(1);
        }

        function prevWindow(): void {
            root.stepWindow(-1);
        }

        function setHold(on: bool): void {
            root.hold = on;
        }

        function close(): void {
            root.shown = false;
        }
    }
}
