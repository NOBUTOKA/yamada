# Specification

## Purpose

Create a MATLAB application that can either create a new programmatic MATLAB class derived from `matlab.apps.AppBase` or load an existing one, and let the user inspect and edit its UI components through a graphical interface.

The editor application itself must be a MATLAB `.m` class derived from `matlab.apps.AppBase`. It must not be implemented as an `.mlapp` file.

## Project creation and input

- A new app can be created from an empty canvas or a built-in starter template.
- New-app creation must request a valid MATLAB class name and produce a normal `.m` class derived from `matlab.apps.AppBase`.
- A MATLAB class source file with the `.m` extension.
- The class is expected to derive from `matlab.apps.AppBase`.
- The source may contain App Designer-style public component properties, private helper methods, component initialization code, callbacks, and constructor/destructor methods.
- For an existing app, the original source should remain available for comparison and rollback.
- New and loaded apps must use the same component model, editor, validation, and source-generation pipeline after project creation or parsing.

## Planned editor capabilities

1. Create a new app from an empty canvas or starter template.
2. Select and open an existing `.m` file.
3. Parse the class definition and identify UI component declarations.
4. Parse component creation statements and relevant property assignments.
5. Display the component hierarchy in a component browser.
6. Display the UI layout on an editable canvas.
7. Select a component and edit supported properties in a property inspector.
8. Add supported components from a palette.
9. Move and resize components on the canvas.
10. Delete components with an explicit user action.
11. Export the created or edited result as a text-based `.m` class.
12. Preserve unsupported code and unknown statements whenever the parser can do so safely.
13. Show parse or generation warnings instead of silently discarding source code.

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
- A newly created app must include a minimal, runnable AppBase class structure with component declarations, component creation, constructor registration, and cleanup.

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
- Use one shared intermediate component model for both newly created apps and loaded source files.
- Prefer explicit warnings for unsupported constructs over destructive rewriting.
- Keep project files text-based wherever practical.

