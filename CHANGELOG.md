# Changelog

For users deciding whether to update, this log describes changes and compatibility limits by version.

## Unreleased

- Support MATLAB R2023a and R2023b in addition to R2024a. Each release offers the components and properties it provides; the color picker requires R2024a and the range slider requires R2023b.
- Editing an app created for a newer MATLAB release on an older release is not supported.

## 1.0.0

Initial stable release for MATLAB R2024a on 64-bit Windows.

- Create and edit ordinary MATLAB handle-class GUI applications with a Safe Preview, component hierarchy, Property Inspector, validation, and source diff.
- Arrange components, edit Grid Layouts, rename components, and manage callback bindings while preserving method bodies.
- Support Copy/Cut/Paste, Undo/Redo, Save/Save As, and external source reload within the supported source-safety boundaries.
- Distribute as a MATLAB Toolbox with command and Apps gallery launch paths.
- Protect existing source through staged saving and native Windows replacement.

The initial release does not support `.mlapp`, AppBase input, other MATLAB releases or operating systems, MATLAB Online, or arbitrary MATLAB source round-tripping. See [SPECIFICATION.md](SPECIFICATION.md).
