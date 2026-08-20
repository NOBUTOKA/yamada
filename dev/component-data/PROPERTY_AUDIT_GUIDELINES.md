# Component Property Audit Guidelines

This document defines the release-independent procedure for auditing MATLAB UI
component properties. Release-specific documentation transcripts live in
directories such as `R2024a`; the same procedure applies when adding another
release such as `R2023b`.

The development transcript records both documentation facts and product audit
decisions. It is not itself the runtime component catalog and does not authorize
editing, source generation, or Safe Preview assignment. Promotion into the
runtime catalog is a separate, tested step.

## Design principles

1. Keep documentation facts separate from product decisions.
2. Keep product intent separate from current implementation availability.
3. Treat a concrete component variant, not a factory name alone, as the unit of
   audit.
4. Preserve source that is outside the editable surface. Omitting a property
   from the inspector never authorizes deleting or rewriting its source.
5. Never infer Safe Preview safety from editability or visual effect alone.
6. Express cross-property constraints in one direction, from the dependent
   property to the property it depends on.
7. Keep executable behavior in allowlisted MATLAB code. JSON names symbolic
   schemas, editors, validators, policies, and reasons only.

## Evidence hierarchy

Audit each release against its release-fixed MathWorks documentation and target
MATLAB runtime. Use evidence in this order:

1. The release-fixed property reference page is authoritative for the public
   surface, category, documented default, accepted values, read-only status,
   and explanatory constraints.
2. Target-release runtime metadata is supporting evidence for declared type,
   public `SetAccess`, and other facts exposed by `meta.class` and
   `meta.property`.
3. One allowlisted hidden runtime fixture per concrete component surface is
   supporting evidence for runtime defaults and representable value classes.
   Read all audited defaults from that fixture in one batch; do not construct a
   component for each property.
4. Focused assignment probes may confirm ambiguous documented constraints. They
   must use owned hidden fixtures, avoid callbacks and arbitrary expressions,
   and always clean up constructed UI objects.

Documentation text and runtime observations must not silently overwrite one
another. When they disagree, retain the documented fact, record the runtime
observation separately, and resolve the discrepancy explicitly.

Read-only extraction must inspect the property body as well as its heading. For
example, R2024a pages use prose such as `This property is read-only.`; a parser
that searches only for a `Read-only:` heading is insufficient.

## Audit unit and variant applicability

Each JSON component file represents one concrete variant, for example
`uibutton-push` or `uibutton-state`. A property contained in a variant file is
implicitly applicable to that variant. Do not repeat an `applicableStyles` list
on every property.

When identical properties are later consolidated into a shared definition,
express applicability using stable variant IDs. Style strings may be derived
from variant construction metadata when adapting the audit data to an older
factory/style runtime representation.

## Value contract

Do not reduce a property type to one MATLAB class name. Normalize its accepted
surface into a value contract while retaining the original documentation text.
A value contract should be able to describe:

- a semantic kind;
- all accepted MATLAB value classes;
- scalar, vector, matrix, fixed-size, or property-dependent shape;
- whether an empty value is accepted;
- fixed vector length and significant row or column orientation;
- missing temporal-value acceptance independently of empty arrays;
- a canonical normalization that affects safe editor round-trip;
- finite enumeration values;
- numeric bounds and integer requirements; and
- cross-property constraints.

Recommended semantic kinds include:

- `text`, `logical`, `onOff`, `enum`, and `number`;
- `numericArray`, `color`, and `stringList`;
- `filePath`, `url`, `dateTime`, and `tabularData`;
- `callback`, `componentReference`, and `graphicsObject`; and
- `arbitraryData` and `opaque` when no narrower safe contract is justified.

`documentedDefault` does not prove that a property accepts every value of the
same class, and an empty documented default does not by itself prove that the
property accepts an empty value. Record `allowsEmpty` independently.

For datetime contracts, record `allowsNaT` independently. A scalar `NaT` is a
missing datetime value, not an empty array. Use `fixedLength` only with a
`fixedLengthVector` shape, and record `orientation` when the documentation
requires a row or column vector. Use `normalization` only for a stable behavior
that an editor must preserve, such as a date picker discarding time information
or MATLAB storing heading input as a column vector.

