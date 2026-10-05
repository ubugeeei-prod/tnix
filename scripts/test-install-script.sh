#!/bin/sh
# End-to-end test for docs/public/install.sh (https://tynix.dev/install.sh).
#
# Usage: sh scripts/test-install-script.sh <install.sh> <bin-dir> [shell]
#
# <bin-dir> must contain runnable `tynix` and `tynix-lsp` binaries. They are
# packed into a fake release laid out like the real download tree
# (<base>/<tag>/tynix-<tag>-<target>.tar.gz + .sha256) and served through a
# file:// TYNIX_DOWNLOAD_BASE, so no network access is needed.
set -eu

install_sh="$1"
bin_dir="$2"
shell="${3:-sh}"

work="$(mktemp -d "${TMPDIR:-/tmp}/tynix-install-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT

fail() {
  printf 'test-install-script: FAIL: %s\n' "$*" >&2
  exit 1
}

pass() {
  printf 'test-install-script: ok - %s\n' "$*"
}

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

tag=v9.9.9
# Pin the platform so the archive name is deterministic; the binaries are
# host-native either way.
target=linux-x64
export TYNIX_UNAME_S=Linux TYNIX_UNAME_M=x86_64

archive="tynix-$tag-$target.tar.gz"
release_dir="$work/download/$tag"
stage="$work/stage/tynix-${tag#v}-$target"
mkdir -p "$release_dir" "$stage/bin"
cp "$bin_dir/tynix" "$bin_dir/tynix-lsp" "$stage/bin/"
chmod 0755 "$stage/bin/tynix" "$stage/bin/tynix-lsp"
tar -C "$work/stage" -czf "$release_dir/$archive" "tynix-${tag#v}-$target"
printf '%s  %s\n' "$(sha256 "$release_dir/$archive")" "$archive" >"$release_dir/tynix-$tag-$target.sha256"

export TYNIX_DOWNLOAD_BASE="file://$work/download"
export TYNIX_INSTALL_DIR="$work/prefix/bin"

# 1. Install a pinned version (without the leading v) and run the result.
TYNIX_VERSION="${tag#v}" "$shell" "$install_sh" >"$work/install.log" 2>&1 ||
  { cat "$work/install.log" >&2; fail "install exited non-zero"; }
for bin in tynix tynix-lsp; do
  [ -x "$TYNIX_INSTALL_DIR/$bin" ] || fail "$bin was not installed"
  "$TYNIX_INSTALL_DIR/$bin" --version >/dev/null || fail "installed $bin does not run"
done
grep -q "checksum verified" "$work/install.log" || fail "checksum was not reported as verified"
pass "installs a pinned release and verifies its checksum"

# 2. The PATH hint is printed when the install dir is not on PATH.
grep -q "is not on your PATH" "$work/install.log" || fail "missing PATH hint"
pass "prints a PATH hint"

# 3. Re-installing over an existing install works (upgrade path).
TYNIX_VERSION="$tag" "$shell" "$install_sh" >/dev/null 2>&1 || fail "re-install failed"
pass "re-installs over an existing install"

# 4. A tampered archive is rejected and nothing is installed.
rm -rf "$TYNIX_INSTALL_DIR"
printf '%064d  %s\n' 0 "$archive" >"$release_dir/tynix-$tag-$target.sha256.good"
mv "$release_dir/tynix-$tag-$target.sha256" "$release_dir/tynix-$tag-$target.sha256.real"
mv "$release_dir/tynix-$tag-$target.sha256.good" "$release_dir/tynix-$tag-$target.sha256"
if TYNIX_VERSION="$tag" "$shell" "$install_sh" >"$work/bad.log" 2>&1; then
  fail "install succeeded despite a checksum mismatch"
fi
grep -q "checksum mismatch" "$work/bad.log" || { cat "$work/bad.log" >&2; fail "checksum mismatch not reported"; }
[ ! -e "$TYNIX_INSTALL_DIR/tynix" ] || fail "binary installed despite a checksum mismatch"
mv "$release_dir/tynix-$tag-$target.sha256.real" "$release_dir/tynix-$tag-$target.sha256"
pass "rejects an archive whose checksum does not match"

# 5. A missing release fails clearly.
if TYNIX_VERSION=v0.0.0-missing "$shell" "$install_sh" >"$work/missing.log" 2>&1; then
  fail "install succeeded for a release that does not exist"
fi
grep -q "failed to download" "$work/missing.log" || fail "missing release not reported"
pass "fails clearly for a missing release"

# 6. Unsupported platforms fail and point at the flake.
for platform in "FreeBSD x86_64" "Linux riscv64" "MINGW64_NT-10.0 x86_64"; do
  # shellcheck disable=SC2086
  set -- $platform
  if TYNIX_UNAME_S="$1" TYNIX_UNAME_M="$2" TYNIX_VERSION="$tag" "$shell" "$install_sh" >"$work/unsupported.log" 2>&1; then
    fail "install succeeded on unsupported platform $platform"
  fi
  grep -q "nix profile install" "$work/unsupported.log" || { cat "$work/unsupported.log" >&2; fail "no flake hint for $platform"; }
done
pass "rejects unsupported platforms with a flake hint"

# 7. --dir and --uninstall.
"$shell" "$install_sh" --version "$tag" --dir "$work/other/bin" >/dev/null 2>&1 || fail "--dir install failed"
[ -x "$work/other/bin/tynix" ] || fail "--dir did not install into the given directory"
"$shell" "$install_sh" --uninstall --dir "$work/other/bin" >/dev/null 2>&1 || fail "--uninstall failed"
[ ! -e "$work/other/bin/tynix" ] && [ ! -e "$work/other/bin/tynix-lsp" ] || fail "--uninstall left binaries behind"
pass "--dir and --uninstall"

# 8. Default install dir is $HOME/.tynix/bin, and uninstall removes it.
fake_home="$work/home"
mkdir -p "$fake_home"
env -u TYNIX_INSTALL_DIR HOME="$fake_home" TYNIX_VERSION="$tag" "$shell" "$install_sh" >/dev/null 2>&1 ||
  fail "default-dir install failed"
[ -x "$fake_home/.tynix/bin/tynix" ] || fail "default install dir is not \$HOME/.tynix/bin"
env -u TYNIX_INSTALL_DIR HOME="$fake_home" "$shell" "$install_sh" --uninstall >/dev/null 2>&1 ||
  fail "default-dir uninstall failed"
[ ! -e "$fake_home/.tynix" ] || fail "uninstall left $fake_home/.tynix behind"
pass "default install dir and uninstall cleanup"

printf 'test-install-script: all tests passed\n'
