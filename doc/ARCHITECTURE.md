# yamada Architecture

This document is a developer reference for the architecture implemented in the current `yamada` source tree. It describes stable responsibilities, data flow, and extension boundaries; it is not a delivery plan. See the [product specification](../SPECIFICATION.md) for supported public behavior and the [roadmap](../ROADMAP.md) for unfinished work.

## Architectural Principles

- Ordinary MATLAB `.m` class files are the persistent source of truth. The project does not read or write the private `.mlapp` format.
- New and opened applications converge on the same `DocumentModel`, registry, validation, Inspector, Preview, and generation pipeline.
- Opening a source file is a static operation. The input class, its constructor, callbacks, helper methods, and arbitrary expressions are never executed.
- Preview handles, Inspector controls, hierarchy nodes, and HTML overlay state are disposable views. Only model state is eligible for source generation.
- Existing source is changed through owned source spans. Unsupported or ambiguous source is preserved and can block an unsafe edit or save.
- Component and property capabilities are declarative JSON data. Executable behavior is selected only through fixed MATLAB allowlists.

## System Map

```text
New App ──> NewAppFactory ───────────────┐
                                         v
Open App ─> AppSourceParser ───────> DocumentModel
                                         │
                    ┌────────────────────┼────────────────────┐
                    v                    v                    v
          ComponentRegistry       ModelValidator        Editor views
          + R2024a catalog   + PropertyBatchValidator   hierarchy/Inspector
                    │                    │               Preview/diagnostics
                    └────────────────────┼────────────────────┘
                                         v
                              RoundTripGenerator
                                ├─ NewAppGenerator
                                └─ source-span edits
                                         │
                                         v
                                  diff and save
```

The main application class, [`yamada.m`](../yamada.m), coordinates these layers. Parsing, model mutation, validation, rendering, and generation remain separate so none of them must infer document state from live UI handles.

Save, Save As, New, Open, and editor close pass through the injected [`DocumentLifecycleService`](../+macd/+ui/DocumentLifecycleService.m). Its native implementation uses MATLAB dialogs and binary UTF-8 output; tests replace its dialog, existence, and write callbacks to cover cancellation and write failures. Only a successful write updates the file path, generated snapshot, and model save checkpoint. The editor title is derived from the document identity and `IsDirty`.

## Package Responsibilities

| Path | Responsibility |
| --- | --- |
| [`yamada.m`](../yamada.m) | Application shell, commands, selection, view synchronization, and save coordination |
| [`+macd/+model`](../+macd/+model) | Document instance state, catalog value objects, property transactions, and undo/redo history |
| [`+macd/+catalog`](../+macd/+catalog) | Strict JSON loading and allowlisted behavior-identifier validation |
| [`+macd/+source`](../+macd/+source) | Lexical scanning, conservative parsing, literal encoding, new-source generation, and localized round trips |
| [`+macd/+validation`](../+macd/+validation) | Document invariants and typed candidate-property validation |
| [`+macd/+ui`](../+macd/+ui) | Safe Preview and Inspector presentation/adapters |
| [`resources/component-catalog/R2024a`](../resources/component-catalog/R2024a) | Runtime component, property, grouping, ordering, context, and Inspector-row data |
| [`resources/EditorInteractionOverlay.html`](../resources/EditorInteractionOverlay.html) | Transparent HTML/SVG pointer and selection layer for the canvas |
| [`dev/component-data`](../dev/component-data) | Audited source data, design artifacts, and reproducible catalog-generation scripts |
| [`tests`](../tests) | Unit tests and preserved handle-class input fixtures |

## Callback Management

HierarchyContextMenu owns one shared native menu and a transient context target. The hit node comes from ContextMenuOpeningFcn.InteractionInformation.Node; it does not modify the editor's SelectedComponentId. Dispatch checks document identity and component existence again, and hierarchy rebuilds reset the transient target.

CallbackManagerDialog owns only its modal figure, scrollable rows, explanations, and injected state/action/validity functions. It displays immutable CallbackState results from CallbackSourceAnalyzer. The effective catalog valueSchema.kind identifies callbacks without introducing special Inspector property rows.

Callback event argument contracts originate in concrete development-ledger properties and are promoted as `metadata.callbackSignature.eventArgument` containing `className` and `shape`; source evidence stays in the ledger. `PropertyDefinition.CallbackSignature` is a validated immutable data value. An empty class name emits an untyped event, without a runtime audit-status flag or a universal event.EventData assumption. New stubs use the effective variant/parent definition; existing methods remain untouched. Type names are checked as identifiers and never evaluated. Typed callback publication and Undo/Redo use the maintained source patch/index path, not AppSourceParser.parseText.

DocumentModel.applyCallbackAction prepares typed immutable CallbackEdit records against CurrentText inside the command. A successful command publishes the exact resulting source and current bindings, clears its preparation records, and stores forward/inverse source patches with history. Original binding and method ownership remains available for Delete/Add, Undo/Redo and stale-source rejection. Broader generation/parsing proof remains inside the command when the local literal transaction cannot establish its scope.

NewAppGenerator emits canonical bindings and English-documented stubs. CallbackSourceEdits supplies original-offset replacements to RoundTripGenerator, which combines common insertion anchors and rejects overlapping source claims. The original input is never run; preserved expressions do not reach Safe Preview. Every accepted command advances CurrentText and source positions together, so later commands do not replay pending changes from the opened snapshot. Reopening reparses the saved file and creates fresh ownership spans. Source reload uses the same replacement boundary: the shell first resolves dirty/external-change policy through DocumentLifecycleService, then captures fresh bytes, parses without execution and verifies an unchanged snapshot before swapping documents. A separate saved-source snapshot tracks the last successful Open/Reload/Save; OriginalText remains the opened-file comparison image, while CurrentText owns current editing positions. The reload target remains the original file even if conflict handling saves local changes to a different file. All three entry points share one reentrancy guard.

Window activation checks the current file text against the last successful Open/Reload/Save source snapshot (the original loaded text until the first Save). A difference offers Reload/Cancel before entering the existing reload policy; local saves do not trigger this prompt. Read failures leave the document untouched, and a separate activation guard prevents dialog-induced reentry. MATLAB R2024a exposes activation through the internal `FigureActivated` event rather than a public focus callback; this compatibility boundary is confined to the shell listener. Cancel retains edits and remembers the source text captured before the prompt. Later activation suppresses the same dismissed text but prompts for a different external revision. Successful New/Open/Reload/Save clears this dismissal; failed operations retain it. Manual Reload ignores dismissal, and a failed Reload is not recorded as a dismissal.

## Shared Document Model

[`DocumentModel`](../+macd/+model/DocumentModel.m) is the authoritative in-memory state for both new and parsed applications. It owns:

- class name, file path, encoding, and line-ending policy;
- exact original text and the latest generated text;
- the ordered component collection and root component identity;
- diagnostics, unknown source regions, and pending source edits; and
- bounded undo/redo history, including a conservative saved-history checkpoint and public dirty-state flag.

[`ComponentRecord`](../+macd/+model/ComponentRecord.m) represents one component instance. It stores stable identity, MATLAB property name, factory, declared type, creation arguments, parent/child IDs, origin, source spans, and ordered `PropertyEntry` objects. Parent relationships use stable model IDs rather than Preview handles or hierarchy nodes.

[`PropertyEntry`](../+macd/+model/PropertyEntry.m) keeps document state separate from catalog capability state. A supported value is either:

- a parsed or generated literal that the model may edit; or
- a source-backed expression that remains read-only and retains its exact source.

Model mutators implement insertion, subtree deletion and reparenting, Copy/Paste, individual and batch property changes, reset, undo, and redo. A batch is preflighted before mutation and becomes one history entry. Parsed deletion also retains enough intent for undo to restore the source-generation state.

