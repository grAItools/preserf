FROM mcr.microsoft.com/devcontainers/base:bookworm

# Pixi is the only extra tool this project needs; it provisions Python, the
# Fortran toolchain, NetCDF, and every dev tool from conda-forge.
# Copy the official static binary into /usr/local/bin so it is on PATH for
# every user with no curl-at-create-time and no PATH gymnastics.
# Keep this tag in lockstep with `pixi-version` in .github/workflows/ci.yml
# so CI and the devcontainer resolve `pixi.lock` with the same pixi.
# NOTE on tag format: the OCI image tag is the bare version (e.g. `0.70.1`);
# the `pixi-version` field in ci.yml is a GitHub release tag and takes a
# leading `v` (`v0.70.1`). Bump both, but keep the formats distinct.
COPY --from=ghcr.io/prefix-dev/pixi:0.70.1 /usr/local/bin/pixi /usr/local/bin/pixi
