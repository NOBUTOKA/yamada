# Specification

## Purpose

Create a MATLAB application that can load a programmatic MATLAB class derived from `matlab.apps.AppBase` and let the user inspect and edit its UI components through a graphical interface.

The editor application itself must be a MATLAB `.m` class derived from `matlab.apps.AppBase`. It must not be implemented as an `.mlapp` file.

## Input

- A MATLAB class source file with the `.m` extension.
- The class is expected to derive from `matlab.apps.AppBase`.
- The source may contain App Designer-style public component properties, private helper methods, component initialization code, callbacks, and constructor/destructor methods.
- The original source should remain available for comparison and rollback.

## Planned editor capabilities

1. Select an input `.m` file.
2. Parse the class definition and identify UI component declarations.
3. Parse component creation statements and relevant property assignments.
4. Display the component hierarchy in a component browser.
5. Display the UI layout on an editable canvas.
6. Select a component and edit supported properties in a property inspector.
7. Add supported components from a palette.
8. Move and resize components on the canvas.
9. Delete components with an explicit user action.
10. Export the edited result as a text-based `.m` class.
11. Preserve unsupported code and unknown statements whenever the parser can do so safely.
12. Show parse or generation warnings instead of silently discarding source code.

## Initial component scope

The first implementation should support these components:

- `uifigure`
- `uipanel`
- `uigridlayout`
- `uilabel`
- `uibutton`
- `uieditfield`
- `uidropdown`
- `uiaxes`

The component model should be extensible so additional MATLAB UI components can be added later.

## Source-generation requirements

- Generated MATLAB source must be UTF-8 without a BOM.
- Generated MATLAB source must use CRLF line endings.
- Comments in generated MATLAB source must be written in English.
- Generated output must remain a normal `.m` file and should be readable, diffable, and reviewable in Git.
- The editor must not require `.mlapp` serialization to save or reload a project.

## Out of scope for the initial version

- Implementing sorting algorithms.
- Editing arbitrary MATLAB code semantics.
- Full App Designer compatibility.
- Round-tripping every possible MATLAB syntax form.
- Reproducing App Designer's proprietary internal model.
- Packaging the editor as a MATLAB toolbox or standalone application.

## Design constraints

- Treat source parsing and source generation as separate layers from the canvas UI.
- Keep the original source and generated source distinguishable.
- Prefer explicit warnings for unsupported constructs over destructive rewriting.
- Keep project files text-based wherever practical.

