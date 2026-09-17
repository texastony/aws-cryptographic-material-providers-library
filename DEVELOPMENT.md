# Development Guide

This document covers building the AWS Cryptographic Material Providers Library (MPL)
**from source**. For the runtime dependencies needed to _use_ a published build of the
library (AWS SDKs, etc.), see the [README](README.md#optional-prerequisites) instead.

This library is written in Dafny and transpiled into each target runtime (Java, .NET,
Python, Rust, Go). The build chain is defined by this repo's GitHub Actions workflows
(`.github/workflows/`) and composite actions (`.github/actions/`) — those are the source
of truth; this document explains how to reproduce that chain locally.

## 1. Submodules

This repo vendors a few dependencies as git submodules:

```sh
git submodule update --init libraries
git submodule update --init --recursive smithy-dafny
```

`aws-encryption-sdk-specification` is a private submodule. CI does not initialize it
(see the comment in `.github/workflows/library_codegen.yml`), and neither do you unless
you specifically have access and need the specification sources.

## 2. Toolchain

Building even a single language target (e.g. Java) pulls in a surprising number of
tools, because Smithy-Dafny's codegen dependencies are installed unconditionally in CI
regardless of which runtime you're building. As of this writing, building for **Java**
requires:

| Tool            | Version                                                               | Why                                                                                                                                                         |
| --------------- | --------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| .NET SDK        | 9.0.x                                                                 | Needed to run the Dafny CLI itself (`.github/actions/setup_dafny`)                                                                                          |
| Dafny CLI       | pinned in [`project.properties`](project.properties) (`dafnyVersion`) | Transpiles `.dfy` sources to each target language                                                                                                           |
| Java (Corretto) | 8 **and** 17                                                          | 17 for Smithy-Dafny codegen tooling; Gradle's toolchain auto-detection needs both 8 and 17 present for various modules (e.g. `StandardLibrary` pins Java 8) |
| Python          | 3.11 + `black==25.1`, `docformatter==1.7.7`, `tox`                    | Formats/tests generated code when codegen runs (`.github/actions/install_smithy_dafny_codegen_dependencies`)                                                |
| Go              | 1.24 + `goimports@v0.36.0`                                            | Same codegen-dependencies action; only exercised if you regenerate Go bindings                                                                              |
| Node.js         | any recent LTS                                                        | `make setup_prettier` — only needed if you regenerate smithy-dafny code (`make polymorph_java`)                                                             |

**Rust is _not_ required** for a Java build. `cargo`/`rustc` only appear in
`smithy-dafny/SmithyDafnyMakefile.mk`'s Rust runtime build/test targets — the
`mvn_local_deploy_polymorph_dependencies` step that touches `smithy-rs` only runs its
Gradle wrapper (pure JVM), never the actual Rust compiler.

Fedora/RHEL-family distros (and possibly others) only ship recent JDK majors in their
package repos — no Java 8 or 17 — so a bare-metal install may require a JDK version
manager (SDKMAN, etc.) regardless of OS.

### Recommended: container

The `.devcontainer/` directory has a `Containerfile` that installs the exact toolchain
above on an `ubuntu-22.04` base (matching the CI runner OS), plus a `run.sh` wrapper
that bind-mounts the repo and persists Gradle/Maven/NuGet caches across runs in named
volumes. Works with Docker or Podman (rootless podman needs no `sudo`).

```sh
# Build the image once (or after editing .devcontainer/Containerfile)
podman build -t mpl-dev:latest -f .devcontainer/Containerfile \
  --build-arg USER_UID=$(id -u) --build-arg USER_GID=$(id -g) .

# Create the cache volumes once
podman volume create mpl-gradle-cache
podman volume create mpl-m2-cache
podman volume create mpl-dotnet-cache

# Drop into a shell with the toolchain and repo available at /workspace
./.devcontainer/run.sh
```

(Swap `podman` for `docker` in the build command if you're using Docker instead — `run.sh` itself just needs `podman` on `PATH`, or edit it to call `docker`.)

If you bump `dafnyVersion` in `project.properties`, rebuild the image with
`--build-arg DAFNY_VERSION=<new version>` (or edit the `ARG` default in the
Containerfile) — the Dafny CLI version is pinned there, not auto-detected.

### Bare-metal alternative

If you'd rather not containerize, install the tools in the table above directly
(a JDK version manager like SDKMAN is recommended for getting Java 8 _and_ 17
side-by-side) and skip straight to [3. Building](#3-building) below.

## 3. Building

These are the same steps CI runs in `.github/workflows/library_java_build.yml`. All
commands below assume you're either inside the dev container (`./.devcontainer/run.sh`)
or have the bare-metal toolchain on `PATH`, from the repo root.

```sh
# Publish Smithy-Dafny's codegen modules to the local Maven repo.
make -C smithy-dafny mvn_local_deploy_polymorph_dependencies

# One-time workaround: the *first* Gradle wrapper invocation in a fresh environment
# prints a "Downloading gradle..." progress line that corrupts a Makefile $(shell ...)
# variable used later to build the `dafny translate` command line, breaking the very
# next build with a confusing "'Downloading' is neither a recognized option nor a
# filename" error. Run any throwaway Gradle-backed target once first to prime the
# ~/.gradle wrapper cache (CI does exactly this):
make -C StandardLibrary setup_net

# Build TestVectorsAwsCryptographicMaterialProviders, which recursively transpiles
# and builds all of its dependency libraries (StandardLibrary,
# AwsCryptographyPrimitives, ComAmazonawsKms, ComAmazonawsDynamodb,
# AwsCryptographicMaterialProviders) and publishes them to Maven local.
make -C TestVectorsAwsCryptographicMaterialProviders build_java CORES=4

# build_java only transpiles each dependency's implementation; also transpile their
# tests if you want to run them.
for lib in StandardLibrary AwsCryptographyPrimitives ComAmazonawsKms ComAmazonawsDynamodb AwsCryptographicMaterialProviders; do
  make -C "$lib" transpile_test_java CORES=4
done
```

This does **not** regenerate code from the Smithy models — it builds the Dafny/Java
sources already checked into the repo. To regenerate (e.g. after changing a `.smithy`
model), see `.github/actions/polymorph_codegen/action.yml` and the `polymorph_dafny`
/ `polymorph_java` Makefile targets in `smithy-dafny/SmithyDafnyMakefile.mk`.

## 4. Testing

Per-library, per-JDK tests (mirroring `.github/workflows/library_java_tests.yml`):

```sh
cd AwsCryptographicMaterialProviders/runtimes/java   # or any other library
./gradlew runTests
./gradlew test --info
```

Some tests (anything touching KMS or DynamoDB) need real AWS credentials for an
account with the relevant test fixtures — see the `Configure AWS Credentials for
Tests` step in `library_java_tests.yml` for which libraries require this.
