#!/usr/bin/bash

echo "Activating virtualenv"
. Cython/Pegen/genenv/bin/activate || exit 1

echo "Generating the parser"
python -m pegen Cython/Pegen/cython.gram -o Cython/Pegen/cy_parser.py

echo "Deactivating virtualenv"
deactivate || exit 1
