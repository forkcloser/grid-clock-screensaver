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
# The Go-source analyzers are go.mod `tool` directives, not aqua packages
# (book/tooling.md).
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
    # Regex-escape the slug: aqua slugs carry dots, and an unescaped '.' would
    # match a sibling (`foo/li.r` vs `foo/liar`). ']' and '\' are absent from
    # slugs and trip BSD sed.
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
    # See `add` for the escaping.
    esc=$(printf '%s' '{{ pkg }}' | sed 's/[.^$*+?()[{}|]/\\&/g')
    if ! grep -qE "^[[:space:]]*-[[:space:]]*name:[[:space:]]*${esc}@" aqua.yaml; then
        echo "{{ pkg }} is not pinned in aqua.yaml — add it with 'just do tools add {{ pkg }}'." >&2
        exit 1
    fi
    # Explicit sibling template: macOS mktemp ignores $TMPDIR, and a sibling
    # makes the mv an atomic same-filesystem rename.
    tmp=$(mktemp aqua.yaml.XXXXXX)
    trap 'rm -f "$tmp"' EXIT
    sed -E "s#(^[[:space:]]*-[[:space:]]*name:[[:space:]]*${esc})@[^[:space:]]*#\1@{{ version }}#" aqua.yaml > "$tmp"
    mv "$tmp" aqua.yaml
    aqua update-checksum --prune      # new checksum in, replaced version's out
    aqua install                      # REAL install: a bad pin fails here, not at first use

# Update an existing tool to its latest version, e.g. `just do tools update golangci-lint`.
# Takes the COMMAND name (`just`, `limen`), not the package slug: `aqua update`
# resolves a command to its pinned package, local registry included.
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
    # Exact string compare on the parsed slug, not a regex (a dot would be a
    # wildcard, and escaping for awk is unportable: -v eats backslashes). The
    # entry's extent is decided by indentation, as YAML decides it: deeper lines
    # belong to it, a line at its own depth or shallower ends it — so a
    # `# --- section ---` header at item depth stays with what follows.
    awk -v pkg="{{ pkg }}" '
        function indent(l) { match(l, /^[[:blank:]]*/); return RLENGTH }
        {
            if (skip) { if ($0 !~ /^[[:blank:]]*$/ && indent($0) > depth) next; skip = 0 }
            if (match($0, /^[[:blank:]]*-[[:blank:]]*name:[[:blank:]]*/)) {
                slug = substr($0, RLENGTH + 1)
                sub(/[[:blank:]].*$/, "", slug)   # drop trailing spaces / comment
                sub(/@.*$/, "", slug)             # drop @version
                if (slug == pkg) { skip = 1; depth = indent($0); next }
            }
            print
        }
    ' aqua.yaml > "$tmp"
    mv "$tmp" aqua.yaml
    aqua remove "{{ pkg }}" || true   # uninstall the binary (no-op for go_install tools)
    aqua update-checksum --prune      # drop the now-unused checksum
