# Source and Resource Provenance

This document identifies runtime and development inputs for distribution review. It does not grant permission to redistribute third-party material or certify that an unresolved input is covered by the project's GPL. The [1.0.0 plan](https://github.com/NOBUTOKA/yamada/blob/main/doc/RELEASE_1_0_0_PLAN.md) records outstanding release gates.

## Project Code and Editor Resources

Project-owned MATLAB source is licensed under GPL-3.0-or-later as stated in the trailing notices and repository `LICENSE`. The HTML interaction overlay has its existing GPL notice. `RootResizeGuide.html` and `stabilize-request.js` were added in this project's Git history by its maintainer; retain that provenance and the repository license when distributing these project resources. Do not infer a different upstream license from their use of standard HTML, SVG, JavaScript, or MATLAB module names.

The runtime distribution consists of `yamada.m`, the `+yamada` package, the complete `resources/component-catalog/R2024a` runtime catalog, `EditorInteractionOverlay.html`, `RootResizeGuide.html`, `stabilize-request.js`, and the selected user documentation and license notices. The packager must keep their relative layout and include the resources explicitly.

No downloaded browser library, bundled font, external CDN dependency, or separately vendored runtime library was identified in these editor HTML/JavaScript resources. SVG namespace URLs identify the markup namespace; they are not network downloads.

## MathWorks APIs, Catalog Data, and Documentation

The R2024a catalog is promoted from the development ledger under `dev/component-data/R2024a`. That ledger records release-fixed MathWorks documentation URLs and observations, for example the [Button properties reference](https://www.mathworks.com/help/releases/r2024a/matlab/ref/matlab.ui.control.button-properties.html). It retains API identifiers, type/value constraints, literal defaults, category labels, and project policy decisions. Property descriptions are now composed by the project-owned `ProjectPropertyText.ps1` definitions from API identifiers and reviewed contracts. Runtime promotion uses those definitions directly rather than importing a reference heading. The mirrored ledger summaries can be refreshed with `UpdateProjectPropertyText.ps1`.

The maintainer has confirmed that no separate redistribution permission has been obtained for documentation transcriptions. The installed R2024a `license_agreement.txt` includes online help in Documentation (23.6), grants limited intranet access and printing (2.3/2.4), and restricts republication except as expressly permitted in Article 2 (3.13). This is a proprietary documentation license, not an absence of licensing and not a GPL/CC grant for public republication. Read the actual agreement supplied with the licensed installation; source references or notices alone do not grant reuse rights. Other agreements or legal exceptions, if relevant, require their own assessment.

The current catalog replaces the 1,825 reference-derived property headings with project-authored descriptions. Descriptive value notation is shortened to factual forms where appropriate; exact API tokens, literal values, type names, and reviewed semantic contracts remain. The schema no longer requires verbatim reference headings, enum normalization uses reviewed enum arrays, and multiline classification uses typed contracts. No documentation paragraphs, reference examples, graphics, or MathWorks logos are introduced by this remediation. The project does not represent rewriting as a clean-room process or as retrospective permission for earlier copies.

Development inputs are not Toolbox runtime dependencies. Excluding them from `.mltbx` alone does not resolve their inclusion in GitHub's automatic source archives; the review must cover the tagged source tree as well. Catalog changes must still pass promotion/parity and source-safety checks.

### Factual Metadata and Authored Text

The retention boundary is engineering policy rather than a legal clearance certificate. Retain API names, literal enum/default values, types, dimensions, numeric bounds, source URLs, and common functional labels where they identify actual MATLAB behavior. Avoid reproducing reference narrative or examples. The [U.S. Copyright Office](https://www.copyright.gov/help/faq/faq-protect.html) distinguishes facts and short names from protected expression; that does not establish compliance with a contract, determine the status of an entire collection, or make a length threshold a legal test. Existing category IDs and Inspector order are retained for functional compatibility, not presented as a legal conclusion about all possible compilation/arrangement rights.

The editor loads Undo/Redo image data from the user's installed MATLAB and accesses MATLAB-provided UI/browser modules. These are MATLAB installation dependencies and must not be copied into this Toolbox. Any replacement distribution artwork must have its own clear project or compatible third-party provenance. MATLAB and product names identify the required environment; no MathWorks logo is supplied as yamada branding.

## Fixtures, User Applications, and Investigation Material

Preserved test inputs have their original notices and the adaptation record in [the fixture README](https://github.com/NOBUTOKA/yamada/blob/main/tests/fixtures/README.md). Some fixtures have no file-level redistribution notice; their presence in a test tree is not evidence of a separate upstream grant. Do not automatically turn these preserved inputs into public Toolbox examples. Use a small project-owned example with explicit provenance in the packaging stage, and include retained fixtures in the tagged-source review where appropriate.

Generated and user-supplied apps do not automatically inherit the editor's GPL. The editor must not insert, replace, or remove their license notices without the user's explicit request.

Historical performance plans and reports are preserved unchanged on the [`codex/investigation-pre-v1` branch](https://github.com/NOBUTOKA/yamada/tree/codex/investigation-pre-v1). They are excluded from the release branch's source and the Toolbox; unfinished implementation work remains in the roadmap. Existing history is retained.

## Included Tutorial and Screenshots

`examples/WelcomeApp.m` is an original project example licensed under GPL-3.0-or-later. The project-owned screenshots under `doc/images` show yamada and this example.
