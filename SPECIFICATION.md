# yamada Product Specification

This document describes the current public feature scope, input and output contract, and safety limitations of the development version of `yamada`. It is not a roadmap for future implementation.

## Purpose

`yamada` is a visual editor for `matlab.apps.AppBase` applications that treats ordinary MATLAB class files (`.m`) as the source of truth.

Users can create a new AppBase class from an empty canvas or open an existing AppBase class, then inspect and edit supported UI components and properties graphically. `yamada` does not depend on the private internal format of `.mlapp` files.

## Supported Environment

- Development and verification target: MATLAB R2024a
- Input: A `.m` file defining a class derived from `matlab.apps.AppBase`
- Output: A `.m` file defining an ordinary MATLAB class

Compatibility with MATLAB releases other than R2024a is not guaranteed. No versioned release, MATLAB Toolbox package, or standalone application is currently available.

## Supported Operations

### New applications

- Create an empty AppBase class with a valid MATLAB class name and a root `uifigure`.
- Add supported components from the palette.
- Inspect the component hierarchy and Safe Preview.
- Edit supported properties in the typed Property Inspector.
- Move and resize absolutely positioned components.
- Edit Grid Layout row, column, and span values in the Property Inspector.
- Explicitly delete components and undo or redo changes.
- Validate the document, review the source diff, and save a runnable AppBase `.m` file.

### Existing applications

- Open an AppBase `.m` file with a common App Designer-like or programmatic structure.
- Statically parse supported declarations, creation statements, parent-child relationships, and direct property assignments.
- Display parsed components in the hierarchy browser, Safe Preview, and Property Inspector.
- Edit property assignments and components whose source ownership can be determined safely.
- Compare the original and generated source, then save to a new path or to an explicitly confirmed path.
- Show diagnostics for unsupported or ambiguous structures.

## Standard Component Catalog

The catalog includes the following persistent MATLAB R2024a UI components and creation variants:

- Basic controls: `uilabel`, `uibutton`, `uicheckbox`, `uicolorpicker`, `uidatepicker`, `uidropdown`, `uieditfield`, `uihyperlink`, `uiimage`, `uilistbox`, `uiradiobutton`, `uislider`, `uispinner`, `uitable`, `uitextarea`, and `uitogglebutton`
- Containers and layout: `uifigure`, `uipanel`, `uigridlayout`, `uitabgroup`, `uitab`, and `uibuttongroup`
- Trees: `uitree` and `uitreenode`
- Axes: `uiaxes`, `axes`, `geoaxes`, and `polaraxes`
- Instrumentation: `uigauge`, `uiknob`, `uilamp`, and `uiswitch`
- Extended display and figure tools: `uihtml`, `uicontextmenu`, `uimenu`, `uitoolbar`, `uipushtool`, and `uitoggletool`

Catalog inclusion does not mean that every creation variant supports insertion, Preview, layout, and property editing to the same extent. The parent component, creation variant, or property value may limit available operations. Unsupported state remains read-only where possible and is reported through diagnostics.

Transient operations such as `uialert`, `uiconfirm`, `uiprogressdlg`, `uisetcolor`, and file-selection dialogs are out of scope because they are not persistent components in the document.

## Static Parsing and Safe Preview

`yamada` does not execute an input application to discover its UI structure.

- It does not call the input class constructor, callbacks, or helper methods.
- It does not evaluate arbitrary MATLAB expressions through `eval` or an equivalent mechanism.
- Safe Preview applies only catalog-approved components and values that can be interpreted safely.
- Callbacks, nonliteral expressions, and unsupported statements remain in the original source where possible.
- Diagnostics distinguish state that cannot be previewed from state that cannot be preserved safely.

Because of this limitation, Safe Preview may not reproduce the input application's appearance completely. It displays the model that could be parsed safely and is not a substitute for running the input application.

## Editing and Source Preservation

- New and existing applications use the same component model, validation, Preview, and generation pipeline.
- Generating an existing source file without edits does not change its original text.
- Edits make localized changes only to declarations, creation statements, and assignments whose ownership can be determined safely.
- If an insertion point or ownership range required for addition or deletion is ambiguous, the edit or save is rejected with a diagnostic.
- Failed validation of a supported value restricts Preview or saving as necessary for safety.
- Deletion occurs only after an explicit user action.

`yamada` prioritizes source preservation, but it does not guarantee complete round-tripping of arbitrary MATLAB syntax. Use version control such as Git or create a backup before editing an existing file.

## Output

- Output is ordinary AppBase `.m` source that can be reviewed and compared as text.
- Files are written as UTF-8 without a BOM.
- A new file includes the class and component declarations, creation method, application registration, and cleanup required for execution.
- New files use the host platform's standard line ending; existing files preserve the detected CRLF or LF convention.
- Generated comments and help text are written in English.
- `yamada` does not automatically add, replace, or remove the project's GPL notice in an application created or opened by the user.

## Out of Scope

- Reading, writing, or reproducing the internal format of `.mlapp` files
- Full compatibility with App Designer
- Semantic analysis or rewriting of arbitrary MATLAB code
- Recovery of every dynamically created component
- Complete round-tripping of arbitrary MATLAB syntax
- Preview by executing the input application
- Visual editing of application-specific computational logic

## Updating This Specification

Update this document and the [README](README.md) when a change affects externally visible behavior, input requirements, output, or safety limitations. See [CONTRIBUTING.md](CONTRIBUTING.md) for development and contribution guidance.
