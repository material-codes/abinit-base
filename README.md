# abinit-base

Prebuilt [ABINIT](https://www.abinit.org/) + [LibXC](https://libxc.gitlab.io/) Docker image — serial CPU build (no MPI), compiled from upstream sources on `debian:bookworm-slim`. Ships ABINIT at `/opt/abinit` and LibXC at `/opt/libxc`.

LibXC is built from source because Debian bookworm ships 5.2.3 and ABINIT 10.x needs 6.x. The LibXC version is pinned as a Dockerfile constant (single source of truth); see "Bump LibXC" below.

Intended as a base layer for downstream containers (workflow runners, CI fixtures, reproducibility artifacts) that need a known-good ABINIT binary without the build toolchain. **Not** intended for production HPC use.

## Pull

```sh
docker pull ghcr.io/material-codes/abinit-base:10.6.5
```

Image tag = ABINIT version. `latest` tracks the most recent release.

## Use as a base

```dockerfile
FROM ghcr.io/material-codes/abinit-base:10.6.5

RUN apt-get update && apt-get install -y --no-install-recommends \
        libopenblas0 \
        libfftw3-double3 \
        libfftw3-single3 \
        libnetcdff7 \
        libhdf5-103 \
        libgfortran5 \
        libgomp1 \
 && rm -rf /var/lib/apt/lists/*

ENV LD_LIBRARY_PATH=/opt/libxc/lib:/opt/abinit/lib \
    PATH=/opt/abinit/bin:$PATH
```

The base image ships only the ABINIT/LibXC binaries; runtime libraries are not included so consumers can choose their own.

## Build locally

```sh
docker build --build-arg ABINIT_VERSION=10.6.5 -t abinit-base:10.6.5 .
```

## Bumping the ABINIT version

1. Edit the `ARG ABINIT_VERSION` default in `Dockerfile` (both stages).
2. Commit, push.
3. Tag: `git tag v<new-version> && git push --tags`. The workflow publishes `ghcr.io/material-codes/abinit-base:<new-version>` and updates `latest`.

## Bumping LibXC

LibXC is pinned in the Dockerfile, not the tag. To bump:

1. Edit the `ARG LIBXC_VERSION` default in `Dockerfile` (both stages).
2. Cut a patch tag, e.g. `v10.6.5-1`. The image content is what changes; the ABINIT version in the headline tag stays the same.

## Licensing

The Dockerfile and CI in this repo are MIT-licensed (see `LICENSE`). The published image **contains** ABINIT and LibXC binaries built from upstream source and is therefore distributable under their respective licenses (ABINIT: GPL-3.0-or-later; LibXC: MPL-2.0). Refer to upstream sources for full terms.
