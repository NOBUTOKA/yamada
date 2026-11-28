# yamada Architecture

For contributors changing yamada, this reference explains the internal structure and conditions to preserve during development.

## Architectural Principles

**Conditions to preserve**

- Ordinary MATLAB `.m` class files are the persistent source of truth. The project does not read or write the private `.mlapp` format.
- New and opened applications converge on the same `DocumentModel`, registry, validation, Inspector, Preview, and generation pipeline.
- Opening a source file is a static operation. The input class, its constructor, callbacks, helper methods, and arbitrary expressions are never executed.
- Preview handles, Inspector controls, hierarchy nodes, and HTML overlay state are disposable views. Only model state is eligible for source generation.
- Existing source is changed through owned source spans. Unsupported or ambiguous source is preserved and can block an unsafe edit or save.
- Component and property capabilities are declarative JSON data. Executable behavior is selected only through fixed MATLAB allowlists.

**Explanation**

These principles define the shared boundaries for the workflows and mechanisms described below.

## System Map

**Conditions to preserve**

- Parsing, model mutation, validation, rendering, and generation remain separate so none of them must infer document state from live UI handles.
- Only a successful write updates the file path, generated snapshot, and model save checkpoint.

**Explanation**

```text
New App ──> NewAppFactory ───────────────┐
                                         v
Open App ─> AppSourceParser ───────> DocumentModel
                                         │
                    ┌────────────────────┼────────────────────┐
                    v                    v                    v
          ComponentRegistry       ModelValidator        Editor views
          + release catalog  + PropertyBatchValidator   hierarchy/Inspector
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

The main application class, [`yamada.m`](../yamada.m), coordinates these layers.

Save, Save As, New, Open, and editor close pass through the injected [`DocumentLifecycleService`](../+yamada/+ui/DocumentLifecycleService.m). Its native implementation uses MATLAB dialogs and binary UTF-8 output; tests replace its dialog, existence, and write callbacks to cover cancellation and write failures. The editor title is derived from the document identity and `IsDirty`.

## Package Responsibilities

**Conditions to preserve**

- Keep model state, source handling, validation, catalog loading, and UI presentation within their respective package responsibilities.

**Explanation**

| Path | Responsibility |
| --- | --- |
| [`yamada.m`](../yamada.m) | Application shell, commands, selection, view synchronization, and save coordination |
| [`+yamada/+model`](../+yamada/+model) | Document instance state, catalog value objects, property transactions, and undo/redo history |
| [`+yamada/+catalog`](../+yamada/+catalog) | Strict JSON loading and allowlisted behavior-identifier validation |
| [`+yamada/+source`](../+yamada/+source) | Lexical scanning, conservative parsing, literal encoding, new-source generation, and localized round trips |
| [`+yamada/+validation`](../+yamada/+validation) | Document invariants and typed candidate-property validation |
| [`+yamada/+ui`](../+yamada/+ui) | Safe Preview and Inspector presentation/adapters |
| [`resources/component-catalog/<release>`](../resources/component-catalog) | Runtime component, property, grouping, ordering, context, and Inspector-row data of each release, generated from the surface ledger |
| [`resources/EditorInteractionOverlay.html`](../resources/EditorInteractionOverlay.html) | Transparent HTML/SVG pointer and selection layer for the canvas |
| [`dev/component-data`](../dev/component-data) | Audited source data, design artifacts, and reproducible catalog-generation scripts |
| [`tests`](../tests) | Unit tests and preserved handle-class input fixtures |

## Finding the Change Boundary

Start with the feature you are changing. Its conditions and explanation are grouped below; the shared-boundary column identifies the additional rules that the feature relies on.

| Change | Feature reference | Shared boundary |
| --- | --- | --- |
| Add a component or change its capabilities | [Component Catalog](#component-catalog-and-capability-resolution) | [Property resolution](#property-resolution-and-geometry) |
| Open, Reload, or interpret a newer app | [New and Open Workflows](#new-and-open-workflows) | [Source ownership](#property-setting-history-and-source-placement) |
| Change a property policy or effective value | [Property Resolution and Geometry](#property-resolution-and-geometry) | [Validation](#validation-and-diagnostics) |
| Add or change an Inspector editor | [Property Inspector](#property-inspector) | [Source acceptance](#insertion-proof-and-validation-scope) |
| Change Copy, Cut, Paste, Delete, or Move | [Subtree editing](#subtree-editing-and-clipboard-ownership) | [Source transactions](#source-transactions-and-incremental-evaluation) |
| Change callback management | [Callback Management](#callback-management) | [Source publication](#source-publication-and-history) |
| Change Preview rendering or canvas interaction | [Safe Preview](#safe-preview-and-canvas-overlay) | [Layout completion](#preview-layout-completion) |
| Change source edits, generation, or history | [Source Transactions](#source-transactions-and-incremental-evaluation) | [Generation and Save](#generation-diff-and-save) |
| Change packaging or release support | [Resources and development data](#resource-and-development-data-boundary) | [Runtime and release boundaries](#runtime-and-release-boundaries) |

## Shared Document Model

**Conditions to preserve**

- [`DocumentModel`](../+yamada/+model/DocumentModel.m) is the authoritative in-memory state for both new and parsed applications. Parent relationships use stable model IDs rather than Preview handles or hierarchy nodes.
- [`PropertyEntry`](../+yamada/+model/PropertyEntry.m) keeps document state separate from catalog capability state. A supported `PropertyEntry` value is either:
  - a parsed or generated literal that the model may edit; or
  - a source-backed expression that remains read-only and retains its exact source.
- A batch is preflighted before mutation and becomes one history entry. Parsed deletion also retains enough intent for undo to restore the source-generation state.
- A property batch or grid layout edit that mutates records directly records each change in a partial history entry before applying it. If any change fails, the partial entry is reversed with the same `applyHistory` path as Undo, last change first, so a change interrupted between its removal and its setting is also restored. The partial entry is never added to the history.
- Overlay move and resize gestures commit `Position` through the same batch path as Inspector rows and editor dialogs, so they pass the same batch validation, dependent restatement, and post-commit validation.
- Only `DocumentModel` changes component membership, order, and hierarchy links. `Components` is readable but not settable from outside the document, and `ComponentRecord.ParentId`, `addChild`, `removeChild`, and `replaceChildren` are restricted to the document and to the snapshot and literal-transaction builders that link detached records they construct. The property set methods for `Components`, `ParentId`, and `Children` advance a document-owned structure revision, so a new structural mutator cannot forget to advance it. Value edits do not advance it.
- The identity lookup behind `getComponent` is keyed by the structure revision and confirms the stored record's `Id` on a hit, so a stale index can cost only a scan, never a wrong record. A record adopted by another document advances its previous owner's structure revision.

**Explanation**

`DocumentModel` owns:

- class name, file path, encoding, and line-ending policy;
- exact original text and the latest generated text;
- the ordered component collection and root component identity;
- diagnostics, unknown source regions, and pending source edits; and
- bounded undo/redo history, including a conservative saved-history checkpoint and public dirty-state flag.

[`ComponentRecord`](../+yamada/+model/ComponentRecord.m) represents one component instance. `ComponentRecord` stores a stable identity, which `ComponentRecord.newId` assigns at random to every new, inserted, pasted, and parsed component so that no document content determines it and an identity never recurs in another document. It also stores the MATLAB property name, factory, declared type, creation arguments, parent/child IDs, origin, source spans, and ordered `PropertyEntry` objects.

Model mutators implement insertion, subtree deletion and reparenting, Copy/Paste, individual and batch property changes, reset, undo, and redo.

### Property setting history and source placement

**Conditions to preserve**

- Positional arguments and construction styles remain distinct from named property settings.
- Source occurrence history is separate from user Undo/Redo. Editing an existing value retains the target setting's identity; repeated edits do not append fictitious source occurrences. Adding a previously unset property creates one pending setting; subsequent edits retain its identity and update the `PropertyEntry`.
- Earlier source settings remain intact. Existing settings keep their location and form. If an in-place change would fail at an intermediate setter or lose its requested final value, the edit is rejected instead of moving existing settings, converting their form, or adding a compensating assignment.
- A new setting is placed before existing settings of its `applyAfter` dependents when that candidate validates. Otherwise it may follow them; each dependent whose final value the later setter changes is restated in its own owned literal value token within the same history step. A dependent that cannot be restated that way rejects the later slot. Independently of placement, `DocumentModel.restateDependentChanges` keeps the current effective value of each transitive `boundedValue` or `numericValue` dependent that the candidate would change when the new domain still accepts it, adding a setting if needed. When the candidate is rejected because a later stored `Value` falls outside new `Limits`, that value is restated clamped into them. It then adds the candidate effective value of every remaining owned literal dependent that the batch leaves diverged, so in-place prerequisite edits follow the same rule. Before that step, an Inspector `Units` change adds the stored geometry literals measured on the Preview handle in the new units to the same batch, and overlay gestures on non-pixel components run in pixels and convert back through the Preview affine mapping.
- A final expression or uncertain setting does not expose an earlier literal as the editable value.
- Initialization sequence follows proven same-class calls rather than file order, and runtime callback writes do not become initial settings. Implicit defaults and setter effects belong to resolved state, not source history.

**Explanation**

[`PropertySetting`](../+yamada/+model/PropertySetting.m) is the immutable record of an original setting occurrence or a pending generated setting. Original occurrences retain the literal or unevaluated expression, constructor/assignment syntax, statement/name/value/pair spans, source snapshot identity, initializer ownership, execution sequence, and certainty. Pending settings have no original source spans. `ComponentRecord.getSettings(path)` returns that property's occurrences; `PropertyEntry` owns its current requested value and binding to the target setting, while `CreationArguments` projects factory inputs from that state.

`RoundTripGenerator` replaces an owned value token; [`FactoryCallEditor`](../+yamada/+source/FactoryCallEditor.m) preserves surrounding constructor tokens, comments, and unknown arguments.

#### Ordering and insertion intervals

**Conditions to preserve**

- Inspector presentation order, value constraints, and effect dependencies are separate contracts. The loader rejects invalid graph references and cycles after variant/group/context expansion.
- Setter access, product disposition, parent applicability, literal safety, source ownership, and complete candidate validation independently constrain insertion. An existing initialization that sets properties only through named constructor arguments may receive additional named arguments only when ownership, writable direct properties, dependencies, and reference availability are proven; positional-only or mixed initialization does not imply that permission.
- Constructor arguments are evaluated under their finite application policy rather than assumed to be sequential assignment setters.
- Unknown statements delimit intervals. Existing code is never moved and unknown-call effects are user-owned. Absence of a syntactically and semantically valid owned slot still rejects insertion.
- Insertions sharing an offset are combined in stable dependency order.

**Explanation**

[`PropertyApplicationPlanner`](../+yamada/+model/PropertyApplicationPlanner.m) orders new settings using the catalog's `metadata.application.applyAfter` graph. All registered factories document name-value construction for their applicable writable properties; the release-specific [constructor syntax review](../dev/component-data/R2026b/CONSTRUCTOR_SYNTAX_REVIEW.json) records that evidence. There is no per-property constructor-support flag.

[`PropertyInsertionPlanner`](../+yamada/+source/PropertyInsertionPlanner.m) finds a proven initialization interval for new settings while holding existing occurrences fixed. New components use post-construction assignments by default; supported constructor-only components use name-value arguments. When constructor additions are not permitted, the planner inserts assignments after their prerequisites and before relevant modeled downstream setters. The default interval precedes the next unknown statement; prerequisites may select a later interval, ending at its next unknown statement.

#### Axes setting function placement

**Conditions to preserve**

- A recognized call effect owns a replaceable value token only when it comes from an argument or option, that single-line token belongs to it alone or to effects owning disjoint `elements` of it, and the target is explicit. An element effect, such as `XLim` of `axis(ax, [x1 x2 y1 y2])`, is edited by rewriting the whole vector with its own elements replaced; slices changed in one batch compose into one replacement, and the result must still satisfy the argument kind. The aspect-ratio forms of `axis` own a pseudo path, `AxisStyle`, holding their keyword token; it has no native property and is skipped in Preview. These forms are marked `composable`: a call that lists several of their keywords records each keyword's effects in order, each keyword owning its own token, because the combined call matched the keywords applied one by one in every ordered pair of `equal`, `image`, `square`, `normal`, `vis3d`, `tight`, and `fill` for axes and UI axes in 2-D and 3-D views on R2023a through R2026b. `AxesInspectorProperties.axisKeywordState` derives both Inspector rows from these tokens: the style is the last keyword other than `vis3d`, and the `AxisVis3d` toggle is on while a `vis3d` token follows the last `normal`, which returns its Modes to automatic. Changing either row rewrites the keyword list of one call in its quote style and swaps the call statement's recorded effects for those of the new keywords in one indexed transaction, leaving later settings untouched; a call left without keywords is removed. The Inspector marks the keyword when a later setting of an effect path, or of its paired value or `Mode` path, comes after the call. Implied literal effects, such as `XLimMode` from `xlim(ax, [0 1])`, and effects that share their token with other paths, such as `XLimitMethod` from `axis(ax, "tight")`, have no `ValueSpan` and are never rewritten; a requested change supersedes them with a new setting after the call. Effects of a call whose target is only inferred, including command syntax, keep their token ranges but carry the `implicitCall` syntax, so they are superseded the same way: the axis style or `vis3d` is changed by inserting a new explicit `axis` call, and turning `vis3d` off restates the style after `normal`. Insertion after a statement without a terminator anchors before its line break, because the scanner ends such a statement at the line, including its CR. When the change needs the wider model proof, the batch replaces the read-only entry with a pending value and records the entry for Undo.
- Placement follows one priority: an existing owned value is replaced in place; a dependent path of a catalog `settingGroups` entry follows the method of its main path's last setting; otherwise a form marked `insertion` precedes constructor arguments and assignments. A group exists only where the dependent path is meaningless without its main path, which currently means the axes text objects.
- A dependent setting whose main path is a call joins the last certain call of that function that declares exactly one option for the path, then an earlier such call. A new call that would restate the main value is not emitted; the next candidate is the constructor or assignment.
- An `insertion` form has one argument and owns exactly one path, and its implied effects must match a plain assignment of that path. Forms that also change other properties, such as `xticklabels`, `grid`, `xlim("tight")`, the Cartesian and polar `tickformat` functions, which set the ruler's `TickLabelMode` to `auto`, `title` with a subtitle, and every `axis` form, are never chosen for new settings. A value that an inserted call already implies needs no statement of its own. A `companionInsertion` form, such as `xlim(ax, "padded")` or `xtickformat`, is used for a new setting only when every value it implies is requested in the same edit; it takes the place of the first such pending value and follows every setting those values supersede. The specialized ruler format editor applies the same form while the implied tick label Mode is not known to be `auto`, resolving that effective Mode only for a form that implies one.
- Axes text sizes and weights have hidden Modes, so their parameters cannot select automatic text. `AxesInspectorProperties.automaticTexts` names the text values that `TitleFontSizeMultiplier`, `LabelFontSizeMultiplier`, `TitleFontWeight`, and `SubtitleFontWeight` shape; the resolver makes an otherwise editable parameter read-only while every one of them holds an explicit value. The resolver returns explicit text sizes to automatic, with reason code `automatic-text`, when the axes `FontSize` is set, and for the catalog `automaticPaths` of a recognized call, such as a label's `FontSize` and, from R2024b, `FontWeight` for `xlabel`. The text `FontSize` rows apply after the axes `FontSize`, and an edit of a size returned to automatic is written after every certain setting.
- Call insertions, option additions, and their Undo use the indexed literal path. They do not reparse or validate the whole source: the call form supplies the owned and implied occurrences, each new or extended statement reports its event count to the execution index, and removing an option keeps the statement while another of its occurrences survives.

**Explanation**

[`AxesSettingFunctionCatalog`](../+yamada/+catalog/AxesSettingFunctionCatalog.m) loads each release's `axes-setting-functions.json` once per catalog root and indexes forms by name and identifier, insertion forms by factory and path, and setting groups. [`AxesSettingPlacement`](../+yamada/+source/AxesSettingPlacement.m) holds the ownership rule and builds call text and occurrences. [`AxesInspectorEdits`](../+yamada/+source/AxesInspectorEdits.m) applies the rules to specialized axes text, ruler, and geographic rows; the insertion planner applies the insertion-form rule to ordinary rows such as limits, ticks, scales, and `Box`.

### Subtree editing and clipboard ownership

#### Subtree transactions

**Conditions to preserve**

- Structural edits prepare owned source patches and history before mutating the live document. Paste and reparenting plan placement against the live destination. Delete and Cut obtain removal ranges from existing bindings and repair owned direct-parent selection in the same transaction.
- The detached transaction candidate must not share mutable component handles with the live document. It reads the live document's accepted evaluation state only through the read-only `EvaluationBaseline`, and owns a separate `EvaluationContext` for its own results. It shares the published `SourceAnalysis` and the component registry by identity. A published analysis rejects any change to its cached execution events, because those events are determined by its text. Only a candidate whose patched source binds successfully permits one history record, clipboard publication, and selection/view changes; Paste from a literal copy configuration additionally verifies the emitted configuration. Failure preserves document state, diagnostics, generated source, history, clipboard, and selection.
- Actual commands revalidate the current document even when availability results were previously computed.

**Explanation**

Subtree responsibilities are split as follows:

| Owner | Responsibility |
| --- | --- |
| [`SubtreeSnapshot`](../+yamada/+model/SubtreeSnapshot.m) | Capture independent value data in stable parent-before-child order; reject missing components, cycles, and repeated children, and cross-check parent/child links unless the caller already holds the live hierarchy |
| [`SubtreePlacementPlanner`](../+yamada/+model/SubtreePlacementPlanner.m) | Validate construction style and destination; plan root placement across absolute and Grid parents |
| [`SubtreeReferencePolicy`](../+yamada/+model/SubtreeReferencePolicy.m) | Validate the finite set of static component references without evaluation |
| `SubtreeSourceEdits` / `SubtreeReparentSourceEdits` | Remove or relocate owned declarations and initialization statements while preserving other source |
| `DocumentModel` | Preflight the complete candidate and commit records, links, order, placement, and source intentions as one history entry |
| [`ComponentClipboard`](../+yamada/+model/ComponentClipboard.m) | Retain a document-scoped snapshot and update it only after successful Copy/Cut preparation |
| `yamada` / Hierarchy / HTML overlay | Resolve explicit command targets, present availability, and refresh selection and disposable views after success |

Shared boundaries: [Shared Document Model](#shared-document-model) and [Source publication and history](#source-publication-and-history).

#### Clipboard identity and lifetime

**Conditions to preserve**

- Reparenting preserves IDs; Paste allocates new IDs and unique member names before remapping internal references. Copy uses a `Copy` suffix; Cut preserves original names unless they collide.
- Paste is one transaction, not insertion followed by a separate reparent command. Undo/Redo restores IDs, document and child order, properties, and source intentions, but does not rewind clipboard contents.
- Copy leaves document/history unchanged. Cut publishes the snapshot only after deletion succeeds. Paste retains the clipboard snapshot for repeated use. The clipboard is not tied to a document. New, Open, and Reload keep it, and Paste into another document follows the same rules.

**Explanation**

`ComponentClipboard` retains the prepared snapshot, which holds values only. It keeps no reference to the document it was copied from. The component registry is shared by the editor window, so no document context needs checking at Paste. Document history restores the edited subtree independently of that snapshot, so Undo does not consume or rewind clipboard contents.

The clipboard snapshot retains independent component records and owned initialization fragments in execution order. Each fragment carries relative ranges for tokens that Paste may rewrite. Copy, Cut, and Delete use the same non-root selection rule. Paste checks clipboard ownership and selection for availability, then resolves destination, occupancy, and name allocation when invoked. Descendants retain their internal parent context and original settings.

Copy captures source fragments whenever the document has a bound current source with no pending structural, callback, or rename intentions. Every completed editor command publishes its source through `publishCurrentSource`, which clears those intentions, so ordinary editing always reaches this path. The literal `CopyConfiguration` path remains for programmatic builder documents without bound source; it omits callback bindings and rejects expressions that have no source fragment.

Deletion removes owned declaration and initialization spans. The catalog projects the per-property `metadata.referencesDirectChild` flag from the ledger and aggregates it as `ComponentDefinition.ReferencesDirectChild`. At commit, an owned selection in the surviving direct parent is retargeted or removed with the subtree in one history entry. User-written logic and unrecognized initializer references remain the source author's responsibility.

#### Subtree placement

**Conditions to preserve**

- A drop validates only the requested destination through the model transaction, including construction style, editability, managed references, source ownership, and generated-source checks. Rejected drops preserve document and history.
- Paste searches from its target toward the nearest catalog-compatible ancestor. Reparenting uses the explicitly chosen destination without substituting an ancestor. Paste retains its separate free-cell placement policy.
- `SubtreePlacementPlanner` transforms only the subtree root's parent-dependent placement and preserves internal layouts. Reparenting permits overlapping Grid children and clips the original span to the tracks remaining from the requested drop cell; it neither searches occupancy nor adds tracks implicitly.
- Conversion to absolute placement requires known model geometry or verified Preview measurements fixed in the plan; unresolved source placement is rejected rather than silently discarded.

**Explanation**

Destination-grid occupancy reads share immutable coordinate values after one successful hierarchy/value capture for the exact document and catalog inputs. This avoids capturing a nested destination child subtree repeatedly just to read its root placement.

Preview destination regions describe visible container geometry without precomputing edit eligibility or constructing subtree snapshots. Self and descendant regions are excluded by parent-link traversal. Geometry reuse refreshes labels and revisions without querying destination eligibility.

The destination-grid occupancy projection retains the original explicit-coordinate validation and does not share native rectangles.

If the whole-root capture cannot be proved, the planner uses the previous destination-child capture path so unrelated invalid data or hierarchy cannot introduce a new placement refusal.

#### Subtree references and callbacks

**Conditions to preserve**

- Static `SelectedTab` and `SelectedObject` refer to eligible direct children. Static `ContextMenu` refers to a context menu under the document root. Paste maps internal references to fresh identities. An external reference follows its target's identity when the destination contains that identity and the target still passes the rule Copy applied (a context menu under the document root). Otherwise the reference keeps its copied text. `ModelValidator` warns (`missing-reference-target`, `missing-callback-method`) about a static `ContextMenu` reference or callback binding whose target the document does not define, without blocking edits or Save.
- Source-backed Copy and Cut retain callback registrations, constructor arguments, and opaque settings with the component's owned statements. Paste reuses existing callback methods. It allocates fresh setting identities when binding the inserted fragments. Delete and Cut remove the owned registration with the component and leave the existing handler method in place.
- Reparenting may preserve owned callback source; pending callback edits on a parsed relocation target require Save + Reload Source or Undo before relocation. Arbitrary reference rewriting remains outside this boundary.

**Explanation**

Reference analysis distinguishes internal, outgoing external, and incoming references. Source-backed Paste rewrites recognized references using clipboard identities. Unknown expressions remain source text and Safe Preview does not evaluate them.

#### Subtree command dispatch

**Conditions to preserve**

- Edit commands, keyboard shortcuts, and Hierarchy context commands use the same dispatch and availability rules.
- A context target is independent of selection and is invalidated on tree rebuild or document replacement. Preview forwards clipboard keys only outside text editing, popovers, and active gestures; MATLAB checks selection identity and revision.
- Parent movement is exposed only through Preview drag gestures. The root UIFigure, unsupported construction families, OS clipboard integration, and multiple selection retain their explicit supported-scope limits in the product specification.

**Explanation**

The shell resolves the command target and availability, while Hierarchy and the HTML overlay forward context actions and keyboard input. They use the same model commands rather than implementing separate subtree edits.

## Component Catalog and Capability Resolution

### Catalog capability queries

**Conditions to preserve**

- Variant selection prefers an exact creation-argument match, then the most specific prefix, then an unstyled default.
- `PropertyDefinition` never stores an instance value. All consumers obtain the effective component/direct-parent property surface through `ComponentRegistry.getEffectiveProperties`. Catalog JSON is data, not executable configuration.
- Loader validation rejects unknown fields, broken references, duplicate ownership, invalid ordering, and unknown behavior identifiers.
- The `figureTool` component capability marks the figure tools that Safe Preview does not render: `uicontextmenu`, `uimenu`, `uitoolbar`, `uipushtool`, and `uitoggletool`. Source analysis, validation, and Preview ask `ComponentRegistry.isFigureTool` instead of listing factory names. yamada retains their source but does not render them, edit them in the Inspector, or probe their native defaults.
- Three component capabilities state how a container couples its children, so evaluation, validation, editing, and Preview ask the registry instead of listing factory names. `childStateCoupling` (`uigridlayout`, `uibuttongroup`) makes an evaluation scope include the container's complete subtree. `childTopologyCoupling` (`uigridlayout`, `uibuttongroup`, `uitabgroup`) marks the container for rechecking when its children are added, removed, moved, or reordered, and prevents Preview from keeping existing children in place unless a container-specific proof holds, which exists only for Grid Layout children with literal cells. `selectionMembers` (`uiradiobutton` and `uitogglebutton` in `uibuttongroup`) lists the child factories that share the container's exclusive selection; a group holds members of one factory at a time. The loader requires `childTopologyCoupling` whenever `childStateCoupling` is set, and requires every selection member to be a registered factory that accepts the group as its parent. How a scope is closed, and how undetermined cases fall back, stays in `EvaluationContext` and `ButtonSelectionPolicy` and does not depend on the component.

**Explanation**

[`ComponentRegistry`](../+yamada/+model/ComponentRegistry.m) is the runtime query boundary. `createDefault` loads a packaged catalog through [`ComponentCatalogLoader`](../+yamada/+catalog/ComponentCatalogLoader.m).

The schema-version 2 manifest references:

- concrete component variants;
- reusable property groups;
- category-order profiles;
- declarative Inspector composite-row templates; and
- direct-parent context rules.

`ComponentDefinition` describes one concrete factory variant, including creation arguments, declared MATLAB type, allowed parents, palette metadata, Preview outline shape, and resize constraints.

`PropertyDefinition` describes one property capability. It includes the property path, default, editability, category and order, typed value schema, style scope, Preview/reset policies, audit disposition, and symbolic editor and validator IDs.

`ParentContextRule` composes the effective property surface from the selected component and its direct parent. For example, a Grid Layout parent suppresses absolute `Position` and contributes `Layout.Row` and `Layout.Column`.

`PropertyBehaviorRegistry` contains the finite allowlists that bridge symbolic catalog IDs to project-owned MATLAB code.

### Ledger validation

**Conditions to preserve**

- The development pipeline validates every complete concrete document against the release schema before writing outputs. Application graph, source evidence, and grouping parity checks remain separate.
- Accepted MATLAB classes remain JSON arrays even for a single class; their order has no semantic meaning. Full-schema verification does not establish that a property's setter effects have been audited.

**Explanation**

The development pipeline runs `Assert-ComponentLedgerSchema` from `dev/component-data/ComponentLedger.ps1` before policy application, grouping artifact generation, grouping design, and runtime promotion. Combined official headings supply each named property's description, rather than leaving earlier names blank.

### Setter access and review evidence

**Conditions to preserve**

- Native setter access and product disposition are separate catalog facts.
- The setter-access review applicator validates all observations before writing any ledger, rejects duplicate targets and documented read-only conflicts, and carries runtime access through grouping and promotion. Detailed `runtimeObservations` remain development evidence.

**Explanation**

The review applicator can retain passed, release-specific `setterAccess` evidence without completing a property effect review. Checkbox Tree Position is publicly writable; InnerPosition is also writable in source but remains omitted from the Inspector. OuterPosition has a restricted setter.

### Catalog release selection

**Conditions to preserve**

- Each catalog lives in a release-named folder under `resources/component-catalog`, and the loader selects the newest release that is not newer than the running MATLAB, so a newer MATLAB relies on backward compatibility until its own catalog exists. A running release older than every catalog is rejected. Each manifest names its release, and every property-group and Inspector-row artifact must name the same release.

**Explanation**

`ComponentCatalogLoader`, called by `ComponentRegistry.createDefault`, selects the packaged release projection before validating its manifest and related artifacts.

### Catalog load reuse

**Conditions to preserve**

- The loader reuses the remembered validated state only when the full catalog-root fingerprint is unchanged; otherwise it validates from source again. Any edit, added file or unreadable file therefore forces full validation, and a failed load is never remembered.
- Every call returns a new, independent registry, so registration or other mutation by one caller never reaches the cache or another caller.
- A registry carries the axes setting call forms of its catalog root, read with the rest of the catalog and shared by its duplicates. Call-form lookups take the registry, so they follow its lifetime and need no cache of their own.

**Explanation**

The loader remembers successful loads in process memory, one entry per catalog root. Before each load it computes a SHA-256 fingerprint over the full path and bytes of every file under the root. Nothing is written to disk, and the cache is lost when MATLAB clears the loader class.

## New and Open Workflows

### New documents

**Conditions to preserve**

- `NewAppFactory.createEmpty` creates a `DocumentModel` with one generated root `uifigure`.

**Explanation**

Subsequent palette insertion asks the registry for the selected variant and allowed parent, seeds required creation arguments and layout defaults, then records the insertion in model history.

### Opened documents

**Conditions to preserve**

- `AppSourceParser.parseFile` reads source as bytes, requires valid UTF-8, detects the existing line-ending convention, and retains the exact decoded source.
- The supported app directly inherits from `handle` and owns one `uifigure`; zero or multiple statically recognized roots produce diagnostics. AppBase input has no compatibility or automatic-conversion path. Other UI components are descendants of that figure as a user precondition; there is no dedicated descendant-membership validation.
- Existing model consistency and source-ownership checks still apply. Callback values, arbitrary expressions, unsupported statements, and uncertain regions are retained as source-backed data or `UnknownSourceRegion` records.
- Constructor tracing follows ordinary same-class calls without inspecting external base classes or executing factories. Parsing never uses `eval` and never constructs the opened application.

**Explanation**

`MatlabLexicalScanner` first identifies safe statement boundaries around strings, comments, continuations, and balanced delimiters. The parser then recognizes the supported handle-class subset:

- class inheritance;
- component property declarations;
- direct registered factory calls;
- parent relationships; and
- direct component property assignments with supported literals.

A constructor try/catch that only deletes the owner and rethrows the caught exception is traced on its successful path; other guarded initialization remains uncertain.

`MatlabLiteralParser` interprets only the conservative literal subset.

### Source loading progress

**Conditions to preserve**

- Whole-source parsing in a visible editor uses one progress dialog; cleanup closes it on success or exception, and nested parses reuse the active dialog. Model-only callers and hidden figures do not create a dialog. Partial editor-owned fragment scanning does not enter this progress route.

**Explanation**

`AppSourceParser.parseText` is the shared whole-source parse entry. A registry-bound `SourceParseProgress` registration associates whole-source parsing with the visible editor figure and opens one indeterminate `uiprogressdlg` with `Loading source...`.

### Reload and external source changes

**Conditions to preserve**

- Source reload uses the same replacement boundary: the shell first resolves dirty/external-change policy through DocumentLifecycleService, then captures fresh bytes, parses without execution and verifies an unchanged snapshot before swapping documents. The reload target remains the original file even if conflict handling saves local changes to a different file.
- A separate saved-source snapshot tracks the last successful Open/Reload/Save; OriginalText remains the opened-file comparison image, while CurrentText owns current editing positions.
- The reload entry points share one reentrancy guard. Read failures leave the document untouched, and a separate activation guard prevents dialog-induced reentry.
- Window activation checks the current file text against the last successful Open/Reload/Save source snapshot (the original loaded text until the first Save). A difference offers Reload/Cancel before entering the existing reload policy; local saves do not trigger this prompt.
- Cancel retains edits and remembers the source text captured before the prompt. Later activation suppresses the same dismissed text but prompts for a different external revision.
- Successful New/Open/Reload/Save clears this dismissal; failed operations retain it. Manual Reload ignores dismissal, and a failed Reload is not recorded as a dismissal.

**Explanation**

MATLAB exposes activation through the internal `FigureActivated` event rather than a public focus callback; this compatibility boundary is confined to the shell listener.

### Release-unavailable source

#### Unavailable component preservation

**Conditions to preserve**

- Release availability is a source interpretation boundary. A release-unavailable source variant retains its component identity, hierarchy, settings, and spans in the document as a read-only node. Annotated properties and enum values excluded by the selected release remain source settings and are omitted from native Preview writes. A property known to be excluded by the runtime release stays source-backed and out of native Preview writes and generic unsupported-property diagnostics.
- Delete and Cut remove the source ranges already owned by the subtree, including unavailable descendants and their callback registrations. Any existing callback methods stay in the class. A surviving direct parent’s owned child reference is repaired in the same edit. Reparenting an enclosing container retains its unavailable descendants and their existing direct-parent relationships.
- Moving an unavailable component itself uses its source catalog for destination compatibility. A move within its existing parent requires owned, explicit placement literals and patches only their value tokens. Source rebinding uses the original variant definition for moved and restored occurrences. Source changes still pass through the existing ownership and transaction checks, and availability does not infer release-specific setter interactions.

**Explanation**

A runtime catalog can use the bundled surface catalog to identify a source variant absent from its release. Descendants of an unavailable container remain in the hierarchy, and Preview renders that subtree through one editor-owned label using certain literal placement.

#### Unavailable component clipboard operations

**Conditions to preserve**

- Pasting an unavailable component uses the bundled source catalog for destination compatibility and source binding. The live model and Preview retain the runtime catalog. Cut replaces the clipboard after the source-owned deletion succeeds.

**Explanation**

Copying a subtree with an unavailable component reads the same owned source spans and preserves its source-catalog identity.

#### Source release inference

**Conditions to preserve**

- Open and Reload intersect catalog availability bounds for recognized creation variants and explicit initialization properties. Missing bounds stay open.
- A running release outside the inferred range, or conflicting bounds, produces a range diagnostic published before other diagnostics. The range describes observed feature usage rather than a whole-application compatibility proof.

**Explanation**

Open and Reload infer the source release range and retain any range diagnostic as document metadata. Model revalidation publishes it first, including after edits.

## Property Resolution and Geometry

### Effective values and effect status

**Conditions to preserve**

- The application contract distinguishes `independent`, `modeled`, `unsupported`, and `unknown` effect status, separately from documented constructor syntax and product editability. Legacy catalogs default to unknown. The exact per-property review artifact passes through schema validation, grouping, promotion, and loader; `effectPolicy: none` alone never grants independence.
- An unknown review status does not disable editing or invalidate other states for certain literal writes. Product omissions/read-only access, value validation, and source ownership remain separate gates.
- Unsupported writes and source-uncertain unknown writes invalidate the declared paths, or all same-component states when the scope is unbounded. Unexpanded initialization, nonempty constructor CreateFcn, uncataloged setters, and unsupported Parent/Children writes invalidate document-level guarantees while retaining original source. Later coupled setters do not erase identified unsupported or source-uncertain upstream effects.
- On/off states are read only through [`OnOffState`](../+yamada/+model/OnOffState.m), given the list of [`OnOffForm`](../+yamada/+model/OnOffForm.m) members that the place accepts: every form for property assignments and name-value arguments, and the `onOffForms` that an axes setting function catalog argument lists for its release. Forms are independent, such as text and logical, which compare unequal in MATLAB outside `matlab.lang.OnOffSwitchState`, so no form implies another. Settings keep the value as written; `DocumentModel` writes an edited state in the logical, numeric, or enumeration form of the owned value it replaces, and as `"on"` or `"off"` otherwise.
- A later reviewed independent setter can restore its own stored input. Unknown explicit calls are bounded even without an app argument; only allowlisted data constructors with inert literal arguments bypass the execution barrier.

**Explanation**

For properties with unknown review status, the resolver projects stored inputs and catalog defaults while retaining `PropertyState.EffectStatus == "unknown"`; `IsKnown` is a finite-model result, not proof of reviewed native independence. Untouched Inspector values and related editor transactions may also use the existing owned default fixture for unknown properties, without materializing source settings. Source hierarchy writes can affect destination siblings outside the constructor ownership graph, so a local unknown state is insufficient.

### Position geometry policies

**Conditions to preserve**

- The Position policies do not calculate decoration-dependent aliases. Position request comparison tolerates only floating-point roundoff; it does not accept an unrelated normalized size in place of a request.
- Preview rendering and both pointer-resize paths consume the same geometry rules. Existing source occurrences are still edited at their original value spans, and copied configurations use the resolved native rectangle.

**Explanation**

`PositionGeometry` owns finite rectangle normalization, linked-field edits, fixed slider thickness, and constrained resize anchors. The `switchPosition` and `semicircularPosition` policies use Orientation-aware ratios and replay native size exchange in actual setter order, including constructor arguments. The `linearPosition` policy retains independent dimensions while replaying Orientation size exchange; its runtime resize capability is `free`.

### Position aliases

**Conditions to preserve**

- Unknown aliases invalidate the group; a later certain literal restores it. Grid-managed aliases remain unknown with a layout reason. Unknown geometry produces a diagnostic instead of silently treating an earlier value as the effective one.
- The position-alias family does not describe decorated sliders, knobs, containers, or axes.
- Original constructor arguments and setting ownership stay unchanged.

**Explanation**

`positionAlias` and `squarePositionAlias` select finite getter effects for 14 reviewed simple-control variants. `PositionAliasPolicy` propagates a public setter's value and setting identity across the shared getters without changing their explicit inputs. Lamp uses the smaller finite nonnegative size component for both dimensions.

Preview filters skipped named arguments before invoking native factories and projects known alias geometry once through Position. Named ImageSource values use the existing asset adapter after construction.

### Grid track state

**Conditions to preserve**

- Unknown placement affects the corresponding track state; later certain literals can restore it.
- Pixel geometry and `fit` measurements are outside the grid track state policy. Native `fit` geometry remains a separate concern even for logically independent font or text settings.
- `PropertyState.EffectPolicy` scopes normalized track comparisons to this audited family; a table's unrelated `ColumnWidth` retains its own comparison semantics. The shared resolver exposes final tracks and implicit placements without adding source occurrences.
- Pending changes must retain their actual initialization placement and account for effects on related grid members; independent property writes do not automatically become logical track or placement changes. Grid batches verify requested tracks and affected placements before committing one history record, so an occupied-track shrink cannot silently change the requested size.

**Explanation**

`gridTracks` selects the finite `GridLayoutStatePolicy`. The parser records a global initialization sequence and certainty for each creation, including calls without named properties. The policy merges these events with explicit track and direct-child placement writes. It retains requested track baselines, pads occupied rows/columns with `1x`, and releases implicit padding after children move out. Default placement follows the last occupied cell in row-major order. Positional grid size precedes named track overrides.

Preview projects known values, and the literal copy configuration for unbound builder documents freezes affected values for independent generation and verification. Grid overlay track data and track actions consume the same effective values. Single-property history wraps cell values as scalar record fields so track lists remain one Undo/Redo operation.

### Button group selection

**Conditions to preserve**

- Source occurrences remain intact. New/copy generators defer selection assignments until siblings exist; the insertion planner admits proven same-group creation boundaries.
- Copy materializes child values and omits the source-only parent handle. Mixed radio/toggle families and unresolved handles are not generalized.

**Explanation**

`ButtonSelectionPolicy` replays parent SelectedObject references, sibling creation, and Value events. Preview selects the resolved child after rendering all siblings.

### Ancestor geometry

**Conditions to preserve**

- `AncestorGeometryPolicy` invalidates child geometry after later ancestor position writes unless prior AutoResizeChildren is explicitly off. `AncestorGeometryPolicy` does not calculate native reflow. Stored position, slider thickness, and selected square control rules keep decoration-dependent aliases unknown.
- Pending ancestor changes use the same complete emitted candidate as other cross-component policies. The subtree creation anchor follows proven ancestor geometry initialization. A later ancestor setter in a different unresolved insertion context causes refusal; existing source settings are not moved to accommodate the new component.

**Explanation**

New subtree creation shares an execution-order anchor with grid event replay.

### Value modes and automatic followers

**Conditions to preserve**

- `PropertyStateResolver` keeps original explicit values, replacement requests, and effective values separate.
- For new initialization, the canonical application graph applies an explicitly requested final mode after its corresponding value, while parsed settings retain their original order and token ownership. Copy retains audited automatic-mode inputs and their mode without claiming a computed getter value. The `valueMode` rule is not generalized to color modes, grid-width followers, camera properties, or unreviewed geographic behavior. `DataAspectRatio` and `PlotBoxAspectRatio` of axes and UI axes are `valueMode` pairs whose manual values are their own effective values; their automatic values stay runtime-derived. A manual `DataAspectRatio` with two or more manual limits makes MATLAB replace a manual `PlotBoxAspectRatio` while its Mode stays manual, as verified on R2023a through R2026b for axes and UI axes in 2-D and 3-D views. The resolver keeps the requested value, and `AspectRatioOverride` derives a marker for that row from the known Modes instead of refusing the settings.
- Held defaults carry their determining mode occurrence without becoming explicit source writes. The insertion planner preserves existing manual hold points before new upstream assignments and validated constructor additions.
- Source-backed Paste retains the order of explicit width and mode setters. The copied component derives implicit width values from its retained source inputs.

**Explanation**

The allowlisted `valueMode` policy covers individually reviewed axes font, tick, limit, and map value/mode pairs. An explicit value selects manual mode; an automatic or unevaluated mode makes computed output unknown.

`modeFlag` separately models reviewed color/alpha setters that select manual mode while preserving the stored getter when auto is restored. `setterModeFlag` keeps that rule for assignments, but constructor name-value arguments that restore auto after the value leave it runtime-derived, as release catalogs record for UIAxes colors and alphas from R2025a. From R2026a, axis colors use `valueMode` because restoring auto replaces them in both forms. `autoParameter` marks a reviewed setting, such as `XLimitMethod`, that only shapes the automatic value of its single `affectedPaths` entry and leaves every stored value unchanged. It is owner-local like the value/mode policies. As an editor policy, a property batch that edits it also requests that value's `Mode` as `auto` unless the batch sets the Mode or it is already known to be automatic. `axisWidth` resolves LineWidth -> GridLineWidth -> MinorGridLineWidth using audited defaults, automatic followers, and manual holds. Constructor arguments set explicit values and flags before follower synchronization; assignments update followers at each setter.

### Copied and relocated geometry

**Conditions to preserve**

- Copied configuration collapses reviewed Position aliases to one effective `Position` while retaining the full original source snapshot. Placement uses that frozen configuration, and copy verification checks placement changes, including offsets, rather than excluding them.
- Source relocation continues to retain the original alias statements. Source relocation reparses generated output and checks each requested placement before committing; an earlier Position overwritten by a preserved later alias cannot silently determine a different destination.
- Native-verified zero sizes remain valid for these alias families in both model validation and placement. Other families retain their existing size constraints.

**Explanation**

When a grid child moves to an absolute parent, the literal copy configuration omits ignored aliases and uses layout coordinates or supplied measured geometry. Source-backed Paste uses the supplied measured geometry.

## Property Inspector

### Defaults and Inspector rows

**Conditions to preserve**

- [`DefaultValueProvider`](../+yamada/+ui/+inspector/DefaultValueProvider.m) resolves implicit values without changing the document. The default-value probe never constructs the application being edited.
- Composite rows change presentation only; underlying property contracts remain independent. Source-only assignments that are outside the effective catalog surface are appended as read-only rows instead of being dropped.
- A `valueMode` row reuses the value property's singleton editor beside an Auto state button. It displays the member's stored literal rather than its effective value, derives Auto from the effective Mode, and commits through the batch route. Turning Auto off without a stored value setting also commits the value read from the Preview handle, which applies only explicit settings, and the planner places it before the Mode setting. The Auto callback locks the value editor before committing and unlocks it only after turning Auto off is accepted. An automatic Mode leaves the value state unknown without reason text, since the Auto button presents it. A Mode setting sequenced before its value setting makes the button read-only rather than moving source.

**Explanation**

The Inspector begins with `DocumentModel.getEffectivePropertyStates`, which joins catalog definitions with explicit instance entries.

`DefaultValueProvider` first uses catalog or MATLAB class metadata and then, when required, constructs one hidden, editor-owned fixture for the allowlisted factory and direct-parent context. The result is cached by MATLAB release and catalog surface.

[`InspectorSurfaceBuilder`](../+yamada/+ui/+inspector/InspectorSurfaceBuilder.m) projects atomic property states into deterministic singleton or declarative composite rows.

`RowHeight` and `ColumnWidth` have the `gridTrackList` editor capability, which marks them for the canvas overlay rather than a native Inspector row. The normal Grid Layout Inspector retains `RowSpacing`, `ColumnSpacing`, `Padding`, `BackgroundColor`, `Visible`, and `Scrollable`; the child Inspector retains `Layout.Row` and `Layout.Column` as the exact-value fallback.

### Position editing

**Conditions to preserve**

- Factory binding, transient draft capture, and stale-callback guards remain owned by the existing Inspector infrastructure.

**Explanation**

`PositionEditor` is one panel inside the existing Inspector row, containing four vertically stacked `NumericEditField` controls with left-hand X/Y/W/H headings and two vertically aligned link labels. `PositionEditor` derives constraints from the property policy and the related Orientation state, sets fixed-field tooltips explicitly, updates linked sizes locally, and forwards one complete numeric Position vector. Vertical sliders publish fixed-width handle affordances.

Shared boundaries: [Position geometry policies](#position-geometry-policies).

### Property transactions

**Conditions to preserve**

- Editors submit one or more changes through `PropertyTransaction`. The editor reconciles dependent values such as `Items`/`ItemsData`/`Value`, validates the candidate transaction with `PropertyBatchValidator`, and submits it to `DocumentModel.setPropertyBatch` for model acceptance. A batch that changes values produces one history record and updates the affected views; a rejected request does not partially commit.
- A requested change equal to the property's known effective value, from the Inspector or a dialog, is not an edit: `inspectorValuesCommitted` drops it before validation, so it adds no source setting and no history step even when the source has no assignment. A value with a different representation, such as a cell where the effective value is a character vector, still commits.
- A row whose value MATLAB defines but yamada could not read is read-only, with the reason as its tooltip: the property has no source assignment, no modeled upstream effect, no unsupported application status, and the `DefaultValueProvider` probe did not read it. Such a row indicates a catalog or probe defect; `CatalogDefaultProbeTest` requires the probe to read every editable property of every variant outside the figure tools. A value that is unknown because other settings may change it stays editable.

**Explanation**

[`PropertyEditorFactory`](../+yamada/+ui/+inspector/PropertyEditorFactory.m) maps an allowlisted editor ID to a native control or project-owned dialog.

[`InspectorView.reveal`](../+yamada/+ui/+inspector/InspectorView.m) centers a row by moving an empty label, a direct child of the Inspector scroll host, over the row's bounds padded to the viewport height, and scrolling to that label. Numeric `scroll(container, x, y)` is not used: on R2024a and R2024b it updates only the model `ScrollableViewportLocation`, while the client receives only `ScrollTarget`, so the view never moves. Component targets reach the client in every supported release, but from R2024a the client resolves them among the host's direct children only, so the nested row itself cannot be the target. Verified on R2023a, R2024a, R2024b, and R2025a. On R2023a and R2023b the component view model keeps the last location sent to the client; locations reported back after user scrolling update only the MATLAB model, and assigning the view model's current value again does not reach the client, so a repeated reveal of the same row would never move the view. When the resolved location equals the previous reveal, `reveal` nudges it by one pixel through numeric `scroll`, which reaches the client on those releases; the branch is gated by `isMATLABReleaseOlderThan("R2024a")`. Verified on R2023a and R2023b.

Shared boundaries: [Insertion proof and validation scope](#insertion-proof-and-validation-scope).

## Editing and View Synchronization

**Conditions to preserve**

- The editor uses stable component IDs for hierarchy selection and Preview mapping. View updates follow the accepted model change rather than reconstructing document state from UI handles.
- Insertion eligibility is determined from catalog metadata and the selected or nearest eligible parent. Deletion is explicit for any non-root component and removes only the source ranges the model owns; references in user-written logic do not block it.
- `GridChildPlacementPlanner` accepts only an editable literal placement of an immediate child, rejects new overlap and out-of-range targets, and returns one change set for `DocumentModel.applyGridLayoutEdit`.
- The model, not the Preview, owns source-coordinate geometry. The editor converts between the fitted Preview scale and source pixels and applies the catalog's component/style-specific resize constraint before committing a candidate.

**Explanation**

After an accepted model command, `yamada` coordinates updates to the affected hierarchy, palette, diagnostics, Safe Preview, Inspector, and command state.

Absolute canvas gestures keep a temporary candidate rectangle in editor state and commit one `Position` change on pointer release. A selected Grid Layout child instead uses the active-grid overlay: its cell-snapped draft is owned by HTML and a release sends a declarative move or span candidate for MATLAB-side validation.

## Callback Management

### Menu and dialog ownership

**Conditions to preserve**

- Context actions target the hit component without changing the editor selection.
- Dispatch checks document identity and component existence again, and hierarchy rebuilds reset the transient target.
- CallbackManagerDialog owns only its modal figure, scrollable rows, explanations, and injected state/action/validity functions.

**Explanation**

HierarchyContextMenu owns one shared native menu and a transient context target. Before R2023b a tree-level menu does not open over nodes and its opening event carries no hit node, as verified on R2023a, so those releases leave the tree without a menu and offer the same menu only from a Preview right-click; a menu per node was measured at four to five times the hierarchy rebuild time and is not used.

CallbackManagerDialog displays immutable CallbackState results from CallbackSourceAnalyzer. The effective catalog valueSchema.kind identifies callbacks without introducing special Inspector property rows.

The context-menu hit node comes from ContextMenuOpeningFcn.InteractionInformation.Node; it does not modify the editor's SelectedComponentId.

### Callback signatures and handler names

**Conditions to preserve**

- An empty callback event class name emits an untyped event, without a runtime audit-status flag or a universal event.EventData assumption. New stubs use the effective variant/parent definition; existing methods remain untouched. Type names are checked as identifiers and never evaluated.
- Every maintained ledger callback declares a nonempty identifier suffix, including unchanged naming cases; promotion preserves it and the loader rejects malformed supplied values. Older catalogs with an absent suffix retain the original callback-name rule. Creation and explicit component rename share this resolver.
- Rename recognizes both reviewed and legacy default stems under existing ownership checks, preserving collision suffixes and custom/shared handlers; Open, Reload and Save do not migrate method names.

**Explanation**

Callback event argument contracts originate in concrete development-ledger properties and are promoted as `metadata.callbackSignature.eventArgument` containing `className` and `shape`; source evidence stays in the ledger. `PropertyDefinition.CallbackSignature` is a validated immutable data value.

Callback handler naming uses the effective callback definition's direct `handlerSuffix` metadata.

Typed callback publication and Undo/Redo use the maintained source patch/index path, not AppSourceParser.parseText.

### Target eligibility and binding actions

**Conditions to preserve**

- Input constraints are textual data and user defaults and validators are never executed.
- Only directly declared fixed positional instance methods with one to three inputs are eligible. Two-input methods receive event data by convention; receiver-only methods receive no forwarded arguments. Ignored positional inputs (`~`) are retained in both method declarations and arguments blocks and count toward the same forwarding convention. Proven source/event type mismatches are excluded, while unresolved constraints remain marked unchecked.
- Callback binding safety is a separate query from exclusive method-body ownership. Connect and replacement modify only the assignment; Disconnect retains every method body, including newly generated methods.
- New validates an explicit name and creates its method plus assignment as one history step. Canceling the name popup does not dispatch a model command.
- Callback commands never delete method bodies; the model accepts only New, Connect, and Disconnect.

**Explanation**

Existing callback targets come from immutable `CallbackMethodSignature` values compiled with the lexical method layout. Editor patch projection retains signatures on unaffected methods and compiles only inserted method fragments; opening the manager reads this cache. Callback candidate labels omit the receiver class and retain MATLAB's argument-name-before-class order for other typed inputs.

The manager uses binding-only discovery and one target dropdown per callback.

All commands retain local patch publication and Undo/Redo without AppSourceParser.parseText.

### Callback source publication

**Conditions to preserve**

- A successful callback command publishes the exact resulting source and current bindings, clears its preparation records, and stores forward/inverse source patches with history. Every accepted command advances CurrentText and source positions together, so later commands do not replay pending changes from the opened snapshot.
- Original binding ownership remains available for Undo/Redo and stale-source rejection. Callback command preparation uses the maintained lexical/scope indexes and model validation; editor-owned publication rejects a missing proof rather than invoking the whole-source parser.
- The original input is never run; preserved expressions do not reach Safe Preview.

**Explanation**

DocumentModel.applyCallbackAction prepares typed immutable CallbackEdit records against CurrentText inside the command.

NewAppGenerator emits canonical bindings and English-documented stubs. CallbackSourceEdits supplies original-offset replacements to RoundTripGenerator, which combines common insertion anchors and rejects overlapping source claims. Reopening reparses the saved file and creates fresh ownership spans.

Shared boundaries: [Source publication and history](#source-publication-and-history).

### Callback revision checks

**Conditions to preserve**

- Name reservation includes inherited `handle` members, actual generated members, and existing user members. Callback dropdown commands retain the listed model/source/catalog revision and refresh instead of dispatching if it changes, including while the name prompt is open. Commit reuses the listed ownership and target values; newly supplied method names still require identifier and member-collision checks.
- Source publication and Undo/Redo refresh the edited owner's states and carry unrelated states and diagnostics forward; they preserve the existing independent-value publication boundary. Catalog/template correctness and retention of unrelated method bodies are implementation contracts, not whole-document checks repeated at each command.

**Explanation**

`CallbackSourceEdits` owns callback registration and new handler templates. New three-input stubs use `@app.Handler`; eligible existing two-input and receiver-only methods use inert forwarding wrappers. Catalog event signatures and handler suffixes drive new method generation. The default close binding is infrastructure: New creates a handler containing `delete(app)`, and Disconnect restores the fallback while retaining the method body. The current management UI dispatches only New, Connect, and Disconnect.

Callback lists and eligible method targets are prepared by `DocumentModel.callbackStates` and `callbackTargets` for an exact model/source/catalog revision. Callback commands apply `CallbackSourceEdits` directly through guarded source patches, rather than running general source generation and whole-document model validation.

All generation paths use `CallbackSourceEdits`, while existing registrations are preserved as source during localized edits and reparenting.

## Safe Preview and Canvas Overlay

**Conditions to preserve**

- `PreviewRenderer` creates only registered factories, applies editable literal values permitted by each `PreviewPolicy`, skips source expressions and callbacks, and reports individual construction or assignment failures as non-executing diagnostics. Certain literal effects of recognized axes setting calls are replayed in source order under the same rules as an assignment to the same property; the call itself is never executed. Reusing a control does not make its native state authoritative for source generation.
- All pointer events, hit targets, and Grid Layout measurements use canvas-local pixels.
- Editor window resizing repositions the fixed-size canvas without changing the document. Source-backed root positions remain noneditable.
- The HTML/SVG layer never mutates the document directly. MATLAB rejects actions with a stale revision, a mismatched active grid, unsupported source ownership, or an invalid final placement. The sending and receiving code in `EditorInteractionOverlay.html` and `yamada.m` must agree on the overlay `Data` structure and event format.
- Tab content geometry is published only after observed layout values stabilize. Inactive-tab child outlines are omitted, and the active tab selection remains disposable Preview state unless a supported model property is explicitly edited.
- MATLAB handles the Preview-to-source scale, component-specific resize constraints, and candidate geometry during a gesture. The completed gesture is then committed as one change to `DocumentModel` and the undo/redo history. The HTML overlay and Preview handles are disposable presentation and input state; neither is the authoritative document state.

**Explanation**

[`PreviewRenderer`](../+yamada/+ui/PreviewRenderer.m) projects model state into disposable editor-owned controls. Native menu and toolbar families are currently not rendered on the Preview canvas.

The outer Preview panel keeps a light native heading; its child is a dark-gray scroll host. The renderer adds a padded dark content panel so all four edges of the figure remain distinct from the scroll bars at their limits. Two fixed dark dividers mark the viewport boundary next to visible native scroll tracks while the canvas extends beyond the viewport. The renderer places an unscaled canvas at the root `UIFigure.Position(3:4)` client-area size, uses the figure's supported `Color`. The scroll content encompasses the figure and visible component bounds, with room for resize handles. The transparent HTML overlay is a sibling of the figure frame in that content, so component outlines remain selectable outside a shrunken figure. The canvas itself continues to clip native controls at the actual UIFigure boundary. The overlay's `surfaceBounds` describes its extent in canvas pixels; SVG viewBox and HTML layer offsets preserve those coordinates when the editing area extends beyond the canvas. The frame gives the canvas a one-pixel border on each side. Eight root resize handles remain available when the root has an editable literal Position, including an empty document. West and south root drags also update the screen origin to anchor the opposite edge. A disposable HTML guide is placed in the scroll content during a root drag, so its dashed proposed bounds can extend beyond the current canvas. The guide disappears when the gesture ends; the overlay shows no size label.

The renderer returns a map from stable component IDs to disposable Preview handles. `yamada` uses this map to build the transparent [`EditorInteractionOverlay.html`](../resources/EditorInteractionOverlay.html) `uihtml` layer. MATLAB sends source-derived component outlines, selection state, and Tab Group information to the overlay. For the nearest selected Grid Layout, `GridLayoutOverlayDataBuilder` also publishes versioned public Preview geometry, track headers, immediate-child occupancy, and editability. The HTML/SVG layer owns pointer capture, outlines, resize handles, tab-selection hit targets, and temporary grid drafts, then sends declarative pointer or grid actions back to MATLAB.

Canvas selection, drag movement, eight-direction resizing, and Tab Group selection use `resources/EditorInteractionOverlay.html`, which is loaded as a transparent `uihtml` layer. The native Preview components do not process these editing gestures directly.

- `yamada.m` sends the canvas dimensions, component IDs, display positions, outline shapes, selection state, and tab information to HTML through `InteractionOverlay.Data`.
- The HTML renders SVG outlines and resize handles, converts DOM coordinates to a bottom-left origin, and sends the pointer phase, coordinates, target ID, and handle type back to MATLAB through `sendEventToMATLAB`.

Related interaction tests are in `tests/unit/EditorInteractionTest.m`.

Shared boundaries: [Geometry invalidation](#geometry-invalidation) and [Preview Layout Completion](#preview-layout-completion).

The geographic limits call catalog captures its requested latitude and longitude as separate source arguments of the same call. Safe Preview pairs those arguments by their source occurrence and invokes the allowlisted geographic limits operation in initialization order. Automatic and manual calls are separate operations. MATLAB computes the displayed limits from the preview geometry; the displayed values are never treated as source arguments. The Inspector edits both requested intervals inline and shows the displayed extent read from the Preview axes under each field. An edit to either field writes both arguments of one call; when no call exists yet, the fields start from the displayed extent, so the untouched interval keeps what Preview currently shows.

### Preview synchronization

**Conditions to preserve**

- `PreviewRenderer.synchronize` handles ordinary property requests across all catalog variants without component or property allowlists. Invalidation membership and setter ordering are distinct graphs.
- Safe Preview never installs callback bindings. `PreviewRenderer.acknowledgeCallbackChanges` accepts a new input version only when every visual input and the registry version remain identical; CallbackEdits is the sole excluded source-intent field. Simultaneous visual/source/structure changes cannot be hidden by callback acknowledgement.
- `PreviewRenderer.acknowledgeRenameChanges` compares complete input snapshots while allowing only component record names and RenameEdits to differ; identities, order, hierarchy, properties, source text, and the catalog revision must still match. Visual property settings remain in the strict comparison. Unrelated changes retain the full refresh fallback.
- Preview-skipped settings do not trigger native assignments.
- Reconstruction preserves unchanged sibling handles, native stacking/tab order, and transient tab selection; failure to restore a native child order escalates reconstruction to its enclosing scope. Unrelated source or hierarchy changes, untracked values, and registry changes retain full reconstruction. Preview reconstruction boundaries preserve the accepted model and do not introduce a reset UI or a second document-edit trial.
- `PreviewRenderer.synchronizeStructure` updates the existing surface only after component insertion, Paste, or reparenting has been accepted. It renders the accepted root subtree under the existing parent handle and, for a move, first deletes the subtree's old handles. Delete and Cut keep full reconstruction.
- The structural path applies only when the rendered inputs, surface, root, and registry revision are current, combined configuration and unresolved execution are absent, and the root is the last child of its parent. Menu, toolbar, colorbar, and context-menu roots, documents with a colorbar, release-unavailable, Button Group, or Tab Group parents, and Grid parents with a non-literal child `Layout.Row` or `Layout.Column` fall back to full reconstruction. Any native failure also falls back.

**Explanation**

`PreviewUpdatePlanner` derives a local dependency closure from the catalog and resolved implicit effects, compares public native values only in that closure, and orders final writes. Range and selection policies supply valid intermediate states for disjoint old/new domains; automatic modes, group selection, grid-child placement, and final child geometry reuse existing model resolution. Figure-root size/color use the existing panel-based Preview surface adapter; figure window chrome is not represented by that surface.

Callback commands and their history operations use a source-only update path. The editor refreshes Inspector/diagnostics/save/history/availability and existing overlay command revisions without reconstructing controls, measuring rectangles, solving boundaries, or rerendering HTML regions.

Validated component-member renames use the same source-only view refresh. The shell updates hierarchy labels, the root preview panel title, and existing drop-target names without replacing native controls or geometry. Rename Undo/Redo replays the primary identifier patches and projects existing positions before refreshing these views.

Asset adaptation uses the same catalog policy in full and incremental rendering; clearing a local image uses the native empty text value. R2024a UIFigure-incompatible setters such as panel ShadowColor remain source-only with ledger observations. Unresolved local effects and native assignment failures reconstruct the affected ownership subtree through the established safe renderer. Grid/ButtonGroup dependencies enlarge that subtree as needed.

### Geometry invalidation

**Conditions to preserve**

- Heterogeneous atomic updates carry exact component/property pairs in `RefreshRequest.forChanges`; another component's property with the same name cannot be hidden by a union of paths. New performance work must cover the full capability: a minimal initial test does not justify retaining component/property allowlists after that initial stage.
- Group equality, generated runtime entries, and contributed parent-context properties preserve both `gridGeometryImpact` and `absoluteGeometryImpact`. `geometryEvidence` remains development-only and distinguishes documented facts, inference, and runtime observations.
- Missing metadata defaults to full refresh. `affectsDisplay` and initialization independence do not prove geometry stability. The development review script classifies common mechanisms conservatively; unknown properties keep full refresh. Existing setter reuse eligibility is separate from geometry classification.
- Reparent availability and operation revisions still advance; HTML retains regions and updates existing event revisions without rerendering. Pending native layout, unavailable measurements, selection or structural changes, and full Preview reconstruction retain the normal measurement path.

**Explanation**

Inspector, visual grid editing, and completed position gestures use the same property update path.

The development ledger owns two geometry capabilities per component property: `gridGeometryImpact` (`none`, `fit`, `required`) and `absoluteGeometryImpact` (boolean).

`RefreshRequest.affectsGeometry` resolves these capabilities through the effective catalog and actual placement. Fit-dependent properties inspect applied row/column settings of native grid ancestors without reading pixel rectangles. Safe incremental setters with unchanged geometry reuse measured component bounds, grid boundaries, selection frames, and pointer regions.

### Tab visibility and overlay revisions

**Conditions to preserve**

- On a Tab switch the editor immediately removes controls belonging to the hidden Tab, then refreshes settled geometry. Visibility must be checked through every enclosing Tab Group; a selected grid on a hidden Tab does not remain active on the canvas.
- Overlay publication reserves one revision before native layout can reenter the update. Every overlay payload section uses the reserved revision. A superseded overlay update discards its result instead of overwriting newer geometry; stale incoming actions still fail the revision check.

**Explanation**

Preview geometry may change after an initial Open or Tab switch. The editor publishes an initial overlay and schedules a bounded refresh after visible grid and child rectangles stabilize, including when no grid is selected.

### Current source ownership and visual invalidation

**Conditions to preserve**

- A setting's legacy `SourceSnapshotId` is allocation provenance, not a guard for current offsets; current source revision and exact expected patch text provide that guard.
- A source-only callback/rename acknowledgement or property diff requires an exact published history transition and an unchanged tracked input stamp; it then compares visual inputs without source coordinates. Unrelated model/catalog/source writes still reject reuse.
- Catalog geometry effects continue to decide bounds, measured rectangles, selection outlines and click-target updates.

**Explanation**

`PropertyCheckpoint` and its second editable source model have been removed. `PropertySetting` stores the current explicit source value and stable occurrence/statement/scope IDs; `PropertyEntry` projects that setting and resolver results supply effective values. `Origin` records provenance, while `SourceOwnership` tests actual current factory ownership. Copy reuses current indexed statement ranges to capture the selected subtree’s owned initializer fragments.

Preview invalidation distinguishes current source-coordinate changes from visual model changes.

### Grid Layout Visual Editor

**Conditions to preserve**

- Preview and HTML are disposable views of the document state.

**Explanation**

The editor follows one model-to-canvas-to-model flow. `DocumentModel` holds track values and child placements. `PreviewRenderer` draws disposable MATLAB controls from that model. `GridLayoutOverlayDataBuilder` combines model values with the controls' realized geometry into a versioned payload. The HTML overlay draws the grid UI and sends a proposed action to `yamada`, which validates it and commits one model change before updating the Preview. The Inspector edits ordinary component properties alongside this canvas workflow.

#### Selection and editing context

**Conditions to preserve**

- `SelectedComponentId` drives the hierarchy and Inspector; the nearest selected Grid Layout (`ActiveGridId`) drives track controls. Selecting a nested Grid Layout enters that grid's immediate tracks and children.
- Selection targets for visible grid-managed children are published independently of the active grid. Selecting a child changes view state only.

**Explanation**

Without independently published child targets, an opened document, which initially selects `UIFigure`, could not select a grid child from the canvas. Transparent targets are painted from outer to inner grids in one background layer so descendants win hit testing without covering active child controls or track settings.

The editing surface reserves space around the active grid for its row and column settings buttons. Headers and their popovers use the editing surface bounds, including the dark area outside UIFigure, so full-figure grids and stranded grids retain their settings controls. The buttons sit outside the grid edges, distinct from the figure resize handles.

#### Track and child edits

**Conditions to preserve**

- The Inspector remains focused on the selected component. The HTML popover owns only the draft. MATLAB validates the submitted action and `DocumentModel.applyGridLayoutEdit` commits a structural edit with all affected child placements as one Undo step.
- Expression-backed tracks or placements remain locked when source ownership cannot be proved.
- Inserting or deleting a track remaps explicit immediate-child placements in the same transaction. Deleting a track occupied by a single-track child is rejected rather than moving or deleting that child implicitly.
- Existing overlaps are preserved, while a canvas drop that would create a new overlap is rejected; exact Inspector placement remains available for intentional overlap.

**Explanation**

`RowHeight` and `ColumnWidth` use the compact canvas settings controls; spacing and padding stay in the ordinary Inspector. Track editing uses explicit Fit, Fixed, and Flexible modes instead of dragging a boundary, because a pixel drag would silently convert a fit or weighted track to a fixed size.

#### Geometry and interaction

**Conditions to preserve**

- When geometry is ambiguous, `GridLayoutOverlayDataBuilder` withholds geometry-dependent editing instead of publishing a plausible but incorrect boundary.
- An unoccupied `fit` track can have zero extent without losing its logical index. The overlay keeps its settings control addressable and supplies a temporary drop band during a child move; that band changes neither the Preview grid nor source.

**Explanation**

R2024a exposes the grid and rendered controls' public geometry, but not the realized rectangle of every track. `GridLayoutOverlayDataBuilder` reconstructs track boundaries from literals, spacing, and settled Safe Preview measurements. For `fit` measurements it prefers a direct child's `OuterPosition`, which can include decorations omitted from its control-body `Position`; selection hit targets still use the visible child's ordinary bounds. This distinction matters for controls such as Range Slider, whose narrow body understates the height required by its row. `OuterPosition` is still not a grid-cell measurement, so this reconstruction is not guaranteed to align every separator exactly. Adding invisible nested `uigridlayout` controls as cell probes was tested and rejected: in a populated R2024a grid they changed the native layout and did not reliably occupy the requested cell.

Span-handle drags begin from the handle even when it overlaps spacing or padding. The moving edge snaps at the midpoint between valid track edges in either direction, independently of the perpendicular axis.

## Preview Layout Completion

**Conditions to preserve**

- The editor applies native Preview changes and the surrounding MATLAB UI changes before awaiting `yamada.ui.waitForPreviewLayout`. After layout completion, the editor collects one Canvas-relative native snapshot, shares it between component bounds and Grid overlay consumers, computes the outer workspace placement, and publishes the final geometry once. The fixed pixel Canvas and all size-changing native writes must be established before this wait: the promise alone does not guarantee delivery of a pending operating-system Figure resize notification.
- Catalog geometry policies retain the existing snapshot for changes that cannot affect geometry. Reentrant changes invalidate the older generation; a completed response never publishes an obsolete snapshot.
- Source offsets are published immediately by the source transaction and do not depend on native layout completion. Owner projections are validated together before the transaction-only publication method applies changed fields; equal-length literal changes still update live bindings.
- The adapter does not execute opened app code. Do not replace layout completion checking with a fixed delay or assume that `drawnow` alone completes Web layout. Adapter failure or pending/inconsistent Grid geometry explicitly retains the legacy bounded geometry-recovery path; the one-pass contract applies to successfully settled geometry.
- Before supporting another MATLAB version, verify controller access, event ordering, completion and timeout cleanup, and representative fit layouts, nested grids, tabs, axes, HTML, icons, images, tables, and text areas.

**Explanation**

Preview comparison retains the preceding normalized projection, while current input capture and checks for unrelated changes remain in place.

`waitForPreviewLayout` delegates to the bundled `waitForFigureLayout`, which reaches the figure window through an **undocumented route**: the figure controller's CEF window, the client `ViewModelManagerFactory` and `ControllerService` modules, and a token-matched reply dispatched as an event on the figure ViewModel, with a bounded MATLAB-side timeout; failures before the figure ViewModel is found are reported on the MATLAB message service. Because the reply travels on the same ViewModel channel behind the client's position notifications, MATLAB has handled every notification sent before it when the wait returns, so MATLAB-side positions are read rather than browser DOM rectangles. Inside the window, `+yamada/+ui/+layoutwait/waitForFigureLayout.js` wraps each container controller's `emitContainerResizeControllerEvent` to record when a container last told its children that its client area changed; a call that hooks new controllers treats that moment as the last resize. The controllers come from the `_controllerCache` of the figure channel's `ControllerService` instance, which is a plain object holding every controller of the figure in R2023a through R2026b. The reply's `hooked` and `watched` fields report the controllers newly wrapped and all wrapped controllers. The layout script then waits until no such resize has occurred for 220 ms, bounded at 3000 ms, waits for pending image loads, awaits the root ViewModel `stabilize()` promise where it exists (from R2023b), and replies after the next animation frame; the other browser-side waits are bounded at 500 ms, the same bound MATLAB's own R2023a UI-test gestures use before acting. The quiet period is required in every release from R2023a through R2026b: Grid Layouts handle the parent `containerClientAreaSizeChanged` event through `lodash.throttle(handler, THROTTLE_DELAY, {leading: true, trailing: true})` with `THROTTLE_DELAY` 200 ms, so the trailing relayout and the position notifications it sends run on a timer that neither `stabilize()` nor an animation frame observes. The 220 ms value is that delay plus a margin. The bundles are `toolbox/matlab/uitools/divfigurejs/release/bundle.mwBundle.gbtdivfigure.js` and `toolbox/matlab/uitools/figureuicontainerjs/release/bundle.mwBundle.gbtfigure_uicontainer.js` in R2023a through R2024a, and `toolbox/matlab/uitools/figurelibjs/release/bundle.mwBundle.gbtfigure-lib.js` from R2024b. The animation frame runs after the frame callbacks in which Grid Layouts relayout their children, and the image wait covers icon and image loads that resize fit layouts. The route was verified on every release from R2023a through R2026b with fit content, tables, axes, HTML, tabs, nested Grid Layouts, icons, images, and text areas.

Do not use the figure controller's `_controllerMap`, which is absent in R2023a and R2026b.

The layout completion reply must report a positive `watched` count for any figure with a container.

The library is vendored from [waitForFigureLayout](https://github.com/NOBUTOKA/waitForFigureLayout) at a released tag. Update it with `git subtree pull --prefix=+yamada/+ui/+layoutwait --squash https://github.com/NOBUTOKA/waitForFigureLayout.git <tag>` and retain the subtree merge commits when integrating the PR. The Toolbox input list explicitly includes the bundled runtime and license.

