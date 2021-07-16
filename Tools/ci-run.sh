#!/usr/bin/bash

GCC_VERSION=${GCC_VERSION:=8}

if [[ $BACKEND == *"cpp"* ]]; then
  BACKEND_IS_CPP=true
  ALTERNATIVE_FLAGS=" --slave /usr/bin/g++ g++ /usr/bin/g++-$GCC_VERSION"
else
  BACKEND_IS_CPP=false
  ALTERNATIVE_FLAGS=""
fi

# Set up compilers
echo "Setting up compilers"
if [[ $OSTYPE == "linux"* && "$TEST_CODE_STYLE" != "1" ]]; then
  echo "Installing requirements [apt]"
  sudo apt-add-repository -y "ppa:ubuntu-toolchain-r/test"
  sudo apt update -y -q
  sudo apt install -y -q ccache gdb python-dbg python3-dbg gcc-$GCC_VERSION || exit 1

  if [[ $BACKEND_IS_CPP = true ]]; then
    sudo apt install -y -q g++-$GCC_VERSION || exit 1
  fi
  sudo /usr/sbin/update-ccache-symlinks
  echo "/usr/lib/ccache" >> $GITHUB_PATH # export ccache to path

  sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-$GCC_VERSION 60 $(echo $ALTERNATIVE_FLAGS)

  export CC="gcc"
  if [[ $BACKEND_IS_CPP = true ]]; then
    sudo update-alternatives --set g++ /usr/bin/g++-$GCC_VERSION
    export CXX="g++"
  fi

elif [[ $OSTYPE == "darwin"* ]]; then
  export CC="clang -Wno-deprecated-declarations"
  export CXX="clang++ -stdlib=libc++ -Wno-deprecated-declarations"

elif [[ $OSTYPE == "msys" ]]; then
  export CC="clang -Wno-deprecated-declarations"
  export CXX="clang++ -stdlib=libc++ -Wno-deprecated-declarations"

else
  echo "Unexpected OS $OSTYPE: '$OS_NAME'"
  exit 1
fi
echo "Configured for $OSTYPE: '$OS_NAME'"

# Set up miniconda
if [[ $STACKLESS == "true" ]]; then
  echo "Installing stackless python"
  #conda install --quiet --yes nomkl --file=test-requirements.txt --file=test-requirements-cpython.txt
  conda config --add channels stackless
  conda install --quiet --yes stackless || exit 1
fi

# Log versions in use
echo "===================="
echo "|VERSIONS INSTALLED|"
echo "===================="
python -c 'import sys; print("Python %s" % (sys.version,))'
if [[ $CC ]]; then
  which ${CC%% *}
  ${CC%% *} --version
fi
if [[ $CXX ]]; then
  which ${CXX%% *}
  ${CXX%% *} --version
fi
echo "===================="

# Install python requirements
echo "Installing requirements [python]"
if [[ $PYTHON_VERSION == "2.7"* ]]; then
  pip install wheel || exit 1
  pip install -r test-requirements-27.txt || exit 1
elif [[ $PYTHON_VERSION == "3."[45]* ]]; then
  python -m pip install wheel || exit 1
  python -m pip install -r test-requirements-34.txt || exit 1
else
  python -m pip install -U pip setuptools wheel || exit 1

  if [[ $PYTHON_VERSION == *"-dev" || $COVERAGE == "1" ]]; then
    python -m pip install -r test-requirements.txt || exit 1

    if [[ $PYTHON_VERSION == "pypy"* && $PYTHON_VERSION == "3."[4789]* ]]; then
      python -m pip install -r test-requirements-cpython.txt || exit 1
    fi
  fi
fi

if [[ $TEST_CODE_STYLE == "1" ]]; then
  STYLE_ARGS="--no-unit --no-doctest --no-file --no-pyregr --no-examples";
  python -m pip install -r doc-requirements.txt || exit 1
else
  RUNTESTS_ARGS="$RUNTESTS_ARGS -j7"
  STYLE_ARGS="--no-code-style";
  
  # Install more requirements
  if [[ $PYTHON_VERSION == *"-dev" ]]; then
    if [[ $BACKEND_IS_CPP = true ]]; then
      echo "WARNING: Currently not installing pythran due to compatibility issues"
      # python -m pip install pythran==0.9.5 || exit 1

    elif [[ $PYTHON_VERSION == "pypy"* && $PYTHON_VERSION == "2"* && $PYTHON_VERSION == *"3.4" ]]; then
      python -m pip install mypy || exit 1
    fi
  fi
fi

# Run tests
echo "Running tests"
ccache -s 2>/dev/null || true
export PATH="/usr/lib/ccache:$PATH"

# if [[ "$OSTYPE" == "msys" ]]; then  # for MSVC clang
#   WARNFLAGS="/Wall"
#   GFLAG="-g"
# else
WARNFLAGS="-Wall -Wextra"
GFLAG="-ggdb"
# fi

if [[ $COVERAGE == "1" ]]; then
  COVERAGE_ARGS="--cython-coverage"
  RUNTESTS_ARGS="$RUNTESTS_ARGS --coverage --coverage-html --cython-only"
fi

if [[ $NO_CYTHON_COMPILE != "1" && $PYTHON_VERSION == "pypy"* ]]; then
  CFLAGS="-O2 $GFLAG $WARNFLAGS $(python -c 'import sys; print("-fno-strict-aliasing" if sys.version_info[0] == 2 else "")')" \
  python setup.py build_ext -i \
  $(if [[ $COVERAGE == "1" ]]; then echo " --cython-coverage"; fi) \
  $(python -c 'import sys; print("-j5" if sys.version_info >= (3,5) else "")') \
  || exit 1
  if [[ -z $COVERAGE && -z $STACKLESS && -z $LIMITED_API && -z $EXTRA_CFLAGS && -n ${BACKEND//*cpp*} ]]; then
    python setup.py bdist_wheel || exit 1
  fi
fi

if [[ $TEST_CODE_STYLE == "1" ]]; then
  make -C docs html || exit 1
elif [[ $PYTHON_VERSION == "pypy"* ]]; then
  # Run the debugger tests in python-dbg if available (but don't fail, because they currently do fail)
  PYTHON_DBG="python$( python -c 'import sys; print("%d.%d" % sys.version_info[:2])' )-dbg"
  if $PYTHON_DBG -V >&2; then
    CFLAGS="-O0 -ggdb" $PYTHON_DBG runtests.py -vv --no-code-style Debugger --backends=$BACKEND
  fi
fi

export CFLAGS="-O0 $GFLAG $WARNFLAGS $EXTRA_CFLAGS"

python runtests.py \
  -vv $STYLE_ARGS \
  -x Debugger \
  --backends=$BACKEND \
  $LIMITED_API $EXCLUDE $RUNTESTS_ARGS

EXIT_CODE=$?

ccache -s 2>/dev/null || true

exit $EXIT_CODE
