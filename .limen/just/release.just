# DO NOT EDIT MANUALLY.
# This file provides shared tasks common to all projects and managed by limen.
# Project recipes live in the root Justfile, below the shared-baseline import.

# Imported flat into the canonical Justfile — not a module — so the recipe can
# take arguments (`just do release v1.2.3`; a module invocation would parse the
# tag as a recipe path). Deliberately no settings and no _lib import here: an
# import's settings would apply to the whole importing module.

# Release. The default is the CI lane; everything local is opted into with
# --local (see book/recipes.md):
#
#   just do release vX.Y.Z
#       Verify a clean tree, create the signed tag (your key signs the
#       INTENT), push — the release workflow builds, signs the artifacts
#       (keyless cosign), and publishes.
#
#   just do release --local <cosign-key> vX.Y.Z [--cosign-password-stdin]
#       The fully local lane: goreleaser + key-based cosign from this machine,
#       and the SOLE publisher — it pushes the commit but not the tag, so it does
#       not re-trigger the CI release workflow (goreleaser creates the GitHub
#       release, and its remote tag, itself). The key path is a mandatory
#       argument; the passphrase is read from stdin with --cosign-password-stdin —
#       piped, so it never lands in argv or shell history (`pass show cosign |
#       just do release … --cosign-password-stdin`) — and prompted on the terminal
#       when the flag is absent. For private repos (nothing touches Rekor's public
#       log) — and the escape hatch when CI is down.
#
#   just do release --local --dry-run
#       Unsigned local snapshot into build/release/: no tag, no token, no
#       publish — and works on a dirty tree, by design.
#
#   just do release --ci
#       The workflow half of the default lane (GitHub Actions only): the
#       pushed tag triggered us; run goreleaser with keyless signing.
#
# Tag pushes are always exactly one tag, never --tags: stray local tags stay
# local. A tag already on HEAD is reused, so a failed publish retries safely.
[doc('Release: `vX.Y.Z` tags for CI · `--local <cosign-key> vX.Y.Z` · `--local --dry-run` · `--ci`')]
release *args:
    #!/usr/bin/env bash
    set -euo pipefail
    # Releasing is opt-in, by carrying a goreleaser config (project-owned, like
    # the root Justfile — limen neither pins nor seeds it). Checked before
    # anything else: past this point the recipe creates tags and pushes.
    if [ ! -f .goreleaser.yaml ] && [ ! -f .goreleaser.yml ]; then
        echo "this project has no .goreleaser.yaml — goreleaser releases are opt-in (see book/recipes.md)." >&2
        exit 1
    fi
    usage() {
        echo "usage: just do release <tag>                                               # signed tag + push; CI builds, signs (keyless), publishes" >&2
        echo "       just do release --local <cosign-key> <tag> [--cosign-password-stdin] # fully local, key-based cosign" >&2
        echo "       just do release --local --dry-run                                   # local unsigned snapshot into build/release/" >&2
        echo "       just do release --ci                                                # workflow half of the default lane (GitHub Actions only)" >&2
    }
    require_clean() {
        # A dirty tree is the most common failure and goreleaser hard-refuses
        # it — check long before anything is created or pushed.
        if [ -n "$(git status --porcelain)" ]; then
            echo "the working tree is dirty — commit or stash before releasing:" >&2
            git status --short >&2
            exit 1
        fi
    }
    require_version_tag() {
        if ! printf '%s' "$1" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?$'; then
            echo "'$1' is not a version tag (vX.Y.Z or vX.Y.Z-prerelease, e.g. v0.0.0-test.1)." >&2
            exit 2
        fi
    }
    ensure_signed_tag() {
        # Create the signed tag — unless it already exists pointing at HEAD, so
        # a retry after a failed publish resumes instead of failing here.
        if existing=$(git rev-parse -q --verify "refs/tags/$1^{commit}"); then
            if [ "$existing" != "$(git rev-parse HEAD)" ]; then
                echo "tag $1 already exists and does not point at HEAD — refusing." >&2
                exit 1
            fi
            # Only reuse a pre-existing tag if it is itself SIGNED — otherwise a
            # lightweight or unsigned tag placed on HEAD by hand would be pushed,
            # silently bypassing the `git tag -s` guarantee. We check that a
            # signature block is PRESENT (a lightweight tag has no tag object;
            # `git cat-file tag` on it fails and greps empty) rather than running
            # `git verify-tag`: verification additionally needs the signer's key
            # to be trusted — the GPG keyring, or gpg.ssh.allowedSignersFile for
            # SSH — and would reject a legitimately SSH-signed tag when that is
            # not set up, breaking the very retry this branch exists for.
            if ! git cat-file tag "refs/tags/$1" 2>/dev/null | grep -qE '^-----BEGIN [A-Z0-9]+ SIGNATURE-----'; then
                echo "tag $1 is on HEAD but is not a signed tag — refusing to reuse it." >&2
                echo "delete it and let the release create a fresh signed tag: git tag -d $1" >&2
                exit 1
            fi
            echo "tag $1 already on HEAD (signed) — reusing it."
        else
            git tag -s "$1" -m "$1"
        fi
    }
    # The DEFAULT (CI) lane's publish trigger: create the signed tag and push it.
    # Pushing a v* tag is what starts the release workflow — this is the ONE event
    # that owns publication in the CI lane. The --local lane, by contrast, pushes
    # only HEAD (never the tag) so it does NOT re-trigger this workflow: exactly
    # one publisher per release. See the --local lane below.
    tag_and_push() {
        ensure_signed_tag "$1"
        git push origin HEAD
        git push origin "refs/tags/$1"
    }
    set -- {{ args }}
    case "${1:-}" in
        --local)
            shift
            if [ "${1:-}" = "--dry-run" ]; then
                # Snapshot builds skip signing: no key material needed.
                exec goreleaser release --snapshot --clean --skip=sign
            fi
            key="${1:-}"
            if [ -z "$key" ]; then
                usage
                exit 2
            fi
            shift
            tag=""
            password=""
            password_from_stdin=""
            while [ $# -gt 0 ]; do
                case "$1" in
                    --cosign-password-stdin)
                        # A boolean flag, NOT a value: the passphrase is read from
                        # stdin below, so it never enters argv or shell history.
                        password_from_stdin=1
                        shift
                        ;;
                    -*)
                        echo "unknown option: $1" >&2
                        usage
                        exit 2
                        ;;
                    *)
                        if [ -n "$tag" ]; then
                            echo "unexpected argument: $1 (tag already given: $tag)" >&2
                            usage
                            exit 2
                        fi
                        tag="$1"
                        shift
                        ;;
                esac
            done
            if [ -z "$tag" ]; then
                usage
                exit 2
            fi
            if [ ! -f "$key" ]; then
                echo "cosign key not found: $key" >&2
                echo "generate a key pair once with 'cosign generate-key-pair'; commit cosign.pub, keep the private key out of the tree." >&2
                exit 1
            fi
            require_version_tag "$tag"
            require_clean
            if [ -z "${GITHUB_TOKEN:-}" ]; then
                echo "GITHUB_TOKEN is not set — goreleaser needs it to publish the GitHub release." >&2
                exit 1
            fi
            # cosign under goreleaser cannot prompt (no tty on its stdin), so the
            # passphrase is collected here and handed down via COSIGN_PASSWORD.
            # That env hand-off to the goreleaser→cosign subtree is unavoidable —
            # cosign has no other non-interactive channel — so the goal here is to
            # keep the passphrase out of argv/history and out of the caller's own
            # shell env: read it once, scoped to this run. Empty is legal (an
            # unencrypted key).
            if [ -n "$password_from_stdin" ]; then
                # --cosign-password-stdin: the passphrase is piped in, so `cat`
                # would echo it in cleartext if stdin were the terminal. Refuse
                # that footgun and point at the two safe forms.
                if [ -t 0 ]; then
                    echo "--cosign-password-stdin expects the passphrase piped on stdin, but stdin is a terminal." >&2
                    echo "pipe it (e.g. 'pass show cosign | just do release --local $key $tag --cosign-password-stdin'), or drop the flag to be prompted." >&2
                    exit 2
                fi
                # Read ALL of stdin; command substitution strips trailing
                # newlines, so a here-string, a `printf | ` pipe, and a file with
                # or without a trailing newline all yield the same passphrase.
                password=$(cat)
            else
                # No stdin channel: prompt on the terminal itself (/dev/tty, never
                # fd 0 — goreleaser may want stdin, and fd 0 may be redirected).
                printf 'cosign key password (empty for an unencrypted key): ' >&2
                read -rs password < /dev/tty
                echo >&2
            fi
            export COSIGN_KEY="$key"
            export COSIGN_PASSWORD="$password"
            # Sole-publisher discipline: create the signed tag and push the COMMIT,
            # but NOT the tag. goreleaser publishes the GitHub release itself (it
            # only needs the tag locally — `validate` checks the working tree, not
            # the remote — and creates the release, and its remote tag, through the
            # API). Because no `git push` of a v* tag happens, the release workflow
            # (on: push tags) never fires, so this machine is the only publisher —
            # no race with a second, CI-driven GoReleaser. The signed tag stays
            # local (the local lane is for private repos / a CI-down escape hatch);
            # the default lane is the one that puts a signed tag on the remote.
            ensure_signed_tag "$tag"
            git push origin HEAD
            exec goreleaser release --clean
            ;;
        --ci)
            # The workflow half: the tag exists (its push triggered this run,
            # and CI checks out exactly that commit), publishing uses the
            # workflow's GITHUB_TOKEN, and signing is keyless — the OIDC
            # identity replaces any key.
            if [ -z "${GITHUB_ACTIONS:-}" ]; then
                echo "--ci is the workflow half — locally, 'just do release <tag>' cuts the tag CI releases." >&2
                exit 1
            fi
            if [ -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ]; then
                echo "no OIDC token available — the workflow needs 'id-token: write' for keyless signing." >&2
                exit 1
            fi
            if [ -z "${GITHUB_TOKEN:-}" ]; then
                echo "GITHUB_TOKEN is not set — pass the workflow token to this step's env." >&2
                exit 1
            fi
            if ! git describe --exact-match --tags HEAD >/dev/null 2>&1; then
                echo "HEAD carries no tag — this lane only runs on a tag push." >&2
                exit 1
            fi
            # Keyless is enforced, not defaulted: a key leaking into the CI
            # environment must not silently flip the signing mode.
            unset COSIGN_KEY
            exec goreleaser release --clean
            ;;
        --dry-run)
            echo "dry runs are a local concern: use 'just do release --local --dry-run'." >&2
            exit 2
            ;;
        "")
            usage
            exit 2
            ;;
        -*)
            echo "unknown option: $1" >&2
            usage
            exit 2
            ;;
        *)
            # The default lane: cut the signed tag and push — the release
            # workflow takes it from here.
            tag="$1"
            shift
            if [ $# -gt 0 ]; then
                echo "unexpected argument: $1" >&2
                usage
                exit 2
            fi
            require_version_tag "$tag"
            require_clean
            tag_and_push "$tag"
            echo "tag $tag pushed — the release workflow builds, signs, and publishes from here."
            ;;
    esac
