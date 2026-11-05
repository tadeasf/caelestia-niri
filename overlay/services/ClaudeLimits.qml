pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.utils

// Claude plan usage (5h session + 7d week) from the endpoint Claude Code's /usage reads.
Singleton {
    id: root

    property var raw: null
    property string error
    property date updated
    property bool loading
    property date now: new Date()

    readonly property var session: info(raw?.five_hour, 5)
    readonly property var week: info(raw?.seven_day, 7 * 24)

    function info(w: var, hours: int): var {
        if (!w)
            return null;
        const end = w.resets_at ? new Date(w.resets_at) : null;
        const elapsed = end ? Math.min(1, Math.max(0, 1 - (end - now) / (hours * 3600000))) : 0;
        return {
            pct: w.utilization ?? 0,
            end: end,
            elapsed: elapsed,
            diff: (w.utilization ?? 0) - elapsed * 100
        };
    }

    // behind pace = good (success), ahead of pace = burning fast (error)
    function colourFor(w: var): color {
        if (!w)
            return Colours.palette.m3onSurfaceVariant;
        return w.diff > 0 ? Colours.palette.m3error : Colours.palette.m3success;
    }

    function refresh(): void {
        let token = "";
        try {
            token = JSON.parse(creds.text()).claudeAiOauth.accessToken;
        } catch (e) {}
        if (!token) {
            error = "Not logged in to Claude Code";
            return;
        }

        loading = true;
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            loading = false;
            now = new Date();
            if (xhr.status === 200) {
                try {
                    raw = JSON.parse(xhr.responseText);
                    updated = now;
                    error = "";
                } catch (e) {
                    error = "Bad response";
                }
            } else {
                // shortcut: we never refresh the OAuth token ourselves (would race Claude Code over the
                // credentials file); a 401 clears as soon as any claude session refreshes it.
                error = xhr.status === 401 ? "Token expired, start claude" : xhr.status === 0 ? "Offline" : `HTTP ${xhr.status}`;
            }
        };
        xhr.open("GET", "https://api.anthropic.com/api/oauth/usage");
        xhr.setRequestHeader("Authorization", `Bearer ${token}`);
        xhr.setRequestHeader("anthropic-beta", "oauth-2025-04-20");
        xhr.send();
    }

    FileView {
        id: creds

        path: `${Paths.home}/.claude/.credentials.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.refresh()
    }

    Timer {
        interval: 5 * 60 * 1000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Timer {
        interval: 60 * 1000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }
}
