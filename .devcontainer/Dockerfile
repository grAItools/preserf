FROM mcr.microsoft.com/devcontainers/base:bookworm

# Pixi is the only extra tool this project needs; it provisions Python, the
# Fortran toolchain, NetCDF, and every dev tool from conda-forge.
# Copy the official static binary into /usr/local/bin so it is on PATH for
# every user with no curl-at-create-time and no PATH gymnastics.
COPY --from=ghcr.io/prefix-dev/pixi:0.70.1 /usr/local/bin/pixi /usr/local/bin/pixi
