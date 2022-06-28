#!/usr/bin/bash

echo "Activating virtualenv"
. Cython/Parser/genenv/bin/activate || exit 1

echo "Generating the parser"
python -m pegen Cython/Parser/Cython.gram -o Cython/Parser/Parser.py

echo "Deactivating virtualenv"
deactivate || exit 1
