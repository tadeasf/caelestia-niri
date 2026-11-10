pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services

// Grips beside each workspace in niri's overview: drag one (left or right button) to
// reorder, close button to delete. niri draws the overview itself and would lose its own
// clicks under a layer, so this only takes input on a strip right of the workspace column
// and mirrors niri's geometry: workspaces scaled by `zoom` and centred, a gap of 10% of
// their height between them, the active one in the middle. scripts/niri-ws does the work.
Variants {
    model: Quickshell.screens

    StyledWindow {
        id: win

        required property ShellScreen modelData

        // shortcut: niri's default `overview { zoom }`; read it from config.kdl if that ever gets set
        readonly property real zoom: 0.5
        readonly property real step: height * zoom * 1.1
        readonly property var monitor: Hypr.monitorFor(modelData)
        readonly property var wss: Hypr.workspaces.values.filter(w => w.monitor === monitor)
        readonly property int activeIdx: monitor?.activeWorkspace?.idx ?? 1

        property var dragged: null
        property real dragY
        readonly property int dropIdx: Math.max(1, Math.min(wss.length, activeIdx + Math.round((dragY - height / 2) / step)))
        readonly property int scrollDir: !dragged ? 0 : dragY < 40 ? -1 : dragY > height - 40 ? 1 : 0
        readonly property real gripH: strip.width * 2.4

        // top of the grip for the workspace `d` slots from the active one; the neighbours' centres
        // are off screen, so their grips are pulled in to the part of them that still shows
        function slotY(d: int): real {
            return Math.max(Tokens.padding.medium, Math.min(height - gripH - Tokens.padding.medium, height / 2 + d * step - gripH / 2));
        }

        function run(...args): void {
            Quickshell.execDetached([Quickshell.shellPath("scripts/niri-ws"), ...args.map(String)]);
        }

        name: "wshandles"
        screen: modelData
        visible: Hypr.overviewOpen
        mask: Region {
            Region {
                x: strip.x
                y: win.slotY(-1)
                width: strip.width
                height: win.gripH
            }
            Region {
                x: strip.x
                y: win.slotY(0)
                width: strip.width
                height: win.gripH
            }
            Region {
                x: strip.x
                y: win.slotY(1)
                width: strip.width
                height: win.gripH
            }
        }

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore

        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        // only the neighbours of the active workspace fit on screen: holding a grip at the edge scrolls on
        Timer {
            running: win.scrollDir !== 0
            repeat: true
            interval: 450
            onTriggered: Hypr.action(win.scrollDir < 0 ? "focus-workspace-up" : "focus-workspace-down")
        }

        Item {
            id: strip

            x: win.width * (1 + win.zoom) / 2 + Tokens.spacing.medium
            width: Tokens.font.icon.medium.pointSize * 2 + Tokens.padding.small * 2
            height: win.height

            Repeater {
                model: ScriptModel {
                    values: win.wss
                }

                StyledRect {
                    id: grip

                    required property var modelData
                    readonly property bool dragging: win.dragged === modelData

                    // further ones are off screen, scroll or drag to the edge to reach them
                    // no grip on the empty workspace niri keeps last: it can neither go away nor be moved (niri ignores it)
                    visible: (modelData.niriName !== "" || modelData.toplevels.values.length > 0) && (dragging || Math.abs(modelData.idx - win.activeIdx) <= 1)
                    width: strip.width
                    height: win.gripH
                    y: dragging ? win.dragY - height / 2 : win.slotY(modelData.idx - win.activeIdx)
                    z: dragging ? 1 : 0
                    radius: Tokens.rounding.full
                    color: dragging ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainer

                    Behavior on y {
                        enabled: !grip.dragging

                        Anim {}
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                        onPressed: mouse => {
                            win.dragY = mapToItem(strip, 0, mouse.y).y;
                            win.dragged = grip.modelData;
                        }
                        onPositionChanged: mouse => win.dragY = mapToItem(strip, 0, mouse.y).y
                        onReleased: {
                            if (win.dropIdx !== grip.modelData.idx)
                                win.run("move", grip.modelData.niriId, win.dropIdx);
                            win.dragged = null;
                        }
                        onCanceled: win.dragged = null
                    }

                    Column {
                        id: col

                        anchors.centerIn: parent
                        spacing: Tokens.spacing.small

                        MaterialIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "drag_indicator"
                            color: Colours.palette.m3onSurfaceVariant
                        }

                        StyledText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: grip.dragging ? win.dropIdx : grip.modelData.idx
                            color: Colours.palette.m3onSurface
                        }

                        IconButton {
                            anchors.horizontalCenter: parent.horizontalCenter
                            type: IconButton.Text
                            icon: "close"
                            onClicked: win.run("delete", grip.modelData.niriId)
                        }
                    }
                }
            }
        }
    }
}