Local property preflight may reuse either its private checkpoint or an already cached `combined` configuration that passed complete generation, parsing, and validation for the exact current semantic inputs and catalog revision. The shared plan is materialized as an independent document before mutation; partial insertion plans do not substitute for a complete proof. The live file path is restored for relative resource interpretation. A complete matching configuration proves owned existing occurrences across components and paths, so switching the selected component or property alone does not require another whole-source trial.

Eligibility comes from the catalog and literal contract rather than component or property allowlists. Independent editable settings need reviewed independence, no ordering/effect dependencies or additional cross-property constraints, a known source-owned literal occurrence, valid batch values, and exact literal encode/decode equality. Numeric `Value` settings use the modeled `numericValue` policy and the complete known constraint transaction for every registered implementation of that policy. Layout-changing settings on components with children retain complete source preflight; unresolved effects, missing spans, stale inputs, unsupported representations, and physical line breaks in unproven syntax also retain the full path. A failed private update restores its previous values. Public configurations and older results remain independent, history records remain atomic, and save continues complete generation and verification. Input application classes and callbacks are never executed.


When multiple parsed owners need inserted settings alongside generated components, the insertion planner tentatively chooses their owned placements and emits the complete post-addition source before validating it once. A friend-only method on the value-class `RoundTripGenerator` receives these temporary plans; public generation retains input validation. The planner must reparse the complete result and match every pending literal before retaining a `combined` configuration. A failed joint candidate retains the established per-owner placement search. Deleted or relocated source, callback edits, and rename edits retain their existing proof paths. No partial candidate, live component record, or externally mutable plan substitutes for the complete proof.

A batch that emits and validates the complete post-addition source may retain that exact string in the current evaluation context. Public generation still validates its inputs before reusing this emission; tentative generation cannot take that shortcut. Combined configuration may reuse an independent parsed document only when both its original source and the recorded complete emission equal the newly generated output. Partial placement plans do not authorize either shortcut. Input or catalog changes discard the emission proof rather than inheriting it with ordinary resolver values.

### Property setting history and source placement

[`PropertySetting`](../+macd/+model/PropertySetting.m) is the immutable record of an original setting occurrence or a pending generated setting. Original occurrences retain the literal or unevaluated expression, constructor/assignment syntax, statement/name/value/pair spans, source snapshot identity, initializer ownership, execution sequence, and certainty. Pending settings have no original source spans. `ComponentRecord.getSettings(path)` returns that property's occurrences; `PropertyEntry` owns its current requested value and binding to the target setting, while `CreationArguments` projects factory inputs from that state. Positional arguments and construction styles remain distinct from named property settings.

Source occurrence history is separate from user Undo/Redo. Editing an existing value retains the target setting's identity; repeated edits do not append fictitious source occurrences. Adding a previously unset property creates one pending setting; subsequent edits retain its identity and update the `PropertyEntry`. Earlier source settings remain intact. A final expression or uncertain setting does not expose an earlier literal as the editable value. Initialization sequence follows proven same-class calls rather than file order, and runtime callback writes do not become initial settings. Implicit defaults and setter effects belong to resolved state, not source history.

Existing settings keep their location and form. `RoundTripGenerator` replaces an owned value token; [`FactoryCallEditor`](../+macd/+source/FactoryCallEditor.m) preserves surrounding constructor tokens, comments, and unknown arguments. If an in-place change would fail at an intermediate setter or lose its requested final value, the edit is rejected instead of moving existing settings, converting their form, or adding a compensating assignment.

[`PropertyApplicationPlanner`](../+macd/+model/PropertyApplicationPlanner.m) orders new settings using the catalog's `metadata.application.applyAfter` graph. Inspector presentation order, value constraints, and effect dependencies are separate contracts. The loader rejects invalid graph references and cycles after variant/group/context expansion. All registered factories document name-value construction for their applicable writable properties; the release-specific [constructor syntax review](../dev/component-data/R2024a/CONSTRUCTOR_SYNTAX_REVIEW.json) records that evidence. There is no per-property constructor-support flag. Setter access, product disposition, parent applicability, literal safety, source ownership, and complete candidate validation independently constrain insertion. Constructor arguments are evaluated under their finite application policy rather than assumed to be sequential assignment setters.

[`PropertyInsertionPlanner`](../+macd/+source/PropertyInsertionPlanner.m) finds a proven initialization interval for new settings while holding existing occurrences fixed. New components use post-construction assignments by default. An existing initialization that sets properties only through named constructor arguments may receive additional named arguments only when ownership, writable direct properties, dependencies, and reference availability are proven; positional-only or mixed initialization does not imply that permission. Otherwise the planner inserts assignments after their prerequisites and before relevant modeled downstream setters. Unknown statements delimit intervals. The default interval precedes the next unknown statement; prerequisites may select a later interval, ending at its next unknown statement. Existing code is never moved and unknown-call effects are user-owned. Absence of a syntactically and semantically valid owned slot still rejects insertion. Insertions sharing an offset are combined in stable dependency order.

Generation consumes only the value-only edits of a successful insertion proof through a generator-restricted planner entry point. Exact document inputs and the catalog revision still determine the evaluation context; an absent proof runs the existing placement search and validation. Retrieving cached edits does not materialize an unused parsed document for each owner. Public `PropertyInsertionPlanner.plan` results retain independent mutable documents and component records, including after generation has reused their cached edits. This applies to every eligible owner and setting without factory or property allowlists; partial placement proof does not imply a complete emitted-source proof.

`DocumentModel` owns acceptance of property requests before live mutation. Validation must preserve source ownership, supported intermediate-state rules, and the requested effective result; a valid final value alone cannot hide an earlier invalid assignment or a later setter that overwrites it. Rejected requests leave live values and history unchanged. [`PropertySourcePlan`](../+macd/+source/PropertySourcePlan.m) supplies the source-placement configuration used by effective-state consumers, keeping original setting identities separate from candidate configuration identities. The resolver supplies independent value results; consumers must not expose shared mutable candidate records or mix offsets from different source snapshots.

Post-commit validation distinguishes a complete matching diagnostic proof from a pending bounded scope. With a proven complete baseline and catalog-modeled effects, a newly inserted setting schedules the component and its hierarchy context for validation instead of reevaluating unrelated property states. Catalog selection, placement, and reference policies include the parent subtree when siblings may change. Structural checks remain document-wide. The validator reports checked identities so the document can retain unaffected diagnostics, discard replaced ones, and preserve component ordering. Pending scopes cannot justify another proof until consumed; source, history, external writes, or catalog changes invalidate them. Independent local replacements keep their existing proof reuse. Public generation and saving retain their validation paths, and parsed checkpoints remain private value snapshots rather than shared public model handles.

Parent-before-child creation, deferred component references, and final root visibility remain separate generation responsibilities. Relocation retains all original setting occurrences; copies receive fresh setting IDs and ownership instead of reusing source offsets. Saved output uses the separate `SavedSourceCheckpoint` described below, leaving the original edit basis and Undo/Redo intact. Per-property effect classifications, evidence, and unresolved audit reasons are maintained in the release-specific [application effect review](../dev/component-data/R2024a/APPLICATION_EFFECT_REVIEW.json).

### Subtree editing and clipboard ownership

Destination-grid occupancy reads share immutable coordinate values after one successful hierarchy/value capture for the exact document and catalog inputs. This avoids capturing a nested destination child subtree repeatedly just to read its root placement. The projection retains the original explicit-coordinate validation and does not share native rectangles. If the whole-root capture cannot be proved, the planner uses the previous destination-child capture path so unrelated invalid data or hierarchy cannot introduce a new placement refusal.

Deletion, reparenting, Cut, and Paste share complete-subtree validation, placement planning, detached source preflight, and atomic history. Their responsibilities are split as follows:

