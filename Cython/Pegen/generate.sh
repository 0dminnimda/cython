#!/usr/bin/bash

# python -m pip install -U pip setuptools wheel || exit 1

echo "Installing virtualenv"
python -m pip install virtualenv || exit 1

echo "Making virtualenv"
python -m virtualenv Cython/Pegen/genenv || exit 1

echo "Activating virtualenv"
. Cython/Pegen/genenv/bin/activate || exit 1

echo "Installing pegen"
python -m pip install git+https://github.com/0dminnimda/pegen.git@cython_peg || exit 1

echo "Generating the parser"
python -m pegen Cython/Pegen/cython.gram -o Cython/Pegen/parser.py

echo "Deactivating virtualenv"
deactivate || exit 1
