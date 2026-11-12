# yamada Product Specification

For users evaluating or using yamada, this specification defines the supported behavior, application format, and safety limits of version 1.0.0.

## Purpose

`yamada` is a visual editor for `handle` applications that treats ordinary MATLAB class files (`.m`) as the source of truth.

Users can create a new handle class from an empty canvas or open an existing handle class, then inspect and edit supported UI components and properties graphically. `yamada` does not depend on the private internal format of `.mlapp` files.

## Supported Environment

- Release target: MATLAB R2024a on 64-bit Windows, with a graphical session, JVM enabled, and MATLAB .NET support
- Required MathWorks product: MATLAB, without additional toolboxes
- Launch command: `yamada`, without parentheses or an output assignment
- Planned distribution: MATLAB Toolbox (`.mltbx`) with an Apps gallery entry
- Input: A `.m` file defining a class derived from `handle`
- Output: A `.m` file defining an ordinary MATLAB class

Other MATLAB releases, macOS, Linux, MATLAB Online, and headless operation are outside the 1.0.0 support contract. MATLAB remains required; no standalone executable is planned. No versioned release has been published yet.

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

Supported input classes directly inherit from `handle` and own exactly one `uifigure`. All other UI components must be descendants of that figure. Applications outside this hierarchy, arbitrary inheritance graphs, dynamic construction, and AppBase input are unsupported.

- Open a handle `.m` file with a common App Designer-like or programmatic structure.
- Read supported declarations, creation calls, parent relationships, and property assignments from the source. Supported initialization can span helpers declared in the same class and called from the constructor. Dynamic or recursive initialization may leave some settings unresolved.
- Display parsed components in the hierarchy browser, Safe Preview, and Property Inspector.
- Edit property assignments and components whose source ownership can be determined safely.
- Reviewed axes value/Mode pairs follow their original initialization order. A later automatic mode can make the effective value unknown; the editor keeps the explicit source input and reports that uncertainty. New initialization applies an explicitly requested final mode after its corresponding value.
- Axes/UIAxes grid widths follow upstream widths in auto mode and hold their current values in manual mode. New upstream assignments preserve existing manual hold points. Reviewed color/alpha modes keep stored values separate from the rendered appearance.
- Reviewed simple controls share `Position`, `InnerPosition`, and read-only `OuterPosition` getters. Later writable aliases determine the effective geometry while original inputs retain their own source tokens. Lamp's getters use the smaller requested dimension for both width and height. These reviewed controls support finite nonnegative sizes, including zero-sized copies. An earlier `Position` edit shadowed by a later alias is rejected without changing history. Copies emit one effective `Position` and verify their placement offset. Grid layout geometry remains managed by the layout rather than an alias literal. Parent changes also verify the requested geometry before committing history.
- Grid Layout track getters include flexible padding required by direct-child placements. The editor retains explicit track inputs, resolves implicit child positions from initialization order, and uses the resulting layout for Preview and copies. Moving children out releases implicit padding. Track edits and combined grid/child edits must survive generated initialization before they commit. Unknown placement expressions remain unresolved; `fit` stays a stored token rather than a predicted pixel measurement.
- Compare the original and generated source in Diff Preview. The panes scroll together and highlight added, deleted, and modified lines. The map shows changes across the source and the currently visible range. Click the map to jump to a location. Save to a new path or to an explicitly confirmed path.
- Show diagnostics for unsupported or ambiguous structures.
- Track unsaved edits in the editor title. New, Open, and closing the editor offer Save, Discard, or Cancel when required; a canceled or failed save leaves the current document open.

### Copy, cut, paste, delete, and move

- These operations act on a component and its descendants. Copy leaves the document clean if there were no previous edits. Cut removes the subtree immediately. Cut, Paste, Delete, and moving a subtree are each one Undo/Redo step. Undo leaves the clipboard available.
- Copy gives pasted components unique names with a `Copy` suffix. Paste after Cut tries the original names and uses numeric suffixes on collisions. Cut selects the former parent and Paste selects the inserted component. Clipboard contents belong to the current document in one editor window. A successful New, Open, or Reload clears them.
- Paste uses the closest compatible container, offsets absolutely positioned components, and looks for free cells in a grid without adding tracks. Drag a component on the canvas to change its parent. An explicit grid drop uses the indicated cell. Rejected or canceled operations leave the current document and clipboard intact.
- Copy and moving require editable subtrees. The root figure, programmatic-only components, and figure tools are outside those operations. Cycles, unsupported values, ambiguous initialization, and references that would be broken can prevent an operation.
- Copy supports literal settings and two static reference types. A Tab Group can refer to one of its own tabs through `SelectedTab`. A component can refer to a context menu in the same app through `ContextMenu`. Copied targets are connected to their copies. Targets outside the copied subtree keep their original references when still valid.
- Copy leaves callback bindings behind and preserves the original method bodies. A construction callback that makes the initial configuration unknown can still prevent Copy. Other expressions or unknown values can prevent Copy or Cut. Existing callback bindings block Cut and Delete. A supported move preserves those bindings. Save and reload, or undo pending callback edits, before moving an opened subtree whose bindings have just changed.