Before supporting another MATLAB version, search its figure client bundle for the Grid Layout controller's `containerClientAreaSizeChanged` listener (stored as `_throttledHandleParentSizeChanged` from R2025b) and for `THROTTLE_DELAY` in the `gbtshared/util/EventSupport` module it imports, and update the constant upstream in `waitForFigureLayout` if the delay or the throttle options changed.

Before supporting another MATLAB version, also verify controller access, event ordering, completion/timeout cleanup, and those layouts again.

### Figure host compatibility

**Conditions to preserve**

- Run layout completion only through a verified figure host and retain bounded recovery when the required host is unavailable. Before widening release support or changing the adapter, verify layout completion and the editor in a desktop session as well as batch tests.

**Explanation**

The wait needs a figure with its own CEF window, which the figure controller's `PlatformHost` exposes as `CEF` only on `CEFFigurePlatformHost`. Under `matlab -batch`, and in the desktop through R2024b, every uifigure has that host. From R2025a the MATLAB desktop hosts uifigures with `DivFigurePlatformHost`, which renders the figure inside the desktop's own page; MATLAB has no handle that runs scripts in that page (`webwindowmanager` lists no window for it, and `uihtml` iframes there use a separate `mwext://` origin), so the settle script cannot run there. The editor figure is therefore created by `yamada.ui.createEditorFigure`, the one adapter for this difference: before R2025a it calls `uifigure`; from R2025a it calls the internal `matlab.ui.internal.uifigureIsolated`, which sets the figure's `IsIsolatedRequested` capability so that `FigurePlatformHostFactory` chooses `CEFFigurePlatformHost` whenever the local client is available, and it falls back to `uifigure` if that call fails. Because the editor figure is no longer created by a `uifigure` factory call, `yamada.m` is not an editable yamada document: it parses without execution but has no registered root, and editing yamada with itself is not supported. The isolated host and the unchanged settle script were verified in desktop sessions of R2025a, R2025b, R2026a, and R2026b, including a resize burst inside the Grid Layout throttle window, and `uifigureIsolated` is unchanged across those releases. The regular suite runs under `matlab -batch`, where every figure already has its own window, so it cannot detect a desktop-only regression.

