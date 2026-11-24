# yamada Product Specification

For users evaluating or using yamada, this specification defines the supported behavior, application format, and safety limits of version 1.1.1.

## Purpose

`yamada` is a visual editor for `handle` applications that treats ordinary MATLAB class files (`.m`) as the source of truth.

Users can create a new handle class from an empty canvas or open an existing handle class, then inspect and edit supported UI components and properties graphically. `yamada` does not depend on the private internal format of `.mlapp` files.

## Supported Environment

- Release targets: MATLAB R2023a through R2026b on 64-bit Windows, with a graphical session, JVM enabled (R2026b installs no Java runtime, so install the MATLAB Support for OpenJDK add-on or another OpenJDK distribution first), and MATLAB .NET support
- Cross-release editing: an app can be opened on an older supported release when its newer features are recognized by the bundled catalogs. Unavailable components remain in the hierarchy as read-only source records, and Safe Preview uses a labeled stand-in with any proven placement. Unavailable explicit properties and values remain in the original source. Supported settings can be edited under the normal validation rules as long as the operation preserves protected source. The saved app retains its newer MATLAB requirements. If the running MATLAB release falls outside the inferred source requirements or the requirements conflict, a warning appears first in the diagnostics. The inferred range describes recognized feature usage, not a guarantee that the app runs on every release within it.
- Required MathWorks product: MATLAB, without additional toolboxes
- Launch command: `yamada`, without parentheses or an output assignment
- Planned distribution: MATLAB Toolbox (`.mltbx`) with an Apps gallery entry
- Input: A `.m` file defining a class derived from `handle`
- Output: A `.m` file defining an ordinary MATLAB class