| Owner | Responsibility |
| --- | --- |
| [`SubtreeSnapshot`](../+macd/+model/SubtreeSnapshot.m) | Capture independent value data in stable parent-before-child order; reject missing links, cycles, and repeated children |
| [`SubtreePlacementPlanner`](../+macd/+model/SubtreePlacementPlanner.m) | Validate construction style and destination; plan root placement across absolute and Grid parents |
| [`SubtreeReferencePolicy`](../+macd/+model/SubtreeReferencePolicy.m) | Validate the finite set of static component references without evaluation |
| `SubtreeSourceEdits` / `SubtreeReparentSourceEdits` | Remove or relocate owned declarations and initialization statements while preserving other source |
| `DocumentModel` | Preflight the complete candidate and commit records, links, order, placement, and source intentions as one history entry |
| [`ComponentClipboard`](../+macd/+model/ComponentClipboard.m) | Retain a document-scoped snapshot and update it only after successful Copy/Cut preparation |
| `yamada` / Hierarchy / HTML overlay | Resolve explicit command targets, present availability, and refresh selection and disposable views after success |

Preview destination regions describe visible container geometry without precomputing edit eligibility or constructing subtree snapshots. Self and descendant regions are excluded by parent-link traversal. A drop validates only the requested destination through the model transaction, including construction style, editability, managed references, source ownership, and generated-source checks. Rejected drops preserve document and history. Geometry reuse refreshes labels and revisions without querying destination eligibility.

Reparenting preserves IDs; Paste allocates new IDs and unique member names before remapping internal references. Paste is one transaction, not insertion followed by a separate reparent command. Copy uses a `Copy` suffix; Cut preserves original names unless they collide. Undo/Redo restores IDs, document and child order, properties, and source intentions, but does not rewind clipboard contents. Copy leaves document/history unchanged. Cut publishes the snapshot only after deletion succeeds. Paste retains it for repeated use. Successful New/Open/Reload clears the clipboard; failed or canceled document replacement preserves it.

Paste searches from its target toward the nearest catalog-compatible ancestor. Reparenting uses the explicitly chosen destination without substituting an ancestor. `SubtreePlacementPlanner` transforms only the subtree root's parent-dependent placement and preserves internal layouts. Reparenting permits overlapping Grid children and clips the original span to the tracks remaining from the requested drop cell; it neither searches occupancy nor adds tracks implicitly. Paste retains its separate free-cell placement policy. Conversion to absolute placement requires known model geometry or verified Preview measurements fixed in the plan; unresolved source placement is rejected rather than silently discarded.

Reference analysis distinguishes internal references, outgoing external references, and incoming references from outside the subtree. Static `SelectedTab` is limited to a direct child Tab; static `ContextMenu` remains bound to a valid same-document target. Internal copied references map to fresh identities, and external references retain their targets. `SubtreeCopyPlanner` excludes effective catalog callback properties from copied configuration and constructor arguments while retaining original snapshot records, bindings, pending callback edits, and handler bodies. Copy-only value resolution excludes those callback definitions while retaining source-execution guards for construction effects. Copy does not require editable callback ownership and never duplicates handlers. Other unsupported expressions, handle payloads, and unknown effective configuration still block Copy. Callback bindings and unsafe incoming references continue to block Delete/Cut. Reparenting may preserve owned callback source; pending callback edits on a parsed relocation target require Save + Reload Source or Undo before relocation. Arbitrary reference rewriting remains outside this boundary.

The transaction prepares identities, names, parent/child order, placement, references, and owned source edits before mutating the live document. Its detached candidate must not share mutable component handles with that document. Only a successful preflight permits one history record, clipboard publication, and selection/view changes; failure preserves document state, diagnostics, generated source, history, clipboard, and selection. Actual commands revalidate the current document even when availability results were previously computed.

Edit commands, keyboard shortcuts, and Hierarchy context commands use the same dispatch and availability rules. A context target is independent of selection and is invalidated on tree rebuild or document replacement. Preview forwards clipboard keys only outside text editing, popovers, and active gestures; MATLAB checks selection identity and revision. Parent movement is exposed only through Preview drag gestures. The root UIFigure, unsupported construction families, cross-document copying, OS clipboard integration, and multiple selection retain their explicit supported-scope limits in the product specification.

## Component Catalog and Capability Resolution

The development pipeline runs `Assert-ComponentLedgerSchema` from `dev/component-data/ComponentLedger.ps1` before policy application, grouping artifact generation, grouping design, and runtime promotion. It validates every complete concrete document against the release schema before writing outputs. Application graph, source evidence, and grouping parity checks remain separate. Accepted MATLAB classes remain JSON arrays even for a single class; their order has no semantic meaning. Combined official headings supply each named property's description, rather than leaving earlier names blank. Full-schema verification does not establish that a property's setter effects have been audited.

[`ComponentRegistry`](../+macd/+model/ComponentRegistry.m) is the runtime query boundary. `createDefault` loads the packaged R2024a catalog through [`ComponentCatalogLoader`](../+macd/+catalog/ComponentCatalogLoader.m).

The schema-version 2 manifest references:

- concrete component variants;
- reusable property groups;
- category-order profiles;
- declarative Inspector composite-row templates; and
- direct-parent context rules.

`ComponentDefinition` describes one concrete factory variant, including creation arguments, declared MATLAB type, allowed parents, palette metadata, Preview outline shape, and resize constraints. Variant selection prefers an exact creation-argument match, then the most specific prefix, then an unstyled default.

`PropertyDefinition` describes one property capability. It includes the property path, default, editability, category and order, typed value schema, style scope, Preview/reset policies, audit disposition, and symbolic editor and validator IDs. It never stores an instance value.

`ParentContextRule` composes the effective property surface from the selected component and its direct parent. For example, a Grid Layout parent suppresses absolute `Position` and contributes `Layout.Row` and `Layout.Column`. All consumers obtain this effective surface through `ComponentRegistry.getEffectiveProperties`.

Catalog JSON is data, not executable configuration. Loader validation rejects unknown fields, broken references, duplicate ownership, invalid ordering, and unknown behavior identifiers. `PropertyBehaviorRegistry` contains the finite allowlists that bridge symbolic catalog IDs to project-owned MATLAB code.

## New and Open Workflows

### New documents

`NewAppFactory.createEmpty` creates a `DocumentModel` with one generated root `uifigure`. Subsequent palette insertion asks the registry for the selected variant and allowed parent, seeds required creation arguments and layout defaults, then records the insertion in model history.

### Opened documents

`AppSourceParser.parseFile` reads source as bytes, requires valid UTF-8, detects the existing line-ending convention, and retains the exact decoded source. `MatlabLexicalScanner` first identifies safe statement boundaries around strings, comments, continuations, and balanced delimiters. The parser then recognizes the supported handle-class subset:

- class inheritance;
- component property declarations;
- direct registered factory calls;
- parent relationships; and
- direct component property assignments with supported literals.

The supported app directly inherits from `handle` and owns one `uifigure`; zero or multiple statically recognized roots produce diagnostics. AppBase input has no compatibility or automatic-conversion path. Other UI components are descendants of that figure as a user precondition; there is no dedicated descendant-membership validation. Existing model consistency and source-ownership checks still apply. Constructor tracing follows ordinary same-class calls without inspecting external base classes or executing factories. A constructor try/catch that only deletes the owner and rethrows the caught exception is traced on its successful path; other guarded initialization remains uncertain.

`MatlabLiteralParser` interprets only the conservative literal subset. Callback values, arbitrary expressions, unsupported statements, and uncertain regions are retained as source-backed data or `UnknownSourceRegion` records. Parsing never uses `eval` and never constructs the opened application.

## Editing and View Synchronization

The editor uses stable component IDs for hierarchy selection and Preview mapping. After an accepted model command, `yamada` coordinates updates to the affected hierarchy, palette, diagnostics, Safe Preview, Inspector, and command state. View updates follow the accepted model change rather than reconstructing document state from UI handles.