`waitForPreviewLayout` detects the host rather than the release and raises `yamada:PreviewLayout:NoFigureWindow` for a host without a CEF window, which retains the legacy path with the `yamada:PreviewLayout:Fallback` warning. Tests that call the wait create their figures through the adapter. Before supporting another MATLAB version, or after changing the adapter, run `tests/unit/PreviewLayoutStabilizationTest.m` with `runtests` from a desktop session of that release and launch the editor there to confirm that no `yamada:PreviewLayout:Fallback` warning appears.

### Isolated Figure Implementation

**Conditions to preserve**

- Check the CEF creation path separately when comparing desktop and batch behavior on R2025a through R2026b. Verify docking, focus and activation, and close handling in desktop MATLAB when changing the adapter, particularly keyboard shortcuts, activation-triggered external source checks, and return from file dialogs.

**Explanation**

In the installed Windows MATLAB releases R2025a through R2026b, both `uifigure` and `matlab.ui.internal.uifigureIsolated` call the same internal `uifigureImpl`. The public entry point checks the first supplied argument and passes `false` as the isolation flag. The internal wrapper passes `true`, so the shared implementation sets `FigureConfigurations.isIsolatedRequested`. Both routes use the same app-building defaults, Figure model, and `FigureController`. The controller forwards the isolation capability to `FigurePlatformHostFactory`. A local, non-embedded figure with that capability selects `CEFFigurePlatformHost`. The public `WindowStyle="normal"` controls window presentation and can also produce an undocked DivFigure.

