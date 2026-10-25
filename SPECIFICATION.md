# yamada Product Specification

This document describes the current public feature scope, input and output contract, and safety limitations of the development version of `yamada`. It is not a roadmap for future implementation.

The supported class directly inherits from `handle` and owns exactly one `uifigure`. Every other UI component must be a descendant of that figure, either directly or through nested containers. This hierarchy is a user precondition: there is no new dedicated descendant-membership validation or diagnostic, and behavior outside it is not guaranteed. Existing model consistency and safe-edit validation remain in place. Arbitrary inheritance graphs, dynamic construction, AppBase compatibility, and automatic source conversion are outside the contract.

Generated callbacks are bound methods with `(app, source, event)` inputs. The default CloseRequestFcn deletes the owner. Add replaces the default binding with an editable close handler initialized to delete the app; Delete restores the default binding. The destructor releases owned resources without argument validation or a cancel decision. A source-bound ObjectBeingDestroyed listener handles direct figure deletion without replacing user DeleteFcn code and ignores owner destruction already in progress. No-output startup retains the owner through figure callbacks; constructor failure cleans up a partially created figure.

## Purpose

`yamada` is a visual editor for `handle` applications that treats ordinary MATLAB class files (`.m`) as the source of truth.

Users can create a new handle class from an empty canvas or open an existing handle class, then inspect and edit supported UI components and properties graphically. `yamada` does not depend on the private internal format of `.mlapp` files.

## Supported Environment

- Development and verification target: MATLAB R2024a
- Input: A `.m` file defining a class derived from `handle`
- Output: A `.m` file defining an ordinary MATLAB class

Compatibility with MATLAB releases other than R2024a is not guaranteed. No versioned release, MATLAB Toolbox package, or standalone application is currently available.

## Supported Operations

### New applications

- Create an empty handle class with a valid MATLAB class name and a root `uifigure`.
- Start an untouched new document clean; the first edit marks it as having unsaved changes.
- Add supported components from the palette.
- Inspect the component hierarchy and Safe Preview.
- Edit supported properties in the typed Property Inspector.
- Move and resize absolutely positioned components.
- Select a Grid Layout or one of its children to show Safe Preview's row and column settings buttons. Buttons along the figure boundary appear in the dark editing margin outside the UIFigure. Choose `fit`, a fixed pixel size, or a flexible `x` weight; insert or delete tracks when every affected direct-child placement has a deterministic result.
- Drag a selected direct Grid Layout child to another cell or resize its row and column span. The Property Inspector remains the exact-value fallback for `Layout.Row` and `Layout.Column`.
- Continue to edit `RowSpacing`, `ColumnSpacing`, `Padding`, `BackgroundColor`, `Visible`, and `Scrollable` through the Property Inspector. `Padding` uses the documented MATLAB vector order `[left bottom right top]`.
- Explicitly delete components and undo or redo changes.
- Validate the document, review the source diff, and save a runnable handle `.m` file.

### Existing applications

- Open an handle `.m` file with a common App Designer-like or programmatic structure.
- Statically parse supported declarations, creation statements, parent-child relationships, and direct property assignments.
- Display parsed components in the hierarchy browser, Safe Preview, and Property Inspector.
- Edit property assignments and components whose source ownership can be determined safely.
- Reviewed axes value/Mode pairs follow their original initialization order. A later automatic mode can make the effective value unknown; the editor keeps the explicit source input and reports that uncertainty. New initialization applies an explicitly requested final mode after its corresponding value.
- Axes/UIAxes grid widths follow upstream widths in auto mode and hold their current values in manual mode. New upstream assignments preserve existing manual hold points. Reviewed color/alpha modes keep stored values separate from the rendered appearance.
- Reviewed simple controls share `Position`, `InnerPosition`, and read-only `OuterPosition` getters. Later writable aliases determine the effective geometry while original inputs retain their own source tokens. Lamp's getters use the smaller requested dimension for both width and height. These reviewed controls support finite nonnegative sizes, including zero-sized copies. An earlier `Position` edit shadowed by a later alias is rejected without changing history. Copies emit one effective `Position` and verify their placement offset. Grid layout geometry remains managed by the layout rather than an alias literal. Parent changes also verify the requested geometry before committing history.
- Grid Layout track getters include flexible padding required by direct-child placements. The editor retains explicit track inputs, resolves implicit child positions from initialization order, and uses the resulting layout for Preview and copies. Moving children out releases implicit padding. Track edits and combined grid/child edits must survive generated initialization before they commit. Unknown placement expressions remain unresolved; `fit` stays a stored token rather than a predicted pixel measurement.
- Compare the original and generated source, then save to a new path or to an explicitly confirmed path.
- Show diagnostics for unsupported or ambiguous structures.
- Track unsaved edits in the editor title. New, Open, and closing the editor offer Save, Discard, or Cancel when required; a canceled or failed save leaves the current document open.

