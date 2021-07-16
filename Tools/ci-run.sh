#!/usr/bin/bash

GCC_VERSION=${GCC_VERSION:=8}

if [[ $BACKEND == *"cpp"* ]]; then
  BACKEND_IS_CPP=true
  ALTERNATIVE_ARGS="--slave /usr/bin/g++ g++ /usr/bin/g++-$GCC_VERSION"
else
  BACKEND_IS_CPP=false
fi

# Set up compilers
if [[ "$TEST_CODE_STYLE" == "1" ]]; then
  echo "Skipping compiler setup"
else
  echo "Setting up compiler"
  if [[ $OSTYPE == "linux-gnu"* ]]; then
    echo "Installing requirements [apt]"
    sudo apt-add-repository -y "ppa:ubuntu-toolchain-r/test"
    sudo apt update -y -q
    sudo apt install -y -q ccache gdb python-dbg python3-dbg gcc-$GCC_VERSION || exit 1

    if [[ $BACKEND_IS_CPP = true ]]; then
      sudo apt install -y -q g++-$GCC_VERSION || exit 1
    fi
    sudo /usr/sbin/update-ccache-symlinks
    echo "/usr/lib/ccache" >> $GITHUB_PATH # export ccache to path

    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-$GCC_VERSION 60 $ALTERNATIVE_ARGS

    export CC="gcc"
    if [[ $BACKEND_IS_CPP = true ]]; then
      sudo update-alternatives --set g++ /usr/bin/g++-$GCC_VERSION
      export CXX="g++"
    fi

  elif [[ $OSTYPE == "darwin"* ]]; then
    export CC="clang -Wno-deprecated-declarations"
    export CXX="clang++ -stdlib=libc++ -Wno-deprecated-declarations"

  elif [[ $OSTYPE == "msys" ]]; then
    echo "Installing requirements [apt]"
    # sudo apt-get install -y build-essential
    # sudo apt update -y -q
    # sudo apt install -y -q ccache gdb python-dbg python3-dbg gcc-$GCC_VERSION || exit 1

    # if [[ $BACKEND_IS_CPP = true ]]; then
    #   sudo apt install -y -q g++-$GCC_VERSION || exit 1
    # fi
    # sudo /usr/sbin/update-ccache-symlinks
    # echo "/usr/lib/ccache" >> $GITHUB_PATH # export ccache to path

    # sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-$GCC_VERSION 60 $ALTERNATIVE_ARGS

    export CC="x86_64-w64-mingw32-gcc"
    set msvc=$CC # runtests.get_cc_version hack
    if [[ $BACKEND_IS_CPP = true ]]; then
      # sudo update-alternatives --set g++ /usr/bin/g++-$GCC_VERSION
      export CXX="x86_64-w64-mingw32-g++"
      set msvc=$CXX # runtests.get_cc_version hack
    fi

  else
    echo "Unexpected OS $OSTYPE: '$OS_NAME'"
    exit 1
  fi
  echo "Configured for $OSTYPE: '$OS_NAME'"
fi

# Set up miniconda
if [[ $STACKLESS == "true" ]]; then
  echo "Installing stackless python"
  #conda install --quiet --yes nomkl --file=test-requirements.txt --file=test-requirements-cpython.txt
  conda config --add channels stackless
  conda install --quiet --yes stackless || exit 1
fi

PYTHON_SYS_VERSION=$(python -c 'import sys; print(sys.version)')

# Log versions in use
echo "===================="
echo "|VERSIONS INSTALLED|"
echo "===================="
echo "Python $PYTHON_SYS_VERSION"
if [[ $BACKEND_IS_CPP = true ]]; then
  which ${CXX%% *}
  ${CXX%% *} --version
else
  which ${CC%% *}
  ${CC%% *} --version
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
#   WARNARGS="/Wall"
#   GFLAG="-g"
# else
WARNARGS="-Wall -Wextra"
GFLAG="-ggdb"
# fi

if [[ $COVERAGE == "1" ]]; then
  COVERAGE_ARGS="--cython-coverage"
  RUNTESTS_ARGS="$RUNTESTS_ARGS --coverage --coverage-html --cython-only"
fi

if [[ $NO_CYTHON_COMPILE != "1" && $PYTHON_VERSION == "pypy"* ]]; then
  if [[ $PYTHON_VERSION == "pypy-2"* ]]; then
    ALIASING="$-fno-strict-aliasing"
  fi
  if [[ $PYTHON_SYS_VERSION > "3.5" || $PYTHON_SYS_VERSION == "3.5"* ]]; then
    SETUP_ARGS="-j5"
  fi

  CFLAGS="-O2 $GFLAG $WARNARGS $ALIASING" \
    python setup.py build_ext -i $COVERAGE_ARGS $SETUP_ARGS || exit 1

  if [[ $COVERAGE != "1" && $STACKLESS != "true" && -z $LIMITED_API && -z $EXTRA_CFLAGS && $BACKEND_IS_CPP == false ]]; then
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

export CFLAGS="-O0 $GFLAG $WARNARGS $EXTRA_CFLAGS"

python runtests.py \
  -vv $STYLE_ARGS \
  -x Debugger \
  --backends=$BACKEND \
  $LIMITED_API $EXCLUDE $RUNTESTS_ARGS

EXIT_CODE=$?

ccache -s 2>/dev/null || true

exit $EXIT_CODE