Insertion eligibility is determined from catalog metadata and the selected or nearest eligible parent. Deletion is explicit and model-validated. Absolute canvas gestures keep a temporary candidate rectangle in editor state and commit one `Position` change on pointer release. A selected Grid Layout child instead uses the active-grid overlay: its cell-snapped draft is owned by HTML and a release sends a declarative move or span candidate for MATLAB-side validation. `GridChildPlacementPlanner` accepts only an editable literal placement of an immediate child, rejects new overlap and out-of-range targets, and returns one change set for `DocumentModel.applyGridLayoutEdit`.

The model, not the Preview, owns source-coordinate geometry. The editor converts between the fitted Preview scale and source pixels and applies the catalog's component/style-specific resize constraint before committing a candidate.

## Property Inspector

Native setter access and product disposition are separate catalog facts. The review applicator can retain passed, release-specific `setterAccess` evidence without completing a property effect review. It validates all observations before writing any ledger, rejects duplicate targets and documented read-only conflicts, and carries runtime access through grouping and promotion. Detailed `runtimeObservations` remain development evidence. Checkbox Tree Position is publicly writable; InnerPosition is also writable in source but remains omitted from the Inspector. OuterPosition has a restricted setter.

`positionAlias` and `squarePositionAlias` select finite getter effects for 14 reviewed simple-control variants. `PositionAliasPolicy` propagates a public setter's value and setting identity across the shared getters without changing their explicit inputs. Lamp uses the smaller finite nonnegative size component for both dimensions. Unknown aliases invalidate the group; a later certain literal restores it. Grid-managed aliases remain unknown with a layout reason. This family does not describe decorated sliders, knobs, containers, or axes.

Preview filters skipped named arguments before invoking native factories and projects known alias geometry once through Position. Unknown geometry produces a diagnostic instead of silently treating an earlier value as the effective one. Named ImageSource values use the existing asset adapter after construction. Original constructor arguments and setting ownership stay unchanged.

`gridTracks` selects the finite `GridLayoutStatePolicy`. The parser records a global initialization sequence and certainty for each creation, including calls without named properties. The policy merges these events with explicit track and direct-child placement writes. It retains requested track baselines, pads occupied rows/columns with `1x`, and releases implicit padding after children move out. Default placement follows the last occupied cell in row-major order. Positional grid size precedes named track overrides. Unknown placement affects the corresponding track state; later certain literals can restore it. Pixel geometry and `fit` measurements are outside this policy. `PropertyState.EffectPolicy` scopes normalized track comparisons to this audited family; a table's unrelated `ColumnWidth` retains its own comparison semantics.

The shared resolver exposes final tracks and implicit placements without adding source occurrences. Preview projects known values, and copy configuration freezes affected values for independent generation and verification. Grid overlay track data and track actions consume the same effective values. Pending changes must retain their actual initialization placement and account for effects on related grid members; independent property writes do not automatically become logical track or placement changes. Native `fit` geometry remains a separate concern even for logically independent font or text settings. Grid batches verify requested tracks and affected placements before committing one history record, so an occupied-track shrink cannot silently change the requested size. Single-property history wraps cell values as scalar record fields so track lists remain one Undo/Redo operation.

Copies keep the full original snapshot but collapse its effective configuration to one Position. Placement uses that frozen result, and copy verification checks placement changes, including offsets, rather than excluding them. Grid copy configuration omits ignored aliases and uses layout coordinates or supplied measured geometry when moving to an absolute parent. Source relocation continues to retain the original alias statements. It reparses generated output and checks each requested placement before committing; an earlier Position overwritten by a preserved later alias cannot silently determine a different destination. Native-verified zero sizes remain valid for these alias families in both model validation and placement. Other families retain their existing size constraints.

The Inspector begins with `DocumentModel.getEffectivePropertyStates`, which joins catalog definitions with explicit instance entries. Source-only assignments that are outside the effective catalog surface are appended as read-only rows instead of being dropped.

The application contract distinguishes `independent`, `modeled`, `unsupported`, and `unknown` effect status, separately from documented constructor syntax and product editability. Legacy catalogs default to unknown. The exact per-property review artifact passes through schema validation, grouping, promotion, and loader; `effectPolicy: none` alone never grants independence. An unknown review status does not disable editing or invalidate other states for certain literal writes. The resolver projects their stored inputs and catalog defaults while retaining `PropertyState.EffectStatus == "unknown"`; `IsKnown` is a finite-model result, not proof of reviewed native independence. Untouched Inspector values and related editor transactions may also use the existing owned default fixture for unknown properties, without materializing source settings. Product omissions/read-only access, value validation, and source ownership remain separate gates. Unsupported writes and source-uncertain unknown writes invalidate the declared paths, or all same-component states when the scope is unbounded. Unexpanded initialization, nonempty constructor CreateFcn, uncataloged setters, and unsupported Parent/Children writes invalidate document-level guarantees while retaining original source. Source hierarchy writes can affect destination siblings outside the constructor ownership graph, so a local unknown state is insufficient. Later coupled setters do not erase identified unsupported or source-uncertain upstream effects. A later reviewed independent setter can restore its own stored input. Unknown explicit calls are bounded even without an app argument; only allowlisted data constructors with inert literal arguments bypass the execution barrier.

`ButtonSelectionPolicy` replays parent SelectedObject references, sibling creation, and Value events. Source occurrences remain intact. New/copy generators defer selection assignments until siblings exist; the insertion planner admits proven same-group creation boundaries. Copy materializes child values and omits the source-only parent handle. Preview selects the resolved child after rendering all siblings. Mixed radio/toggle families and unresolved handles are not generalized.

`PositionGeometry` owns finite rectangle normalization, linked-field edits, fixed slider thickness, and constrained resize anchors. The `switchPosition` and `semicircularPosition` policies use Orientation-aware ratios and replay native size exchange in actual setter order, including constructor arguments. The `linearPosition` policy retains independent dimensions while replaying Orientation size exchange; its runtime resize capability is `free`. These policies do not calculate decoration-dependent aliases. Position request comparison tolerates only floating-point roundoff; it does not accept an unrelated normalized size in place of a request.

`PositionEditor` is one panel inside the existing Inspector row, containing four vertically stacked `NumericEditField` controls with left-hand X/Y/W/H headings and two vertically aligned link labels. It derives constraints from the property policy and the related Orientation state, sets fixed-field tooltips explicitly, updates linked sizes locally, and forwards one complete numeric Position vector. Factory binding, transient draft capture, and stale-callback guards remain owned by the existing Inspector infrastructure. Preview rendering and both pointer-resize paths consume the same geometry rules; vertical sliders publish fixed-width handle affordances. Existing source occurrences are still edited at their original value spans, and copied configurations use the resolved native rectangle.

`AncestorGeometryPolicy` invalidates child geometry after later ancestor position writes unless prior AutoResizeChildren is explicitly off. It does not calculate native reflow. Stored position, slider thickness, and selected square control rules keep decoration-dependent aliases unknown. Pending ancestor changes use the same complete emitted candidate as other cross-component policies.

New subtree creation shares an execution-order anchor with grid event replay. The anchor follows proven ancestor geometry initialization. A later ancestor setter in a different unresolved insertion context causes refusal; existing source settings are not moved to accommodate the new component.

`PropertyStateResolver` keeps original explicit values, replacement requests, and effective values separate. The allowlisted `valueMode` policy covers individually reviewed axes font, tick, limit, and map value/mode pairs. An explicit value selects manual mode; an automatic or unevaluated mode makes computed output unknown. The canonical application graph restores a requested final mode after the value, while parsed settings retain their original order and token ownership. Copy retains audited automatic-mode inputs and their mode without claiming a computed getter value. This rule is not generalized to color modes, coupled aspect ratios, grid-width followers, or unreviewed geographic behavior.

`modeFlag` separately models reviewed color/alpha setters that select manual mode while preserving the stored getter when auto is restored. `axisWidth` resolves LineWidth -> GridLineWidth -> MinorGridLineWidth using audited defaults, automatic followers, and manual holds. Constructor arguments set explicit values and flags before follower synchronization; assignments update followers at each setter. Held defaults carry their determining mode occurrence without becoming explicit source writes. The insertion planner preserves existing manual hold points before new upstream assignments and validated constructor additions.

