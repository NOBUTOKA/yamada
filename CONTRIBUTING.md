# Contributing to yamada

For contributors proposing or submitting changes, this guide explains the project workflow, development setup, and checks required for a pull request.

## Before You Start

- Search existing issues for the same problem or proposal.
- Small, self-contained changes such as typo fixes may be submitted directly as pull requests.
- Discuss new features, behavior changes, large refactorings, and expansions of supported syntax or components in an issue before implementation.
- Keep each issue or pull request focused on one reviewable purpose.

## Branch Workflow

Use `main` as the shared integration branch for the next release. There is no permanent `develop` branch. Published versions are identified by immutable release tags such as `v1.0.0` and their GitHub Releases; merging a pull request does not publish a Toolbox.

1. Create a focused work branch from up-to-date `main`, or use a branch in your fork. Use a descriptive name such as `feature/<purpose>`, `fix/<purpose>`, or `docs/<purpose>`.
2. Make the change and run the relevant checks before submitting a pull request. Include the results and explain any checks not run. For documentation-only changes, inspect the diff and links and run `git diff --check`; MATLAB tests are unnecessary unless executable examples or behavior change.
3. Open a pull request targeting `main`. Draft pull requests are welcome while work is incomplete. Check the final diff and validation evidence before merging; rerun affected checks if the change or integration base invalidates that evidence.
4. A maintainer merges the pull request after reviewing scope, source safety, and validation. A separate person's approval is not mandatory for sole-maintainer work. Delete the work branch when it is no longer needed.

Use pull requests for documentation and maintenance changes too. Do not push changes directly to `main` or routinely bypass its protection.

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

