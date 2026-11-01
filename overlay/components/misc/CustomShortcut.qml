import QtQuick

// niri has no hyprland_global_shortcuts_v1; keep the API, do nothing.
// Bind keys in niri to `qs -p <run dir> ipc call ...` instead.
QtObject {
    property string appid: "caelestia"
    property string name
    property string description
    property string triggerDescription

    signal pressed
    signal released
}
