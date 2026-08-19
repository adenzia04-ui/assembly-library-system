# APU Library Management System — x86 Assembly 📚

A command-line **library management system written in 32-bit x86 assembly**,
assembled with **NASM** and linked with **ld** (Linux / ELF32).

> Module: **CT073-3-2 Computer System Low-Level Techniques** — Asia Pacific University (APU).

## ✨ Features
1. Display the book catalogue
2. Search for a book by ID
3. Borrow a book — enforces a **3-book member limit** and shelf availability
4. Return a book — calculates an **overdue fine** (`days × RM1`)
5. Library statistics (running totals)
6. Exit

All three required low-level constructs are demonstrated:
- **Arithmetic** — fine calculation, copy counts, running totals
- **Loops** — iterating over the catalogue
- **Jumps** — menu dispatch and conditional branching (`je` / `jl` / `jge` / `jmp`)

Book records are held in **parallel arrays** (ids, availability, totals and a
title-pointer table), so each field stays naturally aligned and is easy to index
with `[base + index*4]`.

## ▶️ Build & run

> ⚠️ macOS removed 32-bit support in Catalina, so this must be built and run on **Linux**.

### Native Linux (or a VM)
```bash
sudo apt update && sudo apt install -y nasm binutils
nasm -f elf32 library.asm -o library.o
ld -m elf_i386 library.o -o library
./library
```

### Docker (on macOS / Windows, no VM needed)
```bash
docker run --rm -it --platform linux/amd64 -v "$PWD":/w -w /w ubuntu:22.04 bash -c \
  "apt-get update -qq && apt-get install -y -qq nasm binutils && \
   nasm -f elf32 library.asm -o library.o && \
   ld -m elf_i386 library.o -o library && ./library"
```

A helper `run.sh` is included that runs the build+run steps for you.

## 📁 Files
| File | Purpose |
|---|---|
| `library.asm` | The complete program (~520 lines of commented x86 assembly). |
| `run.sh` | Convenience script to assemble, link and run. |