Other MATLAB releases, macOS, Linux, MATLAB Online, and headless operation are outside the 1.1.1 support contract. MATLAB remains required; no standalone executable is planned.

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
- Read supported literal axes setup calls from the selected release catalog, including titles, labels, limits, ticks, grid settings, and geographic tick formats. Calls with an inferred axes target report a warning. Unsupported forms remain in the source.
- Edit axes titles, subtitles, and labels in the Inspector, including multiline text and supported text styling. Subtitle styling can share or override settings from a common title call. Edit the common geographic tick format.
- Edit requested geographic latitude and longitude ranges inline in the Inspector, each with the extent Safe Preview currently displays. An edit to either range writes both ranges of one call. Preserve existing geographic limit mode calls and apply them in source order.
- Choose the aspect-ratio style of `axis` (`normal`, `equal`, `image`, or `square`) for axes and UI axes in the Inspector, and turn `vis3d` on or off beside it, since `vis3d` combines with a style, as in `axis(app.UIAxes, "equal", "vis3d")`. The style row shows the last such keyword, or `normal` without one, and the Axis Vis3d row is on while a `vis3d` keyword follows the last `normal`. A marker beside the style lists the effects of its call that later settings override, such as an explicit `DataAspectRatio` after `axis(app.UIAxes, "equal")`. Choosing a style rewrites only that keyword of its call; turning `vis3d` on adds the keyword to the end of the last call, and turning it off removes it, together with a call left without keywords. Turning `vis3d` off and on can therefore move it after a style: `axis(app.UIAxes, "vis3d", "square")` becomes `axis(app.UIAxes, "square", "vis3d")`, which also keeps `DataAspectRatioMode` manual. Later settings stay in place, and without a call a new one is written after the existing settings.
- Edit `DataAspectRatio` and `PlotBoxAspectRatio` of axes and UI axes beside an Auto button, like axis limits. Manual ratios leave manual limits editable. When `DataAspectRatio` and two or more of `XLim`, `YLim`, and `ZLim` are also manual, MATLAB derives the plot box from them and ignores a manual `PlotBoxAspectRatio`; such settings are accepted, and a marker on the `PlotBoxAspectRatio` row names the settings that override it.
- Edit numeric ruler details in the Inspector. Cartesian axes support X, Y, and Z tick label formats, exponents, and secondary labels. Polar axes support radial and angular tick label formats and angular tick label rotation.
- Edit each value that has an automatic mode, such as `XLim` with `XLimMode`, in one Inspector row with an Auto button. The field shows the value written in source, or the current value when source has none, and accepts input only while Auto is off. Turning Auto on or off sets the mode setting and keeps an existing value setting, so turning Auto off restores that value. When source has no value setting, turning Auto off also writes the value MATLAB computes from the explicit settings at that moment, so the app opens with that value. When the mode setting precedes the value setting in source, the Auto button is read-only and its tooltip explains why.
- A setting that only shapes an automatic value turns that value's Auto on when it is edited, because it has no effect otherwise: `XLimitMethod` turns on Auto for `XLim`, and a ruler's tick label format turns on Auto for its tick labels. When Auto is off, the edit is written as one call that sets both, such as `xlim(app.UIAxes, "padded")` or `xtickformat(app.UIAxes, "%.2f")`, after the settings it replaces; when Auto is already on, only the setting is written. Undo restores both.
- Title and label text has no public automatic mode. `TitleFontWeight` and `SubtitleFontWeight` are read-only, with the reason shown, while the Title or Subtitle has an explicit `FontWeight`, because they have no effect then. An explicit text size stops applying when a later setting returns it to automatic: setting the axes `FontSize` does so for every title and label, and `xlabel`, `ylabel`, and `zlabel` calls do so for their label, which from R2024b also includes its `FontWeight`. Editing such a size writes the new value after that setting.
- Add a ColorBar to an axes through the context menu. Select it beneath its axes in the hierarchy to edit its supported properties. The Colormap editor belongs to the axes and supports built-in palettes and custom color stops.
- Reviewed axes value/Mode pairs follow their original initialization order. A later automatic mode can make the effective value unknown; the editor keeps the explicit source input and reports that uncertainty. Generated initialization preserves the requested final mode.
- Axes/UIAxes grid widths follow upstream widths in auto mode and hold their current values in manual mode. New upstream assignments preserve existing manual hold points. Reviewed color/alpha modes keep stored values separate from the rendered appearance.
- Reviewed simple controls share `Position`, `InnerPosition`, and read-only `OuterPosition` getters. Later writable aliases determine the effective geometry while original inputs retain their own source tokens. Lamp's getters use the smaller requested dimension for both width and height. These reviewed controls support finite nonnegative sizes, including zero-sized copies. An earlier `Position` edit shadowed by a later alias is rejected without changing history. Copies preserve the effective geometry, including their placement offset. Grid layout geometry remains managed by the layout rather than an alias literal. Parent changes also verify the requested geometry before committing history.
- Grid Layout track getters include flexible padding required by direct-child placements. The editor retains explicit track inputs, resolves implicit child positions from initialization order, and uses the resulting layout for Preview and copies. Moving children out releases implicit padding. Track edits and combined grid/child edits must survive generated initialization before they commit. Unknown placement expressions remain unresolved; `fit` stays a stored token rather than a predicted pixel measurement.
- Compare the original and generated source in Diff Preview. The panes scroll together and highlight added, deleted, and modified lines. The map shows changes across the source and the currently visible range. Click the map to jump to a location. Save to a new path or to an explicitly confirmed path.
- Show diagnostics for unsupported or ambiguous structures.
- A warning reports a component whose Units are known and not `pixels`, such as `normalized`, when its direct parent resizes its children automatically: the parent has `AutoResizeChildren` and does not set it to `'off'`, so the native `'on'` applies. MATLAB recommends `AutoResizeChildren` `'on'` only for apps laid out in pixel units, because non-pixel units might cause unexpected behavior, and Safe Preview may not show the problem. Set the parent's `AutoResizeChildren` to `'off'` or use pixel units. A parent setting whose value cannot be resolved reports nothing. The Inspector also tints that component's Units editor yellow and explains the risk by hover.
- Track unsaved edits in the editor title. New, Open, and closing the editor offer Save, Discard, or Cancel when required; a canceled or failed save leaves the current document open.

### Copy, cut, paste, delete, and move