Copy omits implicit automatic width setters that would otherwise select manual mode, and checks the derived getters after reparsing. A manually held constructor default is materialized in the copied configuration before emitting assignments. The source snapshot retains its original history and getter inputs.

[`DefaultValueProvider`](../+macd/+ui/+inspector/DefaultValueProvider.m) resolves implicit values without changing the document. It first uses catalog or MATLAB class metadata and then, when required, constructs one hidden, editor-owned fixture for the allowlisted factory and direct-parent context. The result is cached by MATLAB release and catalog surface. This controlled probe never constructs the application being edited.

[`InspectorSurfaceBuilder`](../+macd/+ui/+inspector/InspectorSurfaceBuilder.m) projects atomic property states into deterministic singleton or declarative composite rows. Composite rows change presentation only; underlying property contracts remain independent.

`RowHeight` and `ColumnWidth` have the `gridTrackList` editor capability, which marks them for the canvas overlay rather than a native Inspector row. The normal Grid Layout Inspector retains `RowSpacing`, `ColumnSpacing`, `Padding`, `BackgroundColor`, `Visible`, and `Scrollable`; the child Inspector retains `Layout.Row` and `Layout.Column` as the exact-value fallback.

[`PropertyEditorFactory`](../+macd/+ui/+inspector/PropertyEditorFactory.m) maps an allowlisted editor ID to a native control or project-owned dialog. Editors submit one or more changes through `PropertyTransaction`. The editor reconciles dependent values such as `Items`/`ItemsData`/`Value`, validates the candidate transaction with `PropertyBatchValidator`, and submits it to `DocumentModel.setPropertyBatch` for model acceptance. A batch that changes values produces one history record and updates the affected views; a rejected request does not partially commit.

## Safe Preview and Canvas Overlay

[`PreviewRenderer`](../+macd/+ui/PreviewRenderer.m) projects model state into disposable editor-owned controls. It creates only registered factories, applies editable literal values permitted by each `PreviewPolicy`, skips source expressions and callbacks, and reports individual construction or assignment failures as non-executing diagnostics. Reusing a control does not make its native state authoritative for source generation. Native menu and toolbar families are currently not rendered on the Preview canvas.

The outer Preview panel keeps a light native heading; its child is a dark-gray scroll host. The renderer adds a padded dark content panel so all four edges of the figure remain distinct from the scroll bars at their limits. Two fixed dark dividers mark the viewport boundary next to visible native scroll tracks while the canvas extends beyond the viewport. The renderer places an unscaled canvas at the root `UIFigure.Position(3:4)` client-area size, uses the figure's supported `Color`. The scroll content encompasses the figure and visible component bounds, with room for resize handles. The transparent HTML overlay is a sibling of the figure frame in that content, so component outlines remain selectable outside a shrunken figure. The canvas itself continues to clip native controls at the actual UIFigure boundary. The overlay's `surfaceBounds` describes its extent in canvas pixels; SVG viewBox and HTML layer offsets preserve those coordinates when the editing area extends beyond the canvas. All pointer events, hit targets, and Grid Layout measurements use canvas-local pixels. Editor window resizing repositions the fixed-size canvas without changing the document. The frame gives the canvas a one-pixel border on each side. Eight root resize handles remain available when the root has an editable literal Position, including an empty document. West and south drags also update the screen origin to anchor the opposite edge; source-backed positions remain noneditable. A disposable HTML guide is placed in the scroll content during a root drag, so its dashed proposed bounds can extend beyond the current canvas. The guide disappears when the gesture ends; the overlay shows no size label.

The renderer returns a map from stable component IDs to disposable Preview handles. `yamada` uses this map to build the transparent [`EditorInteractionOverlay.html`](../resources/EditorInteractionOverlay.html) `uihtml` layer. MATLAB sends source-derived component outlines, selection state, and Tab Group information to the overlay. For the nearest selected Grid Layout, `GridLayoutOverlayDataBuilder` also publishes versioned public Preview geometry, track headers, immediate-child occupancy, and editability. The HTML/SVG layer owns pointer capture, outlines, resize handles, tab-selection hit targets, and temporary grid drafts, then sends declarative pointer or grid actions back to MATLAB. It never mutates the document directly. MATLAB rejects actions with a stale revision, a mismatched active grid, unsupported source ownership, or an invalid final placement.

Tab content geometry is published only after observed layout values stabilize. Inactive-tab child outlines are omitted, and the active tab selection remains disposable Preview state unless a supported model property is explicitly edited.

### Grid Layout Visual Editor

The editor follows one model-to-canvas-to-model flow. `DocumentModel` holds track values and child placements. `PreviewRenderer` draws disposable MATLAB controls from that model. `GridLayoutOverlayDataBuilder` combines model values with the controls' realized geometry into a versioned payload. The HTML overlay draws the grid UI and sends a proposed action to `yamada`, which validates it and commits one model change before rebuilding the Preview. The Inspector edits ordinary component properties alongside this canvas workflow. Preview and HTML are disposable views of the document state.

#### Selection and editing context

`SelectedComponentId` drives the hierarchy and Inspector; the nearest selected Grid Layout (`ActiveGridId`) drives track controls. Selection targets for visible grid-managed children are published independently of the active grid. Otherwise an opened document, which initially selects `UIFigure`, could not select a grid child from the canvas. Selecting a nested Grid Layout enters that grid's immediate tracks and children. Transparent targets are painted from outer to inner grids in one background layer so descendants win hit testing without covering active child controls or track settings. Selecting a child changes view state only.

The editing surface reserves space around the active grid for its row and column settings buttons. Headers and their popovers use the editing surface bounds, including the dark area outside UIFigure, so full-figure grids and stranded grids retain their settings controls. The buttons sit outside the grid edges, distinct from the figure resize handles.

#### Track and child edits

The Inspector remains focused on the selected component. `RowHeight` and `ColumnWidth` use the compact canvas settings controls; spacing and padding stay in the ordinary Inspector. Track editing uses explicit Fit, Fixed, and Flexible modes instead of dragging a boundary, because a pixel drag would silently convert a fit or weighted track to a fixed size. The HTML popover owns only the draft. MATLAB validates the submitted action and `DocumentModel.applyGridLayoutEdit` commits a structural edit with all affected child placements as one Undo step. Expression-backed tracks or placements remain locked when source ownership cannot be proved.

Inserting or deleting a track remaps explicit immediate-child placements in the same transaction. Deleting a track occupied by a single-track child is rejected rather than moving or deleting that child implicitly. Existing overlaps are preserved, while a canvas drop that would create a new overlap is rejected; exact Inspector placement remains available for intentional overlap.

#### Geometry and interaction

R2024a exposes the grid and rendered controls' public geometry, but not the realized rectangle of every track. `GridLayoutOverlayDataBuilder` reconstructs track boundaries from literals, spacing, and settled Safe Preview measurements. For `fit` measurements it prefers a direct child's `OuterPosition`, which can include decorations omitted from its control-body `Position`; selection hit targets still use the visible child's ordinary bounds. This distinction matters for controls such as Range Slider, whose narrow body understates the height required by its row. `OuterPosition` is still not a grid-cell measurement, so this reconstruction is not guaranteed to align every separator exactly. When geometry is ambiguous, the builder withholds geometry-dependent editing instead of publishing a plausible but incorrect boundary. Adding invisible nested `uigridlayout` controls as cell probes was tested and rejected: in a populated R2024a grid they changed the native layout and did not reliably occupy the requested cell.

An unoccupied `fit` track can have zero extent without losing its logical index. The overlay keeps its settings control addressable and supplies a temporary drop band during a child move; that band changes neither the Preview grid nor source. Span-handle drags begin from the handle even when it overlaps spacing or padding. The moving edge snaps at the midpoint between valid track edges in either direction, independently of the perpendicular axis.