In R2025a and R2025b, the CEF window constructor has no isolation argument, so an isolated desktop figure uses the same CEF creation implementation as a normal `uifigure` that selects CEF under `-batch`. In R2026a and R2026b, isolation is also considered inside the CEF host. An isolated figure creates its CEF web window directly. A non-isolated CEF figure can use the popup/proxy path when the release-specific feature and runtime conditions allow it.

The host owns docking, focus and activation, and close handling for the editor window. Native pickers such as `uisetcolor` can activate the MATLAB desktop when they close, so every caller returns focus through `yamada.ui.DialogFocus.restore`, which raises the editor before the dialog that opened the picker; focusing a modal dialog alone leaves the editor behind other applications.

## Source Transactions and Incremental Evaluation

### Source publication and history

**Conditions to preserve**

- Undo/Redo project the inverse/forward patches through the same source indexes. `recordHistory` and `publishParsedSource` require an exact, current candidate for editor-owned commands; a missing proof rejects publication instead of silently falling back to whole-source parsing.
- User history keeps primary source patches and semantic edits, never a candidate document handle or a transient full source result. Property Undo/Redo derive state from primary patches, reuse only unaffected dependency scopes, and preserve the full validation baseline after checking the changed scope; derived state and position snapshots are not added to user history.
- `DocumentValidationProof` guards the catalog revision, complete component/value join and source positions, then maps occurrence and creation references onto live IDs without adopting a candidate context or component handle. Saved-source line-ending normalization is mapped onto current history coordinates. Stale or untracked inputs retain the existing validation route.