- These operations act on a component and its descendants. Copy leaves the document clean if there were no previous edits. Cut removes the subtree immediately. Cut, Paste, Delete, and moving a subtree are each one Undo/Redo step. Undo leaves the clipboard available.
- Copy gives pasted components unique names with a `Copy` suffix. Paste after Cut tries the original names and uses numeric suffixes on collisions. Cut selects the former parent and Paste selects the inserted component. Clipboard contents belong to the current document in one editor window. A successful New, Open, or Reload clears them.
- Paste uses the closest compatible container, offsets absolutely positioned components, and looks for free cells in a grid without adding tracks. Drag a component on the canvas to change its parent. The move relocates owned initialization statements after the new parent is created and updates the root component’s placement. An explicit grid drop uses the indicated cell, permits overlap, and clips the span to the remaining tracks. Rejected or canceled operations leave the current document and clipboard intact.
- Copy, Cut, and Delete are available for non-root components in Hierarchy, including components with a read-only Inspector. Paste is available with a selection and clipboard contents. It checks the destination and placement when run. Moving a subtree has its own placement and source-ownership requirements.
- Copy and Cut retain owned initialization statements in execution order. They preserve constructor arguments, recognized settings, and opaque setting expressions. Paste changes the component names and parent, adjusts the root placement when it can be resolved, and remaps recognized component references. Copied references to targets outside the subtree continue to point to the existing targets. Paste reports an error if a recognized reference target has since been removed.
- Delete and Cut manage declarations and recognized initialization settings. The surviving parent’s owned selection of a deleted child is adjusted within the same undo step. References in user-written application logic and unrecognized initialization code remain the user’s responsibility.
- Copy and Cut carry callback connections and reuse the existing handler methods. Delete removes owned connections with the component and retains the handler methods. Safe Preview continues to skip callback bindings and opaque expressions.
- Components unavailable in the running MATLAB release retain their source settings when copied, cut, pasted, or deleted. A move within the current parent still requires explicit, owned placement settings.

### Callback management

Right-click a component in **Hierarchy** and choose **Manage Callbacks**. The dialog applies to that component without changing the current selection. Each row offers **New**, **Disconnect**, and compatible existing methods. New creates a named method and connects it. New close handlers start with `delete(app)`. A method can be connected to several callbacks.

Disconnect removes the binding and keeps the method body. Disconnecting the close handler of a new app restores the default close behavior. Close the dialog to keep your edits, or use Undo to reverse an individual change. Use MATLAB's editor to change or remove method bodies.

Supported bindings include direct method handles and two-input forwarding functions such as `@(~, event) app.SomeButtonPushed(event)`. A forwarding function can pass its named inputs in order or call the method with no arguments. Expressions with computed or captured arguments and incompatible signatures restrict editing. The dialog explains unavailable bindings and indicates when argument types could not be checked.

### Reload externally edited code

Use **Edit > Reload Source**, the toolbar refresh button, or **F5** after saving the file in MATLAB. Reload reads the disk file, closes callback dialogs, clears Undo/Redo, and keeps the selected component where its name still identifies it uniquely. If you have unsaved edits in yamada, choose Save, Discard, or Cancel. If both copies changed, save the yamada edits under another filename to retain both versions. A failed reload leaves the current document open.

## Standard Component Catalog

The catalog includes the following persistent MATLAB UI components and creation variants. The catalog of each release offers only what that release provides: `uicolorpicker` requires R2024a and the range-slider variant of `uislider` requires R2023b, and some properties of other components are likewise limited to the releases that provide them.

- Basic controls: `uilabel`, `uibutton`, `uicheckbox`, `uicolorpicker`, `uidatepicker`, `uidropdown`, `uieditfield`, `uihyperlink`, `uiimage`, `uilistbox`, `uiradiobutton`, `uislider`, `uispinner`, `uitable`, `uitextarea`, and `uitogglebutton`
- Containers and layout: `uifigure`, `uipanel`, `uigridlayout`, `uitabgroup`, `uitab`, and `uibuttongroup`
- Trees: `uitree` and `uitreenode`
- Axes: `uiaxes`, `axes`, `geoaxes`, and `polaraxes`
- Instrumentation: `uigauge`, `uiknob`, `uilamp`, and `uiswitch`
- Extended display and figure tools: `uihtml`, `uicontextmenu`, `uimenu`, `uitoolbar`, `uipushtool`, and `uitoggletool`