#### Preview updates and Tab visibility

`PreviewRenderer.synchronize` handles ordinary property requests across all catalog variants without component or property allowlists. `PreviewUpdatePlanner` derives a local dependency closure from the catalog and resolved implicit effects, compares public native values only in that closure, and orders final writes. Invalidation membership and setter ordering are distinct graphs. Range and selection policies supply valid intermediate states for disjoint old/new domains; automatic modes, group selection, grid-child placement, and final child geometry reuse existing model resolution. Figure-root size/color use the existing panel-based Preview surface adapter; figure window chrome is not represented by that surface.

Callback Add/Delete and their history operations use a source-only update path. Safe Preview never installs callback bindings. `PreviewRenderer.acknowledgeCallbackChanges` accepts a new input version only when every visual input and the registry version remain identical; CallbackEdits is the sole excluded source-intent field. The editor refreshes Inspector/diagnostics/save/history/availability and existing overlay command revisions without reconstructing controls, measuring rectangles, solving boundaries, or rerendering HTML regions. Simultaneous visual/source/structure changes cannot be hidden by that acknowledgement.

Validated component-member renames use the same source-only view refresh. `PreviewRenderer.acknowledgeRenameChanges` compares complete input snapshots while allowing only component record names and RenameEdits to differ; identities, order, hierarchy, properties, source text, and the catalog revision must still match. Visual property settings remain in the strict comparison. The shell updates hierarchy labels, the root preview panel title, and existing drop-target names without replacing native controls or geometry. Rename Undo/Redo replays the primary identifier patches and projects existing positions before refreshing these views. Unrelated changes retain the full refresh fallback.


Preview-skipped settings do not trigger native assignments. Asset adaptation uses the same catalog policy in full and incremental rendering; clearing a local image uses the native empty text value. R2024a UIFigure-incompatible setters such as panel ShadowColor remain source-only with ledger observations. Unresolved local effects and native assignment failures reconstruct the affected ownership subtree through the established safe renderer. Grid/ButtonGroup dependencies enlarge that subtree as needed. Reconstruction preserves unchanged sibling handles, native stacking/tab order, and transient tab selection; failure to restore a native child order escalates reconstruction to its enclosing scope. Unrelated source or hierarchy changes, untracked values, and registry changes retain full reconstruction. These boundaries preserve the accepted model and do not introduce a reset UI or a second document-edit trial.

Heterogeneous atomic updates carry exact component/property pairs in `RefreshRequest.forChanges`; another component's property with the same name cannot be hidden by a union of paths. Inspector, visual grid editing, and completed position gestures use the same property update path. New performance work follows the plan's capability-wide coverage rule: a minimal initial test does not justify retaining component/property allowlists after that initial stage.

The development ledger owns two geometry capabilities per component property: `gridGeometryImpact` (`none`, `fit`, `required`) and `absoluteGeometryImpact` (boolean). Group equality, generated runtime entries, and contributed parent-context properties preserve both fields. `geometryEvidence` remains development-only and distinguishes documented facts, inference, and runtime observations. Missing metadata defaults to full refresh. `affectsDisplay` and initialization independence do not prove geometry stability. The development review script classifies common mechanisms conservatively; unknown properties keep full refresh.

`RefreshRequest.affectsGeometry` resolves these capabilities through the effective catalog and actual placement. Fit-dependent properties inspect applied row/column settings of native grid ancestors without reading pixel rectangles. Safe incremental setters with unchanged geometry reuse measured component bounds, grid boundaries, selection frames, and pointer regions. Reparent availability and operation revisions still advance; HTML retains regions and updates existing event revisions without rerendering. Pending native layout, unavailable measurements, selection or structural changes, and full Preview reconstruction retain the normal measurement path. Existing setter reuse eligibility is separate from geometry classification.

Preview geometry may change after an initial Open or Tab switch. The editor publishes an initial overlay and schedules a bounded refresh after visible grid and child rectangles stabilize, including when no grid is selected. On a Tab switch it immediately removes controls belonging to the hidden Tab, then refreshes settled geometry. Visibility must be checked through every enclosing Tab Group; a selected grid on a hidden Tab does not remain active on the canvas.

Overlay publication reserves one revision before native layout can reenter the update. Every payload section uses that revision. A superseded update discards its result instead of overwriting newer geometry; stale incoming actions still fail the revision check.

## Validation and Diagnostics

`ModelValidator` checks document-wide invariants: valid and unique identifiers, one registered root, resolvable parents, allowed hierarchy relationships, effective property applicability, editable/source-backed consistency, typed property values, and supported geometry.

`PropertyBatchValidator` validates one complete candidate property state. This is important for dependent contracts such as limits and values or item labels, item data, multiselect mode, and selection. Validation returns user-facing messages; document validation publishes structured `Diagnostic` objects with severity, code, component identity, and source span where available.

Errors block unsafe generation or Save. Warnings can describe state that is preserved but cannot be edited or rendered. The diagnostics drawer, status line, generators, and tests consume the same diagnostic model.

## Generation, Diff, and Save

`RoundTripGenerator` is the editor's generation entry point.

- Before a new document is presented, `NewAppGenerator` establishes its canonical skeleton once. The displayed document then uses the same current-source transactions as an opened document. Detached model builders can still assemble a new model before initialization.
- Generation reads `CurrentText`. Supported literal replacements and insertions use `SourceLiteralTransaction` and `IndexedSettingEdit`, deriving current settings, statements, method membership, and execution events from known edits rather than rediscovering them by parsing the edited body. `SourceLocationUpdate` is the common writer for surviving positions; statement code offsets are relative to their statement. New components require unambiguous declaration and creation anchors. Component insertion, deletion/Cut, callbacks and reparenting also publish their exact editor-owned patches and current bindings without reparsing the class. Undo/Redo project the inverse/forward patches through the same source indexes.
- Structural commands prepare independently validated candidates using the loaded lexical, scope and initialization-call indexes. `EditorSourceProjection` rescans changed statement windows, compiles only newly inserted callback methods, and retains established call expansions and opaque boundaries. `recordHistory` and `publishParsedSource` require an exact, current candidate for editor-owned commands; a missing proof rejects publication instead of silently falling back to whole-source parsing. User history keeps primary source patches and semantic edits, never a candidate document handle or a transient full source result.
- `DocumentValidationProof` carries independently validated definitions, effective states and diagnostics across exact source publication, indexed candidates and confirmed saves. It guards the catalog revision, complete component/value join and source positions, then maps occurrence and creation references onto live IDs without adopting a candidate context or component handle. Saved-source line-ending normalization is mapped onto current history coordinates. Property Undo/Redo derive state from primary patches, reuse only unaffected dependency scopes, and preserve the full validation baseline after checking the changed scope; derived state and position snapshots are not added to user history. Stale or untracked inputs retain the existing validation route.
- `PropertyStateResolver.ownerLocalPaths` identifies reviewed finite effects that stay inside one component, including domain-backed values, text constraints, tick/value modes and width followers. Their ordered final states and affected schemas are checked on detached owner values; unchanged document-dependent states come from the exact validated baseline. Implicit follower values and modes must advance with the edit even when they have no explicit source setting. Geometry, hierarchy, references and sibling selection retain their document-dependent proof.
- Atomic literal batches spanning multiple owners, including Grid track and child placement changes, use `SourceLiteralBatchTransaction`: plan every owner against the same source, update the shared statement/execution indexes once, and validate the combined final model before publication. History retains primary forward/inverse patches, typed values, insertion recipes and setting identities per owner; Undo/Redo derive positions and execution indexes from those patches instead of storing secondary position edits.
- Catalog editability controls permitted property changes, not removal of existing source. Restricted or unresolved setter access preserves original assignments and constructor arguments, including callback registrations, during generation and unrelated edits. Only an explicit, validated source-edit operation may remove those occurrences; new generated initialization still omits catalog-declared read-only properties.
- Edits are rejected if required spans are missing, deletion ownership is ambiguous, or calculated edits overlap.