**Explanation**

Supported literal replacements and insertions use `SourceLiteralTransaction` and `IndexedSettingEdit`, deriving current settings, statements, method membership, and execution events from known edits rather than rediscovering them by parsing the edited body. `SourceLocationUpdate` is the common writer for surviving positions; statement code offsets are relative to their statement.

Structural commands prepare independently validated candidates using the loaded lexical, scope and initialization-call indexes. `EditorSourceProjection` rescans changed statement windows, compiles only newly inserted callback methods, and retains established call expansions and opaque boundaries.

`DocumentValidationProof` carries independently validated definitions, effective states and diagnostics across exact source publication, indexed candidates and confirmed saves.

Component insertion, deletion/Cut, callbacks and reparenting also publish their exact editor-owned patches and current bindings without reparsing the class.

### Canonical setting identity and indexed literal edits

**Conditions to preserve**

- Positive integer IDs remain stable across value replacement, position projection, and Undo/Redo. Deleted records leave tombstones; `NextId` is a high-water mark that history does not rewind. Negative IDs are temporary tokens for detached records and are replaced before registration in the canonical store.
- Initializer event order is separate from physical source order: it includes creation, assignments, method calls and returns, certainty, and opaque boundaries. Method calls retain their callee return boundary; a statement inserted after a call executes after that return, not inside the callee.
- Unchanged source text, statement-local code offsets, method membership, and source provenance remain independent values.
- Numeric IDs alone do not identify a setting across documents or Reload: snapshot reuse and raw subtree copy also check source provenance, and candidate resolutions explicitly map their references back to the owning document. Imported canonical IDs are reserved before detached additions receive new addresses, including when materializing a structural candidate.
- Paste publishes independent value materializations of validated candidate records; a candidate-owned component or property handle must never be registered as a second live document owner.
- Ordinary source-property history does not retain complete Settings arrays, source-position updates, execution sequence updates, or derived indexes. Position shifts, statement membership and execution numbering are derived from primary source patches, rather than stored as independent Undo operations.

