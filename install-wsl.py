#!/usr/bin/env python3
"""Python 3.11+, WSL. Surgical TOML edits, backup and reversible installation."""
import argparse
import datetime
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib


def slot(text):
    data = tomllib.loads(text)
    command = data.get("notify", [])
    if not isinstance(command, list) or not all(isinstance(x, str) for x in command):
        raise ValueError("notify must be an array of strings")
    table = re.search(r"(?m)^\s*\[", text)
    prefix = text[:table.start()] if table else text
    matches = list(re.finditer(r"(?m)^[ \t]*notify[ \t]*=[^\r\n]+", prefix))
    if "notify" in data and len(matches) != 1:
        raise ValueError("Put the top-level notify array on one line first")
    match = matches[0] if matches else None
    if match:
        # A multiline value cannot be surgically replaced as a single line.
        parsed = tomllib.loads(match.group())
        if parsed.get("notify") != command:
            raise ValueError("Unsupported notify syntax")
    return match, command


def replace(text, line):
    match, _ = slot(text)
    if match:
        updated = text[:match.start()] + line + text[match.end():]
        return updated.lstrip("\r\n") if not line else updated
    return line + "\n" + text if line else text


def atomic(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def install(config, target, renderer, scale, speed):
    text = config.read_text() if config.exists() else ""
    match, previous = slot(text)
    state_file = target / "install-state.json"
    command = [sys.executable, str(target / "notify-wsl.py")]
    line = "notify = " + json.dumps(command)
    if state_file.exists():
        state = json.loads(state_file.read_text())
        if state["config"] != str(config) or not match or match.group().strip() != state["installed_line"].strip():
            raise ValueError("Config changed after installation; resolve notify before reinstalling")
    else:
        state = {"config": str(config), "original_line": match.group() if match else "",
                 "original_command": previous}
    windows_script = subprocess.check_output(["wslpath", "-w", str(renderer)], text=True).strip()
    if not renderer.is_file():
        raise ValueError("Windows renderer not found")
    state.update(installed_line=line, windows_script=windows_script, scale=scale, speed=speed)
    updated = replace(text, line)
    tomllib.loads(updated)
    target.mkdir(parents=True, exist_ok=True)
    shutil.copy2(pathlib.Path(__file__).with_name("notify-wsl.py"), target / "notify-wsl.py")
    if config.exists():
        stamp = datetime.datetime.now().strftime("%Y%m%d%H%M%S%f")
        shutil.copy2(config, str(config) + ".chatgpt-done." + stamp + ".bak")
    atomic(state_file, json.dumps(state, indent=2))
    atomic(config, updated)


def uninstall(target):
    state_file = target / "install-state.json"
    if not state_file.exists():
        return
    state = json.loads(state_file.read_text())
    config = pathlib.Path(state["config"])
    text = config.read_text()
    match, _ = slot(text)
    if not match or match.group().strip() != state["installed_line"].strip():
        raise ValueError("notify changed; no files or configuration removed")
    updated = replace(text, state["original_line"])
    tomllib.loads(updated)
    shutil.copy2(config, str(config) + ".chatgpt-done.uninstall.bak")
    atomic(config, updated)
    for name in ("notify-wsl.py", "install-state.json"):
        (target / name).unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=pathlib.Path, default=pathlib.Path(os.environ.get("CODEX_HOME", str(pathlib.Path.home()/".codex")))/"config.toml")
    parser.add_argument("--target", type=pathlib.Path, default=pathlib.Path.home()/".local/share/chatgpt-done-pixel")
    parser.add_argument("--windows-script", type=pathlib.Path, default=pathlib.Path(__file__).with_name("chatgpt-done.ps1"))
    parser.add_argument("--scale", type=float, default=4)
    parser.add_argument("--speed", type=float, default=1)
    parser.add_argument("--uninstall", action="store_true")
    args = parser.parse_args()
    if not 2 <= args.scale <= 12 or not .25 <= args.speed <= 4:
        parser.error("scale: 2..12; speed: 0.25..4")
    if args.uninstall:
        uninstall(args.target.resolve())
        print("Uninstalled; previous notify restored.")
    else:
        install(args.config.resolve(), args.target.resolve(), args.windows_script.resolve(), args.scale, args.speed)
        print("Installed. Restart Codex to load notify.")


if __name__ == "__main__":
    main()
