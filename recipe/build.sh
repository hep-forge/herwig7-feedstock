#! /usr/bin/bash
set -eux

chmod +x configure

NPROC=$(nproc 2>/dev/null || sysctl -n hw.ncpu)

# ThePEG's shared libraries live under $PREFIX/lib/ThePEG (a
# subdirectory), which the toolchain's default rpath ($PREFIX/lib)
# doesn't cover -- confirmed the FINAL INSTALLED Herwig binary itself
# (not just a build-time transient) fails with "libThePEG.so.30:
# cannot open shared object file" without this, since Herwig's own
# Makefile.am only passes THEPEGLDFLAGS (-L, not -Wl,-rpath) when
# linking. Append (not replace) conda's own LDFLAGS.
export LDFLAGS="${LDFLAGS:-} -Wl,-rpath,${PREFIX}/lib/ThePEG"

# arm64-only: the bundled LoopTools Fortran (D/D0func.F, D/D0funcC.F)
# has an integer constant that overflows gfortran's default range
# check on aarch64 but not x86_64 ("Integer too big for its kind" /
# "must be a PARAMETER in DATA statement", both symptoms of the same
# range-check failure) -- gfortran's own error message names the fix.
case "$(uname -m)" in
  aarch64) export FFLAGS="${FFLAGS:-} -fno-range-check" ;;
esac

./configure \
  --prefix="${PREFIX}" \
  --with-thepeg="${PREFIX}" \
  --with-gsl="${PREFIX}" \
  --with-fastjet="${PREFIX}"

# Herwig's `make install` runs an install-data-hook that executes the
# freshly built (not-yet-installed) Herwig binary to generate its
# persistent repository file. That binary links against ThePEG via
# -L$PREFIX/lib/ThePEG (a subdirectory the toolchain's default rpath
# doesn't cover), and libtool's uninstalled build-tree wrapper script
# only auto-manages LD_LIBRARY_PATH for libraries built as part of
# *this* package -- not pre-installed external deps like ThePEG. The
# final installed binary gets a proper rpath from libtool at install
# time, so this is only needed to get through the install step itself.
export LD_LIBRARY_PATH="${PREFIX}/lib/ThePEG:${LD_LIBRARY_PATH:-}"

make -j"${NPROC}"

# That same install-data-hook default-repository generation step also
# sets default PDFs (src/defaults/PDF.in.in: CT14lo for
# HardLOPDF/ShowerLOPDF/MPIPDF/RemnantPDF, CT14nlo for HardNLOPDF/
# ShowerNLOPDF -- the complete set, checked directly against upstream's
# own default config), which require the actual PDF set *data* (not
# just the lhapdf library) to be present -- LHAPDF ships PDF sets as
# separate downloadable data, not bundled with the library. Installs
# into $PREFIX/share/LHAPDF, the same prefix this build already
# targets, so it ends up shipped as part of this package -- reasonable
# for two small (~few MB each), standard default sets needed for
# Herwig to have any usable out-of-the-box default at all.
lhapdf install CT14lo CT14nlo

make install

# same cross-package libtool interference class documented in
# thepeg-feedstock/recipe/build.sh -- strip Herwig's own .la files too.
find "${PREFIX}/lib" "${PREFIX}/lib64" -maxdepth 1 -name '*.la' -delete 2>/dev/null || true