### Subtree editing and component clipboard

- Copy, Cut, Paste, Delete, and parent changes treat one component and all its descendants as an ordered unit. A failed preflight leaves model, history, diagnostics, source preview, clipboard and selection unchanged.
- Copy captures independent value data and does not dirty the document or add history. Cut deletes immediately. Paste allocates fresh IDs and unique names, including collision checks against source members and pending names. Copy uses a Copy suffix; Cut reuses original names, with numeric suffixes on collision. Each Cut, Paste, Delete, or parent change is one Undo/Redo step. Undo does not rewind the clipboard. Parent changes preserve existing component IDs and handles.
- Edit menus, Ctrl+C/X/V and Hierarchy context menus share commands and availability checks. Context targets do not change selection when opening a menu or copying. Text-entry controls and inline renaming retain their shortcuts. Preview HTML forwards Ctrl+C/X/V to those same commands with selected-ID and revision validation. Edit menus show shortcut hints; Rename shows F2 in the same column. Cut selects the former parent; Paste selects the inserted root.
- Paste resolves the nearest catalog-compatible ancestor, including the target itself. It retains descendant order and internal placement, offsets absolute roots, and finds a free grid rectangle without expanding tracks. Clipboard ownership is limited to one document in one editor instance. Successful New/Open/Reload clears it; canceled or failed replacement retains it.
- Parent changes use Safe Preview cross-container dragging with candidate guides. No parent-change menu command or dedicated destination window is provided. Absolute/grid changes commit Position and Layout.Row/Column together. Grid-to-absolute placement requires a literal position or verified preview pixels. Explicit grid drops never fall back to another free cell. Invalid, occupied, cyclic, stale or canceled drops leave the model unchanged.
- The root UIFigure and noneditable, programmatic-only or FigureTools subtrees cannot be copied or reparented. Other catalog families are enabled only when complete hierarchy, placement and generation preflight succeeds. Native menu, toolbar and tree editing is not expanded into a comprehensive workflow here.
- Copy supports safely encodable literals and two static component-reference families: SelectedTab on a TabGroup must name its direct child Tab; ContextMenu must name a context menu under the same document root. Internal targets receive copied identities; external targets retain their same-document identity and are revalidated at Paste. Generated assignments follow target creation.
- Other expressions, unknown object payloads and executable callback bindings prevent Copy/Cut rather than being omitted. Delete/Cut reject surviving external references. Reparenting retains callback methods and proven direct bindings, but rejects ambiguous initialization dependencies and unsupported internal references. Pending callback edits on parsed moved nodes are not combined with relocation; Save and Reload Source, or Undo, is required first.
- Opened-source changes use proven original-offset spans; original text remains the source snapshot. Parsed relocation and generated insertion share creation ordering. Unsupported source is preserved or the operation is refused. Input applications, handlers and expressions are never executed by these operations.

### Callback management

- Right-clicking a Hierarchy node opens an editor-owned context menu for that node without changing the selected component, Inspector, or Preview selection. Empty space and stale/deleted targets cannot reuse a previous command target.
- Manage Callbacks opens one independent modal popup for the target. Callback rows come from the effective component/style/parent catalog surface, excluding callback execution-control properties. Long lists scroll.
- Add creates a unique instance method and an `@app.Method` binding. Ordinary handlers start empty; CloseRequestFcn starts with `delete(app)`. Delete removes both the owned binding and the complete owned method, including its body and immediately following help. Closing the popup retains edits.
- Each action preflights complete source generation and records one Undo/Redo step. Failure leaves intentions, source preview, diagnostics, history and dirty state unchanged. Undo restores exact original source bodies; unrelated code is kept.
- Existing direct createComponents assignments using `@app.Method` can be deleted when the method is unique and has no other detected references. Empty bindings can be replaced safely.
- Shared/missing methods, arbitrary anonymous functions, constructor bindings, conditional/repeated assignments, indirect/dynamic references, and unproven structural scopes disable both Add and Delete with an explanatory tooltip.
- A two-input anonymous wrapper may identify an owned handler when its body is exactly one `app.Handler(...)` call with zero arguments or an ordered subset of the wrapper's named inputs. Ignored inputs may use `~`. This includes `@(~, event) app.SomeButtonPushed(event)` and `@(~,~) app.SomeButtonPushed()`. Named wrapper inputs must be distinct valid identifiers other than `app`; computed arguments, captured argument values, and additional expressions remain unsupported. Certain catalog callback registrations using direct method handles or these wrappers are retained as source-backed bindings without generic `source-expression` warnings or unknown-source regions. This does not grant ordinary literal-property editing or exclusive handler ownership. Existing ownership and sharing checks still apply, and unchanged wrapper syntax and method signatures are preserved.
- The popup refreshes after edits and history changes, reuses an existing instance for the same target, and closes when its target or document expires.
- Source parsing, source generation and Safe Preview never execute handlers. MATLAB remains the editor for handler bodies. Refresh / Edit > Reload Source / F5 read saved disk source and atomically replace the document after successful parsing. Reload clears history and stale callback spans, closes the popup and preserves selection by a unique component name where possible. Local dirty changes require Save/Discard/Cancel; concurrent external edits require a different Save As target, Discard, or Cancel. Unreadable, invalid or changing files do not replace the current document. Unsaved MATLAB buffers are outside the reload operation.

