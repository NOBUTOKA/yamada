# yamada — Yet Another MATLAB App Designer Alternative

**A visual GUI editor for MATLAB that works with ordinary `.m` class files instead of `.mlapp` files.**

[日本語で解説記事を書きました](https://qiita.com/N-Kaitoh/items/b788f4342447016a4304)

yamada provides an App Designer-like visual editing experience while keeping your application code in plain-text MATLAB class files, making it easier to edit, review, and manage with version control systems such as Git.

**Key features**

- Create and visually edit MATLAB GUI applications based on `handle` classes and `uifigure`.
- Add and arrange UI components, including nested Grid Layouts.
- Edit component properties and manage callback connections.
- Rename, copy, paste, and move UI components.
- Preview UI layouts without executing the application.
- Validate changes and review a side-by-side source diff with synchronized scrolling before saving.
- Edit supported settings on older MATLAB releases while preserving newer components and settings recognized by yamada.

**Requirements and limitations**

Requires MATLAB R2023a through R2026b on 64-bit Windows, with a graphical session, JVM, and MATLAB .NET support. On R2026b, install MATLAB Support for OpenJDK or another supported OpenJDK distribution before launching yamada. No additional MATLAB toolboxes are required.

Other MATLAB releases, macOS, Linux, and MATLAB Online are not currently supported. Existing `.mlapp` files and AppBase-based applications cannot be edited.

Running the saved app requires a MATLAB release that supports the features it uses.

**Getting started**

Install the `.mltbx` package and run `yamada` in MATLAB, or launch it from the Apps tab.

For documentation, examples, supported features, and known limitations, visit the [GitHub repository](https://github.com/NOBUTOKA/yamada).

Licensed under GPL-3.0-or-later.