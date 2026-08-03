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
# Build dependencies (libtool/cmake/ispc) are needed to compile the
# VapourSynth plugins below. Homebrew already includes vapoursynth, but it
# ships no plugins, so every filter the default VPy needs is built from source.
BREW_PACKAGES=(mkvtoolnix ffmpeg flac x264 x265 svt-av1 fdkaac-encoder vapoursynth libass mpv \
               meson ninja cmake libtool ispc libplacebo)
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
# VapourSynth plugins (build from source into ~/plugins)
# ---------------------------------------------------------------------------
# Homebrew's vapoursynth formula ships no plugins. The default VPy requires
# L-SMASH-Works (reading), fmtconv (bit depth), mvsfunc (helper), plus the
# filters nlm_ispc, placebo, eedi2, rgvs and descale. Every step below was
# verified on macOS 24 (Apple Silicon).
PLUGIN_DIR="${PLUGIN_DIR:-$HOME/plugins}"
VS_CELLAR="$BREW_PREFIX/Cellar/vapoursynth"
VS_VERSION="$(ls "$VS_CELLAR" | sort -V | tail -n 1)"
VS_INCLUDE="$VS_CELLAR/$VS_VERSION/libexec/lib/python3.14/site-packages/vapoursynth/include"
VS_PYTHON="$VS_CELLAR/$VS_VERSION/libexec/bin/python3"

build_dir="$(mktemp -d /tmp/bluraysub-vsplugins.XXXXXX)"
trap 'rm -rf "$build_dir"' EXIT
cd "$build_dir"

# --- liblsmash (static library and headers for L-SMASH-Works) ---
# macOS clang does not accept the GNU ld --version-script used for the shared
# library, so only the static archive is built and installed.
log_blue "$(msg "Building L-SMASH library..." "正在编译 L-SMASH 库...")"
git clone --depth 1 https://github.com/l-smash/l-smash.git l-smash || die "$(msg "Failed to clone l-smash" "克隆 l-smash 失败")"
cd l-smash
./configure --enable-shared --prefix="$BREW_PREFIX" >/dev/null || die "$(msg "L-SMASH configure failed" "L-SMASH configure 失败")"
make liblsmash.a >/dev/null || die "$(msg "L-SMASH build failed" "L-SMASH 编译失败")"
cp liblsmash.a "$BREW_PREFIX/lib/"
cp lsmash.h config.h "$BREW_PREFIX/include/"
cat > "$BREW_PREFIX/lib/pkgconfig/liblsmash.pc" <<EOF
prefix=$BREW_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: liblsmash
Description: Loyal to Spec of MPEG4, and Ad-hock Simple Hackwork
Version: 2.16.1
Libs: -L\${libdir} -llsmash
Cflags: -I\${includedir}
EOF
cd "$build_dir"

