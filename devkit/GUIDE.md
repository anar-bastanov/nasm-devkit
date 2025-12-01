# NASM DevKit Guide

This document explains how to start your own project with the DevKit.

## 0. Requirements

You need the following tools:

* CMake 3.20 or newer
* NASM 2.15 or newer
* A C/C++ toolchain

  * Windows:
    * Visual Studio with C++ build tools (any recent version), or
    * MinGW / LLVM toolchain plus a build tool (Ninja or Make)
  * Linux / macOS:
    * Compiler: gcc or clang
    * Build tool: Ninja or Make
* Git (optional, but recommended)

All tools should be available on your `PATH`.

## 1. Create a project

You can begin in three ways:

* **Use the GitHub template**: Click **"Use this template"** on the DevKit repo and create a new project directly.

* **Download a ZIP**: Download source code & extract anywhere.

* **Clone and detach**:

  ```bash
  git clone https://github.com/anar-bastanov/nasm-devkit.git MyApp
  cd MyApp
  rm -rf .git
  # Do not run `git init` yet
  ```

## 2. Set project name

Run the bootstrap script **once** to set the project and, optionally, executable names.

* **Windows (PowerShell)**

  ```powershell
  ./tools/bootstrap.ps1 -Project MyApp -Executable myapp-cli
  ```

* **Linux / macOS**

  ```bash
  ./tools/bootstrap.sh MyApp myapp-cli
  ```

This updates the placeholders in `CMakeLists.txt`:

```cmake
set(PROJECT_NAME_VAR "MyApp")
set(EXECUTABLE_NAME_VAR "myapp-cli")
```

## 3. Build

You can choose one of the available build types:

* **Debug** (default): debug symbols, no optimizations
* **Release**: full optimizations, stripped binary
* **RelWithDebInfo**: optimized but keeps debug info
* **MinSizeRel**: optimized for size

Use one of the recipes below depending on your generator and toolchain.

### 3.1. Windows with Visual Studio (multi-config)

```bash
cmake -S . -B build  # VS is usually the default generator on Windows
cmake --build build --config Debug  # build/bin/Debug/myapp-cli.exe
cmake --build build --config Release  # build/bin/Release/myapp-cli.exe
```

### 3.2. Ninja (recommended on all platforms)

**Debug:**

```bash
cmake -S . -B build-debug -G Ninja -DCMAKE_BUILD_TYPE=Debug
cmake --build build-debug  # build-debug/bin/myapp-cli
```

**Release:**

```bash
cmake -S . -B build-release -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build-release  # build-release/bin/myapp-cli
```

### 3.3. Windows with MinGW Makefiles

**Debug:**

```bash
cmake -S . -B build-debug -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Debug
cmake --build build-debug  # build-debug/bin/myapp-cli.exe
```

**Release:**

```bash
cmake -S . -B build-release -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Release
cmake --build build-release  # build-release/bin/myapp-cli.exe
```

## 4. Test

Running the binary from your chosen build directory should print a hello message:

```none
# Example: Ninja Debug build
./build-debug/bin/myapp-cli
Hello, World!

# Example: Visual Studio Debug build
./build/bin/Debug/myapp-cli.exe
Hello, World!
```

## 5. Initialize Git

Run this **after** your first build; else, you will commit all library source files, not just the ones you use.

```bash
git init
git add .
git commit -m "Bootstrap project."
```

## 6. Add your code

In `src/` you will find two starting files:

* **`main.nasm`:** the reserved runtime entrypoint. It sets up the environment, collects arguments, and transfers control to your program.

  * This file must remain named `main.nasm`.
  * You normally do not edit it unless you are customizing the runtime itself.

* **`program.nasm`:** your program’s entrypoint. This is where your own code begins.

  * You may rename or expand this file as your project grows.
  * Keep your headers and symbols consistent if you rename it.

Headers can be placed anywhere, but by default live in `src/include/`.

## 7. Manage dependencies

Declare dependencies in `src/dependencies.list`:

```
anrc
argparse
styling
```

* Each library lives under `lib/<name>/`.
* Libraries may declare their own `dependencies.list`.
* You can remove or add libraries freely.

> [!WARNING]
> **Libraries are incomplete.**
>
> The libraries under `lib/` are a work in progress and currently lack documentation, expect changes in future updates.

## 8. Next steps

* Follow [CALLING_CONVENTION.md](CALLING_CONVENTION.md) for the `__anrc64` spec.
* Keep `/devkit/` and the root `NOTICE` file intact.
* Add your own project README, LICENSE, and .gitignore at the repository root.
