#!/usr/bin/env bash
# setup_macos_environment.sh
#
# Installs the runtime tools required by BluraySubtitle on macOS through
# Homebrew. Run it from anywhere:
#
#   chmod +x setup_macos_environment.sh
#   ./setup_macos_environment.sh
#
# You can preset BLURAY_LANG=en or BLURAY_LANG=zh to skip the prompt.

# Resolve the repository root from the script location so this works when
# invoked from any directory.
BLURAY_SETUP_SOURCE="${BLURAY_SETUP_SOURCE:-${BASH_SOURCE[0]:-$0}}"
BLURAY_SETUP_DIR="$(cd -- "$(dirname -- "$BLURAY_SETUP_SOURCE")" >/dev/null 2>&1 && pwd)"

set -euo pipefail

# If this file was transferred with CRLF line endings, rewrite it to a
# temporary LF copy and re-execute so the shebang and logic stay valid.
if grep -q $'\r' "$BLURAY_SETUP_SOURCE"; then
  tmp_file="$(mktemp /tmp/bluraysubtitle-setup.XXXXXX)"
  tr -d '\r' < "$BLURAY_SETUP_SOURCE" > "$tmp_file"
  chmod +x "$tmp_file"
  BLURAY_SETUP_SOURCE="$BLURAY_SETUP_SOURCE" exec "$tmp_file" "$@"
fi

# ---------------------------------------------------------------------------
# Language selection
# ---------------------------------------------------------------------------
BLURAY_LANG="${BLURAY_LANG:-}"

select_language() {
  if [[ -n "$BLURAY_LANG" ]]; then
    return
  fi
  if [[ ! -t 0 ]]; then
    BLURAY_LANG="en"
    return
  fi
  echo ""
  echo "Please select a language / 请选择语言："
  echo "  1) English"
  echo "  2) 简体中文"
  echo ""
  local choice
  while true; do
    read -r -p "Enter 1 or 2 (default: 1): " choice
    choice="${choice:-1}"
    case "$choice" in
      1) BLURAY_LANG="en"; break ;;
      2) BLURAY_LANG="zh"; break ;;
      *) echo "Invalid input, please enter 1 or 2." ;;
    esac
  done
  echo ""
}

# msg <english_text> <chinese_text>
# Returns the string for the currently selected language.
msg() {
  if [[ "${BLURAY_LANG:-en}" == "zh" ]]; then
    printf '%s' "$2"
  else
    printf '%s' "$1"
  fi
}

die()      { echo -e "\n[BluraySubtitle][ERROR] $*\n" >&2; exit 1; }
log_blue() { printf "\n\033[34m[BluraySubtitle][SETUP] %s\033[0m\n\n" "$*"; }

select_language

# ---------------------------------------------------------------------------
# Platform check
# ---------------------------------------------------------------------------
if [[ "$(uname -s)" != "Darwin" ]]; then
  die "$(msg "This script supports macOS only." "此脚本仅支持 macOS。")"
fi

case "$(uname -m)" in
  arm64)  BREW_PREFIX="/opt/homebrew" ;;
  x86_64) BREW_PREFIX="/usr/local" ;;
  *) die "$(msg "Unsupported CPU architecture." "不支持的 CPU 架构。")" ;;
esac
BREW_BIN="$BREW_PREFIX/bin/brew"

# ---------------------------------------------------------------------------
# Xcode Command Line Tools
# ---------------------------------------------------------------------------
if ! xcode-select -p >/dev/null 2>&1; then
  log_blue "$(msg "Installing Xcode Command Line Tools. Complete the installer window, then run this script again." "正在安装 Xcode 命令行工具,请在弹出的安装窗口中完成安装,然后重新运行本脚本。")"
  xcode-select --install
  exit 0
fi

# ---------------------------------------------------------------------------
# Homebrew
# ---------------------------------------------------------------------------
if [[ ! -x "$BREW_BIN" ]]; then
  log_blue "$(msg "Homebrew not found; installing Homebrew. This may require your password." "未找到 Homebrew,正在安装。可能需要输入密码。")"
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [[ ! -x "$BREW_BIN" ]]; then
    die "$(msg "Homebrew installation failed. Install it manually and rerun this script." "Homebrew 安装失败,请手动安装后重新运行本脚本。")"
  fi
fi
export PATH="$BREW_PREFIX/bin:$PATH"

