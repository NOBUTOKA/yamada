# Source and Resource Provenance

This document identifies runtime and development inputs for distribution review. It does not grant permission to redistribute third-party material or certify that an unresolved input is covered by the project's GPL. The [1.0.0 plan](RELEASE_1_0_0_PLAN.md) records outstanding release gates.

## Project Code and Editor Resources

Project-owned MATLAB source is licensed under GPL-3.0-or-later as stated in the trailing notices and repository `LICENSE`. The HTML interaction overlay has its existing GPL notice. `RootResizeGuide.html` and `stabilize-request.js` were added in this project's Git history by its maintainer; retain that provenance and the repository license when distributing these project resources. Do not infer a different upstream license from their use of standard HTML, SVG, JavaScript, or MATLAB module names.

The runtime distribution consists of `yamada.m`, the `+yamada` package, the complete `resources/component-catalog/R2024a` runtime catalog, `EditorInteractionOverlay.html`, `RootResizeGuide.html`, `stabilize-request.js`, and the selected user documentation and license notices. The packager must keep their relative layout and include the resources explicitly.

No downloaded browser library, bundled font, external CDN dependency, or separately vendored runtime library was identified in these editor HTML/JavaScript resources. SVG namespace URLs identify the markup namespace; they are not network downloads.

## MathWorks APIs, Catalog Data, and Documentation

The R2024a catalog was promoted from the development transcript under `dev/component-data/R2024a`. That transcript records release-fixed MathWorks documentation URLs and observations, for example the [Button properties reference](https://www.mathworks.com/help/releases/r2024a/matlab/ref/matlab.ui.control.button-properties.html). The runtime JSON contains API identifiers, type/value constraints, project policy decisions, category labels, and short property descriptions. The development transcript additionally contains documentation-derived accepted-value and default text.

The maintainer has confirmed that no separate redistribution permission has been obtained for documentation transcriptions. References and factual API observations are provenance, not a grant to relicense copied explanatory text. Before release, review both the runtime descriptions and development transcriptions, identify retained upstream wording, and replace nonessential explanatory text with independently authored descriptions or remove it, unless an applicable redistribution basis is established. Preserve API facts and the source-audit trail without treating all documentation as GPL-covered project prose. This is an unresolved release gate, not a conclusion that every API name or short label requires permission.

Development inputs are not Toolbox runtime dependencies. Excluding them from `.mltbx` alone does not resolve their inclusion in GitHub's automatic source archives; the review must cover the tagged source tree as well. Catalog changes must still pass promotion/parity and source-safety checks.

The editor loads Undo/Redo image data from the user's installed MATLAB and accesses MATLAB-provided UI/browser modules. These are MATLAB installation dependencies and must not be copied into this Toolbox. Any replacement distribution artwork must have its own clear project or compatible third-party provenance. MATLAB and product names identify the required environment; no MathWorks logo is supplied as yamada branding.

## Fixtures, User Applications, and Investigation Material

Preserved test inputs have their original notices and the adaptation record in [the fixture README](../tests/fixtures/README.md). Some fixtures have no file-level redistribution notice; their presence in a test tree is not evidence of a separate upstream grant. Do not automatically turn these preserved inputs into public Toolbox examples. Use a small project-owned example with explicit provenance in the packaging stage, and include retained fixtures in the tagged-source review where appropriate.

Generated and user-supplied apps do not automatically inherit the editor's GPL. The editor must not insert, replace, or remove their license notices without the user's explicit request.

Historical performance plans and reports are preserved unchanged on the [`codex/investigation-pre-v1` branch](https://github.com/NOBUTOKA/yamada/tree/codex/investigation-pre-v1). They are excluded from the release branch's source and the Toolbox; unfinished implementation work remains in the roadmap. Existing history is retained.
