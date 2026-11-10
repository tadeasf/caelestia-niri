#!/usr/bin/python3
"""Scenario test for overlay/scripts/niri-ws against a nested niri (NIRI_SOCKET must point at it)."""
import json
import subprocess
import sys
import time

SCRIPT = sys.argv[1]


def q(what):
    return json.loads(subprocess.check_output(["niri", "msg", "-j", what]))


def state():
    wins = q("windows")
    out = []
    for w in sorted(q("workspaces"), key=lambda w: w["idx"]):
        titles = sorted(x["title"] for x in wins if x["workspace_id"] == w["id"])
        out.append((w["name"], titles, w["is_focused"]))
    return out


def by_idx(i):
    return next(w["id"] for w in q("workspaces") if w["idx"] == i)


def run(*args):
    subprocess.run([SCRIPT, *map(str, args)], check=True)
    time.sleep(0.2)
    s = state()
    print(" ".join(args[0:1]), args[1:], "->", " | ".join(f"{n}{t}{'*' if f else ''}" for n, t, f in s))
    names = [n for n, _, _ in s]
    assert names[:3] == ["1", "2", "3"], names
    assert len(names) >= 4 and all(n is None for n in names[3:]), names
    return [t for _, t, _ in s]


ids = {w["title"]: w["id"] for w in q("windows")}
for title, ws in (("winA", 1), ("winB", 2), ("winC", 4)):
    subprocess.run(["niri", "msg", "action", "move-window-to-workspace", "--window-id", str(ids[title]), "--focus", "false", str(ws)], check=True)
subprocess.run(["niri", "msg", "action", "focus-workspace", "1"], check=True)
time.sleep(0.3)
print("start ->", state())

t = run("move", by_idx(1), 3)
assert t[:5] == [["winB"], [], ["winA"], ["winC"], []], t
t = run("move", by_idx(4), 2)  # an unnamed workspace takes a named slot
assert t[:5] == [["winB"], ["winC"], [], ["winA"], []], t
t = run("delete", by_idx(2))  # windows go to the workspace above
assert t[:4] == [["winB", "winC"], [], ["winA"], []], t
t = run("delete", by_idx(1))  # first one: windows go below
assert t[:4] == [["winB", "winC"], ["winA"], [], []], t
t = run("delete", by_idx(4))  # empty named: still four left
assert t[:4] == [["winB", "winC"], ["winA"], [], []], t
t = run("move", by_idx(1), 99)  # clamped to the end
assert ["winB", "winC"] in t and t[0] == ["winA"], t
t2 = run("move", by_idx(len(t)), 1)  # niri ignores moving its trailing empty workspace
assert t2 == t, t2
subprocess.run([SCRIPT, "renumber"], check=True)
assert subprocess.run([SCRIPT, "delete", "99999"]).returncode != 0
print("ALL OK")