R2026b changes that the catalog does not support yet: R2026b lets radio and toggle buttons be placed directly in containers other than a button group, adds their read-only `Group` property, and introduces `uiselectiongroup`, while `uibuttongroup` becomes not recommended. In every release, yamada accepts `uiradiobutton` and `uitogglebutton` only as children of `uibuttongroup`. A button placed elsewhere is reported as an invalid parent, `uiselectiongroup` is retained as unsupported source and is not previewed, and editing apps that use these R2026b features is outside the supported contract. R2026b also places new radio and toggle buttons at a different default position.

Menu and context-menu branches are preserved in loaded source and omitted from the component Hierarchy.

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

- An edit replaces the existing value where it was set, including a constructor name-value argument, a later assignment, or the argument of a recognized axes setting function call such as `xlim(app.UIAxes, [0 1])`. Earlier settings and nearby comments are preserved. A value that a call implies without an argument of its own, such as the manual `XLimMode` of `xlim(app.UIAxes, [0 1])`, is changed by a new setting after that call. Reviewed `axis` forms are recognized, including the aspect-ratio forms `equal`, `image`, `square`, `normal`, and `vis3d` and calls that list several of them, whose fixed ratios, Modes, and limit methods are recorded as implied values; ratios they derive from the data or the axes size remain automatic, and `fill` is not modeled because its effect depends on the current Modes. In `axis(app.UIAxes, [0 1 2 3])`, editing `XLim` rewrites its two elements of the vector and keeps the others, and `axis(app.UIAxes, "off")` is edited in place. The values that `axis(app.UIAxes, "tight")`, `"auto"`, `"manual"`, `"ij"`, and `"xy"` set for every axis are changed by new settings after the call, as are values of other arguments that set several properties at once, such as `XGrid` of `grid(app.UIAxes, "on")`. Calls with an implicit axes target, such as `axis("equal")`, are never rewritten; an edit of a value they set, including the axis style or `vis3d`, adds an explicit call after them, such as `axis(app.UIAxes, "square")`. Turning `vis3d` off after such a call writes `normal` followed by the current style, because only `normal` returns its Modes to automatic. Axes setting calls in command syntax, such as `axis equal vis3d` or `grid on`, always target the current axes and are read like implicit-target calls whose words are character-vector arguments. A command whose words are not plain keywords, such as `xlim [0 1]`, or that matches no reviewed form is preserved without modeling its effects, and a warning reports it.
- A new axes setting follows the method of the main setting it depends on. Text formatting such as `Title.Color` joins an existing `title(app.UIAxes, "A")` call as a name-value option, or follows an existing assignment of `Title.String`. Without such a main setting, a reviewed axes setting function is used when one writes exactly that property, for example `xlim`, `xticks`, `box`, `title`, or `geotickformat`; a new setting of the same function joins an existing call when that call can hold it. Functions that also change other properties, such as `xticklabels`, `grid`, `xlim("tight")`, `xtickformat`, which also returns manual tick labels to automatic labels, or `axis`, are not used for new settings. Other settings become constructor name-value arguments when the creation statement sets properties only through verified name-value arguments, and assignments otherwise.
- An editable literal can still have effects yamada has not modeled. In that case the Inspector shows the stored input. Settings with known unsupported effects can block an edit. Source expressions and read-only properties retain their own editing restrictions.
- RadioButton and ToggleButton selection uses the owning ButtonGroup and sibling creation order. Mixed RadioButton/ToggleButton groups and unresolved selection references remain outside the supported contract. No handle-reference editor is provided.
- Nonempty construction callbacks, uncataloged setters, and unsupported Parent/Children assignments prevent guarantees about initial values, including those of destination siblings. Unknown initialization calls are preserved and diagnosed, but their effects are the user's responsibility and do not make every component state uneditable. Modeled values describe recognized initialization settings, not the effects of arbitrary code. Callback registration alone does not imply that its body executed.
- Finite geometry rules cover reviewed stored Position inputs, slider thickness, and selected knob/gauge square adjustments. Decoration-dependent getters and child positions affected by later ancestor resizing remain unknown. Axes camera coupling and unresolved tree/tab references are explicitly bounded rather than approximated as independent values.
- Move and save check the settings and component relationships yamada supports. Mismatched `Items` and `ItemsData` lengths are outside the supported editing scope.