# --- VapourSynth headers: API v3 + vapoursynth/ subdirectory ---
log_blue "$(msg "Preparing VapourSynth headers..." "正在准备 VapourSynth 头文件...")"
mkdir -p "$VS_INCLUDE/vapoursynth"
ln -sf "$VS_INCLUDE"/*.h "$VS_INCLUDE/vapoursynth/" 2>/dev/null || true
curl -fsSL -o "$VS_INCLUDE/VapourSynth.h" https://raw.githubusercontent.com/vapoursynth/vapoursynth/R57/include/VapourSynth.h
curl -fsSL -o "$VS_INCLUDE/VSHelper.h" https://raw.githubusercontent.com/vapoursynth/vapoursynth/R57/include/VSHelper.h

# --- L-SMASH-Works (VapourSynth source reader) ---
log_blue "$(msg "Building L-SMASH-Works (VapourSynth reader)..." "正在编译 L-SMASH-Works(VapourSynth 读取器)...")"
git clone https://github.com/HomeOfAviSynthPlusEvolution/L-SMASH-Works.git lsmash-works || die "$(msg "Failed to clone L-SMASH-Works" "克隆 L-SMASH-Works 失败")"
cd lsmash-works/VapourSynth
meson setup build --buildtype=release >/dev/null || die "$(msg "L-SMASH-Works configure failed" "L-SMASH-Works 配置失败")"
ninja -C build >/dev/null || die "$(msg "L-SMASH-Works build failed" "L-SMASH-Works 编译失败")"
cp build/libvslsmashsource.dylib "$PLUGIN_DIR/" || die "$(msg "L-SMASH-Works plugin not produced" "未生成 L-SMASH-Works 插件")"
cd "$build_dir"

# --- fmtconv (bit depth / format conversion) ---
log_blue "$(msg "Building fmtconv..." "正在编译 fmtconv...")"
git clone https://github.com/EleonoreMizo/fmtconv.git fmtconv || die "$(msg "Failed to clone fmtconv" "克隆 fmtconv 失败")"
cd fmtconv/build/unix
export PATH="$BREW_PREFIX/opt/libtool/bin:$PATH"
./autogen.sh >/dev/null 2>&1 || die "$(msg "fmtconv autogen failed" "fmtconv autogen 失败")"
./configure >/dev/null 2>&1 || die "$(msg "fmtconv configure failed" "fmtconv configure 失败")"
make -j"$(sysctl -n hw.ncpu)" >/dev/null || die "$(msg "fmtconv build failed" "fmtconv 编译失败")"
cp .libs/libfmtconv.dylib "$PLUGIN_DIR/" || die "$(msg "fmtconv plugin not produced" "未生成 fmtconv 插件")"
cd "$build_dir"

# --- mvsfunc (Python helper library) into the VapourSynth environment ---
log_blue "$(msg "Installing mvsfunc into the VapourSynth Python environment..." "正在向 VapourSynth Python 环境安装 mvsfunc...")"
git clone https://github.com/HomeOfVapourSynthEvolution/mvsfunc.git mvsfunc || die "$(msg "Failed to clone mvsfunc" "克隆 mvsfunc 失败")"
"$VS_PYTHON" -m pip install ./mvsfunc >/dev/null || die "$(msg "mvsfunc install failed" "mvsfunc 安装失败")"

# --- muvsfunc (getnative resolution detection) + numpy runtime ---
# numpy is required by mvsfunc/muvsfunc at script evaluation time and must be
# present in the VapourSynth Python environment. Homebrew's bundled pip may
# miss the wheel on the first attempt; retry against pypi.org directly.
log_blue "$(msg "Installing muvsfunc and numpy into the VapourSynth Python environment..." "正在向 VapourSynth Python 环境安装 muvsfunc 与 numpy...")"
"$VS_PYTHON" -m pip install --index-url https://pypi.org/simple numpy >/dev/null 2>&1 \
  || "$VS_PYTHON" -m pip install --index-url https://pypi.org/simple numpy >/dev/null \
  || die "$(msg "numpy install into VapourSynth Python failed" "numpy 安装到 VapourSynth Python 环境失败")"
git clone --depth 1 https://github.com/WolframRhodium/muvsfunc.git muvsfunc-repo || die "$(msg "Failed to clone muvsfunc" "克隆 muvsfunc 失败")"
cp muvsfunc-repo/muvsfunc.py "$(dirname "$(dirname "$(command -v "$VS_PYTHON")")")/lib/python3.14/site-packages/" || die "$(msg "muvsfunc install failed" "muvsfunc 安装失败")"

# --- remaining filter plugins ---
install_meson_plugin() {
  local name="$1" url="$2" out="$3"
  log_blue "$(msg "Building ${name}..." "正在编译 ${name}...")"
  git clone --depth 1 "$url" "$name" || die "$(msg "Failed to clone ${name}" "克隆 ${name} 失败")"
  cd "$name"
  meson setup build --buildtype=release >/dev/null 2>&1 || die "$(msg "${name} configure failed" "${name} 配置失败")"
  ninja -C build >/dev/null 2>&1 || die "$(msg "${name} build failed" "${name} 编译失败")"
  cp "$out" "$PLUGIN_DIR/" || die "$(msg "${name} plugin not produced" "未生成 ${name} 插件")"
  cd "$build_dir"
}

install_meson_plugin descale "https://github.com/Irrational-Encoding-Wizardry/vapoursynth-descale.git" build/libdescale.dylib
install_meson_plugin eedi2 "https://github.com/HomeOfVapourSynthEvolution/VapourSynth-EEDI2.git" build/libeedi2.dylib
install_meson_plugin vs-placebo "https://github.com/Lypheo/vs-placebo.git" build/libvs_placebo.dylib
install_meson_plugin rgvs "https://github.com/vapoursynth/vs-removegrain.git" build/libremovegrain.dylib

# --- vs-nlm-ispc (CMake + ISPC) ---
log_blue "$(msg "Building vs-nlm-ispc..." "正在编译 vs-nlm-ispc...")"
git clone --depth 1 https://github.com/AmusementClub/vs-nlm-ispc.git nlm-ispc || die "$(msg "Failed to clone vs-nlm-ispc" "克隆 vs-nlm-ispc 失败")"
cd nlm-ispc
cmake -B build -DCMAKE_BUILD_TYPE=Release >/dev/null || die "$(msg "vs-nlm-ispc configure failed" "vs-nlm-ispc 配置失败")"
cmake --build build >/dev/null || die "$(msg "vs-nlm-ispc build failed" "vs-nlm-ispc 编译失败")"
cp build/libvsnlm_ispc.dylib "$PLUGIN_DIR/" || die "$(msg "vs-nlm-ispc plugin not produced" "未生成 vs-nlm-ispc 插件")"
cd "$build_dir"

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
"$VENV_DIR/bin/pip" install --upgrade pip >/dev/null
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

MISSING_PLUGINS=""
for plugin in libvslsmashsource libfmtconv libdescale libeedi2 libvs_placebo libvsnlm_ispc libremovegrain; do
  if [[ ! -f "$PLUGIN_DIR/$plugin.dylib" ]]; then
    MISSING_PLUGINS="${MISSING_PLUGINS}- $plugin\n"
  fi
done
if ! "$VS_PYTHON" -c 'import mvsfunc' >/dev/null 2>&1; then
  MISSING_PLUGINS="${MISSING_PLUGINS}- mvsfunc (Python module)\n"
fi

if [[ -n "$MISSING" ]]; then
  echo ""
  echo "$(msg "The following tools are still missing:" "以下工具仍然缺失:")"
  echo -e "$MISSING"
  echo "$(msg "Check the installation output above and rerun this script." "请检查上方的安装输出,然后重新运行本脚本。")"
else
  log_blue "$(msg "All tools are installed." "所有工具已安装。")"
fi
if [[ -n "$MISSING_PLUGINS" ]]; then
  echo ""
  echo "$(msg "The following VapourSynth plugins are still missing:" "以下 VapourSynth 插件仍然缺失:")"
  echo -e "$MISSING_PLUGINS"
  echo "$(msg "Check the plugin build output above and rerun this script." "请检查上方的插件编译输出,然后重新运行本脚本。")"
else
  log_blue "$(msg "All VapourSynth plugins are installed in $PLUGIN_DIR" "所有 VapourSynth 插件已安装到 $PLUGIN_DIR")"
fi

# ---------------------------------------------------------------------------
# Unavailable tools
# ---------------------------------------------------------------------------
echo ""
echo "$(msg "Tools unavailable on macOS:" "macOS 上不可用的工具:")"
echo "$(msg "- tsMuxeR, truehdd and vsedit have no macOS builds. Remux and Encode tasks that require them will report an explicit error." "- tsMuxeR、truehdd 与 vsedit 没有 macOS 版本,需要它们的任务会报告明确错误。")"

# ---------------------------------------------------------------------------
# Launch
# ---------------------------------------------------------------------------
echo ""
echo "================================================================"
echo "$(msg "Setup complete. Launch BluraySubtitle with:" "安装完成。使用以下命令启动 BluraySubtitle:")"
echo "  cd $BLURAY_SETUP_DIR"
echo "  .venv/bin/python src/main.py"
echo "================================================================"