For an `enum` whose documentation establishes the complete finite choice set,
record its normalized, unquoted values in `valueContract.values`. Include the
documented default when it is one of the choices. Do not synthesize a partial
list from examples or prose: omit `values` until the complete set is known.

### Cross-property constraints

Place each constraint only on the dependent property and name the dependency
target explicitly. For example, `ItemsData` depends on `Items`:

```json
{
  "path": "ItemsData",
  "valueContract": {
    "kind": "arbitraryData",
    "constraints": [
      {
        "kind": "sameLengthAs",
        "property": "Items"
      }
    ]
  }
}
```

Do not add a reciprocal `Items` to `ItemsData` dependency. The dependency graph
must be acyclic. Schema validation must reject missing targets, self-reference,
and direct or indirect cycles.

Other directional constraint kinds may include `memberOf`, `withinLimitsOf`,
`sameShapeAs`, and `pairedWith`. Add a new symbolic constraint kind only when
its validation semantics are defined in allowlisted MATLAB code.

Intrinsic constraints such as `strictlyIncreasing` and `sortedAscending` do not
name another property. Keep them in the same constraint list, but do not add an
empty `property` field merely to satisfy the cross-property shape.

## Parent-dependent surface

Represent parent dependency as changes to the effective property surface, not
as a boolean attached indiscriminately to every property.

- `intrinsic`: the concrete variant owns the property independently of its
  direct parent.
- `contributed`: a parent context adds the property to the effective surface.
- `suppressed`: a parent context removes an otherwise intrinsic property from
  the effective editable surface.
- `constrained`: the property remains present but the parent context changes a
  documented constraint or interpretation.

The initial known rules are:

- an absolute parent contributes or exposes `Position`;
- a direct `uigridlayout` parent contributes `Layout.Row` and `Layout.Column`
  and suppresses `Position`; and
- structural parents expose neither ordinary absolute geometry nor grid child
  placement unless an explicit rule says otherwise.

Keep contributed definitions in the parent-context rule data. Do not copy
`Layout.Row` and `Layout.Column` into every child variant. A property such as
`Parent` describes a structural reference but is not, for that reason alone, a
parent-dependent property; hierarchy editing owns that relationship.

## Display effect and Safe Preview refresh

Record display effect as one boolean:

- `affectsDisplay: true` when changing the value can alter visible content,
  appearance, geometry, visibility, displayed data, or interaction feedback;
- `affectsDisplay: false` when changing the value cannot alter what Safe Preview
  is intended to show.

Immediate and conditional effects are intentionally combined. Properties such
as `Tooltip` and `Enable` are display-affecting even though their full effect is
observed only during interaction. Conservatively choose `true` when an effect is
plausible but cannot yet be excluded; record uncertainty in audit notes.

Display effect is independent of Preview applicability. Record a separate
Preview policy:

- `apply`: assign the committed value directly to the Preview object;
- `adapt`: apply it through a defined Preview transformation, such as coordinate
  scaling;
- `skip`: preserve and possibly edit the property, but do not apply it to Safe
  Preview; or
- `notRendered`: the component variant itself has no Safe Preview object.

The editor should refresh Safe Preview after a property commit when
`affectsDisplay` is true and the effective Preview policy is `apply` or `adapt`.
Structural operations that rebuild hierarchy or geometry trigger refresh through
their own model operation regardless of this property flag. A `skip` property
does not trigger a refresh merely because it would affect a real application.

Callbacks, arbitrary expressions, unresolved handle references, and unsafe
external content always use `skip`. Read-only or hierarchy-managed properties
are not assigned as ordinary Preview properties. A Preview policy must be
consumed explicitly by the renderer; editability alone is never sufficient
authorization.

## Editor requirement

For an editable property, record the semantic editor kind required to edit its
value contract. The editor kind describes product intent, not whether an adapter
has already been implemented.

