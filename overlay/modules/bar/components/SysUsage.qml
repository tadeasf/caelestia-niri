import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.services
import qs.utils

StyledRect {
    id: root

    // Bar is 40px wide: no room for "KB/s", so K/M stands for the per-second rate
    function rate(bps: real): string {
        const kb = bps / 1024;
        if (kb < 1000)
            return `${Math.round(kb)}K`;
        const mb = kb / 1024;
        return `${mb.toFixed(mb < 10 ? 1 : 0)}M`;
    }

    // Line capacity in bytes/s (125 / 26 Mbit), the 100% mark for the network load colour
    readonly property real maxDown: 125e6 / 8
    readonly property real maxUp: 26e6 / 8

    // Normal text up to 50% load, then fades to the error colour at 100%
    function loadColour(load: real): color {
        const t = Math.min(1, Math.max(0, (load - 0.5) * 2));
        const a = Colours.palette.m3onSurface;
        const b = Colours.palette.m3error;
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1);
    }

    implicitWidth: Tokens.sizes.bar.innerWidth
    implicitHeight: layout.implicitHeight + Tokens.padding.medium * 2

    color: Colours.tPalette.m3surfaceContainer
    radius: Tokens.rounding.full

    ServiceRef {
        service: NetworkUsage
    }

    ServiceRef {
        service: Cpu
    }

    ServiceRef {
        service: Memory
    }

    ServiceRef {
        service: Gpu
    }

    ColumnLayout {
        id: layout

        anchors.centerIn: parent
        spacing: 0

        Stat {
            icon: "arrow_downward"
            value: root.rate(NetworkUsage.downloadSpeed ?? 0)
            load: (NetworkUsage.downloadSpeed ?? 0) / root.maxDown
            accent: Colours.palette.m3tertiary
        }

        Stat {
            icon: "arrow_upward"
            value: root.rate(NetworkUsage.uploadSpeed ?? 0)
            load: (NetworkUsage.uploadSpeed ?? 0) / root.maxUp
            accent: Colours.palette.m3tertiary
        }

        Stat {
            Layout.topMargin: Tokens.spacing.small
            icon: "memory_alt"
            value: Strings.percentOne(Memory.percentage)
            load: Memory.percentage
        }

        Stat {
            icon: "memory"
            value: Strings.percentOne(Cpu.percentage)
            load: Cpu.percentage
        }

        Stat {
            icon: "developer_board"
            value: Strings.percentOne(Gpu.percentage)
            load: Gpu.percentage
        }
    }

    component Stat: ColumnLayout {
        property string icon
        property string value
        property real load
        property color accent: Colours.palette.m3secondary

        Layout.alignment: Qt.AlignHCenter
        Layout.bottomMargin: Tokens.spacing.extraSmall
        spacing: 0

        MaterialIcon {
            Layout.alignment: Qt.AlignHCenter
            text: parent.icon
            color: parent.accent
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: parent.value
            color: root.loadColour(parent.load)
            font: Tokens.font.label.builders.small.scale(0.85).build()
        }
    }
}
