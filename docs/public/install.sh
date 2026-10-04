#!/bin/sh
# tnix installer
#
#   curl -fsSL https://tnix.dev/install.sh | sh
#   curl -fsSL https://tnix.dev/install.sh | sh -s -- --version 0.5.0
#   curl -fsSL https://tnix.dev/install.sh | sh -s -- --uninstall
#
# Installs the prebuilt `tnix` CLI and `tnix-lsp` language server from the
# GitHub release archives. Every archive is verified against its published
# SHA-256 checksum before anything is installed.
#
# Environment variables:
#   TNIX_VERSION        Release to install, e.g. 0.5.0 or v0.5.0 (default: latest)
#   TNIX_INSTALL_DIR    Directory for the binaries (default: $HOME/.tnix/bin)
#   TNIX_DOWNLOAD_BASE  Base URL of the release assets; files are fetched from
#                       <base>/<tag>/<file> (default: https://tnix.dev/download)
#   TNIX_REPO           GitHub repository used to resolve the latest release
#                       (default: ubugeeei-prod/tnix)
#
# Supported targets: linux-x64, linux-arm64, macos-arm64, macos-x64.
# Everywhere else (and for NixOS users), install through the Nix flake:
#   nix profile install github:ubugeeei-prod/tnix

set -eu

TNIX_REPO="${TNIX_REPO:-ubugeeei-prod/tnix}"
TNIX_DOWNLOAD_BASE="${TNIX_DOWNLOAD_BASE:-https://tnix.dev/download}"
TNIX_LATEST_URL="${TNIX_LATEST_URL:-https://tnix.dev/latest}"
TNIX_VERSION="${TNIX_VERSION:-}"
TNIX_INSTALL_DIR="${TNIX_INSTALL_DIR:-}"
FLAKE_REF="github:ubugeeei-prod/tnix"
BINARIES="tnix tnix-lsp"

tmp_dir=""

say() {
  printf 'tnix-install: %s\n' "$*"
}

warn() {
  printf 'tnix-install: warning: %s\n' "$*" >&2
}

die() {
  printf 'tnix-install: error: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [ -n "$tmp_dir" ] && [ -d "$tmp_dir" ]; then
    rm -rf "$tmp_dir"
  fi
}

usage() {
  cat <<EOF
tnix installer

Usage:
  curl -fsSL https://tnix.dev/install.sh | sh
  curl -fsSL https://tnix.dev/install.sh | sh -s -- [options]

Options:
  --version <version>   Install a specific release (e.g. 0.5.0); default: latest
  --dir <path>          Install directory (default: \$HOME/.tnix/bin)
  --uninstall           Remove tnix and tnix-lsp from the install directory
  -h, --help            Show this help

Environment:
  TNIX_VERSION, TNIX_INSTALL_DIR, TNIX_DOWNLOAD_BASE, TNIX_REPO

With Nix, prefer the flake instead:
  nix profile install $FLAKE_REF
EOF
}

has() {
  command -v "$1" >/dev/null 2>&1
}

suggest_flake() {
  cat >&2 <<EOF

Prebuilt tnix binaries are available for linux-x64, linux-arm64,
macos-arm64 and macos-x64. On other platforms, build from source with Nix:

  nix profile install $FLAKE_REF
  # or run without installing:
  nix run $FLAKE_REF -- check ./main.tnix

EOF
}

unsupported() {
  printf 'tnix-install: error: %s\n' "$*" >&2
  suggest_flake
  exit 1
}

# --- platform detection ------------------------------------------------------

detect_target() {
  # TNIX_UNAME_S / TNIX_UNAME_M exist so the installer can be tested for
  # other platforms; they are not meant for normal use.
  os="${TNIX_UNAME_S:-$(uname -s)}"
  arch="${TNIX_UNAME_M:-$(uname -m)}"

  case "$os" in
    Linux) os_part=linux ;;
    Darwin) os_part=macos ;;
    MINGW* | MSYS* | CYGWIN* | Windows_NT)
      unsupported "Windows is not supported natively. Use WSL2 and re-run this installer inside it."
      ;;
    *) unsupported "unsupported operating system: $os" ;;
  esac

  case "$arch" in
    x86_64 | amd64) arch_part=x64 ;;
    aarch64 | arm64) arch_part=arm64 ;;
    *) unsupported "unsupported CPU architecture: $arch ($os)" ;;
  esac

  # An x86_64 shell running under Rosetta 2 on Apple silicon should still get
  # the native arm64 build.
  if [ "$os_part" = macos ] && [ "$arch_part" = x64 ] && [ -z "${TNIX_UNAME_M:-}" ]; then
    if [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" = 1 ]; then
      arch_part=arm64
    fi
  fi

  printf '%s-%s\n' "$os_part" "$arch_part"
}