### Callback management

Right-click a component in **Hierarchy** and choose **Manage Callbacks**. The dialog applies to that component without changing the current selection. Each row offers **New**, **Disconnect**, and compatible existing methods. New creates a named method and connects it. New close handlers start with `delete(app)`. A method can be connected to several callbacks.

Disconnect removes the binding and keeps the method body. Disconnecting the close handler of a new app restores the default close behavior. Close the dialog to keep your edits, or use Undo to reverse an individual change. Use MATLAB's editor to change or remove method bodies.

Supported bindings include direct method handles and two-input forwarding functions such as `@(~, event) app.SomeButtonPushed(event)`. A forwarding function can pass its named inputs in order or call the method with no arguments. Expressions with computed or captured arguments and incompatible signatures restrict editing. The dialog explains unavailable bindings and indicates when argument types could not be checked.

### Reload externally edited code

Use **Edit > Reload Source**, the toolbar refresh button, or **F5** after saving the file in MATLAB. Reload reads the disk file, closes callback dialogs, clears Undo/Redo, and keeps the selected component where its name still identifies it uniquely. If you have unsaved edits in yamada, choose Save, Discard, or Cancel. If both copies changed, save the yamada edits under another filename to retain both versions. A failed reload leaves the current document open.

## Standard Component Catalog

The catalog includes the following persistent MATLAB R2024a UI components and creation variants:

- Basic controls: `uilabel`, `uibutton`, `uicheckbox`, `uicolorpicker`, `uidatepicker`, `uidropdown`, `uieditfield`, `uihyperlink`, `uiimage`, `uilistbox`, `uiradiobutton`, `uislider`, `uispinner`, `uitable`, `uitextarea`, and `uitogglebutton`
- Containers and layout: `uifigure`, `uipanel`, `uigridlayout`, `uitabgroup`, `uitab`, and `uibuttongroup`
- Trees: `uitree` and `uitreenode`
- Axes: `uiaxes`, `axes`, `geoaxes`, and `polaraxes`
- Instrumentation: `uigauge`, `uiknob`, `uilamp`, and `uiswitch`
- Extended display and figure tools: `uihtml`, `uicontextmenu`, `uimenu`, `uitoolbar`, `uipushtool`, and `uitoggletool`

Catalog inclusion does not mean that every creation variant supports insertion, Preview, layout, and property editing to the same extent. The parent component, creation variant, or property value may limit available operations. A Tab Group accepts only Tabs as direct children. To place controls within the group, add them to a Tab. Unsupported state remains read-only where possible and is reported through diagnostics.

Transient operations such as `uialert`, `uiconfirm`, `uiprogressdlg`, `uisetcolor`, and file-selection dialogs are out of scope because they are not persistent components in the document.

## Static Parsing and Safe Preview

`yamada` does not execute an input application to discover its UI structure.

- It does not call the input class constructor, callbacks, or helper methods.
- It does not evaluate arbitrary MATLAB expressions through `eval` or an equivalent mechanism.
- Safe Preview applies only catalog-approved components and values that can be interpreted safely.
- Constructor arguments and later assignments follow the same preview rules. The editor keeps callbacks and HTML sources in the code and skips them in the preview. Supported local image files can appear in the preview.
- Safe Preview draws the figure at its configured pixel size. Scroll to reach parts of the figure or components outside the visible pane.
- Resizing the editor window changes the viewing area. Drag a figure resize handle to change the app window size when Position is editable. A dashed outline shows the proposed bounds and each completed drag is one Undo step. Left and bottom handles keep the opposite edge fixed.
- The scrollable editing area also includes visible component bounds outside the UIFigure. After shrinking the figure, stranded components remain accessible as selectable outlines on the dark background and can be dragged back into the figure. The figure canvas keeps its actual model size.
- Unmanaged callbacks, nonliteral expressions, and unsupported statements remain in the original source where possible; callback management changes only proven binding/method ranges.
- Diagnostics distinguish state that cannot be previewed from state that cannot be preserved safely.

Because of this limitation, Safe Preview may not reproduce the input application's appearance completely. It displays the model that could be parsed safely and is not a substitute for running the input application.

## Property Setting Effects