`CallbackSourceEdits` owns new bound-method registration and handler templates. All four generation paths use that formatter, while existing registrations are preserved as source during localized edits and reparenting. Canonical bindings use `@app.Handler` and handler inputs are `(app, source, event)`. Event argument types and handler suffix metadata are independent roadmap work; neither is inferred from callback names. Name reservation includes inherited `handle` members, actual generated members, and existing user members. The default close binding is infrastructure: Add replaces it with an editable handler containing `delete(app)` and Delete restores it without duplicate registrations.

### Canonical setting identity and indexed literal edits

`SourceSettingStore.Records(id)` is the canonical value-record address space for one live document. Positive integer IDs remain stable across value replacement, position projection, and Undo/Redo. Deleted records leave tombstones; `NextId` is a high-water mark that history does not rewind. A separate `Active` vector describes membership in the current store, rather than an intrinsic property of an immutable setting value that can also appear in historical or detached snapshots. Negative IDs are temporary tokens for detached records and are replaced before registration in the canonical store. Their allocator retains only a scalar counter, never a persistent map of closed documents or source revisions.

Each component retains its owned ID list, while `SourceOrder` independently orders active IDs by physical statement and value-token positions. Initializer event order is separate from physical source order: it includes creation, assignments, method calls and returns, certainty, and opaque boundaries. Source parsing establishes these facts and insertion trivia once. Known literal edits splice new statements into the physical and execution indexes and transform existing positions in batches. Unchanged source text, statement-local code offsets, method membership, and source provenance remain independent values. Method calls retain their callee return boundary; a statement inserted after a call executes after that return, not inside the callee.

`PropertyState.LastSettingId` and `EffectSettingId` are numeric occurrence references. `EffectKey` separately represents the generalized cause of a value, including creation and pending effects that are not Settings. Numeric IDs alone do not identify a setting across documents or Reload: snapshot reuse and raw subtree copy also check source provenance, and candidate resolutions explicitly map their references back to the owning document. Imported canonical IDs are reserved before detached additions receive new addresses, including when materializing a structural candidate. Paste publishes independent value materializations of validated candidate records; a candidate-owned component or property handle must never be registered as a second live document owner. Deletion intentions retain only value ownership records (names, identities and source ranges), not component/property handles or unrelated literal payloads. The source layer rechecks those frozen ranges and references; clearing a completed intention must not leave a formerly shared input clock behind.

Ordinary source-property history retains exact forward/inverse source patches, edited occurrence guards, added/removed identities, old/new typed primary values, and insertion recipes. Typed values avoid decoding source during history replay. It does not retain complete Settings arrays, source-position updates, execution sequence updates, or derived indexes. Both directions use the same indexed edit mechanism. Document-dependent literal policies can validate an independent candidate model before publication without reparsing its known source edits. Structural history additionally retains detached subtree values or command-specific semantic changes needed to restore the model. Position shifts, statement membership and execution numbering are derived from primary source patches, rather than stored as independent Undo operations.

Both the editor and generated apps own their figure lifetime explicitly, including launches without an output variable: figure-side registrations retain the owner. `CloseRequestFcn` decides whether closing is allowed and calls `delete(app)` on acceptance; the destructor only releases owned resources, so canceling close leaves the app alive while explicit deletion still cleans it up. A figure-bound `ObjectBeingDestroyed` listener deletes a still-valid owner without replacing user `DeleteFcn` code. Owner deletion skips a figure already being destroyed and guards reentry. Constructor failure deletes the partially constructed owner and rethrows the original exception; destructors contain no argument-validation block.

Diff Preview directly compares the opened `OriginalText` image with committed `CurrentText`; opening Diff does not generate source. The application enables in-place Save only after Open or Save As establishes a confirmed path and validation has no errors. Generated text is written as UTF-8 without a BOM. New documents use the host line-ending convention; opened source preserves detected CRLF or LF text. `SourceWriter` provides the separately tested byte-level utility for callers that need explicit line-ending normalization.

`AppSourceParser.parseText` is the shared whole-source parse entry. A registry-bound `SourceParseProgress` registration associates it with the visible editor figure and opens one indeterminate `uiprogressdlg` with `Loading source...`; cleanup closes it on success or exception, and nested parses reuse the active dialog. Model-only callers and hidden figures do not create a dialog. Partial editor-owned fragment scanning does not enter this progress route.

`SavedSourceCheckpoint` reparses the exact normalized output without executing input code. It verifies the component set, parent links, and known effective property states before writing. Its value-only subtree snapshot owns the saved setting histories and offsets under a fresh source version; `ComponentMap` joins those parsed identities to the editable document's stable component identities. Unknown effective values remain unknown and are not fabricated by the save check.

Only after writing succeeds does `DocumentModel.confirmSavedSource` attach this checkpoint and advance the saved history position. Current text, history identity, catalog/input context, component identity and known effective values guard the save; it does not regenerate a second source from deferred intentions. `OriginalText` is retained for the original-side Diff, not for current offsets. `CurrentSourceState` separates monotonic publication revision from history StateId, and history stores exact forward/inverse patches. Save As rebases class identity, separated history patches and setting ranges across Undo/Redo branches without adding an Undo step. Output normalization owns separate saved positions and does not silently replace the working source with normalized text.

`PropertyCheckpoint` and its second editable source model have been removed. `PropertySetting` stores the current explicit source value and stable occurrence/statement/scope IDs; `PropertyEntry` projects that setting and resolver results supply effective values. `Origin` records provenance, while `SourceOwnership` tests actual current factory ownership. Copy reuses the current source analysis, direct-initializer proof and indexed statement ranges for its subtree ownership checks. A setting's legacy `SourceSnapshotId` is allocation provenance, not a guard for current offsets; current source revision and exact expected patch text provide that guard.

Preview invalidation distinguishes current source-coordinate changes from visual model changes. A source-only callback/rename acknowledgement or property diff requires an exact published history transition and an unchanged tracked input stamp; it then compares visual inputs without source coordinates. Unrelated model/catalog/source writes still reject reuse. Catalog geometry effects continue to decide bounds, measured rectangles, selection outlines and click-target updates.

## Resource and Development-Data Boundary

Runtime code resolves resources relative to the project root:

- `resources/component-catalog/R2024a` is loaded by the registry;
- `resources/EditorInteractionOverlay.html` is loaded by `yamada`; and
- development ledgers and generation scripts under `dev/component-data` are not runtime dependencies.

The development ledger is the review surface for catalog research and audit decisions. Promotion scripts generate the grouped runtime catalog; loader and baseline tests verify that the promoted variants reconstruct the audited intrinsic and parent-effective property surfaces without capability drift.

## Extending the Architecture

### Add or change a component or property

1. Update the release-specific audited data under `dev/component-data/R2024a`.
2. Regenerate or promote the runtime catalog rather than adding declarative inventory to `ComponentRegistry.m`.
3. Add only allowlisted executable behavior required by a new editor, validator, Preview adapter, or reset policy.
4. Test loader failure modes, registry parity, parent-context projection, Inspector behavior, Preview safety, validation, and source generation.

### Add an Inspector editor

1. Define a typed value schema and symbolic editor/validator identifiers.
2. Add the identifiers to the finite behavior allowlists.
3. Implement the native adapter or dialog in `+macd/+ui/+inspector`.
4. Commit through `PropertyTransaction` and the shared batch validator; do not mutate a component record directly from a UI callback.
5. Preserve source-backed values and test rejected drafts, atomic history, Preview refresh, and round-trip output.

### Extend source syntax

Extend the lexical/parser contract and source ownership model together. A syntax form may be parsed for preservation without becoming editable. Generation must still prove exact ownership and insertion anchors before rewriting it.

## Verification Boundaries

Tests are organized by architectural boundary:

- parser and lexical tests prove static, non-evaluating recovery;
- model and transaction tests prove atomic mutation and reversible history;
- loader and registry baseline tests prove strict catalog expansion and parity;
- Inspector and editor tests construct real hidden UI fixtures and delete them;
- Preview tests prove allowlisted rendering without input-app execution;
- generation tests cover canonical output, localized edits, source preservation, encoding, and line endings; and
- project-convention tests enforce MATLAB documentation, license, encoding, and line-ending rules.

Run focused tests for a change before the complete `tests/unit` suite. Current known failures and unfinished product capabilities belong in [ROADMAP.md](../ROADMAP.md), not in this architecture reference.

HTML overlay tests cover DOM pointer/key dispatch through the real iframe handlers and MATLAB event bridge, as well as isolated Node gesture tests. Synthetic DOM dispatch does not prove OS mouse or physical keyboard automation. Preserved handle-class inputs live directly under `tests/fixtures/`, with their notices and adaptation provenance retained. Pre-migration AppBase versions remain in Git history; there is no parallel fixture copy.

## Preview Layout Completion (MATLAB R2024a)

The editor applies native Preview changes and the surrounding MATLAB UI changes before awaiting `macd.ui.waitForPreviewLayout`. It then collects one Canvas-relative native snapshot, shares it between component bounds and Grid overlay consumers, computes the outer workspace placement, and publishes the final geometry once. Catalog geometry policies retain the existing snapshot for changes that cannot affect geometry. Reentrant changes invalidate the older generation; a completed response never publishes an obsolete snapshot. Source offsets are published immediately by the source transaction and do not depend on native layout completion. Owner projections are validated together before the transaction-only publication method applies changed fields; equal-length literal changes still update live bindings. Preview comparison retains the preceding normalized projection, while current input capture and checks for unrelated changes remain in place.

`waitForPreviewLayout` uses an **undocumented R2024a route**: the figure controller's CEF window, `ViewModelManagerFactory`, and the owning root ViewModel's `stabilize()` promise, with a token-matched message-service reply and a bounded timeout. MATLAB's R2024a Web capture implementation also awaits `stabilize()` before image capture; that observation is evidence for this release, not a public compatibility guarantee or a guarantee for every asynchronous widget. The adapter does not execute opened app code. Before supporting another MATLAB version, independently verify controller access, module names, manager ownership, message ordering, completion/timeout cleanup, tables/axes/HTML, tabs, and fit layouts. Do not replace this check with a fixed delay or assume that `drawnow` alone completes Web layout. The fixed pixel Canvas and all size-changing native writes must be established before this wait: the promise alone does not guarantee delivery of a pending operating-system Figure resize notification. Adapter failure or pending/inconsistent Grid geometry explicitly retains the legacy bounded geometry-recovery path; the one-pass contract applies to successfully settled geometry.

## Incremental Evaluation Inputs

Full source parsing binds its completed model diagnostics and resolved states to the final input and catalog revision. Limited parsing never establishes a whole-document validation baseline. For eligible local literals, `SourceLiteralTransaction` validates the actual emitted settings before publication, combines unaffected effective states from that exact baseline, and prepares the updated diagnostics. Candidate-only states are not treated as complete document-dependent states. Changed dependency closures touching layout, ancestor geometry, or unsupported coupling retain the established broader validation path.

After all freshness checks succeed, the same prepared source, settings, effective states and diagnostics are published together. `validatePropertyCommit` then publishes retained diagnostics rather than running semantic validation again. Registry changes, management-free writes, missing baselines and unresolved proofs invalidate this reuse. Unchanged Grid configuration and unresolved-effect results are inherited only when their semantic dependencies are proven unchanged; pixel geometry and fit measurements keep their separate catalog-driven invalidation.

Document-backed component separator formatting uses the exact `SourceAnalysis` snapshot and binary neighbor lookup in its immutable statement indexes. Only the inserted text and neighboring lexical fragment are scanned for formatting; the original full source is not lexed again. Standalone callers without analysis retain the scanner-based path, and a supplied stale analysis is rejected.

### Canonical settings and derived positions

The canonical address, membership, and history contracts are defined in [Canonical setting identity and indexed literal edits](#canonical-setting-identity-and-indexed-literal-edits). `PropertySetting` remains a value class. The private document store maintains five source-range indexes (`SourceSpan`, `ValueSpan`, `NameSpan`, `PairSpan`, `ScopeSpan`), component ID lists, and physical source order. Bound `ComponentRecord.Settings` exposes a revision-guarded derived value view; detached components and materialized snapshots retain independent values. Deleted canonical addresses are tombstones and are never recycled into another occurrence.

Source-position preparation groups component, setting, and property ranges into one vector transform over the atomic patch batch. All owner freshness checks precede publication; unchanged payloads and identities remain immutable values. `IndexedSettingEdit` updates only the edited owner's primary setting records, while maintained numeric maps project existing statement positions, execution visits, return boundaries, and subsequent sequence numbers. It does not rediscover unchanged settings from the source body. Constructor-pair order uses physical source order, independently from canonical IDs and execution order.

Undo/Redo applies exact primary text patches, reuses the stored typed before/after values and insertion recipes, restores occurrence identities, and derives positions, sequence, indexes, diagnostics, and evaluation inputs through the same indexed edit path. These derived updates are never separate history entries. Save As rebases primary source patches. Other structural, callback, reset, and unsupported coupled command schemas retain their command-specific proofs; component paste and identifier-only rename use the indexed publication contracts below.

A validated local source command carries its prepared position projections into the preceding value-only `EvaluationContext` key. Only the edited component is captured again; unchanged component values remain independent shared MATLAB values, and prepared positions replace their location fields. The same route supports source-property Undo/Redo. The transaction verifies input-clock ownership/revision before publication; the context also checks catalog identity/revision and tracking. The view accepts this transition only for the exact preceding token and all changed paths, then normalizes only the changed owner. Public `inputs()` results retain value independence. Direct writes, foreign document clocks, mutable/untracked data, and unsupported source transitions use the existing complete capture/comparison route.

Position-only publication does not reapply literal values or kinds. `PropertyEntry.applySourceSetting` also computes its final result first and assigns only changed fields, merging source metadata once. Current source and all positions are still updated immediately; this optimization does not defer source generation or weaken setter/order validation.


### Indexed component paste and member rename

Loading source records class member names and inert code/help masks in `SourceAnalysis`. Literal patches project these masks without interpreting the unchanged body. Component renames check the maintained member list, MATLAB identifiers, inherited members, and existing unresolved-reference restrictions. Only proven component references, exclusively owned default callback identifiers, and their help text are replaced. Current settings, scopes, source expressions, opaque regions and positions are projected through the primary token patches; unchanged literal values and execution events retain their validation. Invalid names are rejected before publication and use the existing red rename field and explanatory Tooltip.

Paste uses the existing component emission policies for declarations, factory arguments, dependency-ordered assignments, deferred selection and supported subtree references. Only the emitted fragments are lexed and their factory/assignment tokens bound. The existing method layout, initialization trace, execution sequence and source-position indexes are spliced and projected; unaffected application statements are not parsed again. Declaration insertions occur after complete existing line terminators, preserving CRLF ownership. The resulting independent candidate receives model/value validation and frozen-copy checks before live publication. A prepared-only publication rejects missing or stale proofs rather than silently invoking the whole-source parser.

Paste history retains the primary forward/inverse source patches, an independent subtree value snapshot, and the detached live component handles needed to restore handle identity. Rename history retains primary identifier patches and semantic name mappings. Undo/Redo derives current spans, settings and execution indexes through the same local paths; these derived updates are not additional history operations. Save As may parse the saved source and rebase primary patches, while subsequent paste/rename history replay remains local. Direct model-builder literal writes are bound through local literal transactions before these commands; they are not mistaken for already published source. Initial document construction, opening, Reload and saved-source checkpoints retain their separate full-load responsibilities.