# --- downloads ---------------------------------------------------------------

download() {
  # download <url> <output-file>
  if has curl; then
    curl --proto '=https,file' --tlsv1.2 -fsSL --retry 3 -o "$2" "$1"
  elif has wget; then
    wget -q -O "$2" "$1"
  else
    die "either curl or wget is required"
  fi
}

download_stdout() {
  if has curl; then
    curl --proto '=https' --tlsv1.2 -fsSL --retry 3 "$1"
  elif has wget; then
    wget -q -O - "$1"
  else
    die "either curl or wget is required"
  fi
}

# Prints the final URL after following redirects.
effective_url() {
  if has curl; then
    curl --proto '=https' --tlsv1.2 -fsSL -o /dev/null -w '%{url_effective}' "$1"
  elif has wget; then
    wget -q -S -O /dev/null "$1" 2>&1 | sed -n 's/^ *[Ll]ocation: *//p' | tail -n 1 | tr -d '\r'
  else
    die "either curl or wget is required"
  fi
}

resolve_latest_tag() {
  tag=""
  api="https://api.github.com/repos/$TNIX_REPO/releases/latest"
  if json="$(download_stdout "$api" 2>/dev/null)"; then
    tag="$(printf '%s\n' "$json" | sed -n 's/^[[:space:]]*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
  fi

  if [ -z "$tag" ]; then
    # Rate-limited or blocked API: follow https://tnix.dev/latest, which
    # redirects to .../releases/tag/<tag>.
    if url="$(effective_url "$TNIX_LATEST_URL" 2>/dev/null)"; then
      case "$url" in
        */tag/*) tag="${url##*/tag/}" ;;
      esac
    fi
  fi

  [ -n "$tag" ] || die "could not determine the latest tnix release; set TNIX_VERSION (e.g. TNIX_VERSION=0.5.0)"
  printf '%s\n' "$tag"
}

normalize_tag() {
  case "$1" in
    v*) printf '%s\n' "$1" ;;
    *) printf 'v%s\n' "$1" ;;
  esac
}

sha256_of() {
  if has sha256sum; then
    sha256sum "$1" | awk '{print $1}'
  elif has shasum; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif has openssl; then
    openssl dgst -sha256 "$1" | awk '{print $NF}'
  else
    die "no SHA-256 tool found (need sha256sum, shasum or openssl)"
  fi
}

# --- install / uninstall -----------------------------------------------------

path_hint() {
  case ":${PATH:-}:" in
    *":$1:"*) return 0 ;;
  esac

  shell_name="$(basename "${SHELL:-sh}")"
  case "$shell_name" in
    fish)
      line="fish_add_path \"$1\""
      rc="${HOME:-~}/.config/fish/config.fish"
      ;;
    zsh)
      line="export PATH=\"$1:\$PATH\""
      rc="${HOME:-~}/.zshrc"
      ;;
    bash)
      line="export PATH=\"$1:\$PATH\""
      rc="${HOME:-~}/.bashrc"
      ;;
    *)
      line="export PATH=\"$1:\$PATH\""
      rc="${HOME:-~}/.profile"
      ;;
  esac

  cat <<EOF

$1 is not on your PATH. Add it by appending this line to $rc:

  $line

then restart your shell.
EOF
}

do_uninstall() {
  removed=0
  for bin in $BINARIES; do
    if [ -e "$TNIX_INSTALL_DIR/$bin" ] || [ -L "$TNIX_INSTALL_DIR/$bin" ]; then
      rm -f "$TNIX_INSTALL_DIR/$bin"
      say "removed $TNIX_INSTALL_DIR/$bin"
      removed=1
    fi
  done

  # Clean up the default layout (~/.tnix/bin) if nothing else lives there.
  if [ "$TNIX_INSTALL_DIR" = "$default_install_dir" ]; then
    rmdir "$TNIX_INSTALL_DIR" 2>/dev/null || true
    rmdir "$(dirname "$TNIX_INSTALL_DIR")" 2>/dev/null || true
  fi

  if [ "$removed" = 0 ]; then
    say "nothing to uninstall in $TNIX_INSTALL_DIR"
  else
    say "tnix has been uninstalled"
  fi
}