- An edit replaces the existing value where it was set, including a constructor name-value argument or a later assignment. Earlier settings and nearby comments are preserved. New settings usually use assignments, with name-value arguments for supported constructor-only components.
- An editable literal can still have effects yamada has not modeled. In that case the Inspector shows the stored input. Settings with known unsupported effects can block an edit. Source expressions and read-only properties retain their own editing restrictions.
- RadioButton and ToggleButton selection uses the owning ButtonGroup and sibling creation order. Generated and copied values are applied after sibling creation. Mixed RadioButton/ToggleButton groups and unresolved selection references remain outside the supported contract. No handle-reference editor is provided.
- Nonempty construction callbacks, uncataloged setters, and unsupported Parent/Children assignments prevent guarantees about initial values, including those of destination siblings. Unknown initialization calls are preserved and diagnosed, but their effects are the user's responsibility and do not make every component state uneditable. Modeled values describe recognized initialization settings, not the effects of arbitrary code. Reviewed data calls require inert literal inputs. Callback registration alone does not imply that its body executed.
- Finite geometry rules cover reviewed stored Position inputs, slider thickness, and selected knob/gauge square adjustments. Decoration-dependent getters and child positions affected by later ancestor resizing remain unknown. Axes aspect/camera coupling and unresolved tree/tab references are explicitly bounded rather than approximated as independent values.
- Copy, move, and save check the settings and component relationships yamada supports. Mismatched `Items` and `ItemsData` lengths are outside the supported editing scope.

## Editing and Source Preservation

- Generating an existing source file without edits does not change its original text.
- Edits make localized changes only to declarations, creation statements, and assignments whose ownership can be determined safely.
- New settings normally stay before the next unknown statement. If recognized setting dependencies require a later interval, insertion follows those prerequisites without moving existing statements or interpreting unknown code. Values and order are checked for the component and necessary hierarchy context; arbitrary user-code effects remain outside this guarantee.
- Checkbox Tree supports literal `Position` edits in its original assignment or constructor argument. The Inspector edits `Position` and preserves existing writable `InnerPosition` settings.
- The Position row shows `X`, `Y`, `W`, and `H` in MATLAB vector order. A slider dimension fixed by its orientation is displayed read-only.
- An aspect-link marker indicates a fixed width-to-height relationship. Editing either linked size adjusts both dimensions in one Undo step.
- Reviewed Position constraints cover square Lamp/Knob/Gauge families, fixed-thickness sliders, all Switch styles, and the semicircular Gauge. Switch and semicircular Gauge Position are editable within the normal literal/source-ownership contract; decoration-dependent aliases remain outside that finite policy. Linear Gauge width and height are independent: Inspector edits and Preview resizing preserve both requested dimensions without an aspect link; Orientation changes exchange the dimensions in actual setter order. Grid-managed and natively read-only Position properties keep their existing restrictions.

- If an insertion point or ownership range required for addition or deletion is ambiguous, the edit or save is rejected with a diagnostic.
- Failed validation of a supported value restricts Preview or saving as necessary for safety.
- Deletion occurs only after an explicit user action.
- Visual Grid Layout editing accepts only supported literal, source-owned track and placement values. Expression-backed tracks or placements, implicit placements, stale overlay actions, ambiguous geometry, and out-of-range placements are rejected without a partial document update. Moving and resizing children may create overlapping placements, as MATLAB allows.

`yamada` prioritizes source preservation, but it does not guarantee complete round-tripping of arbitrary MATLAB syntax. Use version control such as Git or create a backup before editing an existing file.

## Output

- Output is ordinary handle `.m` source that can be reviewed and compared as text.
- Generated apps stay open when launched without an output variable and release their window when closed. Generated callback methods receive `(app, source, event)`; disconnecting a callback retains its method body.
- Files are written as UTF-8 without a BOM.
- If writing the temporary copy fails, the existing file keeps its original contents. If Windows moves the original during a failed replacement, yamada tries to restore it and reports the recovery location if needed. A failed save keeps your unsaved edits and last successful save state. Keep backups for power loss or storage failure.
- A new file includes the class and component declarations, creation method, callback-based owner retention, and cleanup required for execution; it does not use AppBase registration services.
- New files use the host platform's standard line ending; existing files preserve the detected CRLF or LF convention.
- Generated comments and help text are written in English.
- `yamada` does not automatically add, replace, or remove the project's GPL notice in an application created or opened by the user.
- Save As requires explicit replacement approval for an existing target. A normal Save writes only to the current confirmed path and does not repeat that approval.
- Before saving, yamada checks that the output still represents the supported settings and component hierarchy. Save retains Undo/Redo. Reopening or reloading reads the saved file and starts a new history.

## Out of Scope

- Reading, writing, or reproducing the internal format of `.mlapp` files
- Full compatibility with App Designer
- Semantic analysis or rewriting of arbitrary MATLAB code
- Recovery of every dynamically created component
- Complete round-tripping of arbitrary MATLAB syntax
- Preview by executing the input application
- Visual editing of application-specific computational logic
