# Component catalog generation

For contributors updating a component catalog, this guide describes the generation inputs, output contracts, and verification commands. See the [R2024a ledger](R2024a/SUMMARY.md) for the inputs used by that release.

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

Run `tests/verifyComponentLedgerSchema.ps1` and `tests/verifyCatalogProvenance.ps1` from the repository root. For catalog behavior changes, also run the relevant MATLAB catalog, source, Inspector, or Preview checks described in the [contributor guide](../../CONTRIBUTING.md#testing).