## Standard Component Catalog

The catalog includes the following persistent MATLAB R2024a UI components and creation variants:

- Basic controls: `uilabel`, `uibutton`, `uicheckbox`, `uicolorpicker`, `uidatepicker`, `uidropdown`, `uieditfield`, `uihyperlink`, `uiimage`, `uilistbox`, `uiradiobutton`, `uislider`, `uispinner`, `uitable`, `uitextarea`, and `uitogglebutton`
- Containers and layout: `uifigure`, `uipanel`, `uigridlayout`, `uitabgroup`, `uitab`, and `uibuttongroup`
- Trees: `uitree` and `uitreenode`
- Axes: `uiaxes`, `axes`, `geoaxes`, and `polaraxes`
- Instrumentation: `uigauge`, `uiknob`, `uilamp`, and `uiswitch`
- Extended display and figure tools: `uihtml`, `uicontextmenu`, `uimenu`, `uitoolbar`, `uipushtool`, and `uitoggletool`

Catalog inclusion does not mean that every creation variant supports insertion, Preview, layout, and property editing to the same extent. The parent component, creation variant, or property value may limit available operations. Unsupported state remains read-only where possible and is reported through diagnostics.

Transient operations such as `uialert`, `uiconfirm`, `uiprogressdlg`, `uisetcolor`, and file-selection dialogs are out of scope because they are not persistent components in the document.

## Static Parsing and Safe Preview

`yamada` does not execute an input application to discover its UI structure.

- It does not call the input class constructor, callbacks, or helper methods.
- It does not evaluate arbitrary MATLAB expressions through `eval` or an equivalent mechanism.
- Safe Preview applies only catalog-approved components and values that can be interpreted safely.
- Parsed constructor arguments obey the same Preview policy as assignments. Skipped properties, including executable callbacks and HTML sources, remain in source and do not reach Preview construction. Named image sources use the existing local-asset adapter after construction.
- Safe Preview draws the root UIFigure client area at its model pixel width and height, using its supported Color value. A dark gray area marks the space outside the figure, with a visible dark margin even at scroll limits. A fixed dark divider separates the figure from native scroll bars while scrolling. Scroll bars expose parts larger than the editor pane. The preview heading retains the editor's light panel background and dark text.
- Resizing the editor window changes only the viewport. Root UIFigure resize handles appear on all eight directions for an editable literal Position, even in an empty new document or when a child is selected. Each drag is one undoable model edit. A dashed outline previews the proposed figure bounds during the drag without a numeric size label. Left and bottom drags update the screen origin to keep the opposite edge fixed; right and top drags retain the origin. A thin gray frame marks all four edges of the figure.
- The scrollable editing area also includes visible component bounds outside the UIFigure. After shrinking the figure, stranded components remain accessible as selectable outlines on the dark background and can be dragged back into the figure. The figure canvas keeps its actual model size.
- Unmanaged callbacks, nonliteral expressions, and unsupported statements remain in the original source where possible; callback management changes only proven binding/method ranges.
- Diagnostics distinguish state that cannot be previewed from state that cannot be preserved safely.

Because of this limitation, Safe Preview may not reproduce the input application's appearance completely. It displays the model that could be parsed safely and is not a substitute for running the input application.

## Property Setting Effects

