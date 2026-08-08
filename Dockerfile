# syntax=docker/dockerfile:1.7

# Builder: compile LibXC + ABINIT from source on Debian bookworm.
FROM debian:bookworm AS abinit-builder
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        gfortran \
        libopenblas-dev \
        libfftw3-dev \
        libnetcdff-dev \
        libhdf5-dev \
        pkgconf \
        python3-dev \
        autoconf \
        automake \
        libtool \
        wget \
        ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# LibXC — Debian's libxc is 5.2.3, ABINIT 10.x needs 6.x.
# Version pin is the source of truth; bump here to bump LibXC, then cut a
# new patch tag (e.g. v10.8.3-1).
# Fortran interface disabled; ABINIT links against the C interface.
ARG LIBXC_VERSION=6.2.2
WORKDIR /src
RUN wget -q -O libxc.tar.gz \
        "https://gitlab.com/libxc/libxc/-/archive/${LIBXC_VERSION}/libxc-${LIBXC_VERSION}.tar.gz" \
 && tar -xzf libxc.tar.gz \
 && cd libxc-${LIBXC_VERSION} \
 && autoreconf -i \
 && ./configure --prefix=/opt/libxc --enable-shared --disable-fortran \
 && make -j"$(nproc)" \
 && make install \
 && cd .. && rm -rf libxc.tar.gz libxc-${LIBXC_VERSION}

# ABINIT from forge release tarball (GitHub mirror lacks Makefile.am).
ARG ABINIT_VERSION=10.8.3
RUN wget -q -O abinit.tar.gz \
        "https://forge.abinit.org/abinit-${ABINIT_VERSION}.tar.gz" \
 && tar -xzf abinit.tar.gz \
 && cd abinit-${ABINIT_VERSION} \
 && ./configure \
        --prefix=/opt/abinit \
        --with-mpi=no \
        --with-libxc=/opt/libxc \
        --with-netcdf-fortran \
        --with-hdf5 \
        FC=gfortran CC=gcc CXX=g++ \
 && make -j"$(nproc)" \
 && make install \
 && cd .. && rm -rf abinit.tar.gz abinit-${ABINIT_VERSION}

# Final stage: ship /opt/libxc and /opt/abinit on debian:bookworm-slim.
# Downstream images FROM this and add their own runtime libs + entrypoint.
FROM debian:bookworm-slim
ARG ABINIT_VERSION=10.8.3
ARG LIBXC_VERSION=6.2.2
COPY --from=abinit-builder /opt/libxc /opt/libxc
COPY --from=abinit-builder /opt/abinit /opt/abinit
LABEL org.opencontainers.image.title="abinit-base" \
      org.opencontainers.image.version="${ABINIT_VERSION}" \
      org.opencontainers.image.source="https://github.com/material-codes/abinit-base" \
      org.opencontainers.image.description="Prebuilt ABINIT ${ABINIT_VERSION} + LibXC ${LIBXC_VERSION} — serial CPU build."
