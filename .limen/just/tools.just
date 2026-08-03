# DO NOT EDIT MANUALLY.
# This file provides shared tasks common to all projects and managed by limen.
# Project recipes live in the root Justfile, below the shared-baseline import.

set working-directory := '../..'

# Silence just's per-line command echo; recipes announce themselves via _banner.
set quiet

# Shared private _banner recipe (see lib.just).
import 'lib.just'

# --- Project tooling via aqua (see book/tooling.md). Each recipe takes the
#     owner/repo exactly as it appears in aqua.yaml, e.g. golangci/golangci-lint. ---
#
# The mutating recipes end with a FULL `aqua install`, never `--only-link`:
# links verify nothing (lazy pulls are a CI economy — wrong at the moment a
# pin changes), and for checksum-less package types (go_install) the
# update-checksum step is silent too, so a broken pin would exit green and
# detonate at first tool use (e.g. a nested, untagged Go module pinned to a
# repo tag its module zip does not contain). On a warm machine the full
# install is incremental — only the touched tool downloads or builds.

# Add a new tool at its latest version, e.g. `just do tools add junegunn/fzf`.
add pkg: (_banner "tools" "add")
    #!/usr/bin/env bash
    set -euo pipefail
    # Regex-escape the package name before it enters a grep -E / sed -E pattern.
    # aqua slugs carry dots (github.com, golang.org), and an unescaped '.' is a
    # wildcard: without this, `add foo/li.r` would match an existing `foo/liar`
    # (and set/remove would edit/delete the wrong entry). ']' and '\' are omitted
    # from the class — a Go module slug can contain neither, and both trip BSD sed.
    esc=$(printf '%s' '{{ pkg }}' | sed 's/[.^$*+?()[{}|]/\\&/g')
    if grep -qE "^[[:space:]]*-[[:space:]]*name:[[:space:]]*${esc}([[:space:]]|@|$)" aqua.yaml; then
        echo "{{ pkg }} is already in aqua.yaml — use 'just do tools update {{ pkg }}' or 'just do tools set {{ pkg }} <version>'." >&2
        exit 1
    fi
    aqua generate -i "{{ pkg }}"      # append the latest version to aqua.yaml
    aqua update-checksum --prune      # record its checksum (and drop stale ones)
    aqua install                      # REAL install: a bad pin fails here, not at first use

# Set an existing tool to an exact version, e.g. `just do tools set golangci/golangci-lint v1.55.3`.
set pkg version: (_banner "tools" "set")
    #!/usr/bin/env bash
    set -euo pipefail
    # Regex-escape the slug before grep -E / sed -E — see `add` for why.
    esc=$(printf '%s' '{{ pkg }}' | sed 's/[.^$*+?()[{}|]/\\&/g')
    if ! grep -qE "^[[:space:]]*-[[:space:]]*name:[[:space:]]*${esc}@" aqua.yaml; then
        echo "{{ pkg }} is not pinned in aqua.yaml — add it with 'just do tools add {{ pkg }}'." >&2
        exit 1
    fi
    # An explicit path template: macOS mktemp ignores $TMPDIR and falls back to
    # a per-user temp dir that sandboxes may deny writes to. A sibling file also
    # makes the mv a same-filesystem, truly atomic rename.
    tmp=$(mktemp aqua.yaml.XXXXXX)
    trap 'rm -f "$tmp"' EXIT
    sed -E "s#(^[[:space:]]*-[[:space:]]*name:[[:space:]]*${esc})@[^[:space:]]*#\1@{{ version }}#" aqua.yaml > "$tmp"
    mv "$tmp" aqua.yaml
    aqua update-checksum --prune      # new checksum in, replaced version's out
    aqua install                      # REAL install: a bad pin fails here, not at first use

# Update an existing tool to its latest version, e.g. `just do tools update golangci-lint`.
# Takes the COMMAND name (the executable you type — `just`, `limen`), not the
# owner/name package slug: it delegates to `aqua update`, which resolves a
# command to its pinned package — local-registry packages included. (The
# previous `aqua generate` approach could not work: generate refuses to
# re-emit an already-pinned package, which is the only kind update meets.)
update command: (_banner "tools" "update")
    #!/usr/bin/env bash
    set -euo pipefail
    aqua update "{{ command }}"       # bump aqua.yaml to the latest release
    aqua update-checksum --prune      # new checksum in, replaced version's out
    aqua install                      # REAL install: a bad pin fails here, not at first use

# Remove a tool entirely, e.g. `just do tools remove junegunn/fzf`.
remove pkg: (_banner "tools" "remove")
    #!/usr/bin/env bash
    set -euo pipefail
    # Regex-escape the slug before grep -E — see `add` for why.
    esc=$(printf '%s' '{{ pkg }}' | sed 's/[.^$*+?()[{}|]/\\&/g')
    if ! grep -qE "^[[:space:]]*-[[:space:]]*name:[[:space:]]*${esc}([[:space:]]|@|$)" aqua.yaml; then
        echo "{{ pkg }} is not in aqua.yaml — nothing to remove." >&2
        exit 1
    fi
    # See `set` for why mktemp gets an explicit sibling-path template.
    tmp=$(mktemp aqua.yaml.XXXXXX)
    trap 'rm -f "$tmp"' EXIT
    # Match by an EXACT string compare on the parsed slug, not a regex built from
    # it. A regex would make a dot in the name a wildcard (see `add`) and delete a
    # sibling — and escaping for awk is unportable (its -v processing eats the
    # backslashes), so we parse the slug out and compare literally instead. Drops
    # the entry's line plus its indented continuation lines (registry:, etc.).
    awk -v pkg="{{ pkg }}" '
        function isCont(l) { return (l ~ /^[[:blank:]]+[^[:blank:]#-]/) }
        {
            if (skip) { if (isCont($0)) next; skip = 0 }
            if (match($0, /^[[:blank:]]*-[[:blank:]]*name:[[:blank:]]*/)) {
                slug = substr($0, RLENGTH + 1)
                sub(/[[:blank:]].*$/, "", slug)   # drop trailing spaces / comment
                sub(/@.*$/, "", slug)             # drop @version
                if (slug == pkg) { skip = 1; next }
            }
            print
        }
    ' aqua.yaml > "$tmp"
    mv "$tmp" aqua.yaml
    aqua remove "{{ pkg }}" || true   # uninstall the binary (no-op for go_install tools)
    aqua update-checksum --prune      # drop the now-unused checksum
