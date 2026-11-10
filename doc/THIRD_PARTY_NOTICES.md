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

### Replacement and Retention Policy

This is a conservative engineering policy for preparing the release, not a jurisdiction-specific legal opinion or a finding that the catalog infringes copyright. The [U.S. Copyright Office](https://www.copyright.gov/help/faq/faq-protect.html) distinguishes facts, names, and short phrases from protected expression. Japanese government guidance likewise distinguishes factual data from potentially creative database selection or structure; see the [METI electronic-commerce guidance on copyright treatment of data](https://www.meti.go.jp/policy/it_policy/ec/20250212003-11.pdf). Neither principle makes an entire documentation-derived database automatically free to copy, and copyright analysis alone does not establish compliance with an applicable contract or website license.

| Content | Release preparation policy |
| --- | --- |
| API identifiers, class/type names, enum tokens, numeric bounds, actual literal defaults | Retain required factual spellings and values, with documentation/runtime provenance; do not rename APIs or drop supported values merely because the reference documents them. |
| Ordinary labels and type/shape descriptions | Review as functional factual terminology; no automatic replacement merely because a short phrase matches a reference. Length alone is not clearance. |
| Property summaries and explanatory prose | Independently write necessary user-facing descriptions from verified behavior. Remove nonessential transcriptions or retain them only with an established reuse basis. Do not treat synonym substitution or translation as sufficient independence. |
| Documentation-derived category arrangement | Review separately from individual facts. Do not assume copied selection/arrangement has no protection, but do not disrupt current UI order without a substantiated reason and an explicit product decision. |
| Project audit decisions, safety policies, schemas, effect rules, and independently authored code | Keep the project's license and provenance. Do not rewrite these simply because they cite MathWorks APIs. |
| Third-party examples, figures, logos, or retained fixtures | Establish the specific origin/license; retain notices and do not substitute the project's GPL. These are not automatically approved public examples. |

The current development ledger has 48 component records and 1,825 summaries, each at most 69 characters; default and accepted-value fields are also short. This inventory does not establish infringement or a reuse permission. It corrects the earlier overly broad implication that all these fields are long explanatory transcriptions requiring replacement. For example, a documented enum token is an API input, whereas an optional property explanation is replaceable prose. Preserve the fact and review the expression.

The regeneration chain is part of the remediation: development `summary` becomes runtime `metadata.description`, and some development tools currently infer semantic contracts from default/value wording. Update the producer, schema guidance, relevant consumers, and exact-heading tests together. Reviewing only the installed JSON would allow the next promotion to restore old wording or alter accepted types inadvertently.

MathWorks' [Book Program Brand Guidelines](https://www.mathworks.com/content/dam/mathworks/mathworks-dot-com/support/books/members/pdfs/mathworks-book-program-brand-guidelines.pdf) discuss permission for reprinting documentation and graphics in that program. They are not an open-source license for this project's data and should not be generalized into a legal ruling on every API fact or short heading. An applicable blanket redistribution permission was not established in this review; the cited third-party license bundles for software components are not licenses for MathWorks' own documentation.

### Historical Commits and Public Refs

The current release tree and historical distribution are separate questions. A corrective commit changes future source archives, not the contents of earlier commits, branches, tags, forks, or clones. GitHub documents that [deleted files remain in Git history](https://docs.github.com/en/repositories/working-with-files/managing-files/deleting-files-in-a-repository); its [history-removal guidance](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository) also explains coordination with existing copies. That operational documentation is not a legal requirement to rewrite all history.

Default to forward-only remediation while identifying any specifically problematic historical expression and reachable refs, including `codex/investigation-pre-v1`. Do not rewrite history solely because API names and short factual labels appeared in older commits. If protected expression or an applicable reuse restriction is concretely identified, assess permission, legal basis, or targeted removal separately before recording clearance. Keeping historical content is not automatically justified by fixing `main`, and a force-push cannot guarantee deletion of others' copies or undo past distribution.

Any history rewrite, ref deletion, or repository migration requires separate explicit maintainer authorization and an impact/recovery plan. Until a concrete historical concern is resolved, record it as open rather than asserting that the release is cleared. Do not preserve questionable text by copying it into a newly published archive branch as a workaround.

The editor loads Undo/Redo image data from the user's installed MATLAB and accesses MATLAB-provided UI/browser modules. These are MATLAB installation dependencies and must not be copied into this Toolbox. Any replacement distribution artwork must have its own clear project or compatible third-party provenance. MATLAB and product names identify the required environment; no MathWorks logo is supplied as yamada branding.

## Fixtures, User Applications, and Investigation Material

Preserved test inputs have their original notices and the adaptation record in [the fixture README](../tests/fixtures/README.md). Some fixtures have no file-level redistribution notice; their presence in a test tree is not evidence of a separate upstream grant. Do not automatically turn these preserved inputs into public Toolbox examples. Use a small project-owned example with explicit provenance in the packaging stage, and include retained fixtures in the tagged-source review where appropriate.

Generated and user-supplied apps do not automatically inherit the editor's GPL. The editor must not insert, replace, or remove their license notices without the user's explicit request.

Historical performance plans and reports are preserved unchanged on the [`codex/investigation-pre-v1` branch](https://github.com/NOBUTOKA/yamada/tree/codex/investigation-pre-v1). They are excluded from the release branch's source and the Toolbox; unfinished implementation work remains in the roadmap. Existing history is retained.
