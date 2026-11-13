# Contributing to yamada

For contributors proposing or submitting changes, this guide explains the project workflow, development setup, and checks required for a pull request.

## Before You Start

- Search existing issues for the same problem or proposal.
- Small, self-contained changes such as typo fixes may be submitted directly as pull requests.
- Discuss new features, behavior changes, large refactorings, and expansions of supported syntax or components in an issue before implementation.
- Keep each issue or pull request focused on one reviewable purpose.

## Branch Workflow

Use `main` as the shared integration branch for the next release. There is no permanent `develop` branch. Published versions are identified by immutable release tags such as `v1.0.0` and their GitHub Releases; merging a pull request does not publish a Toolbox.

1. Create a focused work branch from up-to-date `main`, or use a branch in your fork. Agent-created branches use `codex/<purpose>`; other contributors may use descriptive names such as `feature/<purpose>` or `fix/<purpose>`.
2. Make the change and run the relevant checks before submitting a pull request. Include the results and explain any checks not run. For documentation-only changes, inspect the diff and links and run `git diff --check`; MATLAB tests are unnecessary unless executable examples or behavior change.
3. Open a pull request targeting `main`. Draft pull requests are welcome while work is incomplete. Check the final diff and validation evidence before merging; rerun affected checks if the change or integration base invalidates that evidence.
4. A maintainer merges the pull request after reviewing scope, source safety, and validation. A separate person's approval is not mandatory for sole-maintainer work. Delete the work branch when it is no longer needed.

Use pull requests for documentation and maintenance changes too. Do not push changes directly to `main` or routinely bypass its protection. Keep changes to `AGENTS.md` in a commit containing no other files; preserve that separation in the merge method rather than squashing it into unrelated changes.

Create `release/<major>.<minor>` only when a release needs stabilization or maintenance while `main` advances. For a patch to an older release, branch from its published tag if that maintenance branch does not exist. Prefer fixing on `main` and backporting the necessary commits through a pull request; for an old-version-specific fix, record whether `main` also needs it. Do not merge unrelated next-version features into a maintenance branch.

See [the release procedure](doc/RELEASING.md) for versioning, publication checks, and repository protection settings.

## Reporting Bugs

Include as much of the following information as possible in a reproducible bug report:

- MATLAB release, as reported by `version("-release")`
- Operating system and version
- Reproduction steps
- Expected and actual behavior
- Diagnostics shown by `yamada` or the complete MATLAB error message
- A minimal supported handle-class app `.m` file that reproduces the problem, if it can be shared publicly

Before attaching source, make sure it does not contain secrets, personal information, or code that you are not allowed to redistribute.

## Development Environment

Development and verification currently target MATLAB R2024a. After cloning the repository, add its root to the MATLAB path.

```matlab
projectRoot = "/path/to/yamada";
addpath(projectRoot);
yamada
```

Use the repository source for development. Published Toolbox installers are available from [GitHub Releases](https://github.com/NOBUTOKA/yamada/releases).

The documented normal launch command is `yamada`, without parentheses or an output assignment. Development and tests may retain the returned handle when they need to inspect or explicitly clean up the editor.

See the [product specification](SPECIFICATION.md) for the public feature set, input and output contract, and safety limitations. The [roadmap](ROADMAP.md) lists unfinished work as independent contribution candidates. Update the specification when a change affects externally visible behavior. Use the [architecture reference](doc/ARCHITECTURE.md) for current layer responsibilities, data flow, and extension boundaries.

## Repository Layout

| Path | Purpose |
| --- | --- |
| `yamada.m` | Main editor application |
| `+yamada/+model` | Document and component models |
| `+yamada/+source` | Lexical analysis, parsing, and source generation |
| `+yamada/+ui` | Safe Preview and Property Inspector |
| `+yamada/+validation` | Document and property validation |
| `resources/EditorInteractionOverlay.html` | HTML/SVG overlay for canvas selection, movement, and resizing; see below |
| `resources/component-catalog/R2024a` | Release-specific component catalog currently loaded at runtime; add sibling release directories for future MATLAB versions |
| `dev/component-data` | R2024a component data and catalog-generation scripts |
| `dev/compatibility` | Opt-in native MATLAB observations and catalog-promotion checks |
| `doc/ARCHITECTURE.md` | Developer reference for implemented layers, data flow, and extension boundaries |
| `doc/RELEASING.md` | Maintainer workflow, release gates, versioning, and GitHub settings |
| `tests/unit` | MATLAB unit tests |
| `tests/fixtures` | Input fixtures for source preservation, parsing, and preview |
| `tests/runYamadaTests.m` | Developer-only quick, area, and full test-profile runner |

Use the [roadmap](ROADMAP.md) to find proposed work. The [architecture reference](doc/ARCHITECTURE.md) describes the contracts to preserve when changing the model, source handling, or Preview.

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

When adding or changing a standard component or property, start with the [catalog generation guide](dev/component-data/README.md) and update the versioned JSON catalog rather than hard-coding declarative specifications in `ComponentRegistry`.

- Check the official MATLAB R2024a documentation and, when necessary, verify behavior in the R2024a runtime.
- Preserve the boundary that prevents catalog data or identifiers from invoking arbitrary MATLAB code.
- Keep tests consistent with the changed catalog behavior.
- Do not silently import behavior observed in another MATLAB release into the R2024a catalog.
- Keep property descriptions project-authored through `dev/component-data/ProjectPropertyText.ps1`. Preserve factual API tokens and source references; do not copy reference-page narrative or infer semantic contracts from its wording. Refresh ledger descriptions with `UpdateProjectPropertyText.ps1` before promotion.

## Testing

Before submitting a pull request, run the tests relevant to your changes and include the results. If you could not run a test, name it and explain why in the pull request.

The quick profile contains every non-UI test plus a bounded UI smoke set. Area profiles add their tagged tests to the quick profile. Supported area tags are `parser`, `catalog`, `model`, `generation`, `preview`, `gridOverlay`, `inspector`, `dialog`, `editorShell`, `previewTab`, and `lifecycle`.

From the repository root, run the full suite with:

```matlab
addpath(pwd, fullfile(pwd, "tests"));
results = runYamadaTests("full");
```

The other profiles are available as:

```matlab
quickResults = runYamadaTests("quick");
areaResults = runYamadaTests("area", ["inspector", "dialog"]);
```

To run one test file:

```matlab
results = runtests("tests/unit/ModelTest.m");
assertSuccess(results);
```

Optional native MATLAB observations and catalog-promotion provenance checks live outside the normal regression suite:

```matlab
addpath(fullfile(pwd, "dev", "compatibility"));
compatibilityResults = runCompatibilityChecks();
```

For catalog text or promotion changes, also run the PowerShell checks `tests/verifyCatalogProvenance.ps1` and `tests/verifyComponentLedgerSchema.ps1`. They verify reproducible regeneration, independence from reference wording, semantic preservation, and rejection of malformed ledger input before mutation.

## HTML Editing Canvas Overlay

For overlay data flow, event handling, and source-update responsibilities, see the [architecture reference](doc/ARCHITECTURE.md#safe-preview-and-canvas-overlay). Overlay changes should include the relevant browser tests and `tests/unit/EditorInteractionTest.m`.

## Pull Requests

Include the following in a pull request:

- What changed and why
- The related issue, if any
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
