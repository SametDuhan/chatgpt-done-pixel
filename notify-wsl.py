#!/usr/bin/env python3
"""Codex notify adapter: retain the old handler, launch a local Windows overlay."""
import json
import pathlib
import subprocess
import sys


def main():
    if len(sys.argv) != 2:
        return
    state = json.loads(pathlib.Path(__file__).with_name("install-state.json").read_text())
    payload = sys.argv[1]
    previous = state.get("original_command", [])
    if previous:
        try:
            subprocess.run(previous + [payload], timeout=10, check=False,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except (OSError, subprocess.TimeoutExpired):
            pass
    try:
        event = json.loads(payload)
    except (ValueError, TypeError):
        return
    if not isinstance(event, dict) or event.get("type") != "agent-turn-complete":
        return
    subprocess.Popen(["powershell.exe", "-NoProfile", "-STA", "-ExecutionPolicy", "Bypass",
                      "-WindowStyle", "Hidden", "-File", state["windows_script"],
                      "-Scale", str(state["scale"]), "-Speed", str(state["speed"])],
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)


if __name__ == "__main__":
    main()