Do not store `supportStatus`, implementation dates, test status, or adapter
availability in component property data. If implementation coverage needs to be
tracked, create a separate editor capability ledger keyed by editor kind. The
runtime promotion process may then verify that every editable property refers to
an allowlisted, implemented editor and validator.

Known editor requirements include `text`, `logical`, `onOff`, `enum`, `number`,
`numericVector`, `color`, and `stringList`. Likely specialized requirements
include multiline text, numeric matrices, ranges, dates, table data, asset
paths, URLs, component references, and coupled editors for related properties.

A generic MATLAB-literal editor is not the default for a known value contract.
Use it only when the accepted grammar is deliberately bounded and a dedicated
validator exists.

## Initial disposition

Assign one product disposition to every documented candidate property:

- `editable`: intended to be editable in the property inspector;
- `readOnly`: intentionally visible in the inspector but not editable; or
- `omitted`: intentionally absent from the property inspector.

Disposition expresses the intended product surface and must not change merely
because an editor adapter has not yet been implemented. Track that implementation
gap outside component property data.

Every `readOnly` or `omitted` decision requires one or more stable reason codes.
Recommended reasons include:

- `documentedReadOnly` and `runtimeSetRestricted`;
- `hierarchyManaged` and `callbackManaged`;
- `callbackExecutable` and `handleReference`;
- `arbitraryData` and `externalResource`;
- `lifecycleInternal` and `lowDesignTimeValue`; and
- `unsafeToEvaluate` and `sourceOnly`.

`omitted` affects only inspector presentation. The parser and round-trip
generator must continue preserving supported assignments and unknown source.

Typical initial decisions are:

| Property | Display | Preview | Editor requirement | Disposition |
| --- | --- | --- | --- | --- |
| `Text` | true | `apply` | text or string-list | editable |
| `Visible` | true | `apply` | on/off | editable |
| `FontColor` | true | `apply` | color | editable |
| `Position` | true | `adapt` | numeric vector | editable, effective only for absolute context |
| `Icon` | true | `skip` until asset policy is approved | asset | editable |
| `ContextMenu` | true | `skip` until reference mapping exists | component reference | editable |
| callback functions | false | `skip` | none in the property inspector | omitted: `callbackManaged`, `callbackExecutable` |
| `Parent` | false | `skip` | none in the property inspector | omitted: `hierarchyManaged` |
| `UserData` | false | `skip` | none | omitted: `arbitraryData`, `sourceOnly` |
| `Type`, `BeingDeleted` | false | `skip` | none | omitted: `lifecycleInternal` |

## Property audit procedure

Audit each concrete variant in the following order:

1. Re-fetch its release-fixed factory and property pages.
2. Verify categories, property order, defaults, accepted values, and read-only
   prose from the complete property section.
3. Batch-probe one runtime fixture for default values and public metadata.
4. Normalize the value contract, including empty-value and cross-property rules.
5. Confirm that variant applicability follows from the containing variant file.
6. Classify intrinsic and parent-context contributions, suppressions, and
   constraints.
7. Decide `affectsDisplay` conservatively.
8. Assign `apply`, `adapt`, `skip`, or `notRendered` independently.
9. Name the required editor and validator semantics without recording their
   implementation status.
10. Assign `editable`, `readOnly`, or `omitted`, including reason codes where
    required.
11. Review shared properties across variants for factual parity without erasing
    legitimate variant differences.
12. Validate the JSON schema, dependency graph, source URLs, runtime probe
    cleanup, and deterministic output before committing the release ledger.

## Runtime promotion gate

Development audit data may describe desired editors or validators that have not
yet shipped. A property may enter the runtime component catalog as editable only
when all of the following are true:

- its value contract is supported by the source literal parser and encoder;
- its editor and validator identifiers resolve through allowlisted code;
- cross-property and parent-context constraints are enforced;
- the model, history, and generators preserve the value without evaluation;
- the renderer honors its Preview policy; and
- focused tests cover valid, empty, invalid, reset, undo/redo, source round-trip,
  and Preview behavior as applicable.

Properties that do not pass the promotion gate remain represented in the
development audit. Their product disposition is not rewritten to conceal an
implementation gap.
