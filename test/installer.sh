#!/usr/bin/env bash
# What the installer answers to --version, as far as no network is needed: a
# version before the first it installs is told so before anything is fetched,
# and any other goes on to the download. curl and cosign are stand-ins here,
# which record that they were called and fail.

set -euo pipefail

cd "$(dirname "$0")/.."

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir "$work/bin"
for tool in curl cosign; do
    printf '#!/bin/sh\necho "%s $*" >> "%s/called"\nexit 1\n' "$tool" "$work" > "$work/bin/$tool"
    chmod +x "$work/bin/$tool"
done

failures=0
fail() {
    echo "installer: $*" >&2
    failures=$((failures + 1))
}

# The installer's exit status is left in $status, its two streams in $output.
run() {
    rm -f "$work/called"
    status=0
    output=$(PATH="$work/bin:$PATH" bash install.sh "$@" 2>&1) || status=$?
}

has() {
    printf '%s\n' "$output" | grep -qF -- "$1"
}

releases="https://github.com/forkcloser/grid-clock-screensaver/releases/download"

for asked in 1.1.0 v1.1.0 1.0.0 0.1.0 0.9.9 1.1.0-rc.1; do
    tag="v${asked#v}"
    for unverified in no yes; do
        args=(--version "$asked")
        if [ "$unverified" = yes ]; then
            args+=(--allow-unverified)
        fi
        run "${args[@]}"
        [ "$status" -eq 1 ] || fail "${args[*]}: exit $status, want 1"
        has "this installer installs v1.2.0 and later, and $tag is earlier." \
            || fail "${args[*]}: does not say that $tag is earlier than the first release installed: $output"
        has "curl --proto '=https' --tlsv1.2 -fsSL $releases/$tag/install.sh | bash -s -- --version $tag" \
            || fail "${args[*]}: does not give the command of $tag's own installer: $output"
        for alarm in "VERIFICATION FAILED" "Report it" "not signed" "lists no"; do
            if has "$alarm"; then
                fail "${args[*]}: says \"$alarm\" of a release it does not install: $output"
            fi
        done
        [ ! -e "$work/called" ] || fail "${args[*]}: fetched or verified before answering: $(cat "$work/called")"
    done
done

for asked in 1.2.0 v1.2.0 1.2.0-rc.1 1.2.1 1.10.0 2.0.0; do
    tag="v${asked#v}"
    run --version "$asked"
    if has "is earlier"; then
        fail "--version $asked: refused as earlier than v1.2.0: $output"
    fi
    has "fetching the manifest for $tag..." \
        || fail "--version $asked: did not go on to the download: $output"
    grep -qF -- "$releases/$tag/checksums.txt" "$work/called" 2> /dev/null \
        || fail "--version $asked: did not ask for $tag's checksums.txt"
done

if [ "$failures" -ne 0 ]; then
    echo "installer: $failures failed" >&2
    exit 1
fi
echo "installer: a release before v1.2.0 is named as earlier with its own installer's command, nothing fetched; v1.2.0 and later go on to the download"