do_install() {
  target="$(detect_target)"

  if [ -n "$TNIX_VERSION" ]; then
    tag="$(normalize_tag "$TNIX_VERSION")"
  else
    say "resolving the latest release"
    tag="$(normalize_tag "$(resolve_latest_tag)")"
  fi

  archive="tnix-$tag-$target.tar.gz"
  checksum="tnix-$tag-$target.sha256"
  base="${TNIX_DOWNLOAD_BASE%/}/$tag"

  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/tnix-install.XXXXXX")" || die "cannot create a temporary directory"
  trap cleanup EXIT
  trap 'cleanup; exit 130' INT
  trap 'cleanup; exit 143' TERM

  say "installing tnix $tag ($target)"
  say "downloading $base/$archive"
  download "$base/$archive" "$tmp_dir/$archive" ||
    die "failed to download $base/$archive (does release $tag exist for $target?)"
  download "$base/$checksum" "$tmp_dir/$checksum" ||
    die "failed to download $base/$checksum"

  expected="$(awk -v name="$archive" '$2 == name {print $1}' "$tmp_dir/$checksum" | head -n 1)"
  if [ -z "$expected" ]; then
    expected="$(awk 'NR == 1 {print $1}' "$tmp_dir/$checksum")"
  fi
  expected="$(printf '%s' "$expected" | tr 'A-F' 'a-f')"
  case "$expected" in
    *[!0-9a-f]* | "") die "malformed checksum file $checksum" ;;
  esac
  [ "${#expected}" -eq 64 ] || die "malformed checksum file $checksum"

  actual="$(sha256_of "$tmp_dir/$archive")"
  if [ "$actual" != "$expected" ]; then
    die "checksum mismatch for $archive
  expected: $expected
  actual:   $actual"
  fi
  say "checksum verified ($actual)"

  mkdir -p "$tmp_dir/extract"
  tar -xzf "$tmp_dir/$archive" -C "$tmp_dir/extract" || die "failed to extract $archive"

  mkdir -p "$TNIX_INSTALL_DIR" || die "cannot create $TNIX_INSTALL_DIR"
  for bin in $BINARIES; do
    src="$(find "$tmp_dir/extract" -type f -path "*/bin/$bin" | head -n 1)"
    [ -n "$src" ] || die "$archive does not contain bin/$bin"
    # Install through a temporary name so a running tnix-lsp is replaced
    # atomically instead of being overwritten in place.
    cp "$src" "$TNIX_INSTALL_DIR/.$bin.tmp.$$"
    chmod 0755 "$TNIX_INSTALL_DIR/.$bin.tmp.$$"
    mv -f "$TNIX_INSTALL_DIR/.$bin.tmp.$$" "$TNIX_INSTALL_DIR/$bin"
    say "installed $TNIX_INSTALL_DIR/$bin"
  done

  if version_output="$("$TNIX_INSTALL_DIR/tnix" --version 2>&1)"; then
    say "$version_output"
  else
    warn "the installed tnix binary failed to run:"
    printf '%s\n' "$version_output" >&2
    suggest_flake
    exit 1
  fi

  path_hint "$TNIX_INSTALL_DIR"
  say "done. Run 'tnix --help' to get started."
}

main() {
  action=install
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --uninstall) action=uninstall ;;
      --version)
        [ "$#" -ge 2 ] || die "--version requires a value"
        TNIX_VERSION="$2"
        shift
        ;;
      --version=*) TNIX_VERSION="${1#--version=}" ;;
      --dir)
        [ "$#" -ge 2 ] || die "--dir requires a value"
        TNIX_INSTALL_DIR="$2"
        shift
        ;;
      --dir=*) TNIX_INSTALL_DIR="${1#--dir=}" ;;
      -h | --help)
        usage
        exit 0
        ;;
      *) die "unknown option: $1 (see --help)" ;;
    esac
    shift
  done

  [ -n "${HOME:-}" ] || [ -n "$TNIX_INSTALL_DIR" ] || die "HOME is not set; set TNIX_INSTALL_DIR"
  default_install_dir="${HOME:-}/.tnix/bin"
  TNIX_INSTALL_DIR="${TNIX_INSTALL_DIR:-$default_install_dir}"

  case "$action" in
    install) do_install ;;
    uninstall) do_uninstall ;;
  esac
}

main "$@"
