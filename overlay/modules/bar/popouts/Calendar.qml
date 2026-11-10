import QtQuick
import Quickshell
import qs.components
import qs.modules.dashboard.dash as Dash

Item {
    implicitWidth: 360
    implicitHeight: calendar.implicitHeight

    Dash.Calendar {
        id: calendar

        // Own state, so every hover opens on the current month, independent of the dashboard
        screenState: ScreenState {
            modelData: QsWindow.window?.screen ?? null
        }
    }
}