## Editing and Source Preservation

- Generating an existing source file without edits does not change its original text.
- Edits make localized changes only to declarations, creation statements, and assignments whose ownership can be determined safely.
- Adding a setting preserves existing statement order and does not interpret unknown code. Arbitrary user-code effects remain outside the editing guarantee.
- A new setting that other settings depend on, such as `Units` before `Position` or `Limits` before `Value`, is added before them when possible. Whenever adding or editing such a setting would leave an existing dependent literal different from its final value, for example by clamping `Value`, that literal is rewritten to the final value in the same edit, wherever the setting is placed. A value restricted by such a setting, such as `Value` by `Limits`, also keeps its current value when the new range still accepts it, as it would in a running app, and a `Value` setting is added when source has none. A later wider `Limits` therefore keeps the clamped `Value` instead of reviving the discarded one, and a narrower `Limits` clamps a later `Value` setting instead of being rejected.
- Checkbox Tree supports literal `Position` edits in its original assignment or constructor argument. The Inspector edits `Position` and preserves existing writable `InnerPosition` settings.
- The Position row shows `X`, `Y`, `W`, and `H` in MATLAB vector order. A slider dimension fixed by its orientation is displayed read-only.
- Axes, polar axes, and geographic axes accept `Units` edits. A new `Units` setting is added before existing `Position` settings, and changing `Units` in the Inspector converts existing `Position`, `InnerPosition`, and `OuterPosition` literals so the component keeps its size and location. Canvas moves and resizes of axes in other units are written in those units.
- An aspect-link marker indicates a fixed width-to-height relationship. Editing either linked size adjusts both dimensions in one Undo step.
- Reviewed Position constraints cover square Lamp/Knob/Gauge families, fixed-thickness sliders, all Switch styles, and the semicircular Gauge. Switch and semicircular Gauge Position are editable within the normal literal/source-ownership contract; decoration-dependent aliases remain outside that finite policy. Linear Gauge width and height are independent: Inspector edits and Preview resizing preserve both requested dimensions without an aspect link; Orientation changes exchange the dimensions in actual setter order. Grid-managed and natively read-only Position properties keep their existing restrictions.

- If an insertion point or ownership range required for addition or deletion is ambiguous, the edit or save is rejected with a diagnostic.
- Failed validation of a supported value restricts Preview or saving as necessary for safety.
- Deletion occurs only after an explicit user action.
- Visual Grid Layout editing accepts only supported literal, source-owned track and placement values. Expression-backed tracks or placements, implicit placements, ambiguous geometry, and out-of-range placements are rejected without a partial document update. Moving and resizing children may create overlapping placements, as MATLAB allows.

`yamada` prioritizes source preservation, but it does not guarantee complete round-tripping of arbitrary MATLAB syntax. Use version control such as Git or create a backup before editing an existing file.

## Output

- Output is ordinary handle `.m` source that can be reviewed and compared as text.
- Generated apps stay open when launched without an output variable and release their window when closed. Generated callback methods receive `(app, source, event)`; disconnecting a callback retains its method body.
- Files are written as UTF-8 without a BOM.
- If writing the temporary copy fails, the existing file keeps its original contents. If Windows moves the original during a failed replacement, yamada tries to restore it and reports the recovery location if needed. A failed save keeps your unsaved edits and last successful save state. Keep backups for power loss or storage failure.
- A new file includes the class and component declarations, initialization, and cleanup required for execution.
- New files use the host platform's standard line ending; existing files preserve the detected CRLF or LF convention.
- Generated comments and help text are written in English.
- Newly generated applications include English class and method documentation.
- Editing existing applications preserves user-authored documentation and formatting except where supported edits require changes. yamada's internal coding conventions are not imposed on user application source.
- `yamada` does not automatically add, replace, or remove the project's license notice in an application created or opened by the user.
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
