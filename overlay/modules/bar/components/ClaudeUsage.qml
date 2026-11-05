import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

StyledRect {
    id: root

    implicitWidth: Tokens.sizes.bar.innerWidth
    implicitHeight: layout.implicitHeight + Tokens.padding.medium * 2

    color: Colours.tPalette.m3surfaceContainer
    radius: Tokens.rounding.full

    ColumnLayout {
        id: layout

        anchors.centerIn: parent
        spacing: 0

        MaterialIcon {
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: Tokens.spacing.extraSmall
            text: "asterisk"
            color: ClaudeLimits.error ? Colours.palette.m3outline : Colours.palette.m3tertiary
        }

        Pct {
            w: ClaudeLimits.session
        }

        Pct {
            w: ClaudeLimits.week
        }
    }

    component Pct: StyledText {
        property var w

        Layout.alignment: Qt.AlignHCenter
        text: w ? `${Math.round(w.pct)}%` : "--"
        color: ClaudeLimits.colourFor(w)
        font: Tokens.font.label.small
    }
}
