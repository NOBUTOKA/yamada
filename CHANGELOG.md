# Changelog

For users deciding whether to update, this log describes changes and compatibility limits by version.

## 1.1.2

- Improve Safe Preview grid boundaries for overflowing content-sized tracks, collapsed flexible tracks, and overlapping spans.
- Synchronize Safe Preview layout updates with the bundled waitForFigureLayout utility.
- Restore File Exchange keywords in the Toolbox package.

## 1.1.1

- Set the MATLAB Package Manager package name to yamada.

## 1.1.0

- Support MATLAB R2023a through R2026b. Each release offers the components and properties it provides; for example, the color picker requires R2024a and the range slider requires R2023b.
- On R2026b, radio and toggle buttons outside a button group, their `Group` property, and `uiselectiongroup` are not supported yet.
- R2026b installs no Java runtime; install the MATLAB Support for OpenJDK add-on or another OpenJDK distribution before using yamada on it.
- On older supported MATLAB releases, edit supported settings while preserving newer components and explicit settings recognized by the bundled catalogs. Safe Preview shows a placeholder label for components unavailable in the running release. Running the saved app requires a MATLAB release that supports the features it uses.
- On MATLAB R2025a through R2026b, yamada opens in a separate window that cannot be docked in the MATLAB desktop.
- Compare original and generated source side by side in Diff Preview, with aligned lines, synchronized scrolling, and a map of changed locations.
- Preserve Windows file permissions and inheritance when saving over an existing file.

## 1.0.2

- Fix repeated drag moves and resizes of components inside a Panel in a Grid Layout.
- Update the Toolbox display name and cover image.

## 1.0.1

- Restrict Tab Group children to tabs and prevent invalid drops into a Tab Group.
- Update installation and development documentation to reflect the published Toolbox.

## 1.0.0

Initial stable release for MATLAB R2024a on 64-bit Windows.

- Create and edit ordinary MATLAB handle-class GUI applications with a Safe Preview, component hierarchy, Property Inspector, validation, and source diff.
- Arrange components, edit Grid Layouts, rename components, and manage callback bindings while preserving method bodies.
- Support Copy/Cut/Paste, Undo/Redo, Save/Save As, and external source reload within the supported source-safety boundaries.
- Distribute as a MATLAB Toolbox with command and Apps gallery launch paths.
- Protect existing source through staged saving and native Windows replacement.

The initial release does not support `.mlapp`, AppBase input, other MATLAB releases or operating systems, MATLAB Online, or arbitrary MATLAB source round-tripping. See [SPECIFICATION.md](SPECIFICATION.md).
