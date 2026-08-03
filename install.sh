#!/usr/bin/env bash
# Grid Clock installer.
#
# Downloads a published release, PROVES it is the one this project's CI built,
# and installs it into your screensaver directory.
#
#   curl -fsSL https://raw.githubusercontent.com/forkcloser/grid-clock-screensaver/main/install.sh | bash
#
# Why this script exists, and why it is not just a `cp`:
#
# The bundle is ad-hoc signed — there is no Apple Developer ID behind it. That
# is enough for macOS to LOAD it (legacyScreenSaver carries
# com.apple.security.cs.disable-library-validation), but not enough for
# Gatekeeper to let it run once it arrives from the internet carrying a
# quarantine attribute. Clearing that attribute is what makes a downloaded
# .saver usable, and telling you to run `xattr -dr` on an unverified download
# would be asking you to switch off a protection on faith.
#
# So this script establishes the trust first, and only then clears quarantine:
#
#   1. cosign verifies checksums.txt against the SIGNATURE the release workflow
#      produced. That signature is keyless — its identity IS
#      forkcloser/grid-clock-screensaver's release.yaml at a v* tag, certified by
#      Fulcio and logged in Rekor. No key exists to be stolen or misused, and a
#      file signed by anything else fails this step.
#   2. The bundle's SHA-256 is checked against that now-trusted checksums file.
#   3. Only then is the archive expanded, de-quarantined, and installed — and
#      the bundle's own code signature is re-verified afterwards, so a zip that
#      damaged it in transit is caught rather than installed.
#
# Step 1 needs cosign (https://github.com/sigstore/cosign). Without it the
# script stops rather than quietly downgrading to "checksum only", because a
# checksums file you cannot authenticate proves nothing about who made it.
# --allow-unverified opts into that downgrade explicitly, and says so loudly.

set -euo pipefail

REPO="forkcloser/grid-clock-screensaver"
SAVER="Grid Clock.saver"
CERT_IDENTITY="^https://github.com/${REPO}/\.github/workflows/release\.yaml@refs/tags/v.*$"
CERT_ISSUER="https://token.actions.githubusercontent.com"

version=""
prefix="$HOME/Library/Screen Savers"
allow_unverified=""

usage() {
    cat >&2 <<EOF
usage: install.sh [options]

  --version <vX.Y.Z>   install this release (default: the latest release)
  --prefix <dir>       install here (default: ~/Library/Screen Savers)
  --system             install for all users in /Library/Screen Savers (needs sudo)
  --allow-unverified   proceed without cosign — checksum only, NOT recommended
  --help               this message
EOF
}

die() {
    echo "install.sh: $*" >&2
    exit 1
}

while [ $# -gt 0 ]; do
    case "$1" in
        --version)
            [ $# -ge 2 ] || die "--version needs an argument"
            version="$2"
            shift 2
            ;;
        --prefix)
            [ $# -ge 2 ] || die "--prefix needs an argument"
            prefix="$2"
            shift 2
            ;;
        --system)
            prefix="/Library/Screen Savers"
            shift
            ;;
        --allow-unverified)
            allow_unverified=1
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "unknown option: $1" >&2
            usage
            exit 2
            ;;
    esac
done

[ "$(uname -s)" = "Darwin" ] || die "this is a macOS screensaver; uname says $(uname -s)"

major=$(sw_vers -productVersion | cut -d. -f1)
if [ "$major" -lt 14 ]; then
    die "macOS 14 or later required (found $(sw_vers -productVersion)) — on 13 and earlier, run the original: https://github.com/chrstphrknwtn/grid-clock-screensaver"
fi

for tool in curl ditto shasum xattr codesign; do
    command -v "$tool" > /dev/null 2>&1 || die "required tool not found: $tool"
done

if [ -z "$version" ]; then
    echo "resolving the latest release..."
    # No jq dependency: pull tag_name out of the API response directly. The
    # release workflow marks prerelease tags as prereleases, so /latest never
    # returns a test tag.
    version=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
        | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        | head -1)
    [ -n "$version" ] || die "could not determine the latest release — pass --version explicitly"