# ---------------------------------------------------------------------------
# Core tools via Homebrew
# ---------------------------------------------------------------------------
BREW_PACKAGES=(mkvtoolnix ffmpeg flac x264 x265 svt-av1 fdkaac-encoder vapoursynth libass mpv)
log_blue "$(msg "Installing core tools with Homebrew..." "正在通过 Homebrew 安装核心工具...")"
brew install "${BREW_PACKAGES[@]}"

# ---------------------------------------------------------------------------
# Rust tools
# ---------------------------------------------------------------------------
# hdr10plus_tool and dovi_tool are not packaged by Homebrew and are built from
# their official upstream sources with cargo.
if ! command -v cargo >/dev/null 2>&1; then
  log_blue "$(msg "Installing Rust to build hdr10plus_tool and dovi_tool..." "正在安装 Rust 以构建 hdr10plus_tool 和 dovi_tool...")"
  brew install rust
fi
log_blue "$(msg "Building hdr10plus_tool and dovi_tool from source (this can take a while)..." "正在从源码构建 hdr10plus_tool 和 dovi_tool(可能需要较长时间)...")"
cargo install hdr10plus_tool dovi_tool

# ---------------------------------------------------------------------------
# Python dependencies
# ---------------------------------------------------------------------------
PYTHON_BIN="${PYTHON_BIN:-python3}"
if ! "$PYTHON_BIN" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' >/dev/null 2>&1; then
  die "$(msg "Python 3.9+ not found. Install it with: brew install python" "未找到 Python 3.9+,请运行 brew install python 安装。")"
fi
VENV_DIR="$BLURAY_SETUP_DIR/.venv"
if [[ ! -x "$VENV_DIR/bin/python" ]]; then
  log_blue "$(msg "Creating a virtual environment at $VENV_DIR..." "正在 $VENV_DIR 创建虚拟环境...")"
  "$PYTHON_BIN" -m venv "$VENV_DIR"
fi
"$VENV_DIR/bin/pip" install --upgrade pip
log_blue "$(msg "Installing Python packages..." "正在安装 Python 依赖包...")"
"$VENV_DIR/bin/pip" install PyQt6 numpy soundfile pycountry pillow matplotlib

# ---------------------------------------------------------------------------
# Verification against the macOS paths defined in src/core/settings.py
# ---------------------------------------------------------------------------
log_blue "$(msg "Verifying installed tools..." "正在校验已安装的工具...")"
MISSING=""
verify_tool() {
  local name="$1"
  if [[ ! -x "$BREW_PREFIX/bin/$name" ]] && ! command -v "$name" >/dev/null 2>&1; then
    MISSING="${MISSING}- $name\n"
  fi
}
for tool in flac ffmpeg ffprobe x265 x264 SvtAv1EncApp fdkaac vspipe mkvinfo mkvmerge mkvpropedit mkvextract dovi_tool hdr10plus_tool; do
  verify_tool "$tool"
done

if [[ -n "$MISSING" ]]; then
  echo ""
  echo "$(msg "The following tools are still missing:" "以下工具仍然缺失:")"
  echo -e "$MISSING"
  echo "$(msg "Check the installation output above and rerun this script." "请检查上方的安装输出,然后重新运行本脚本。")"
else
  log_blue "$(msg "All tools are installed." "所有工具已安装。")"
fi

# ---------------------------------------------------------------------------
# Unavailable tools
# ---------------------------------------------------------------------------
echo ""
echo "$(msg "Tools unavailable on macOS:" "macOS 上不可用的工具:")"
echo "$(msg "- tsMuxeR, truehdd and vsedit have no macOS builds. Remux and Encode tasks that require them will report an explicit error." "- tsMuxeR、truehdd 与 vsedit 没有 macOS 版本,需要它们的任务会报告明确错误。")"
echo "$(msg "- VapourSynth plugins (descale, VapourSynth scripts) are not installed; automatic getnative and some denoise filters may be unavailable." "- 未安装 VapourSynth 插件(descale、VapourSynth 脚本),自动 getnative 与部分降噪滤镜可能不可用。")"

# ---------------------------------------------------------------------------
# Launch
# ---------------------------------------------------------------------------
echo ""
echo "================================================================"
echo "$(msg "Setup complete. Launch BluraySubtitle with:" "安装完成。使用以下命令启动 BluraySubtitle:")"
echo "  cd $BLURAY_SETUP_DIR"
echo "  .venv/bin/python src/main.py"
echo "================================================================"
