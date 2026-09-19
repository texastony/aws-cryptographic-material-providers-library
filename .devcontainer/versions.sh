#!/usr/bin/env bash
# Single source of truth for the toolchain versions .devcontainer/Containerfile builds.
#
# Every value here is parsed fresh from the file that actually governs it in CI, instead
# of being copied into a second, independently-maintained literal. That way there is
# nothing to keep in sync by hand: bump project.properties or a workflow file, and the
# next build picks it up automatically. If a pattern below stops matching (the upstream
# file was renamed, reformatted, etc.), this script fails loudly rather than silently
# resolving an empty or stale value.
#
# This is meant to be *executed*, not sourced (sourcing would leak `set -euo pipefail`,
# and a failure's `exit 1`, into the caller's interactive shell -- surprising and, in
# the exit case, would close their terminal). Run it via command substitution instead:
#
#   eval "$(.devcontainer/versions.sh)"
#
# which works the same in bash or zsh and only ever affects the current shell's
# variables, never its options.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# resolve NAME VALUE DESCRIPTION
# Prints `export NAME='VALUE'` on success, or fails loudly (stderr + non-zero exit) if
# VALUE is empty.
resolve() {
    local name="$1" value="$2" description="$3"
    if [ -z "$value" ]; then
        echo "ERROR: could not resolve $name ($description)." >&2
        echo "       The file/pattern this script expects may have changed upstream -- see .devcontainer/versions.sh." >&2
        exit 1
    fi
    printf 'export %s=%q\n' "$name" "$value"
}

# --- DAFNY_VERSION: project.properties, the project-wide canonical source (see its own
# header comment, and .github/workflows/dafny_versions.yaml, which reads it for CI). ---
DAFNY_VERSION="$(grep '^dafnyVersion=' "$REPO_ROOT/project.properties" | cut -d= -f2 || true)"
resolve DAFNY_VERSION "$DAFNY_VERSION" "project.properties:dafnyVersion"

# --- DOTNET_CHANNEL: .github/actions/setup_dafny/action.yml, the "Setup .NET Core SDK"
# step -- this is the .NET version needed to run the Dafny CLI itself. Containerfile
# wants a channel like "9.0", not the "9.0.x" floating-patch form used there. ---
DOTNET_CHANNEL="$(grep -oP 'dotnet-version:\s*"\K[^"]+' "$REPO_ROOT/.github/actions/setup_dafny/action.yml" | sed 's/\.x$//' || true)"
resolve DOTNET_CHANNEL "$DOTNET_CHANNEL" ".github/actions/setup_dafny/action.yml:dotnet-version"

# --- JAVA17_VERSION / GO_VERSION: .github/actions/install_smithy_dafny_codegen_dependencies/action.yml.
# Both appear exactly once in that file, each inside a Wandalen/wretry.action `with: |`
# string block (the wrapped action's inputs are a literal string, not nested YAML), so a
# plain grep is the correct tool here -- a YAML parser wouldn't see into that block
# any more easily. ---
JAVA17_VERSION="$(grep -oP 'java-version:\s*"\K[^"]+' "$REPO_ROOT/.github/actions/install_smithy_dafny_codegen_dependencies/action.yml" || true)"
resolve JAVA17_VERSION "$JAVA17_VERSION" "install_smithy_dafny_codegen_dependencies/action.yml:java-version"

GO_VERSION="$(grep -oP 'go-version:\s*"\K[^"]+' "$REPO_ROOT/.github/actions/install_smithy_dafny_codegen_dependencies/action.yml" || true)"
resolve GO_VERSION "$GO_VERSION" "install_smithy_dafny_codegen_dependencies/action.yml:go-version"

# --- PYTHON_VERSION: same file's own `inputs.python-version.default`. This one IS real
# structured YAML (not a wretry string block), but there's a second, unrelated `default:`
# for the mpl-submodule-path input right after it -- isolate the python-version input's
# block first so we don't accidentally grab the wrong one. ---
PYTHON_VERSION="$(sed -n '/^  python-version:/,/^  [a-z-]*:$/p' "$REPO_ROOT/.github/actions/install_smithy_dafny_codegen_dependencies/action.yml" | grep -oP 'default:\s*"\K[^"]+' || true)"
resolve PYTHON_VERSION "$PYTHON_VERSION" "install_smithy_dafny_codegen_dependencies/action.yml:inputs.python-version.default"

# --- JAVA8_VERSION: .github/workflows/library_java_build.yml's "Setup Java 8" step.
# Java 8 isn't part of the codegen-dependencies action above (only 17 is) -- it's added
# separately by each build/test workflow -- and its value is an unquoted YAML integer,
# unlike the quoted Java 17 string above. ---
JAVA8_VERSION="$(grep -A4 'name: Setup Java 8' "$REPO_ROOT/.github/workflows/library_java_build.yml" | grep -oP 'java-version:\s*\K[0-9]+' || true)"
resolve JAVA8_VERSION "$JAVA8_VERSION" "library_java_build.yml:java-version (Setup Java 8 step)"

# NODE_MAJOR is deliberately NOT resolved here -- see the comment on its ARG in
# Containerfile. There is no canonical source for it: the only Node version pins in this
# repo (semantic_release.yml, sem_ver.yml) are for unrelated release tooling, not the
# MPL build/codegen chain this container mirrors.
