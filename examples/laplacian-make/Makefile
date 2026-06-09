# preserf example: consume the INSTALLED preserf_fortran library from plain make.
#
# Prerequisite: the runtime library has been built and installed with CMake
# into PREFIX (run.sh does this first):
#
#     cmake -S "$(preserf --fortran-dir)" -B build/runtime \
#         -DCMAKE_INSTALL_PREFIX=PREFIX -DCMAKE_INSTALL_LIBDIR=lib
#     cmake --build build/runtime --target install
#
# This Makefile then does, by hand, what the PreserfFortran.cmake helper does
# for a CMake consumer, so every step the install path needs is visible:
#
#   expand !$SER  ->  compile (.F90, cpp, SERIALIZE, F2008)  ->  link (lib + netcdf)
#
# Usage:  make PREFIX=/path/to/prefix

# --- knobs --------------------------------------------------------------------
# NB these are simple `:=` assignments, not `?=`: an activated conda/pixi env
# exports BUILD (the build triple) and PREFIX (the env root), and make lets an
# environment variable win over a `?=` default — which would silently redirect
# the output dir or the module search. Command-line overrides (make PREFIX=...)
# still win over `:=`, so run.sh passes PREFIX that way.
PREFIX     := prefix
PRESERF    := preserf
PKG_CONFIG := pkg-config
BUILDDIR   := build
# The !$SER-annotated source is shared with the CMake example next door —
# single source of truth, two build systems.
SRC        := ../laplacian/laplacian.f90
# FC is taken from the environment when set (conda/pixi point it at their own
# gfortran), else defaults to gfortran.
FC         ?= gfortran

# Installed layout (GNUInstallDirs, with LIBDIR pinned to `lib` by run.sh so
# this path is the same on distros where it would default to lib64).
MODDIR := $(PREFIX)/include/preserf_fortran
LIBDIR := $(PREFIX)/lib

# netcdf-fortran is a PUBLIC dependency of the static libpreserf_fortran.a, so
# the consumer has to link it too — a static archive carries no link interface.
# Discover its flags the same way the library's own build did.
NETCDF_LIBS := $(shell $(PKG_CONFIG) --libs netcdf-fortran)

# Compile flags — the recipe the CMake helper would otherwise apply for you:
#   -cpp                     run the C preprocessor for the #ifdef SERIALIZE guards
#   -DSERIALIZE              turn the guarded serialization calls ON (else no-op)
#   -ffree-line-length-none  preserf emits long single-line calls (>132 columns)
#   -std=f2008               the runtime + generated code use Fortran 2008
#   -I$(MODDIR)              find the installed m_serialize.mod / m_preserf.mod
FFLAGS := -cpp -DSERIALIZE -ffree-line-length-none -std=f2008 -I$(MODDIR)

# --- rules --------------------------------------------------------------------
.PHONY: all clean check-prefix
all: $(BUILDDIR)/laplacian

# Fail early with a clear message if PREFIX doesn't point at an install (e.g.
# a conda/pixi shell where $PREFIX is the env root) instead of a cryptic
# "cannot open module file m_serialize.mod" from the compiler.
check-prefix:
	@test -f "$(MODDIR)/m_serialize.mod" || { \
	  echo "error: $(MODDIR)/m_serialize.mod not found."; \
	  echo "       Install the runtime first and pass its prefix, e.g.:"; \
	  echo "         make PREFIX=./prefix"; \
	  exit 1; }

# 1. Expand the !$SER directives. The output is .F90 (uppercase) so the
#    compiler runs cpp on it in the next step.
$(BUILDDIR)/laplacian.F90: $(SRC) | $(BUILDDIR)
	$(PRESERF) $< -o $@

# 2. Compile the generated source against the installed module interface.
$(BUILDDIR)/laplacian.o: $(BUILDDIR)/laplacian.F90 | check-prefix
	$(FC) $(FFLAGS) -c $< -o $@

# 3. Link against the installed static library + netcdf-fortran. Order matters
#    for static linking: the dependency (-lnetcdff, via NETCDF_LIBS) must come
#    AFTER -lpreserf_fortran.
$(BUILDDIR)/laplacian: $(BUILDDIR)/laplacian.o
	$(FC) $< -L$(LIBDIR) -lpreserf_fortran $(NETCDF_LIBS) -o $@

$(BUILDDIR):
	mkdir -p $(BUILDDIR)

clean:
	rm -rf $(BUILDDIR)
