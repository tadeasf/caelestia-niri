import QtQuick
import Quickshell
import Quickshell.Io

// Stand-in for a ScreencopyView on a toplevel: niri has no per-window capture
// protocol, so scripts/niri-window-shot grabs frames over niri's ScreenCast API.
// Same sizing API as ScreencopyView (constraintSize, hasContent, live).
// shortcut: refreshes every 2 s instead of streaming; move back to ScreencopyView if niri adds ext-image-copy-capture.
Item {
    id: root

    property var captureSource: null // a Hypr toplevel; its address is the niri window id
    property bool live: true
    property int shotWidth: 1280 // grab width in px; smaller is cheaper for thumbnails
    property size constraintSize
    readonly property bool hasContent: img.status === Image.Ready
    // two files, alternated, so each refresh is a source change and retainWhileLoading keeps the old frame up
    readonly property string base: `${Quickshell.env("XDG_RUNTIME_DIR")}/caelestia-winshot-${Math.random().toString(36).slice(2)}`
    property int frame
    readonly property real fit: img.implicitWidth > 0 ? Math.min(constraintSize.width / img.implicitWidth, constraintSize.height / img.implicitHeight) : 0

    function shoot(): void {
        if (visible && captureSource && !proc.running)
            proc.exec([Quickshell.shellPath("scripts/niri-window-shot"), captureSource.address, `${base}-${(frame + 1) % 2}.png`, String(shotWidth)]);
    }

    implicitWidth: img.implicitWidth * fit
    implicitHeight: img.implicitHeight * fit

    onVisibleChanged: shoot()
    onCaptureSourceChanged: {
        img.source = "";
        shoot();
    }
    Component.onDestruction: Quickshell.execDetached(["rm", "-f", `${base}-0.png`, `${base}-1.png`])

    Image {
        id: img

        anchors.fill: parent
        cache: false
        asynchronous: true
        fillMode: Image.PreserveAspectFit
        mipmap: true
        retainWhileLoading: true
    }

    Process {
        id: proc

        onExited: code => {
            if (code !== 0)
                return;
            root.frame = (root.frame + 1) % 2;
            img.source = `file://${root.base}-${root.frame}.png`;
        }
    }

    Timer {
        running: root.live && root.visible && !!root.captureSource
        repeat: true
        interval: 2000
        onTriggered: root.shoot()
    }
}
