# Component catalog generation

For contributors updating a component catalog, this guide describes the generation inputs, output contracts, and verification commands. See the [R2026b ledger](R2026b/SUMMARY.md) for the inputs of the current surface release.

## Releases and projection

One ledger describes every release. [`releases.json`](releases.json) lists the known MATLAB releases in chronological order and names the surface release, whose directory holds the ledger; its records describe that release exactly. Each other release has a status: `verified` releases have their annotations checked against native controls and receive a generated catalog, while `known` releases are described by release notes only and receive none, so the runtime loader serves them the newest older catalog.

The surface ledger describes other releases with annotations:

- `availability.releases` on a component document or a property gives a `since` and/or `before` release bound. A record outside its range is absent from that release. A property range must lie within the range of its variant.
- `overrides` on a component document, a property, or a runtime metadata factory entry applies a JSON merge patch (RFC 7386) for a release range. A range may not include the surface release, and overlapping ranges may not patch the same field.
- `valueContract.valueAvailability` gives the range of one enum value.

Every annotation carries `evidence` naming release notes, MathWorks documentation, a native observation, or a project decision. `ProbeReleaseSurface.m` records the native surface of the running release and `CompareReleaseSurfaces.m` compares two such records when verifying annotations.

`ProjectReleaseLedger.ps1` projects the ledger onto one release: it applies overrides, removes unavailable variants, properties, and values, repairs dependent grouping data such as shared subsets, inspector rows, and category order, and strips the annotations. It rejects contradictory input, such as an unknown release, a constraint on a removed property, or removal of a default variant, before writing output. Each projection report in `projections/` lists what was removed, overridden, or repaired.

Run `RegenerateReleaseCatalogs.ps1` with PowerShell 7 after changing the ledger or the release list. With Git on `PATH`, the grouping baseline records the last commit that changed the ledger inputs; without it, the commit is recorded as unavailable. It refreshes presentation text, projects, groups, and promotes every release with a catalog, writes the projection reports and the surface release's grouping review artifacts, and writes `resources/component-catalog/availability.json`, which records the release range of every annotated variant, property, and value so that another release can explain what it lacks.

To move the surface to a newer release, audit the new release, express the differences of older releases as annotations, update `releases.json`, and regenerate. The catalogs of verified releases must not change unless the audit corrects them. Document sources and the reviews that cite them keep the documentation release where the ledger was audited property by property, which the schema URL pattern names; a later surface records its differences through annotations with their own evidence, and projections accept that documentation release and the target release.

The surface ledger also owns `axes-setting-functions.json`. Regeneration publishes a call-form catalog beside each verified release catalog and removes the availability annotations from its runtime records. Source analysis selects the call forms from the same catalog root as the component registry. An argument-owned effect may list `elements`, the 1-based slice of an `axisLimits` vector argument that its path owns, so that `axis` limits keep one token per call while each axis limit is edited separately. A form marked `companionInsertion` is used for a new setting only when every value it implies is requested in the same edit, such as `XLimMode` `auto` for `xlim(ax, "padded")`. A form marked `insertion` is used for new settings of the one path its argument owns, so mark only forms whose implied effects match a plain assignment of that path. A `settingGroups` entry names a main path and the form whose options write paths that are meaningless without it; regeneration publishes a group only in releases that have its form. The separate axes setting function review retains research and documentation references.

## Inputs and output

Each ledger component file describes one concrete factory variant. The release directory contains the schemas, reviewed property contracts, component capabilities, and parent-context rules. Keep documented API facts, observed runtime behavior, and product policy in their respective fields. Refresh presentation text with `UpdateProjectPropertyText.ps1`. Enum and multiline classification use the typed `valueContract` fields.

The generators validate complete component documents against the release schema before writing output. Use the release ledger page for the commands and input paths. The editor loads the promoted catalog under `resources/component-catalog/`.

## Expansion and runtime contracts

- Expanding shared groups must reproduce the reviewed intrinsic and parent-effective property surfaces, including order, types, and capabilities. Each effective property has one owner, and each variant resolves to a deterministic category order.
- Catalog identifiers select allowlisted factories, editors, validators, and policies implemented in MATLAB. A property is promoted as editable only when source encoding, validation, Preview policy, and preservation are supported.
- Inspector row definitions are presentation data in `inspector-rows.json`. A composite row matches its complete member set and declared context. Member paths and roles are unique, templates cannot overlap, and the order anchor names a member. Property types, editability, and source ownership remain properties of individual members. Changes submitted together use the existing atomic batch operation.

### Geometry impact

The `gridGeometryImpact` and `absoluteGeometryImpact` fields describe effects on grid and absolute-position geometry. Preserve the reviewed values unless an editor change includes evidence for a different policy. Use the release schema and application-policy definitions for allowed values.

## Verification

Run `tests/verifyComponentLedgerSchema.ps1`, `tests/verifyCatalogProvenance.ps1`, and `tests/verifyReleaseProjection.ps1` from the repository root. The last one fails when a committed catalog, projection report, or availability index is not the current projection of the ledger. For catalog behavior changes, also run the relevant MATLAB catalog, source, Inspector, or Preview checks described in the [contributor guide](../../CONTRIBUTING.md#testing).
