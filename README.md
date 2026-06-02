# abinit-base

Prebuilt Docker base image for [ABINIT](https://www.abinit.org/) and [LibXC](https://libxc.gitlab.io/) — serial CPU build, compiled from upstream sources on `debian:bookworm-slim`. Ships ABINIT at `/opt/abinit` and LibXC at `/opt/libxc`.

LibXC is built from source because Debian bookworm ships 5.2.3 and ABINIT 10.x requires LibXC 6.x. The LibXC version is pinned as a Dockerfile constant (single source of truth); see [Bumping LibXC](#bumping-libxc) below.

Designed as a thin, predictable base layer that downstream containers can `FROM` to add their own runtime environment, pseudopotentials, and entrypoint — without paying the ~14-minute compile cost on every build.

## When to use this image

**Good fits:**
- **CI fixtures** that need a real `abinit` binary to test input generation, output parsing, or workflow logic
- **Reproducibility artifacts** for published calculations — image tags are immutable, so `ghcr.io/material-codes/abinit-base:10.6.7` ships exactly the ABINIT/LibXC binaries that were current at release time
- **Education / classroom use** where students need a working ABINIT + LibXC stack without battling autotools and upstream-vs-Debian version skew
- **Workflow runners** (e.g. material/core's `abinitrunner`) that want a known-good binary as a base layer
- **Small-to-medium calculations** that fit on a single node and don't need MPI parallelism

**Not a fit:**
- **Production HPC** — no MPI, no GPU, no Wannier90, no BigDFT integration. For real HPC, build from source against your center's MPI and BLAS, or use [the official ABINIT containers](https://gitlab.abinit.org/container-images) where they exist
- **Calculations requiring `bigdft`, `triqs`, `wannier90`, or `libpsml`** — these optional dependencies are not enabled in this build
- **GPU-accelerated runs** — the `--with-gpu` flag is not set; ABINIT GPU support requires a CUDA toolchain in the build stage

## What's inside

| Path | Contents |
|---|---|
| `/opt/abinit/bin/abinit` | Main ABINIT executable (DFT, GW, BSE, DFPT, etc. — see ABINIT docs for the full calculation menu) |
| `/opt/abinit/bin/*` | ABINIT support tools (atompaw, mrgddb, etc., as built by the default install target) |
| `/opt/libxc/lib/libxc.so` | LibXC shared library (C interface; Fortran interface disabled to keep dependencies minimal) |

The image is `FROM debian:bookworm-slim` and **does not include runtime libraries**. Downstream consumers install BLAS, FFTW, NetCDF-Fortran, HDF5, and runtime gfortran themselves — see [Use as a base](#use-as-a-base) below.

**Build configuration:**

| Setting | Value |
|---|---|
| Compilers | `gfortran`, `gcc`, `g++` (Debian bookworm) |
| BLAS | `libopenblas` (link-time) |
| FFTW | `libfftw3` (link-time) |
| NetCDF-Fortran | `libnetcdff-dev` (build), `libnetcdff7` (runtime) |
| HDF5 | `libhdf5-dev` (build), `libhdf5-103` (runtime) |
| LibXC | 6.2.2 (built from source, C interface only) |
| MPI | disabled (`--with-mpi=no`) |
| BigDFT / Wannier90 / TRIQS | disabled (default) |

The build is two-stage: an `abinit-builder` stage with the full compile toolchain (autotools, dev headers), and a final `debian:bookworm-slim` stage that copies only `/opt/libxc` and `/opt/abinit`. The final image carries no build artifacts beyond the binaries themselves.

## Pull

```sh
docker pull ghcr.io/material-codes/abinit-base:10.6.7
```

| Tag pattern | Meaning |
|---|---|
| `<version>` (e.g. `10.6.7`) | Pinned to a specific ABINIT release. Immutable. |
| `<version>-N` (e.g. `10.6.7-1`) | Patch revision — ABINIT version unchanged, but a build dependency (LibXC, Debian base) bumped. |
| `latest` | Tracks the most recent release tag. Moves over time. |

For reproducibility, **always pin a specific version** in production references; reserve `latest` for exploration.

## Use as a base

```dockerfile
FROM ghcr.io/material-codes/abinit-base:10.6.7

# Add the runtime libraries ABINIT and LibXC link against.
RUN apt-get update && apt-get install -y --no-install-recommends \
        libopenblas0 \
        libfftw3-double3 \
        libfftw3-single3 \
        libnetcdff7 \
        libhdf5-103 \
        libgfortran5 \
        libgomp1 \
 && rm -rf /var/lib/apt/lists/*

# LibXC and ABINIT install separately into /opt/libxc and /opt/abinit; the
# linker needs both directories on its search path.
ENV LD_LIBRARY_PATH=/opt/libxc/lib:/opt/abinit/lib \
    PATH=/opt/abinit/bin:$PATH
```

**Pseudopotentials** are not bundled. ABINIT consumes its own formats (`.psp8` for ONCV norm-conserving, `.xml` for PAW), distinct from QE's `.upf`. PseudoDojo publishes both formats; downstream containers should fetch and stage what they need:

```dockerfile
RUN curl -fsSL https://www.pseudo-dojo.org/pseudos/nc-sr-04_pbe_stringent_psp8.tgz \
      | tar -xz -C /opt/pseudodojo
```

(For GW work specifically, the PBE-stringent ONCV set is the standard starting point.)

## Build locally

```sh
docker build --build-arg ABINIT_VERSION=10.6.7 -t abinit-base:10.6.7 .
```

The build is **slow** (~14 minutes on a fast amd64 runner): LibXC's autoreconf + configure + compile takes ~3 minutes, ABINIT's configure + compile takes ~10 minutes. There's no parallelism between the two — LibXC must finish first because ABINIT's configure tests `--with-libxc`.

On Apple Silicon (M1/M2/M3), the build runs under qemu emulation when targeting `linux/amd64` — expect noticeably longer compile times (~10× slower) than on a native amd64 host. For local iteration on Apple Silicon, build natively:

```sh
docker build --platform linux/arm64 --build-arg ABINIT_VERSION=10.6.7 -t abinit-base:10.6.7-arm64 .
```

The published GHCR image is `linux/amd64` only.

## Bumping the ABINIT version

1. Edit `ARG ABINIT_VERSION` default in `Dockerfile` (both stages must match).
2. Commit, push to `main`. **No build runs yet** — the workflow only triggers on tags.
3. Cut the tag: `git tag v<new-version> && git push --tags`. The GHA workflow publishes `ghcr.io/material-codes/abinit-base:<new-version>` and updates `latest`. ~14 minutes on a cold cache; faster on a warm GHA cache.

The trigger is `tags: ['v*']`, so unrelated tags would also fire the workflow — keep tag names limited to ABINIT version pins.

## Bumping LibXC

LibXC's version is pinned in the Dockerfile as `ARG LIBXC_VERSION` (single source of truth — the workflow does not pass it as a build-arg). To bump:

1. Edit `ARG LIBXC_VERSION` default in `Dockerfile` (both stages must match).
2. Cut a **patch revision tag** of the current ABINIT version, e.g. `v10.6.7-1`. The published image will be `ghcr.io/material-codes/abinit-base:10.6.7-1`. The original `10.6.7` image stays in place (tag immutability), and `latest` moves to the patch.

This separation lets you bump LibXC independently of the headline ABINIT version while keeping the QE-version semantics of the primary tag unambiguous.

## Versioning policy

Image tags follow ABINIT's upstream release versioning (e.g. ABINIT release `10.6.7` → image tag `10.6.7`). Patch revisions (LibXC bump, Debian base bump, build-arg default change) get a `-N` suffix.

If a future release switches to MPI-enabled or GPU-enabled builds, that should be a parallel image namespace (`abinit-base-mpi`, `abinit-base-cuda`) rather than overloading this tag stream.

## Licensing

The Dockerfile and CI in this repo are MIT-licensed (see `LICENSE`).

The published image **contains** binaries built from upstream source and is therefore distributable under their respective licenses:
- **ABINIT** — GPL-3.0-or-later (see [ABINIT source](https://gitlab.abinit.org/abinit/abinit) for full terms)
- **LibXC** — MPL-2.0 (see [LibXC source](https://gitlab.com/libxc/libxc) for full terms)

When using the image in published work, please cite both ABINIT and LibXC per their respective citation guidance.
