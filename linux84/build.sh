#!/usr/bin/env bash
# build.sh - build View8's disassembler (v8dasm) for V8 8.4.371.22 on Ubuntu.
#
# Run by GitHub (.github/workflows/v8dasm-linux-84.yml). You don't run this
# on your laptop - it needs ~15 GB of disk and an hour of CPU.
#
#   PC=true  bash linux84/build.sh   -> pointer compression ON
#   PC=false bash linux84/build.sh   -> pointer compression OFF
#
# Why two? NW.js may have built its V8 either way, and the disassembler
# must match exactly. GitHub builds both; whichever reads app.bin is right.
#
# Result: out/v8dasm-8.4.371.22-pc-on (or -pc-off), plus a self-test.

set -euo pipefail

V8_VERSION=${V8_VERSION:-8.4.371.22}
PC=${PC:-true}
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-$PWD/out}
WORK=${WORK:-$HOME/v8work}
[ "$PC" = true ] && TAG=on || TAG=off
NAME=v8dasm-$V8_VERSION-pc-$TAG

step() { echo; echo "=====[ $* ]====="; }

step "1/8 System tools"
sudo apt-get update -qq
sudo apt-get install -y -qq python2 ninja-build pkg-config curl git xz-utils lsb-release
# V8 8.4 is from 2020: its build scripts call plain "python" and expect Python 2.
sudo ln -sf /usr/bin/python2 /usr/local/bin/python
python --version

step "2/8 depot_tools (Google's download/build helpers)"
mkdir -p "$WORK"
[ -d "$WORK/depot_tools" ] ||
  git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git "$WORK/depot_tools"
export PATH="$WORK/depot_tools:$PATH"
gclient --version   # first run sets depot_tools up

step "3/8 V8 $V8_VERSION source (only that version, no history)"
cd "$WORK"
if [ ! -d v8/.git ]; then
  git init -q v8
  git -C v8 remote add origin https://chromium.googlesource.com/v8/v8.git
fi
git -C v8 fetch --depth 1 origin "refs/tags/$V8_VERSION:refs/tags/$V8_VERSION"
git -C v8 -c advice.detachedHead=false checkout -f "tags/$V8_VERSION"
git -C v8 log -1 --format='checked out %H (%cd)'

# "managed: False" = gclient leaves our v8 checkout alone and only
# downloads what V8's DEPS file lists (build files, ICU, libc++, ...).
cat > .gclient <<'EOF'
solutions = [{
  "name": "v8",
  "url": "https://chromium.googlesource.com/v8/v8.git",
  "deps_file": "DEPS",
  "managed": False,
  "custom_deps": {},
}]
EOF
gclient sync --nohooks --no-history -j 8

step "4/8 Compiler + Linux sysroot (the hooks we actually need)"
cd "$WORK/v8"
python build/linux/sysroot_scripts/install-sysroot.py --arch=x64
python tools/clang/scripts/update.py
python build/util/lastchange.py -o build/util/LASTCHANGE || {
  echo "lastchange failed - writing a placeholder"
  echo "LASTCHANGE=0-0" > build/util/LASTCHANGE
  date +%s > build/util/LASTCHANGE.committime
}

step "5/8 Patch V8 so it prints functions"
bash "$HERE/patch-v84.sh" "$WORK/v8"
# Our tool replaces V8's hello-world sample, so V8's own build compiles it.
cp "$HERE/v8dasm.cpp" samples/hello-world.cc

step "6/8 Configure (pointer compression = $PC)"
ARGS="is_debug=false
is_component_build=false
target_cpu=\"x64\"
v8_enable_pointer_compression=$PC
v8_enable_disassembler=true
v8_enable_object_print=true
v8_use_external_startup_data=false
icu_use_data_file=false
treat_warnings_as_errors=false
symbol_level=0
use_goma=false"
ARGS=$(echo $ARGS)   # one line
echo "$ARGS"
buildtools/linux64/gn gen out/dasm --args="$ARGS"

step "7/8 Compile (about an hour)"
/usr/bin/ninja -C out/dasm v8_hello_world
mkdir -p "$OUT"
cp out/dasm/v8_hello_world "$OUT/$NAME"
strip "$OUT/$NAME" || true
ls -lh "$OUT/$NAME"

step "8/8 Self-test"
cd "$OUT"
"./$NAME" --make-test selftest.bin
"./$NAME" selftest.bin > selftest.txt
head -40 selftest.txt
n=$(grep -c '^Start SharedFunctionInfo' selftest.txt || true)
echo "functions printed: $n"
grep -q 'govid' selftest.txt || { echo "SELF-TEST FAILED: no 'govid' in output"; exit 1; }
grep -q '@    0 : ' selftest.txt || { echo "SELF-TEST FAILED: no bytecode in output"; exit 1; }
echo "SELF-TEST OK"
