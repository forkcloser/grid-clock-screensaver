# DO NOT EDIT MANUALLY.
# This file provides shared tasks common to all projects and managed by limen.
# Project recipes live in the root Justfile, below the shared-baseline import.

set working-directory := '../..'

# Silence just's per-line command echo; recipes announce themselves via _banner.
set quiet

# Show the shared tasks.
default:
    @just --list do

mod build 'build.just'
mod tools 'tools.just'
mod lint 'lint.just'
mod test 'test.just'
mod fix 'fix.just'

# Flat (imported, not a module) so it takes arguments: `just do release v1.2.3`.
import 'release.just'
