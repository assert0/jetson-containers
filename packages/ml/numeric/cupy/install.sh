#!/usr/bin/env bash
set -ex

if [ "$FORCE_BUILD" == "on" ]; then
	echo "Forcing build of CuPy ${CUPY_VERSION}"
	exit 1
fi

# Try with the default index first, fallback to PyPI if it fails
uv pip install --default-index "${PIP_INDEX_URL:-https://pypi.org/simple}" cupy==${CUPY_VERSION} || \
  uv pip install --default-index https://pypi.org/simple cupy==${CUPY_VERSION}
