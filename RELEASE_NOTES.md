# Release Notes - Terminal Paint v1.0.0

**Release Date:** October 18, 2026  
**Tag:** `v1.0.0` (Initial Release)

---

## 🎨 Overview

We are excited to announce the initial release of **Terminal Paint (`paint.sh`) v1.0.0**—a lightweight, zero-dependency TUI (Terminal User Interface) paint application built entirely in pure Bash!

Enjoy smooth, lag-free terminal drawing with direct mouse interaction, an intuitive toolbar, and keyboard controls without needing Python, ncurses, or any external libraries.

---

## 🚀 Key Highlights & Features

- **Zero External Dependencies:** Built strictly using Bash built-ins, standard `read`, `stty`, and ANSI escape sequences. Runs seamlessly on Linux and macOS (compatible with modern Bash 4+ as well as macOS `/bin/bash` 3.2+).
- **Extended SGR Mouse Tracking (`\e[?1006h`):** Supports precise click and drag tracking across arbitrary terminal dimensions.
- **Continuous Line Smoothing:** Features an embedded Bresenham line algorithm to interpolate strokes during fast mouse sweeps, eliminating dotted/dashed gaps.
- **Interactive Top-Row Toolbar:**
  - 8 ANSI color swatches (Black, Red, Green, Yellow, Blue, Magenta, Cyan, White) with active brush highlighting.
  - One-click `[C]lear` and `[Q]uit` buttons.
- **Dual Controls (Mouse + Keyboard):**
  - Switch colors using keyboard number keys `1`–`8` or by clicking swatches directly.
  - Press `c` or `C` to clear the canvas.
  - Press `q` or `Q` to exit.
- **Dedicated Eraser Tools:** Erase effortlessly using **Right-Click / Drag** or press `e`/`E` to toggle Eraser mode.
- **Safe & Clean Teardown:** Operates in the alternate screen buffer (`\e[?1049h`) and reliably restores cursor, canonical mode, and echo via `trap ... EXIT INT TERM` and `stty sane`.

---

## 📦 Quick Start

```bash
chmod +x paint.sh
./paint.sh
```

---

*For detailed instructions and technical documentation, refer to [`README.md`](README.md).*