**Explanation**

`SourceSettingStore.Records(id)` is the canonical value-record address space for one live document. A separate `Active` vector describes membership in the current store, rather than an intrinsic property of an immutable setting value that can also appear in historical or detached snapshots.

Each component retains its owned ID list, while `SourceOrder` independently orders active IDs by physical statement and value-token positions. Source parsing establishes these facts and insertion trivia once. Known literal edits splice new statements into the physical and execution indexes and transform existing positions in batches.

`PropertyState.LastSettingId` and `EffectSettingId` are numeric occurrence references. `EffectKey` separately represents the generalized cause of a value, including creation and pending effects that are not Settings.

Ordinary source-property history retains exact forward/inverse source patches, edited occurrence guards, added/removed identities, old/new typed primary values, and insertion recipes. Typed values avoid decoding source during history replay. Both directions use the same indexed edit mechanism. Document-dependent literal policies can validate an independent candidate model before publication without reparsing its known source edits. Structural history additionally retains detached subtree values or command-specific semantic changes needed to restore the model.

The temporary-token allocator retains only a scalar counter, never a persistent map of closed documents or source revisions.

### Canonical settings and derived positions

**Conditions to preserve**

- `PropertySetting` remains a value class. Bound `ComponentRecord.Settings` exposes a revision-guarded derived value view; detached components and materialized snapshots retain independent values. Deleted canonical addresses are tombstones and are never recycled into another occurrence.
- All owner freshness checks precede publication; unchanged payloads and identities remain immutable values. Constructor-pair order uses physical source order, independently from canonical IDs and execution order.
- Derived Undo/Redo updates are never separate history entries. Other structural, callback, reset, and unsupported coupled command schemas retain their command-specific proofs; component paste and identifier-only rename use the indexed publication contracts below.
- The local source transaction verifies input-clock ownership/revision before publication; the evaluation context also checks catalog identity/revision and tracking. The view accepts a local source transition only for the exact preceding token and all changed paths, then normalizes only the changed owner. Public `inputs()` results retain value independence. Direct writes, foreign document clocks, mutable/untracked data, and unsupported source transitions use the existing complete capture/comparison route.
- Position-only publication does not reapply literal values or kinds. Current source and all positions are still updated immediately; this optimization does not defer source generation or weaken setter/order validation.

