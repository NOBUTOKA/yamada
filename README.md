# yamada - Yet Another MATLAB App Designer Alternative

`yamada` is a visual editor for `matlab.apps.AppBase` applications. It is similar in purpose to MATLAB App Designer, but **instead of using the dedicated binary `.mlapp` format**, it treats ordinary MATLAB class files (`.m`) as source. You can create a new application or open an existing AppBase class and inspect, arrange, and edit its UI components graphically.

## Important

`yamada` is under active development. Development and verification currently target MATLAB R2024a, no versioned release is available yet, and some capabilities, including visual Grid Layout editing, remain incomplete. Review the generated diff before saving, and keep the target file under version control or make a backup.

## Features

- Create a runnable `matlab.apps.AppBase` subclass from an empty canvas
- Statically parse an existing `.m` class that follows a common App Designer-like structure
- Use a component palette, hierarchy browser, editing canvas, and typed Property Inspector
- Move and resize absolutely positioned components and edit Grid Layout placement values, with visual Grid Layout editing still under development
- Add and delete components and edit supported properties
- View validation diagnostics and compare the original and generated source before saving
- Preserve unsupported code and nonliteral expressions where possible, and build a Safe Preview without running the input application or its callbacks
- Produce an ordinary, reviewable text-based `.m` source file **rather than a binary file**

## Supported Environment

- MATLAB R2024a

Compatibility with MATLAB releases other than R2024a is not currently guaranteed.

## Getting Started

Clone the repository, or download and extract it from **Code > Download ZIP** on GitHub. Add the repository root to the MATLAB path and start `yamada`.

```matlab
projectRoot = "/path/to/yamada";
addpath(projectRoot);
editor = yamada();
```

If the application object remains after you close the editor, delete it explicitly:

```matlab
delete(editor);
```

## Basic Usage

### Create a new application

1. Select **File > New** and enter a MATLAB class name.
2. Add components from the palette on the left.
3. Select a component on the canvas or in the hierarchy browser, then edit its supported properties in the Property Inspector on the right.
4. Select **Tools > Validate** to validate the document model.
5. Select **Tools > Diff Preview** to review the generated source, then use **File > Save As** to save it as a `.m` file.

### Edit an existing application

1. Select **File > Open** and choose a `.m` file whose class derives from `matlab.apps.AppBase`.
2. Review the parsed hierarchy, Safe Preview, and diagnostics.
3. Modify supported components and properties.
4. Validate the document and review the diff. Save to a new file if you want to preserve the original.

## Scope and Limitations

`yamada` catalogs standard persistent MATLAB R2024a UI components, containers, axes, instrumentation controls, menus, and toolbar tools. See the [product specification](SPECIFICATION.md) for the detailed component and property scope.

The following boundaries protect the input source:

- `.mlapp` files and their internal format are not supported.
- The input application's constructor, callbacks, helper methods, and arbitrary expressions are never executed.
- Dynamic component creation and ambiguous source structures are restricted when they cannot be edited safely; diagnostics explain the restriction.
- Inclusion in the catalog does not mean that every component or property can be previewed, inserted, and edited to the same extent. Unsupported values may remain visible but read-only.
- Full App Designer compatibility and complete round-tripping of arbitrary MATLAB syntax are not goals.

See the [product specification](SPECIFICATION.md) for the current supported behavior, input and output contract, and safety limitations.

## Documentation

- [Product specification](SPECIFICATION.md) - Current scope, input and output contract, and safety limitations
- [Contributing guide](CONTRIBUTING.md) - Issues, development setup, tests, and pull requests

## Feedback and Contributions

Bug reports, feature proposals, documentation improvements, and code contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening an issue or pull request. Please discuss large features and design changes in an issue before starting implementation.

## License

This project is licensed under the GNU General Public License version 3 or later (`GPL-3.0-or-later`). See [LICENSE](LICENSE) for details.
