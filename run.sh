#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Build & run the 32-bit Library Management System.
# macOS cannot execute 32-bit binaries, so we build & run inside a small Linux
# container (Docker). On a real Linux PC you can ignore this and just use:
#     nasm -f elf32 library.asm -o library.o && ld -m elf_i386 library.o -o library && ./library
# -----------------------------------------------------------------------------
set -e
cd "$(dirname "$0")"          # run from this script's folder

echo ">> Building and launching (first run downloads a small Linux image)..."
docker run --rm -it --platform linux/amd64 -v "$PWD":/w -w /w ubuntu:22.04 bash -c '
    apt-get update -qq >/dev/null 2>&1
    apt-get install -y -qq nasm binutils >/dev/null 2>&1
    nasm -f elf32 library.asm -o library.o
    ld -m elf_i386 library.o -o library
    echo "### Build OK - starting program ###"
    ./library
    rm -f library.o library
'