The supported release targets are currently MATLAB R2023a through R2026b, and project-owned MATLAB source must run on R2023a and later; see [MATLAB Release Compatibility](#matlab-release-compatibility). After cloning the repository, add its root to the MATLAB path.

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
| `resources/component-catalog/<release>` | Generated component catalog of each release; the runtime loads the newest catalog that is not newer than the running release |
| `dev/component-data` | Component ledger of the surface release, release list, and catalog-generation scripts |
| `dev/compatibility` | Opt-in native MATLAB observations and catalog-promotion checks |
| `doc/ARCHITECTURE.md` | Developer reference for implemented layers, data flow, and extension boundaries |
| `doc/RELEASING.md` | Maintainer workflow, release gates, versioning, and GitHub settings |
| `tests/unit` | MATLAB unit tests |
| `tests/fixtures` | Input fixtures for source preservation, parsing, and preview |
| `tests/runYamadaTests.m` | Developer-only quick, area, and full test-profile runner |

Folders whose names begin with `.`, at any depth, are reserved for tool configuration and local working material. They are not project-owned source: project conventions and their checks do not apply to them, so do not place project-owned MATLAB files there.

Use the [roadmap](ROADMAP.md) to find proposed work. The [architecture reference](doc/ARCHITECTURE.md) describes the contracts to preserve when changing the model, source handling, or Preview.

## MATLAB Code Conventions

- Project-owned MATLAB source and test files must use UTF-8 without a BOM and CRLF line endings.
- Write source comments, class help, and function and method docstrings in English.
- Put a purpose-oriented docstring immediately after every project-owned function or method declaration.
- Add explicit `arguments (Input)` and `arguments (Output)` blocks to every function and method you add or modify, except nested functions, test methods, and handle-class `delete` methods.
- Prefer MATLAB `string` values and double-quoted string literals for text.
- Put English help comments immediately before public properties. Make implementation state `Access = private`, and use `SetAccess = private` for state that other classes only read.
- Declare a property class whenever all accepted values share one class. Do not add size constraints to property declarations.
- End each project-owned `.m` file with the same GNU GPL notice used by neighboring files. Do not add the project's GPL notice automatically to saved user applications or preserved input fixtures.
- Add concise English comments before meaningful operation groups and explain non-obvious intent, but avoid comments that merely restate self-explanatory assignments.

Follow the formatting of existing code, and do not include unrelated formatting or line-ending changes in a pull request.

## MATLAB Release Compatibility

### Policy

- Project-owned MATLAB source outside the component catalog must run on MATLAB R2023a and every later release. R2023a is a source-compatibility floor, not a support statement: the supported release targets are those listed in the README and the specification, because each target also needs a verified catalog.
- Absorb release differences in the release-specific component catalogs under `resources/component-catalog/<release>`, which are generated from availability annotations in the surface ledger under `dev/component-data`. Components, creation variants, properties, defaults, value sets, and parent-context effects that differ between releases are catalog data. Do not branch MATLAB source on the running release to reproduce catalog facts, and do not reference a UI component property in MATLAB source when the catalog can supply it.
- When a release difference cannot be expressed as catalog data, such as an undocumented integration point like the Preview layout adapter or a behavior change in a MATLAB function that the editor calls, isolate it behind one adapter with a bounded fallback and record the verified releases in the [architecture reference](doc/ARCHITECTURE.md). Gate on the release with `isMATLABReleaseOlderThan`, not by parsing `version` output or calling `ver` or `verLessThan`; those two are not recommended from R2023b, and from R2023b `version` reports numbers such as 23.2 and 24.1 instead of the earlier 9.x scheme.
- Verify MATLAB source changes on the minimum release R2023a as well as on the surface release of the component ledger. See [Testing](#testing) for the required profiles.
- Keep tests shared across releases. When a test exercises a component or property that only some releases' catalogs contain, gate it with `assumeCatalogSupports`, which checks the loaded catalog rather than the release name, so the test is incomplete instead of failing where the catalog lacks it. Put a fixture variant for an older release in `tests/fixtures/<release>/` and load fixtures through `yamadaFixturePath`; see the [fixture notes](tests/fixtures/README.md#release-specific-variants).

### Features Unavailable in R2023a

The following items come from the MATLAB release notes for R2023b through R2026b. R2025b was a quality and stability release whose notes list no language or app-building changes. The list covers the areas that project source uses; check the release notes for any other new function before adopting it.

Dictionaries:

- Do not use `configureDictionary`, `lookup`, `insert`, or `remove` (R2023b), or `readdictionary` and `writedictionary` (R2024b).
- Instead of `configureDictionary`, create an empty typed dictionary from typed empty inputs, for example `dictionary(string([]), {})` or `dictionary(string([]), [])`. Instead of `insert`, `lookup`, and `remove`, use indexed assignment, `isKey` with indexing, and `d(key) = []`.

Classes, metaclasses, and argument validation:

- Use the `meta.*` metaclass names, such as `meta.class`, `meta.property`, `meta.method`, and `meta.package`. The `matlab.metadata.*` names start in R2024a, and `metafunction`, `namespaceFunctions`, `namespaceClasses`, and `innerNamespaces` start in R2026a. From R2024a, `?ClassName` and `meta.class.fromName` return `matlab.metadata.Class`, which is still a `meta.class`; test with `isa(value, "meta.class")` and never compare `class(?ClassName)` with a string.
- Do not read `GetMethod` or `SetMethod` handles from metaclass property objects; this warns from R2026a and will error for non-dynamic properties.
- `?ClassName` access lists, such as `methods (Access = ?yamada.model.DocumentModel)`, behave the same in all supported releases.
- In a constructor `arguments` block, R2023a `.?ClassName` name-value arguments do not accept properties with `SetAccess = immutable`; that support starts in R2024a. Declare such options explicitly.
- Do not use the validators `mustBeSparse` (R2023b), `mustBeMatrix`, `mustBeRow`, or `mustBeColumn` (R2024b), `mustBeBetween` (R2025a), `mustBeSorted` (R2026a), or `mustBeScalar` and `mustBeVectorOrEmpty` (R2026b), and do not pass multiple type names to `mustBeUnderlyingType` (R2024a). Use size constraints such as `(1, :)` or validators that exist in R2023a.
- From R2026a, comparison and sign validators such as `mustBePositive`, `mustBeInteger`, and `mustBeGreaterThan` also accept nonnumeric input. Add `mustBeNumeric` or `mustBeReal` when the argument must be numeric.
- Do not use `matlab.lang.WeakReference` or the `WeakHandle` property attribute (R2024b), the custom element serialization mixins (R2024b), `createArray` (R2024a), `onCleanup` cancellation or `matlab.lang.Workspace` (R2025a), or `matlabProcessID` (R2025a).
- Give enumeration-typed properties and `matlab.mixin.Scalar`-typed properties an explicit default value. Their implicit defaults changed in R2024b and R2026a.

General language behavior:

- Pass only scalar operands to the colon operator, for example `1:numel(values)`. Nonscalar operands warn from R2024a and error from R2025a.
- Do not depend on identifier truncation at 63 characters. `namelengthmax` is 2048 from R2025a. Generated identifiers must still satisfy the limit of the release that runs the generated app, so check names against `namelengthmax` instead of a constant.
- Do not depend on the orientation of the result after deleting elements with an all-false logical index; from R2026b it is a row vector.
- Do not call `min` or `max` with a character array as the second input; it errors from R2024b.

App building and graphics:

- Treat component availability, properties, and defaults as catalog data. Examples include range sliders, `AllowEmpty`, `Placeholder`, and `ValueIndex` (R2023b), `uicolorpicker` (R2024a), the `Interpreter` property of buttons (R2024b), the `Step` property of `uislider` (R2025a), the accessibility `Label` property (R2026a), and radio and toggle buttons outside button groups, `uiselectiongroup`, and their new default positions (R2026b).
- Do not use the theme API, such as `theme`, `Theme`, and `ThemeChangedFcn` (R2025a). Default figure and component colors change in R2025a, so tests must not compare rendered colors with hard-coded defaults.
- Do not use `uitable` `Extent` for layout; it always returns a fixed value from R2025a. Do not capture UI components with `print` or `saveas`; use `exportapp`.
- Axes `PickableParts` defaults to `"all"` from R2026a. Set it explicitly when hit testing depends on it.

Testing:

- Do not use `TestSuite.fromNamespace`, `CodeCoveragePlugin.forNamespace`, or the `IncludingInnerNamespaces` and `IncludeInnerNamespaces` options (R2024a); the earlier package-named forms still work. Do not use `TestRunner.withDefaultPlugins` (R2025a) or `matlab.unittest.fixtures.UIFigureFixture` (R2026b).
- Do not use the app-testing gestures `scroll` (R2024a), `chooseDialog` and `dismissDialog` (R2024b), or `doublePress` (R2026b).
- Pass logical values to the `runtests` option `UseParallel`; the text values `"off"`, `"auto"`, and `"on"` start in R2026b.

Java and environment:

- The editor needs a JVM for UUIDs and canonical path comparisons, and the parallel test runner starts workers with `java.lang.ProcessBuilder`. From R2026b, MATLAB installs no Java runtime, so install the MATLAB Support for OpenJDK add-on or another OpenJDK distribution before running yamada or its tests on R2026b or later.
- Test for Java with `usejava("jvm")`. The `"awt"` and `"swing"` options of `usejava` and `javachk` will be removed.

## Changing the Component Catalog

When adding or changing a standard component or property, start with the [catalog generation guide](dev/component-data/README.md) and update the versioned JSON catalog rather than hard-coding declarative specifications in `ComponentRegistry`.

- Edit only the ledger of the surface release named in `dev/component-data/releases.json`, then run `dev/component-data/RegenerateReleaseCatalogs.ps1` to regenerate every release catalog. Do not edit generated catalogs or projection reports by hand.
- Check the official MATLAB documentation of the surface release and, when necessary, verify behavior in its runtime.
- Describe a difference in another release as an `availability` range or an `overrides` entry on the affected record, with evidence from the release notes, the documentation, or a native observation of that release. Do not silently import behavior observed in another release into the surface record.
- Preserve the boundary that prevents catalog data or identifiers from invoking arbitrary MATLAB code.
- Keep tests consistent with the changed catalog behavior.
- Keep property descriptions project-authored through `dev/component-data/ProjectPropertyText.ps1`. Preserve factual API tokens and source references; do not copy reference-page narrative or infer semantic contracts from its wording. Refresh ledger descriptions with `UpdateProjectPropertyText.ps1` before promotion.

## Testing

Before submitting a pull request, run the tests relevant to your changes and include the results. If you could not run a test, name it and explain why in the pull request.

Before submitting a pull request, run the full suite on both the minimum source release R2023a and the surface release of the component ledger, which `surfaceRelease` in `dev/component-data/releases.json` names and is currently R2026b, except for documentation-only changes that do not affect executable examples or behavior. Use quick and area profiles while iterating. Start the runner from the executable of the release under test; parallel workers start from the same `matlabroot`. If you cannot set up an R2023a environment, run the full suite on the surface release and ask the maintainer in the pull request description to run the R2023a full suite. Before a release, also follow the release checks in [the release procedure](doc/RELEASING.md).

The quick profile contains every non-UI test except catalog-wide sweeps, plus a bounded UI smoke set. Catalog-wide sweeps, which repeat a check for every catalog variant through rendering, generation, or ledger comparison, carry the `exhaustive` tag instead of `fast`; they run in the full suite and in area profiles that select them. Area profiles add their tagged tests to the quick profile. Supported area tags are `parser`, `catalog`, `model`, `generation`, `preview`, `gridOverlay`, `inspector`, `dialog`, `editorShell`, `previewTab`, `lifecycle`, and `exhaustive`. Run the `exhaustive` area while iterating on catalog changes.

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

Any profile can run in parallel by adding `Workers`. The runner starts that many batch MATLAB processes, splits the suite by test class, and returns the combined results in suite order. Each worker needs its own MATLAB session and memory, so choose a count that fits the host; four workers suit an eight-core machine. With the default of one worker, tests run in the current session.

```matlab
results = runYamadaTests("full", Workers=4);
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

For catalog text or promotion changes, also run the PowerShell checks `tests/verifyCatalogProvenance.ps1`, `tests/verifyComponentLedgerSchema.ps1`, and `tests/verifyReleaseProjection.ps1`. They verify reproducible regeneration, independence from reference wording, semantic preservation, rejection of malformed ledger input before mutation, and that every committed release catalog is the current projection of the surface ledger. The checks require PowerShell 7.

## HTML Editing Canvas Overlay

For overlay data flow, event handling, and source-update responsibilities, see the [architecture reference](doc/ARCHITECTURE.md#safe-preview-and-canvas-overlay). Overlay changes should include the relevant browser tests and `tests/unit/EditorInteractionTest.m`.

## Pull Requests

Include the following in a pull request:

- What changed and why
- The related issue, if any
- Effects on source preservation, Safe Preview, and the supported scope
- Tests run, the MATLAB release of each run, and their results
- Checks not run and the reason, including a request for the maintainer to run the R2023a full suite if you could not run it
- Before-and-after images or reproduction steps when useful for a UI change

Before submitting:

- [ ] The change has one focused purpose
- [ ] Tests cover the new behavior or fixed bug
- [ ] The product specification or README is updated when necessary
- [ ] MATLAB file encoding, line endings, docstrings, and GPL notices are correct
- [ ] Changed MATLAB source avoids features unavailable in R2023a
- [ ] The full suite passes on R2023a and the surface release, or the pull request asks the maintainer to run it on R2023a
- [ ] Relevant tests pass and `git diff --check` reports no problems
- [ ] Unsupported source remains preserved and the input application is never executed

## License

Accepted contributions are distributed under the same GNU General Public License version 3 or later (`GPL-3.0-or-later`) as the project. Make sure you have the right to provide your contribution under this license.
