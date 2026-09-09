set -ex

# Try with the default index first, fallback to PyPI if it fails
uv pip install --force-reinstall --default-index "${PIP_INDEX_URL:-https://pypi.org/simple}" ${NUMPY_PACKAGE} || \
  uv pip install --force-reinstall --default-index https://pypi.org/simple ${NUMPY_PACKAGE}
uv pip show numpy && python3 -c 'import numpy; print(numpy.__version__)'

set +e

# some libraries are more tightly-coupled with numpy and might not like minor version changes.
# for example, numba 0.61 requires numpy<2.2.
uv pip show numba

if [ $? = 0 ]; then
  python3 -c 'import numba'
  if [ $? != 0 ]; then # numba failed to import (presumably due to numpy being changed)
    # Try with the default index first, fallback to PyPI if it fails
    uv pip install --force-reinstall --default-index "${PIP_INDEX_URL:-https://pypi.org/simple}" numba || \
      uv pip install --force-reinstall --default-index https://pypi.org/simple numba
  fi
fi