fi

case "$version" in
    v*) ;;
    *) die "version must look like vX.Y.Z (got '$version')" ;;
esac

# The asset names goreleaser produces are keyed on the version WITHOUT the v.
bare="${version#v}"
archive="grid-clock_${bare}_universal.zip"
base="https://github.com/${REPO}/releases/download/${version}"

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

echo "downloading ${version}..."
curl -fsSL -o "$workdir/$archive" "$base/$archive" \
    || die "could not download $archive — does release $version exist?"
curl -fsSL -o "$workdir/checksums.txt" "$base/checksums.txt" \
    || die "could not download checksums.txt"

if [ -n "$allow_unverified" ]; then
    echo
    echo "WARNING: --allow-unverified — the checksums file is NOT being authenticated." >&2
    echo "         A tampered release would pass this run. You are trusting the network." >&2
    echo
elif command -v cosign > /dev/null 2>&1; then
    curl -fsSL -o "$workdir/checksums.txt.sigstore.json" "$base/checksums.txt.sigstore.json" \
        || die "could not download the signature (checksums.txt.sigstore.json)"
    echo "verifying the signature..."
    cosign verify-blob \
        --bundle "$workdir/checksums.txt.sigstore.json" \
        --certificate-oidc-issuer "$CERT_ISSUER" \
        --certificate-identity-regexp "$CERT_IDENTITY" \
        "$workdir/checksums.txt" \
        || die "SIGNATURE VERIFICATION FAILED — do not install this. Report it at https://github.com/${REPO}/issues"
    echo "signature ok: signed by ${REPO}'s release workflow at a v* tag"
else
    die "cosign not found, so the release cannot be authenticated.

Install it (brew install cosign), or re-run with --allow-unverified to
proceed on checksum alone — which proves the download is intact, but not
who produced it."
fi

echo "verifying the checksum..."
expected=$(grep " ${archive}\$" "$workdir/checksums.txt" | awk '{print $1}' | head -1)
[ -n "$expected" ] || die "$archive is not listed in checksums.txt"
actual=$(shasum -a 256 "$workdir/$archive" | awk '{print $1}')
[ "$expected" = "$actual" ] || die "CHECKSUM MISMATCH for $archive
  expected $expected
  got      $actual"
echo "checksum ok"

echo "expanding..."
ditto -x -k "$workdir/$archive" "$workdir/extracted"
[ -d "$workdir/extracted/$SAVER" ] || die "the archive did not contain $SAVER"

# The whole point of the verification above: now that we know exactly what this
# is, clearing the download quarantine is an informed decision rather than a
# leap of faith.
xattr -dr com.apple.quarantine "$workdir/extracted/$SAVER" 2> /dev/null || true

# A transfer that damaged the bundle would show up here rather than as a
# baffling failure later, when macOS refuses to load it.
codesign --verify --deep --strict "$workdir/extracted/$SAVER" \
    || die "the bundle's code signature is not intact after extraction — not installing"
echo "code signature intact"

if [ -e "$prefix/$SAVER" ]; then
    echo "replacing the existing $prefix/$SAVER"
fi

sudo=""
if [ ! -w "$(dirname "$prefix")" ] && [ ! -w "$prefix" ]; then
    sudo="sudo"
    echo "$prefix is not writable — using sudo"
fi

$sudo mkdir -p "$prefix"
$sudo rm -rf "${prefix:?}/$SAVER"
$sudo ditto "$workdir/extracted/$SAVER" "$prefix/$SAVER"

echo
echo "installed $prefix/$SAVER"
echo
echo "If System Settings is open, quit it with ⌘Q and reopen — it reads the"
echo "screensaver list once at launch, so a running copy will not show Grid Clock."
echo
echo "  macOS 26 (Tahoe): System Settings -> Wallpaper -> Screen Saver... -> scroll to the bottom"
echo "  macOS 14 / 15:    System Settings -> Screen Saver -> under Other"
