import QtQuick
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.sidebar as Sidebar

// Dashboard tab: upstream's sidebar notification dock (grouped list, swipe/close per notification, clear all, click opens the app)
Item {
    id: root

    required property ScreenState screenState

    implicitWidth: 840 // WeatherTab's width, keeps the tab bar from squeezing
    implicitHeight: 560

    StyledRect {
        anchors.fill: parent

        radius: Tokens.rounding.large
        color: Colours.tPalette.m3surfaceContainerLow

        Sidebar.NotifDock {
            props: Sidebar.Props {
                reloadableId: "dashboardNotifs"
            }
            screenState: root.screenState
        }
    }
}
