#!/usr/bin/bash

# python -m pip install -U pip setuptools wheel || exit 1

echo "Installing virtualenv"
python -m pip install virtualenv || exit 1

echo "Making virtualenv"
python -m virtualenv Cython/Parser/genenv || exit 1

echo "Activating virtualenv"
. Cython/Parser/genenv/bin/activate || exit 1

echo "Installing pegen"
python -m pip install git+https://github.com/0dminnimda/pegen.git@cython_peg || exit 1

echo "Deactivating virtualenv"
deactivate || exit 1
