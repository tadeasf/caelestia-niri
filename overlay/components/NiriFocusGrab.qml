import QtQuick

// Stand-in for HyprlandFocusGrab on niri (no focus-grab protocol). Sits behind the
// host window's content; while active, a press that lands on nothing else and is
// outside hitRegion's panels / hitItems emits cleared(). The host window must take
// input everywhere while active (ContentWindow's mask is patched to null for that).
Item {
    id: root

    property bool active
    property var windows: []
    // Caelestia's drawers Regions: outside its base rect = bar/frame, its children = open panels.
    property var hitRegion: null
    property var hitItems: []

    signal cleared

    function inside(x: real, y: real): bool {
        const r = hitRegion;
        if (r) {
            if (x < r.x || y < r.y || x > r.x + r.width || y > r.y + r.height)
                return true;
            for (const c of r.regions)
                if (c.width > 0 && c.height > 0 && x >= c.x && x <= c.x + c.width && y >= c.y && y <= c.y + c.height)
                    return true;
        }
        for (const it of hitItems) {
            if (!it?.visible)
                continue;
            const p = it.mapToItem(root, 0, 0);
            if (x >= p.x && x <= p.x + it.width && y >= p.y && y <= p.y + it.height)
                return true;
        }
        return false;
    }

    parent: windows[0]?.contentItem ?? null
    anchors.fill: parent
    z: -1000

    MouseArea {
        anchors.fill: parent
        enabled: root.active
        acceptedButtons: Qt.AllButtons
        onPressed: mouse => {
            if (root.inside(mouse.x, mouse.y)) {
                mouse.accepted = false;
                return;
            }
            root.cleared();
        }
    }
}
