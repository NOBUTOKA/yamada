# Contributing to yamada

Thank you for your interest in contributing to `yamada`. Reproducing bugs, proposing features, improving documentation, adding tests, and changing the code or component catalog are all valuable contributions.

## Before You Start

- Search existing issues for the same problem or proposal.
- Small, self-contained changes such as typo fixes may be submitted directly as pull requests.
- Discuss new features, behavior changes, large refactorings, and expansions of supported syntax or components in an issue before implementation.
- Keep each issue or pull request focused on one reviewable purpose.

## Reporting Bugs

Include as much of the following information as possible in a reproducible bug report:

- MATLAB release, as reported by `version("-release")`
- Operating system and version
- Reproduction steps
- Expected and actual behavior
- Diagnostics shown by `yamada` or the complete MATLAB error message
- A minimal AppBase `.m` file that reproduces the problem, if it can be shared publicly

Before attaching source, make sure it does not contain secrets, personal information, or code that you are not allowed to redistribute.

## Development Environment

Development and verification currently target MATLAB R2024a. Fork and clone the repository, then add its root to the MATLAB path.

```matlab
projectRoot = "/path/to/yamada";
addpath(projectRoot);
editor = yamada();
```

No versioned release or Toolbox package is available yet, so development uses the repository source directly.

See the [product specification](SPECIFICATION.md) for the public feature set,
input and output contract, and safety limitations. The [roadmap](ROADMAP.md)
lists unfinished work as independent contribution candidates. Update the
specification when a change affects externally visible behavior.

## Repository Layout

| Path | Purpose |
| --- | --- |
| `yamada.m` | Main editor application |
| `+macd/+model` | Document and component models |
| `+macd/+source` | Lexical analysis, parsing, and source generation |
| `+macd/+ui` | Safe Preview and Property Inspector |
| `+macd/+validation` | Document and property validation |
| `resources/EditorInteractionOverlay.html` | HTML/SVG overlay for canvas selection, movement, and resizing; see below |
| `resources/component-catalog/R2024a` | Release-specific component catalog currently loaded at runtime; add sibling release directories for future MATLAB versions |
| `dev/component-data` | R2024a component data and catalog-generation scripts |
| `tests/unit` | MATLAB unit tests |
| `tests/fixtures` | Input fixtures for source preservation, parsing, and preview |

## MATLAB Code Conventions

- Project-owned MATLAB source and test files must use UTF-8 without a BOM and CRLF line endings.
- Write source comments, class help, and function and method docstrings in English.
- Put a purpose-oriented docstring immediately after every project-owned function or method declaration.
- Use explicit `arguments (Input)` and `arguments (Output)` blocks when practical validation is possible for the signature.
- Prefer MATLAB `string` values and double-quoted string literals for text.
- Put English help comments immediately before public properties and use the narrowest practical access.
- End each project-owned `.m` file with the same GNU GPL notice used by neighboring files. Do not add the project's GPL notice automatically to saved user applications or preserved input fixtures.
- Add concise English comments before meaningful operation groups, but avoid comments that merely restate self-explanatory assignments.

Follow the formatting of existing code, and do not include unrelated formatting or line-ending changes in a pull request.

## Changing the Component Catalog

When adding or changing a standard component or property, update the versioned JSON catalog rather than hard-coding declarative specifications in `ComponentRegistry`.

- Check the official MATLAB R2024a documentation and, when necessary, verify behavior in the R2024a runtime.
- Review the component data, classifications, and generation scripts under `dev/component-data`.
- Preserve the boundary that prevents catalog data or identifiers from invoking arbitrary MATLAB code.
- Add or update the corresponding loader, registry, validation, Inspector, Preview, and generation tests.
- Do not silently import behavior observed in another MATLAB release into the R2024a catalog.

## Testing

Run tests directly related to your change first, followed by the full unit test suite. In MATLAB, make the repository root the Current Folder and run:

```matlab
addpath(pwd);
clear classes;
rehash path;
results = runtests("tests/unit");
disp(results);
assertSuccess(results);
```

To run one test file:

```matlab
results = runtests("tests/unit/ModelTest.m");
assertSuccess(results);
```

If you could not run a test, name it and explain why in the pull request.

## HTML Editing Canvas Overlay

Canvas selection, drag movement, eight-direction resizing, and Tab Group selection use `resources/EditorInteractionOverlay.html`, which is loaded as a transparent `uihtml` layer. The native Preview components do not process these editing gestures directly.

- `yamada.m` sends the canvas dimensions, component IDs, display positions, outline shapes, selection state, and tab information to HTML through `InteractionOverlay.Data`.
- The HTML renders SVG outlines and resize handles, converts DOM coordinates to a bottom-left origin, and sends the pointer phase, coordinates, target ID, and handle type back to MATLAB through `sendEventToMATLAB`.
- MATLAB handles the Preview-to-source scale, component-specific resize constraints, and candidate geometry during a gesture. The completed gesture is then committed as one change to `DocumentModel` and the undo/redo history.
- The HTML overlay and Preview handles are disposable presentation and input state; neither is the authoritative document state.

If you change the overlay `Data` structure or event format, update the sending and receiving code in `EditorInteractionOverlay.html` and `yamada.m` in the same change. Exercise selection, movement, resizing, and tab-selection paths in `tests/unit/EditorInteractionTest.m`.

## Pull Requests

Include the following in a pull request:

- What changed and why
- The related issue
- Effects on source preservation, Safe Preview, and the supported scope
- Tests run and their results
- Checks not run and the reason
- Before-and-after images or reproduction steps when useful for a UI change

Before submitting:

- [ ] The change has one focused purpose
- [ ] Tests cover the new behavior or fixed bug
- [ ] The product specification or README is updated when necessary
- [ ] MATLAB file encoding, line endings, docstrings, and GPL notices are correct
- [ ] Relevant tests pass and `git diff --check` reports no problems
- [ ] Unsupported source remains preserved and the input application is never executed

## License

Accepted contributions are distributed under the same GNU General Public License version 3 or later (`GPL-3.0-or-later`) as the project. Make sure you have the right to provide your contribution under this license.
