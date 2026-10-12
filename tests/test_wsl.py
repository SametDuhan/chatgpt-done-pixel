import importlib.util
import json
import pathlib
import tempfile
import unittest
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[1]
def load(name, file):
    spec = importlib.util.spec_from_file_location(name, ROOT/file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

installer = load("installer", "install-wsl.py")
notify = load("notify", "notify-wsl.py")

class Integration(unittest.TestCase):
    def test_reversible_and_preserves_later_edits(self):
        with tempfile.TemporaryDirectory() as d:
            root = pathlib.Path(d); config = root/"config.toml"; target = root/"installed"
            original = 'notify = ["old", "arg"]\nmodel = "test"\n[desktop]\nx = true\n'
            config.write_text(original)
            with patch.object(installer.subprocess, "check_output", return_value="C:\\pixel.ps1\n"):
                installer.install(config,target,ROOT/"chatgpt-done.ps1",4,1)
                installer.install(config,target,ROOT/"chatgpt-done.ps1",5,1)
            state = json.loads((target/"install-state.json").read_text())
            self.assertEqual(state["original_command"],["old","arg"])
            config.write_text(config.read_text()+"# later change\n")
            installer.uninstall(target)
            self.assertEqual(config.read_text(),original+"# later change\n")

    def test_renderer_survives_repository_move(self):
        with tempfile.TemporaryDirectory() as d:
            root = pathlib.Path(d)
            source = root / "repo" / "chatgpt-done.ps1"
            source.parent.mkdir()
            source.write_text("renderer")
            target = root / "installed"
            with patch.object(installer.subprocess, "check_output", return_value="\\\\wsl.localhost\\Ubuntu\\installed\\chatgpt-done.ps1") as convert:
                installer.install(root/"config.toml", target, source, 4, 1)
            self.assertEqual(convert.call_args.args[0][-1], str(target/"chatgpt-done.ps1"))
            source.unlink()
            self.assertEqual((target/"chatgpt-done.ps1").read_text(), "renderer")
            installer.uninstall(target)
            self.assertFalse((target/"chatgpt-done.ps1").exists())

    def test_changed_notify_not_removed(self):
        with tempfile.TemporaryDirectory() as d:
            root=pathlib.Path(d); config=root/"config.toml"; target=root/"installed"
            with patch.object(installer.subprocess,"check_output",return_value="C:\\pixel.ps1"):
                installer.install(config,target,ROOT/"chatgpt-done.ps1",4,1)
            config.write_text('notify = ["new"]\n')
            with self.assertRaises(ValueError): installer.uninstall(target)
            self.assertTrue((target/"install-state.json").exists())
            self.assertEqual(config.read_text(),'notify = ["new"]\n')

    def test_multiline_rejected(self):
        with self.assertRaises(ValueError): installer.slot('notify = [\n"x"\n]\n')

    def test_only_completed_event_animates_and_old_handler_receives_exact_payload(self):
        state=json.dumps({"original_command":["old"],"windows_script":"C:\\pixel.ps1","scale":4,"speed":1})
        for event, expected in (("agent-turn-complete",1),("approval-requested",0)):
            payload=json.dumps({"type":event,"last-assistant-message":"private \"quoted\" text"})
            with patch.object(notify.pathlib.Path,"read_text",return_value=state), patch.object(notify.sys,"argv",["notify",payload]), patch.object(notify.subprocess,"run") as previous, patch.object(notify.subprocess,"Popen") as animate:
                notify.main()
                self.assertEqual(previous.call_args.args[0],["old",payload])
                self.assertEqual(animate.call_count,expected)

if __name__ == "__main__": unittest.main()