- Property histories retain constructor name-value arguments and later assignments, including earlier occurrences, comments, and source positions. Existing values are replaced at their original occurrence. New settings normally use an assignment at a proven insertion point; a verified constructor-only component may keep the name-value form.
- The catalog distinguishes reviewed independent inputs, finite modeled effects, unsupported effects, and unaudited effects. Missing effect metadata does not prove independence. Unaudited (`unknown`) literals remain editable under existing product, value-schema, and source-ownership rules, using a stored-input assumption. Identified unsupported effects still prevent affected edits before mutation. Omitted/read-only properties and nonliteral source values keep their separate restrictions; unknown constructor support still falls back to assignment.
- RadioButton and ToggleButton selection uses the owning ButtonGroup and sibling creation order. Generated and copied values are applied after sibling creation. Mixed RadioButton/ToggleButton groups and unresolved selection references remain outside the supported contract. No handle-reference editor is provided.
- Nonempty construction callbacks, unresolved initialization calls, uncataloged setters, and unsupported Parent/Children assignments prevent guarantees about initial values, including those of destination siblings. Unknown explicit calls without an app argument are also bounded; reviewed data calls require inert literal inputs. Callback registration alone does not imply that its body executed.
- Finite geometry rules cover reviewed stored Position inputs, slider thickness, and selected knob/gauge square adjustments. Decoration-dependent getters and child positions affected by later ancestor resizing remain unknown. Axes aspect/camera coupling and unresolved tree/tab references are explicitly bounded rather than approximated as independent values.
- Copy, move, generation, and save preflight use the same state contract. Reparsed output verifies supported rules; it does not prove arbitrary MATLAB behavior. Items/ItemsData length differences remain outside this implementation.

## Editing and Source Preservation

- New and existing applications use the same component model, validation, Preview, and generation pipeline.
- Generating an existing source file without edits does not change its original text.
- Edits make localized changes only to declarations, creation statements, and assignments whose ownership can be determined safely.
- Checkbox Tree supports literal `Position` edits in its original assignment or constructor argument. Existing writable `InnerPosition` settings are preserved; the Inspector continues to use `Position` as its geometry editing surface.
- Position uses one inline Inspector property row containing four vertically stacked numeric fields in original `[X Y Width Height]` order. Each field has an `X`, `Y`, `W`, or `H` heading on its left. Their tooltips are `X`, `Y`, `Width`, and `Height`. Fixed slider dimensions remain readable but cannot be edited; their tooltips are `Width (fixed)` or `Height (fixed)` according to Orientation.
- Fixed aspect ratios are indicated by two labels, `┓` above `┛`, aligned in the same column to the right of Width and Height. Editing either linked size updates its partner before committing a single Position vector, so Undo restores both sizes together. The links indicate a native constraint and are not unlock buttons.
- Reviewed Position constraints cover square Lamp/Knob/Gauge families, fixed-thickness sliders, all Switch styles, and the semicircular Gauge. Position normalization and orientation exchange use shared finite rules in source-state resolution, the inline editor, Safe Preview, and canvas resize handling. Switch and semicircular Gauge Position are editable within the normal literal/source-ownership contract; decoration-dependent aliases remain outside that finite policy. Grid-managed and natively read-only Position properties keep their existing restrictions.

- If an insertion point or ownership range required for addition or deletion is ambiguous, the edit or save is rejected with a diagnostic.
- Failed validation of a supported value restricts Preview or saving as necessary for safety.
- Deletion occurs only after an explicit user action.
- Visual Grid Layout editing accepts only supported literal, source-owned track and placement values. Expression-backed tracks or placements, implicit placements, stale overlay actions, ambiguous geometry, and out-of-range placements are rejected without a partial document update. Moving and resizing children may create overlapping placements, as MATLAB allows.

`yamada` prioritizes source preservation, but it does not guarantee complete round-tripping of arbitrary MATLAB syntax. Use version control such as Git or create a backup before editing an existing file.

## Output

- Output is ordinary handle `.m` source that can be reviewed and compared as text.
- Files are written as UTF-8 without a BOM.
- A new file includes the class and component declarations, creation method, application registration, and cleanup required for execution.
- New files use the host platform's standard line ending; existing files preserve the detected CRLF or LF convention.
- Generated comments and help text are written in English.
- `yamada` does not automatically add, replace, or remove the project's GPL notice in an application created or opened by the user.
- Save As requires explicit replacement approval for an existing target. A normal Save writes only to the current confirmed path and does not repeat that approval.
- Before saving, the editor reparses the output without executing it and checks supported known initial values and component parent links. Successful saving retains Undo/Redo and original source ownership, and records the saved output's positions separately. Reopening or Reload Source establishes fresh ownership from the saved file. A failed write does not advance the saved checkpoint.

## Out of Scope

- Reading, writing, or reproducing the internal format of `.mlapp` files
- Full compatibility with App Designer
- Semantic analysis or rewriting of arbitrary MATLAB code
- Recovery of every dynamically created component
- Complete round-tripping of arbitrary MATLAB syntax
- Preview by executing the input application
- Visual editing of application-specific computational logic

## Updating This Specification

Update this document and the [README](README.md) when a change affects externally visible behavior, input requirements, output, or safety limitations. See [CONTRIBUTING.md](CONTRIBUTING.md) for development and contribution guidance.
