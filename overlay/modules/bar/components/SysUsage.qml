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
            accent: Colours.palette.m3tertiary
        }

        Stat {
            icon: "arrow_upward"
            value: root.rate(NetworkUsage.uploadSpeed ?? 0)
            accent: Colours.palette.m3tertiary
        }

        Stat {
            Layout.topMargin: Tokens.spacing.small
            icon: "memory_alt"
            value: Strings.percentOne(Memory.percentage)
        }

        Stat {
            icon: "memory"
            value: Strings.percentOne(Cpu.percentage)
        }

        Stat {
            icon: "developer_board"
            value: Strings.percentOne(Gpu.percentage)
        }
    }

    component Stat: ColumnLayout {
        property string icon
        property string value
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
            color: Colours.palette.m3onSurface
            font: Tokens.font.label.small
        }
    }
}