**Explanation**

The canonical address, membership, and history contracts are defined in [Canonical setting identity and indexed literal edits](#canonical-setting-identity-and-indexed-literal-edits). The private document store maintains five source-range indexes (`SourceSpan`, `ValueSpan`, `NameSpan`, `PairSpan`, `ScopeSpan`), component ID lists, and physical source order.

Source-position preparation groups component, setting, and property ranges into one vector transform over the atomic patch batch. `IndexedSettingEdit` updates only the edited owner's primary setting records, while maintained numeric maps project existing statement positions, execution visits, return boundaries, and subsequent sequence numbers. It does not rediscover unchanged settings from the source body.

Undo/Redo applies exact primary text patches, reuses the stored typed before/after values and insertion recipes, restores occurrence identities, and derives positions, sequence, indexes, diagnostics, and evaluation inputs through the same indexed edit path. Save As rebases primary source patches.

A validated local source command carries its prepared position projections into the preceding value-only `EvaluationContext` key. Only the edited component is captured again; unchanged component values remain independent shared MATLAB values, and prepared positions replace their location fields. The same route supports source-property Undo/Redo.

`PropertyEntry.applySourceSetting` also computes its final result first and assigns only changed fields, merging source metadata once.

### Local property preflight

**Conditions to preserve**

- Reuse a local preflight proof only for the exact semantic inputs and catalog revision that passed complete generation, parsing, and validation.
- The shared preflight plan is materialized as an independent document before mutation; partial insertion plans do not substitute for a complete proof. The live file path is restored for relative resource interpretation.
- Eligibility comes from the catalog and literal contract rather than component or property allowlists. Independent editable settings need reviewed independence, no ordering/effect dependencies or additional cross-property constraints, a known source-owned literal occurrence, valid batch values, and exact literal encode/decode equality.
- Numeric `Value` settings use the modeled `numericValue` policy and the complete known constraint transaction for every registered implementation of that policy.
- Layout-changing settings on components with children retain complete source preflight; unresolved effects, missing spans, stale inputs, unsupported representations, and physical line breaks in unproven syntax also retain the full path.
- A failed private update restores its previous values. Public configurations and older results remain independent, history records remain atomic, and save continues complete generation and verification. Input application classes and callbacks are never executed.

**Explanation**

A complete matching configuration proves owned existing occurrences across components and paths, so switching the selected component or property alone does not require another whole-source trial.

Local property preflight may reuse either its private checkpoint or an already cached `combined` configuration that passed complete generation, parsing, and validation for the exact current semantic inputs and catalog revision.

### Complete emission proof reuse

**Conditions to preserve**

- A reusable complete-emission proof must validate the complete output and match every pending literal. Partial placement plans, live records, and externally mutable candidates do not establish that proof.
- A failed joint candidate retains the established per-owner placement search. Deleted or relocated source, callback edits, and rename edits retain their existing proof paths.
- Public generation still validates its inputs before reusing a complete emitted-source proof; tentative generation cannot take that shortcut. Combined configuration may reuse an independent parsed document only when both its original source and the recorded complete emission equal the newly generated output.
- Input or catalog changes discard the emission proof rather than inheriting it with ordinary resolver values.

**Explanation**

When multiple parsed owners need inserted settings alongside generated components, the insertion planner tentatively chooses their owned placements and emits the complete post-addition source before validating it once. A friend-only method on the value-class `RoundTripGenerator` receives these temporary plans; public generation retains input validation.

A batch that emits and validates the complete post-addition source may retain that exact string in the current evaluation context.

The insertion planner must reparse the complete result and match every pending literal before retaining a `combined` configuration. No partial candidate, live component record, or externally mutable plan substitutes for the complete proof. Partial placement plans do not authorize either shortcut.

### Insertion proof and validation scope

**Conditions to preserve**

- Exact document inputs and the catalog revision still determine the evaluation context; an absent proof runs the existing placement search and validation. Public `PropertyInsertionPlanner.plan` results retain independent mutable documents and component records, including after generation has reused their cached edits. Insertion-proof reuse applies to every eligible owner and setting without factory or property allowlists; partial placement proof does not imply a complete emitted-source proof.
- `DocumentModel` owns acceptance of property requests before live mutation. Validation must preserve source ownership, supported intermediate-state rules, and the requested effective result; a valid final value alone cannot hide an earlier invalid assignment or a later setter that overwrites it. Rejected requests leave live values and history unchanged. The resolver supplies independent value results; consumers must not expose shared mutable candidate records or mix offsets from different source snapshots.
- Insertion validation checks values and setter order for the component and necessary hierarchy context. Catalog selection, placement, and reference policies include the parent subtree when siblings may change. Structural checks remain document-wide. Arbitrary user-code effects remain outside this proof.
- Pending scopes cannot justify another proof until consumed; source, history, external writes, or catalog changes invalidate them. Public generation and saving retain their validation paths, and parsed checkpoints remain private value snapshots rather than shared public model handles.
- Parent-before-child creation, deferred component references, and final root visibility remain separate generation responsibilities. Relocation retains all original setting occurrences; copies receive fresh setting IDs and ownership instead of reusing source offsets.
- Direct, certain subtree relocations splice the emitted initialization statements into the existing lexical and execution indexes. Unmoved statements and settings retain their identities and receive positions from the patch transform. The relocation planner supplies the owners to rebind. Other relocation shapes use the general editor projection.
- Saved output uses the separate `SavedSourceCheckpoint` described below, leaving the original edit basis and Undo/Redo intact.

**Explanation**

Retrieving cached edits does not materialize an unused parsed document for each owner.

[`PropertySourcePlan`](../+yamada/+source/PropertySourcePlan.m) supplies the source-placement configuration used by effective-state consumers, keeping original setting identities separate from candidate configuration identities.

Post-commit validation distinguishes a complete matching diagnostic proof from a pending bounded scope. With a proven complete baseline and catalog-modeled effects, a newly inserted setting schedules the component and its hierarchy context for validation instead of reevaluating unrelated property states. The validator reports checked identities so the document can retain unaffected diagnostics, discard replaced ones, and preserve component ordering. Independent local replacements keep their existing proof reuse.

Per-property effect classifications, evidence, and unresolved audit reasons are maintained in the release-specific [application effect review](../dev/component-data/R2026b/APPLICATION_EFFECT_REVIEW.json).

Generation consumes only the value-only edits of a successful insertion proof through a generator-restricted planner entry point.

### Incremental Evaluation Inputs

**Conditions to preserve**

- Limited parsing never establishes a whole-document validation baseline. Candidate-only states are not treated as complete document-dependent states.
- Changed dependency closures touching layout, ancestor geometry, or unsupported coupling retain the established broader validation path. Registry changes, management-free writes, missing baselines and unresolved proofs invalidate this reuse. Unchanged Grid configuration and unresolved-effect results are inherited only when their semantic dependencies are proven unchanged; pixel geometry and fit measurements keep their separate catalog-driven invalidation.
- After all freshness checks succeed, the same prepared source, settings, effective states and diagnostics are published together.
- Standalone callers without analysis retain the scanner-based path, and a supplied stale analysis is rejected.

**Explanation**

Full source parsing binds its completed model diagnostics and resolved states to the final input and catalog revision. For eligible local literals, `SourceLiteralTransaction` validates the actual emitted settings before publication, combines unaffected effective states from that exact baseline, and prepares the updated diagnostics.

`validatePropertyCommit` then publishes retained diagnostics rather than running semantic validation again.

Document-backed component separator formatting uses the exact `SourceAnalysis` snapshot and binary neighbor lookup in its immutable statement indexes. Only the inserted text and neighboring lexical fragment are scanned for formatting; the original full source is not lexed again.

### Owner validation and atomic batches

**Conditions to preserve**

- The ordered final states and affected schemas of owner-local effects are checked on detached owner values; unchanged document-dependent states come from the exact validated baseline. Implicit follower values and modes must advance with the edit even when they have no explicit source setting. Geometry, hierarchy, references and sibling selection retain their document-dependent proof.
- Atomic literal batches spanning multiple owners, including Grid track and child placement changes, use `SourceLiteralBatchTransaction`: plan every owner against the same source, update the shared statement/execution indexes once, and validate the combined final model before publication. History retains primary forward/inverse patches, typed values, insertion recipes and setting identities per owner; Undo/Redo derive positions and execution indexes from those patches instead of storing secondary position edits.

**Explanation**

`PropertyStateResolver.ownerLocalPaths` identifies reviewed finite effects that stay inside one component, including domain-backed values, text constraints, tick/value modes and width followers.

### Structural publication and validation footprint

**Conditions to preserve**

- Canonical state values and diagnostics outside the accepted edit footprint are retained, while dependent derived states are recomputed when needed. A change to catalog rules or document-wide unresolved-execution flags deliberately invalidates the wider affected state; this is not a reason to recheck unrelated structural invariants on every edit. Full `ModelValidator.validate` remains at source/model-loading boundaries, explicit Validate, and unproven builder fallbacks.
- Parent-dependent settings are removed or replaced as part of the relocation plan; final requested placement writes follow the owner's retained settings and precede its descendants' creation. Source positions, execution indexes and caches are derived from these primary edits and are not separate Undo entries.

**Explanation**

Editor-owned structural and dependent-property edits carry a known footprint through source binding and publication. `EvaluationContext.editScope` separates owners whose inputs need checking from owners whose derived states are invalidated. `ModelValidator.validateOwners` checks input schemas and affected local constraints; unchanged name/ID/root invariants come from the accepted edit plan.

Parent relocation compiles final root placement into the moved initialization block. The relocation candidate is bound once and published directly. The normal editor path does not regenerate the same candidate and then evaluate the document again to ask whether the requested placement survived. Grid structural edits similarly compile track and child-coordinate changes together.

### Indexed component paste and member rename

**Conditions to preserve**

- Component renames check the maintained member list, MATLAB identifiers, inherited members, and existing unresolved-reference restrictions. Only proven component references, exclusively owned default callback identifiers, and their help text are replaced.
- Declaration insertions occur after complete existing line terminators, preserving CRLF ownership. The resulting independent candidate receives model/value validation and frozen-copy checks before live publication. A prepared-only publication rejects missing or stale proofs rather than silently invoking the whole-source parser.
- Undo/Redo derives current spans, settings and execution indexes through the same local paths; these derived updates are not additional history operations. Save As may parse the saved source and rebase primary patches, while subsequent paste/rename history replay remains local.
- Direct model-builder literal writes are bound through local literal transactions before these commands; they are not mistaken for already published source. Initial document construction, opening, Reload and saved-source checkpoints retain their separate full-load responsibilities.

**Explanation**

Loading source records class member names and inert code/help masks in `SourceAnalysis`. Literal patches project these masks without interpreting the unchanged body. Current settings, scopes, source expressions, opaque regions and positions are projected through the primary token patches; unchanged literal values and execution events retain their validation. Invalid names are rejected before publication and use the existing red rename field and explanatory Tooltip.

Source-backed Paste emits new declarations and the copied initializer fragments in execution order. It rewrites only bound owner, parent, recognized reference and placement tokens. The inserted fragments are lexed and rebound locally. The existing method layout, initialization trace, execution sequence and source-position indexes are spliced and projected.

Paste history retains the primary forward/inverse source patches, an independent subtree value snapshot, and the detached live component handles needed to restore handle identity. Rename history retains primary identifier patches and semantic name mappings.

## Generation, Diff, and Save

### Generation entry and source preservation

**Conditions to preserve**

- A displayed new document uses the same current-source transactions as an opened document. Constructor values and later assignments to the same property retain distinct occurrence identities. The independent candidate must pass complete model/value validation before live handles and source are published. Generation reads `CurrentText`.
- New components require unambiguous declaration and creation anchors. Edits are rejected if required spans are missing, deletion ownership is ambiguous, or calculated edits overlap.
- Catalog editability controls permitted property changes, not removal of existing source. Restricted or unresolved setter access preserves original assignments and constructor arguments, including callback registrations, during generation and unrelated edits. Only an explicit, validated source-edit operation may remove those occurrences; new generated initialization still omits catalog-declared read-only properties.

**Explanation**

`RoundTripGenerator` is the editor's generation entry point.

Before a new document is presented, `NewAppGenerator` establishes its canonical skeleton once. Detached model builders can still assemble a new model before initialization. Initial publication binds the generated declarations, factories and assignments to the already-known model through SourceAnalysis and the emitted-token binder, without AppSourceParser.parseText.

Shared boundaries: [Source publication and history](#source-publication-and-history) and [Saved-source checkpoints](#saved-source-checkpoints).

### Application Source Conventions

**Conditions to preserve**

- Generated class and callback templates use concise documentation appropriate for generated applications rather than the project's internal coding conventions.
- Source-editing paths preserve user-authored documentation, formatting, and license notices outside supported edits. Project license headers are not automatically applied to generated applications.

**Explanation**

`NewAppGenerator` owns generated class documentation through `resources/NewAppTemplate.txt`, and `CallbackSourceEdits` owns callback method templates. Newly generated templates omit extensive property help and routine implementation comments; their concise English documentation serves application users rather than documenting yamada internals.

### Figure lifetime

**Conditions to preserve**

- Keep a generated app alive when launched without an output variable, and separate the decision to close from resource cleanup. Canceling close must leave the app alive; explicit deletion must still release its resources.
- Figure destruction must release a still-live owner without replacing user DeleteFcn code. Cleanup must tolerate an already-destroying figure and guard reentry.
- Constructor failure deletes the partially constructed owner and rethrows the original exception; destructors contain no argument-validation block.

**Explanation**

Both the editor and generated apps own their figure lifetime explicitly; figure-side registrations keep the owner reachable until figure cleanup.

Generated handle applications retain their owner through figure-side callback registrations, including launches without an output variable, without AppBase registration services. `CloseRequestFcn` decides whether closing is allowed and calls `delete(app)` on acceptance; the destructor only releases owned resources, so canceling close leaves the app alive while explicit deletion still cleans it up.

A figure-bound `ObjectBeingDestroyed` listener deletes a still-valid owner without replacing user `DeleteFcn` code. Owner deletion skips a figure already being destroyed and guards reentry.

### Diff presentation

**Conditions to preserve**

- The two Diff panes share scroll positions. The Diff viewer treats line-ending styles equally and renders source as literal text.

**Explanation**

Diff Preview passes the original and committed source snapshots to an HTML viewer. The viewer aligns matching lines, pairs replacements in each change block, and inserts visual gaps opposite unpaired additions and deletions.

### Save bytes and protected writing

**Conditions to preserve**

- The application enables in-place Save only after Open or Save As establishes a confirmed path and validation has no errors.
- Generated text is written as UTF-8 without a BOM. New documents use the host line-ending convention; opened source preserves detected CRLF or LF text.
- After replacement, the writer compares the published discretionary ACL with the original read before replacement and restores it if Windows added explicit rules. The writer retains the backup and reports a recovery error if it cannot restore and verify the original ACL, including its inheritance settings. Windows may update its auto-inheritance bookkeeping flag. There is no truncate-in-place or copy/delete fallback. A failed replacement restores a displaced original with a non-overwriting move when the destination is absent; otherwise it retains the recovery file and reports its path. Temporary cleanup cannot turn a committed replacement into a reported save failure.
- Filesystem permissions must allow sibling creation and native replacement, and filesystem or power-loss durability remains outside this contract.

**Explanation**

`SourceWriter` provides the separately tested byte-level utility for callers that need explicit line-ending normalization.

`SourceWriter` exclusively creates a sibling staging file with `System.IO.FileStream`, writes the encoded bytes, calls `Flush(true)`, and closes the stream before publishing. Existing destinations use `System.IO.File.Replace` with a sibling recovery backup and metadata errors enabled; new destinations use the non-overwriting `System.IO.File.Move`.

`SourceWriter` requires Windows and .NET for protected saving.

### Saved-source checkpoints

**Conditions to preserve**

- `SavedSourceCheckpoint` verifies the component set, parent links, and known effective property states before writing. Unknown effective values remain unknown and are not fabricated by the save check.
- Only after writing succeeds does `DocumentModel.confirmSavedSource` attach the saved-source checkpoint and advance the saved history position. Current text, history identity, catalog/input context, component identity and known effective values guard the save; it does not regenerate a second source from deferred intentions.
- `OriginalText` is retained for the original-side Diff, not for current offsets. `CurrentSourceState` separates monotonic publication revision from history StateId, and history stores exact forward/inverse patches.
- Save As rebases class identity, separated history patches and setting ranges across Undo/Redo branches without adding an Undo step. Output normalization owns separate saved positions and does not silently replace the working source with normalized text.

**Explanation**

`SavedSourceCheckpoint` reparses the exact normalized output without executing input code. The checkpoint's value-only subtree snapshot owns the saved setting histories and offsets under a fresh source version; `ComponentMap` joins those parsed identities to the editable document's stable component identities.

## Validation and Diagnostics

**Conditions to preserve**

- `ModelValidator` checks document-wide invariants: valid and unique identifiers, one registered root, resolvable parents, allowed hierarchy relationships, effective property applicability, editable/source-backed consistency, typed property values, and supported geometry. `PropertyBatchValidator` validates one complete candidate property state.
- Errors block unsafe generation or Save. The diagnostics drawer, status line, generators, and tests consume the same diagnostic model.

**Explanation**

Complete candidate validation covers dependent contracts such as limits and values or item labels, item data, multiselect mode, and selection. Validation returns user-facing messages; document validation publishes structured `Diagnostic` objects with severity, code, component identity, and source span where available.

Warnings can describe state that is preserved but cannot be edited or rendered.

## Resource and Development-Data Boundary

**Conditions to preserve**

- Reference default/value strings retain API facts but are not semantic inputs: enum normalization uses `valueContract.values`, and multiline-text classification uses the reviewed kind and accepted classes. Presentation-text refresh must not change capability metadata, category order, source safety, or Preview behavior.
- The distribution must preserve the relative layout of `yamada.m`, `+yamada`, and runtime resources. Only the distribution root needs to be added to the MATLAB path; tests, development tools, and documentation transcripts must not be added as runtime search folders. Static MATLAB dependency analysis does not enumerate all HTML, JavaScript, or catalog resources, so packaging requires an explicit resource inclusion contract.
- Build manifests, candidates, and checksums are local build outputs; detached signing happens after acceptance and does not modify the `.mltbx`.

**Explanation**

Runtime code resolves resources relative to the project root:

- the registry loads the newest catalog projection that is available to the running release. The sibling `availability.json` supplies release bounds for annotated variants, properties, and values. Source parsing also loads the bundled surface projection when it encounters a factory with a variant absent from the runtime catalog;
- `resources/EditorInteractionOverlay.html`, `resources/RootResizeGuide.html`, and `resources/SourceDiffPreview.html` are loaded by `yamada`;
- `resources/NewAppTemplate.txt` is the fixed new-app skeleton that `NewAppGenerator` fills; its leading `#` lines, including the project license notice, never reach generated source;
- `+yamada/+ui/+layoutwait/waitForFigureLayout.js` is loaded by the bundled `waitForFigureLayout` and executed only in the editor-owned figure window; and
- development ledgers and generation scripts under `dev/component-data` are not runtime dependencies.

The development ledger is the review surface for catalog research and audit decisions. Promotion scripts generate the grouped runtime catalog; loader and baseline tests verify that the promoted variants reconstruct the audited intrinsic and parent-effective property surfaces without capability drift.

Property descriptions are project-authored presentation text composed from API identifiers and reviewed contracts by `dev/component-data/ProjectPropertyText.ps1`. The ledger mirrors these descriptions, while promotion calls the same definitions directly so imported or stale reference headings cannot become runtime help text.

`dev/release/yamadaToolboxFiles.m` implements this inclusion contract with a bounded user-document list, project-owned example, runtime MATLAB files, and JSON/HTML/JavaScript/text resources. The shared `toolbox.json` supplies the version and permanent Toolbox identity. The Apps gallery registers `yamada.m` directly, and only the root is added to the MATLAB path. `buildYamadaToolbox` captures input/configuration hashes and source identity, builds through the documented packager, and checks that inputs did not change during packaging.

### Runtime and release boundaries

**Conditions to preserve**

- The editor requires MATLAB's JVM for UUIDs and canonical path comparisons, and a graphical session for UI components and the CEF-based layout adapter. MATLAB installation files and internal modules are dependencies of the installed MATLAB, not files to copy into the Toolbox.
- Layout-adapter exceptions are caught by the editor and enter its bounded geometry-recovery path; this is not a promise of compatibility on other releases. The support contract is R2023a through R2026b on Windows; each target release is verified with the full suite, and independent validation is required before widening it.
- Project-owned MATLAB source outside the catalog must run on R2023a and later, while release-specific component facts, including default positions, live only in the catalog for each supported release target. Source does not branch on the running release to reproduce catalog data. A release without a verified projection uses the newest older catalog.
- A difference that cannot be catalog data, such as the undocumented Preview layout adapter, stays isolated in one adapter with a bounded fallback, and this reference records the releases on which it was verified. The distributed catalog is trusted product data and must not be replaced with unreviewed executable factory definitions.

**Explanation**

The `FigureActivated` event, figure/controller access, CEF `executeJS` and message-service subscriptions are release-specific integration points. Activation-listener setup and the MATLAB-installation `icons/undo.mat` and `icons/redo.mat` loads occur during shell construction, where failures abort construction and trigger owner cleanup. The packager rejects a maximum release newer than the running release, so the Toolbox is built only on the declared maximum release, R2026b, and the packaging tests run only there. The R2026b packager adds its own `resources/extensions.json` and `resources/mpackage.json` metadata to the payload.

The R2026b catalog records the changed default positions of radio and toggle buttons. The MATLAB release boundary has two layers. The catalogs are generated from one audited ledger of a surface release whose records carry release availability ranges and range-limited overrides; each catalog is the projection of that ledger onto one release, as described in the [catalog generation guide](../dev/component-data/README.md#releases-and-projection). The R2023a-unavailable features to avoid are listed in [CONTRIBUTING.md](../CONTRIBUTING.md#matlab-release-compatibility).

Runtime component factories are drawn from the validated catalog and finite Preview policy. The `feval` calls in component/default construction invoke those approved MATLAB factories, not the input app's constructor, callbacks, or arbitrary expressions.

## Extending the Architecture

### Add or change a component or property

**Conditions to preserve**

- Update the audited ledger of the surface release under `dev/component-data/<surface release>`, recording differences in other releases as availability ranges or overrides with evidence. Regenerate every release catalog with `dev/component-data/RegenerateReleaseCatalogs.ps1` rather than adding declarative inventory to `ComponentRegistry.m` or editing a generated catalog.
- Add only allowlisted executable behavior required by a new editor, validator, Preview adapter, or reset policy.
- Test loader failure modes, registry parity, parent-context projection, Inspector behavior, Preview safety, validation, and source generation.

**Explanation**

The audited ledger is the authoring surface; release catalogs are generated runtime inputs.

### Add an Inspector editor

**Conditions to preserve**

- Define a typed value schema and symbolic editor/validator identifiers. Add the identifiers to the finite behavior allowlists.
- Commit through `PropertyTransaction` and the shared batch validator; do not mutate a component record directly from a UI callback. Preserve source-backed values and test rejected drafts, atomic history, Preview refresh, and round-trip output.
- A modal draft editor subclasses [`PropertyEditDialog`](../+yamada/+ui/+inspector/PropertyEditDialog.m) and implements only `buildContent` and `read`, which stages its draft. The base class holds the commit function privately and owns the frame, Apply, Cancel, closing, and keeping the draft after a rejected read or commit, so a subclass cannot change the document. A draft that stages nothing closes without a commit; values equal to the effective value are dropped by the Inspector commit. An editor that normalizes its starting value, such as the date-list and weekday editors, compares its draft with the normalized start itself and stages nothing when they are equal. A subclass may present a rejection inside the dialog. The list, data, Items, table, column-settings, date-list, and weekday editors use it. The axes text settings dialog commits each row immediately and the custom colormap dialog commits one colormap value, so neither is a draft editor.

**Explanation**

Implement the native adapter or dialog in `+yamada/+ui/+inspector`.

### Extend source syntax

**Conditions to preserve**

- Extend the lexical/parser contract and source ownership model together. Generation must still prove exact ownership and insertion anchors before rewriting it.

**Explanation**

A syntax form may be parsed for preservation without becoming editable.

## Verification Boundaries

**Conditions to preserve**

- Select the `quick`, `area`, or `full` profile in `tests/runYamadaTests.m` according to the change, and run focused test files while iterating. Current known failures and unfinished product capabilities belong in [ROADMAP.md](../ROADMAP.md), not in this architecture reference.
- Synthetic DOM dispatch does not prove OS mouse or physical keyboard automation.
- Preserved handle-class inputs live directly under `tests/fixtures/`, with their notices and adaptation provenance retained.

**Explanation**

Tests are organized by architectural boundary:

- parser and lexical tests prove static, non-evaluating recovery;
- model and transaction tests prove atomic mutation and reversible history;
- loader and registry baseline tests prove strict catalog expansion and parity;
- Inspector and editor tests construct real hidden UI fixtures and delete them;
- Preview tests prove allowlisted rendering without input-app execution;
- generation tests cover canonical output, localized edits, source preservation, encoding, and line endings; and
- project-convention tests enforce encoding, line endings, leading declarations, and trailing license notices in project-owned MATLAB files; documentation and type conventions are reviewed rather than tested.

HTML overlay tests cover DOM pointer/key dispatch through the real iframe handlers and MATLAB event bridge, as well as isolated Node gesture tests. Pre-migration AppBase versions remain in Git history; there is no parallel fixture copy.
