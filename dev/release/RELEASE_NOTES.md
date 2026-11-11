# yamada 1.0.0

A visual editor for MATLAB handle-class GUI applications using ordinary `.m` source files.

## Requirements

MATLAB R2024a on 64-bit Windows, with a graphical session, JVM, and .NET support. No additional MathWorks Toolbox is required.

## Install and start

Open `yamada-1.0.0.mltbx` in MATLAB and follow the installation dialog. Enter `yamada` in the Command Window, or select **yamada** in the **Apps** tab. See the [Getting Started guide](https://github.com/NOBUTOKA/yamada/blob/v1.0.0/doc/GETTING_STARTED.md).

## Included

- Toolbox installer: `yamada-1.0.0.mltbx`
- Detached GPG signature: `yamada-1.0.0.mltbx.asc`
- SHA-256 checksums: `SHA256SUMS`

## Features and limitations

Create or open a supported handle-class app, edit components and properties, arrange Grid Layouts, manage callback bindings, review validation and source diffs, and save ordinary MATLAB source. The preview does not execute your input application or its callbacks. Undo/Redo and staged saving preserve editing state within the documented contract.

This release does not support `.mlapp`, AppBase input, other MATLAB releases or operating systems, MATLAB Online, or arbitrary MATLAB syntax. Some properties remain read-only and preview behavior is bounded. Keep backups or version control for your own apps. See the [specification](https://github.com/NOBUTOKA/yamada/blob/v1.0.0/SPECIFICATION.md) and [changelog](https://github.com/NOBUTOKA/yamada/blob/v1.0.0/CHANGELOG.md).

Report problems through [GitHub Issues](https://github.com/NOBUTOKA/yamada/issues). Author: Nobuto Kaitoh (nobutoka@gmail.com). License: GPL-3.0-or-later.
