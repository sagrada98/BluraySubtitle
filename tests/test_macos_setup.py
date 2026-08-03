"""Static contract tests for the macOS environment setup script."""

from __future__ import annotations

import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
SETUP_SCRIPT = REPOSITORY_ROOT / "setup_macos_environment.sh"
SETTINGS_FILE = REPOSITORY_ROOT / "src" / "core" / "settings.py"
SETTINGS_DIALOG_FILE = (
    REPOSITORY_ROOT
    / "src"
    / "runtime"
    / "gui_runtime_classes"
    / "settings_dialog.py"
)
ACTIONS_FILE = (
    REPOSITORY_ROOT
    / "src"
    / "runtime"
    / "gui_runtime_split"
    / "actions_and_file_dialogs.py"
)
VPY_PREVIEW_FILE = (
    REPOSITORY_ROOT
    / "src"
    / "runtime"
    / "gui_runtime_split"
    / "vpy_edit_and_preview.py"
)
README_EN = REPOSITORY_ROOT / "README.md"
README_ZH = REPOSITORY_ROOT / "README.zh-Hans.md"


class MacOSSetupTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.script = SETUP_SCRIPT.read_text(encoding="utf-8")
        cls.script_raw = SETUP_SCRIPT.read_bytes()
        cls.settings = SETTINGS_FILE.read_text(encoding="utf-8")
        cls.settings_dialog = SETTINGS_DIALOG_FILE.read_text(encoding="utf-8")
        cls.actions = ACTIONS_FILE.read_text(encoding="utf-8")
        cls.vpy_preview = VPY_PREVIEW_FILE.read_text(encoding="utf-8")
        cls.readme_en = README_EN.read_text(encoding="utf-8")
        cls.readme_zh = README_ZH.read_text(encoding="utf-8")

    def test_script_uses_utf8_and_lf(self) -> None:
        self.assertTrue(self.script)
        self.assertNotIn(b"\r", self.script_raw)

    def test_script_has_shebang_and_homebrew_install(self) -> None:
        self.assertTrue(self.script.startswith("#!/usr/bin/env bash"))
        self.assertIn("brew install", self.script)
        for package in (
            "mkvtoolnix",
            "ffmpeg",
            "flac",
            "x264",
            "x265",
            "svt-av1",
            "vapoursynth",
            "libass",
            "mpv",
        ):
            self.assertIn(package, self.script)

    def test_script_builds_rust_tools(self) -> None:
        self.assertIn("cargo install hdr10plus_tool dovi_tool", self.script)

    def test_script_builds_vapoursynth_plugins(self) -> None:
        self.assertIn("libvslsmashsource", self.script)
        self.assertIn("fmtconv", self.script)
        self.assertIn("mvsfunc", self.script)
        self.assertIn("muvsfunc", self.script)
        self.assertIn("WolframRhodium", self.script)
        self.assertIn("vapoursynth-descale", self.script)
        self.assertIn("VapourSynth-EEDI2", self.script)
        self.assertIn("vs-placebo", self.script)
        self.assertIn("vs-nlm-ispc", self.script)
        self.assertIn("vs-removegrain", self.script)
        self.assertIn("PLUGIN_DIR", self.script)
        self.assertIn("liblsmash.a", self.script)
        self.assertIn("libtool", self.script)
        self.assertIn("ispc", self.script)

    def test_script_installs_python_dependencies_in_venv(self) -> None:
        self.assertIn("-m venv", self.script)
        self.assertIn("PyQt6", self.script)
        self.assertIn("numpy", self.script)
        self.assertIn("soundfile", self.script)
        self.assertIn("pycountry", self.script)

    def test_settings_defines_macos_homebrew_paths(self) -> None:
        self.assertIn('sys.platform == "darwin"', self.settings)
        self.assertIn('"/opt/homebrew"', self.settings)
        self.assertIn(
            'os.path.join(_HOMEBREW_PREFIX, "bin", "flac")',
            self.settings,
        )

    def test_settings_dialog_points_to_macos_setup_script(self) -> None:
        self.assertIn('sys.platform == "darwin"', self.settings_dialog)
        self.assertIn('"setup_macos_environment.sh"', self.settings_dialog)

    def test_playback_supports_darwin(self) -> None:
        self.assertIn("import shutil", self.actions)
        self.assertIn("sys.platform == 'darwin'", self.actions)
        self.assertIn("run_command(['open', mpls_path])", self.actions)

    def test_vpy_editor_supports_darwin(self) -> None:
        self.assertIn("sys.platform == 'darwin'", self.vpy_preview)
        self.assertIn("run_command(['open', path], wait=False)", self.vpy_preview)

    def test_vspipe_y4m_flag_compatibility(self) -> None:
        """Newer vspipe (R57+) uses -c y4m instead of the legacy --y4m."""
        from src.runtime.services_split.encode_and_audio_tasks import (
            _vspipe_y4m_flags,
        )

        self.assertEqual(_vspipe_y4m_flags("/nonexistent/vspipe"), ("--y4m",))

    def test_readmes_synchronize_macos_support(self) -> None:
        for readme in (self.readme_en, self.readme_zh):
            self.assertIn("macOS", readme)
            self.assertIn("setup_macos_environment.sh", readme)
