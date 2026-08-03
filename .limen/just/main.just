# DO NOT EDIT MANUALLY.
# This file provides shared tasks common to all projects and managed by limen.
# The root Justfile is the project's own: a shim that imports this file and
# then carries the project's recipes — everything shared lives here, so the
# shim never has to change.

# The project may redefine the shared recipes below (info, or an explicit
# default) in its root Justfile: the later definition — the project's — wins.
set allow-duplicate-recipes
# Likewise for variables: a project's root Justfile may re-export any variable
# set here (notably a hermetic GO* default below) and the importing file wins —
# so an override is explicit and tracked in the Justfile, never an ambient env
# var leaking in. Without this, a duplicate definition is a hard error, which
# is what makes the hermetic defaults below safe to force.
set allow-duplicate-variables

# Project name, derived from the directory the root Justfile lives in.
project := file_name(justfile_directory())

# brew — the one machine-layer tool a shared recipe may call (the homebrew
# modules) — is captured from the AMBIENT PATH here, above the hermetic PATH
# so the lookup still sees the invoking shell's environment: brew is not
# aqua-pinnable and installs at machine-chosen prefixes, so that shell knows
# best where it lives. Empty when absent (the homebrew recipes then fail with
# guidance); override by exporting BREW_BIN.
export BREW_BIN := env_var_or_default('BREW_BIN', `command -v brew || true`)

# Hermetic PATH: aqua-pinned tools + base system only (no homebrew), so any tool that
# isn't pinned fails loudly instead of silently resolving to an unpinned copy.
# Windows (git-bash) is the sanctioned exception to that hermeticity: there is no
# knowable base-system directory list (sh, coreutils, and git live at
# install-dependent roots), and the separator is ';' — so the pinned tools are
# prepended to the ambient PATH instead. Pins still shadow everything, and
# hermeticity stays enforced by the posix legs of the CI matrix.
aqua_bin := env_var_or_default('AQUA_ROOT_DIR', env_var_or_default('XDG_DATA_HOME', home_directory() / '.local/share') / 'aquaproj-aqua') / 'bin'
export PATH := if os() == 'windows' { aqua_bin + ';' + env_var('PATH') } else { aqua_bin + ":/usr/bin:/bin:/usr/sbin:/sbin" }

# Hermetic Go env: the PATH is pinned, but Go reads its behavior from a set of
# GO* environment variables that tunnel straight through it — so without this a
# recipe silently inherits the invoking shell's (or an IDE's) Go configuration
# and diverges from CI. Each is emptied or pinned rather than unexported: go
# treats '' as unset, and unlike `unexport` an `export` propagates into module
# recipes. All remain overridable by a project's root Justfile (see
# allow-duplicate-variables above) — an explicit, tracked override, never an
# ambient one.
#
#   GOROOT       an inherited value (IDEs inject one, often into the module
#                cache that `go clean -modcache` deletes) overrides where the
#                pinned go finds its stdlib; modern go derives it from its own
#                location, so '' is correct.
#   GOTOOLCHAIN  =local forbids silent toolchain switching: when go.mod
#                outpaces the pin, recipes fail loudly asking for a pin bump
#                instead of downloading an unpinned toolchain behind your back.
#   GOFLAGS      ambient flags (-mod=mod, -tags=…, -count=1) rewrite what every
#                go command does; '' leaves the recipes' own args the whole story.
#   GOSUMDB      pinned to the real checksum database so an ambient GOSUMDB=off
#                cannot defeat the GOSUMDB verification the go_install pins in
#                aqua.yaml depend on.
#   GOPRIVATE    '' so no module path is silently exempted from the proxy and
#                checksum db — a non-empty value is precisely how GOSUMDB gets
#                bypassed per-path.
#   GOPROXY      pinned to the default so an ambient GOPROXY=off or a stale
#                mirror cannot change where modules resolve from; a project
#                needing an internal proxy sets it in its own Justfile.
#   GOOS/GOARCH  '' = native. Ambient values silently cross-compile every
#                build/lint/test; the per-GOOS analysis sets GOOS itself where
#                it needs to (see _per-goos in lib.just), overriding this.
#
# GOWORK is deliberately NOT neutralized: a go.work in the tree — or a parent —
# SHOULD put the recipes into workspace mode. Go workspaces are a supported way
# to work here, the one sanctioned exception to Go-env hermeticity. The cost is
# eyes-open: a build under an active workspace can differ from a CI run (which
# has none), and that divergence is intended, not a leak.
export GOROOT := ''
export GOTOOLCHAIN := 'local'
export GOFLAGS := ''
export GOSUMDB := 'sum.golang.org'
export GOPRIVATE := ''
export GOPROXY := 'https://proxy.golang.org,direct'
export GOOS := ''
export GOARCH := ''

# Hermetic, per-project linter cache (same doctrine as PATH and GOROOT: no
# shared mutable state across repos). Lives under build/ — gitignored, and
# local runs behave like CI instead of diverging on cache state.
export GOLANGCI_LINT_CACHE := justfile_directory() / 'build/cache/golangci-lint'

# just's default recipe is the FIRST one defined in the root Justfile, so a
# project's first own recipe takes over from this one — deliberately: the
# default belongs to the project.
# Show every available recipe — the project's own and the shared `do` tree.
default:
    @just --list

# Print meaningful information about this project.
info:
    @echo "name:     {{ project }}"
    @echo "upstream: $(git remote get-url origin 2>/dev/null || echo '(none)')"
    @echo "semver:   $(git describe --tags --abbrev=0 2>/dev/null || echo '(none)')"
    @echo "commit:   $(git rev-parse --short HEAD 2>/dev/null || echo '(none)')"
    @echo "date:     $(git log --max-count=1 --format=%cd --date=short 2>/dev/null || echo '(none)')"

# Every shared limen task: `just do lint`, `just do build go`, `just do release v1.2.3` — the top level stays the project's.
mod do 'do.just'
