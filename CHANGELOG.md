# Changelog

For users deciding whether to update, this log describes changes and compatibility limits by version.

## Unreleased

- Support MATLAB R2023a through R2026b. Each release offers the components and properties it provides; for example, the color picker requires R2024a and the range slider requires R2023b.
- On R2026b, radio and toggle buttons outside a button group, their `Group` property, and `uiselectiongroup` are not supported yet.
- R2026b installs no Java runtime; install the MATLAB Support for OpenJDK add-on or another OpenJDK distribution before using yamada on it.
- Editing an app created for a newer MATLAB release on an older release is not supported.
- In desktop MATLAB R2025a and later, the Preview waits for the native layout to settle again instead of falling back to the slower legacy geometry recovery with a `Layout synchronization failed` warning.

## 1.0.0

Initial stable release for MATLAB R2024a on 64-bit Windows.

- Create and edit ordinary MATLAB handle-class GUI applications with a Safe Preview, component hierarchy, Property Inspector, validation, and source diff.
- Arrange components, edit Grid Layouts, rename components, and manage callback bindings while preserving method bodies.
- Support Copy/Cut/Paste, Undo/Redo, Save/Save As, and external source reload within the supported source-safety boundaries.
- Distribute as a MATLAB Toolbox with command and Apps gallery launch paths.
- Protect existing source through staged saving and native Windows replacement.

The initial release does not support `.mlapp`, AppBase input, other MATLAB releases or operating systems, MATLAB Online, or arbitrary MATLAB source round-tripping. See [SPECIFICATION.md](SPECIFICATION.md).
