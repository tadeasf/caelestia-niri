pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

ColumnLayout {
    id: root

    function until(d: date): string {
        const mins = Math.max(0, Math.round((d - ClaudeLimits.now) / 60000));
        return mins >= 60 ? `${Math.floor(mins / 60)}h ${mins % 60}m` : `${mins}m`;
    }

    function ago(d: date): string {
        const mins = Math.round((ClaudeLimits.now - d) / 60000);
        return mins < 1 ? "just now" : `${mins} min ago`;
    }

    implicitWidth: Tokens.sizes.bar.batteryWidth + 50
    spacing: Tokens.spacing.large

    Window {
        title: "Current session"
        w: ClaudeLimits.session
        segments: 5
        resets: w?.end ? `Resets in ${root.until(w.end)}` : ""
    }

    Window {
        title: "Current week"
        w: ClaudeLimits.week
        segments: 7
        resets: w?.end ? `Resets ${Qt.formatDateTime(w.end, "ddd hh:mm")}` : ""
    }

    StyledRect {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Colours.palette.m3outlineVariant
    }

    RowLayout {
        Layout.fillWidth: true

        StyledText {
            Layout.fillWidth: true
            text: ClaudeLimits.error || (ClaudeLimits.raw ? `Updated ${root.ago(ClaudeLimits.updated)}` : "Loading...")
            color: ClaudeLimits.error ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
            elide: Text.ElideRight
        }

        TextButton {
            type: TextButton.Tonal
            text: ClaudeLimits.loading ? "Refreshing" : "Refresh"
            onClicked: ClaudeLimits.refresh()
        }
    }

    component Window: ColumnLayout {
        id: win

        required property string title
        required property var w
        required property int segments
        required property string resets
        readonly property color colour: ClaudeLimits.colourFor(w)

        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        RowLayout {
            Layout.fillWidth: true

            StyledText {
                Layout.fillWidth: true
                text: win.title
                font: Tokens.font.title.small
            }

            StyledText {
                text: win.w ? `${Math.round(win.w.pct)}%` : "--"
                font: Tokens.font.title.small
            }
        }

        StyledProgressBar {
            Layout.fillWidth: true
            implicitHeight: 6
            value: (win.w?.pct ?? 0) / 100
            fgColour: win.colour
        }

        // time elapsed in the window, ticked per hour (session) / day (week)
        Item {
            Layout.fillWidth: true
            implicitHeight: 4

            StyledRect {
                anchors.fill: parent
                radius: Tokens.rounding.full
                color: Colours.palette.m3surfaceContainerHighest
            }

            StyledRect {
                width: parent.width * (win.w?.elapsed ?? 0)
                height: parent.height
                radius: Tokens.rounding.full
                color: Colours.palette.m3outline
            }

            Repeater {
                model: win.segments - 1

                StyledRect {
                    required property int index

                    x: parent.width * (index + 1) / win.segments
                    width: 2
                    height: parent.height
                    color: Colours.palette.m3surfaceContainer
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true

            StyledText {
                Layout.fillWidth: true
                text: win.w ? `${Math.abs(Math.round(win.w.diff))}% ${win.w.diff > 0 ? "ahead of" : "behind"} pace` : ""
                color: win.colour
                font: Tokens.font.body.small
            }

            StyledText {
                text: win.resets
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
            }
        }
    }
}
