#!/usr/bin/env bash

set -e

CMAKE_MAKE_FLAGS="-j3"

perror_exit() { echo "$1" >&2 ; exit 1 ; }

[[ ":$PATH:" == *":/usr/local/bin:"* ]] || export PATH="/usr/local/bin:$PATH"
export CC=/usr/local/bin/gcc CXX=/usr/local/bin/g++

ASSETD="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )/assets"
[[ -d "$ASSETD" ]] || perror_exit "cannot access asset directory (expected '$ASSETD')"
OUTD="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )/output"
[[ -d "$OUTD" ]] || perror_exit "cannot access output directory (expected '$OUTD')"

HEXTD=$(mktemp -d)
git clone "https://github.com/html-extract/hext.git" "$HEXTD"

LIBHEXTD="$HEXTD/libhext"
cd "$LIBHEXTD/test/build"
cmake -DBUILD_SHARED_LIBS=Off ..
make $CMAKE_MAKE_FLAGS
./libhext-test

cd "$HEXTD/build"
cmake -DBUILD_SHARED_LIBS=Off -DCMAKE_POSITION_INDEPENDENT_CODE=On -DCMAKE_EXE_LINKER_FLAGS=" -static-libgcc -static-libstdc++ " ..
make $CMAKE_MAKE_FLAGS
make install

PYTHOND="$LIBHEXTD/bindings/python"
cd "$PYTHOND"
for i in /opt/python/cp* ; do
  V=$(basename $i)
  mkdir $V
  cd $V
  mkdir -p wheel/hext
  cp "$ASSETD/setup.py" "$ASSETD/README.md" "$ASSETD/MANIFEST.in" "$ASSETD/gumbo.license" "$ASSETD/rapidjson.license" wheel/

  PIP=$(readlink -f /opt/python/$V/bin/pip)
  $PIP install -U setuptools wheel
  PYTHON_PATH=$(readlink -f /opt/python/$V/include/*/)
  cmake -DCMAKE_CXX_FLAGS=" -static-libgcc -static-libstdc++ " -DPYTHON_INCLUDE_DIR="$PYTHON_PATH" -DBUILD_SHARED_LIBS=On ..
  make $CMAKE_MAKE_FLAGS
  cat hext.py\
    | sed '/^# This file was automatically generated by SWIG/,/^del _swig_python_version_info$/d'\
    | cat <(echo "from . import _hext") -\
    > wheel/hext/__init__.py
  strip --strip-unneeded _hext.so
  cp _hext.so wheel/hext

  mkdir wheel/bin
  cp /usr/local/bin/htmlext wheel/bin
  strip --strip-unneeded wheel/bin/htmlext

  cd wheel
  /opt/python/$V/bin/python setup.py bdist_wheel

  WHEEL=$(find . -iname "*linux*.whl")
  [[ -f "$WHEEL" ]] || perror_exit "cannot find wheel (*linux*.whl)"
  MANYLINUX_WHEEL="$(echo $WHEEL | sed 's/linux/manylinux1/')"
  mv "$WHEEL" "$MANYLINUX_WHEEL"

  cp "$MANYLINUX_WHEEL" "$OUTD"
  cd ../..
done

