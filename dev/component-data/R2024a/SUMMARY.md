# R2024a component ledger

For contributors maintaining the R2024a catalog, this page identifies the release inputs and commands to regenerate the runtime catalog.

| Input | Purpose |
| --- | --- |
| [`components/`](components) and [`schema.json`](schema.json) | Concrete component variants and property contracts |
| [`runtime-component-metadata.json`](runtime-component-metadata.json) | Factory construction, palette, overlay, and resize capabilities |
| [`parent-context-rules.json`](parent-context-rules.json) | Parent-dependent property surfaces |
| [`inspector-rows.json`](inspector-rows.json) | Composite Inspector row definitions |
| [`category-scope-classification.json`](category-scope-classification.json) and [`grouping-design-input.json`](grouping-design-input.json) | Reviewed grouping scope, ownership, and ordering inputs |
| [`grouping/`](grouping) | Generated grouping candidates, expansion data, and parity results in JSON |

The ledger records documented facts and runtime observations separately. The [setter-access review](SETTER_ACCESS_RUNTIME_REVIEW.json), [constructor syntax review](CONSTRUCTOR_SYNTAX_REVIEW.json), and [enum review decisions](ENUM_REVIEW_DECISIONS.json) supply reviewed evidence for those fields. Historical evidence entries referring to the former audit guidelines identify the rules in use when those entries were recorded.

Run these commands from the repository root after reviewing any changes to the release inputs:

```powershell
$release = 'dev/component-data/R2024a'
& ./dev/component-data/UpdateProjectPropertyText.ps1 -ReleaseDirectory $release
& ./dev/component-data/GenerateGroupingArtifacts.ps1 -ReleaseDirectory $release
& ./dev/component-data/GenerateGroupingDesign.ps1 -ReleaseDirectory $release
& ./dev/component-data/PromoteGroupingToRuntimeCatalog.ps1 -ReleaseDirectory $release
```

Inspect `grouping/JUDGMENT_CANDIDATES.json` when reviewing possible grouping changes and `grouping/EXPANSION_PARITY.json` when checking the resulting design. See the [catalog generation guide](../README.md) for the contracts and verification commands.
