# yamada - Yet Another MATLAB App Designer Alternative

`yamada` is a visual editor for `matlab.apps.AppBase` applications. It is similar in purpose to MATLAB App Designer, but **instead of using the dedicated binary `.mlapp` format**, it treats ordinary MATLAB class files (`.m`) as source. You can create a new application or open an existing AppBase class and inspect, arrange, and edit its UI components graphically.

## Important

`yamada` is under active development. Development and verification currently target MATLAB R2024a, and no versioned release is available yet. Review the generated diff before saving, and keep the target file under version control or make a backup.

## Features

- Create a runnable `matlab.apps.AppBase` subclass from an empty canvas
- Statically parse an existing `.m` class that follows a common App Designer-like structure
- Use a component palette, hierarchy browser, editing canvas, and typed Property Inspector
- Move and resize absolutely positioned components; edit Grid Layout tracks and direct-child placements on the Safe Preview
- Add and delete components and edit supported properties
- Preserve existing initialization settings and apply reviewed dependencies when
  adding properties, including supported axes value/Mode pairs
- Preserve manual grid-width holds when adding upstream axes widths, and track
  stored color values separately from automatic rendering modes
- Copy, cut, paste, delete, and reparent complete component subtrees with atomic Undo/Redo
- Rename component properties in the hierarchy, including static source references and default callback names
- Manage source-owned callbacks from a Hierarchy context menu, including empty handler generation and complete handler deletion
- View validation diagnostics and compare the original and generated source before saving
- Track unsaved edits and guard New, Open, and Close with Save, Discard, or Cancel
- Preserve unsupported code and nonliteral expressions where possible, and build a Safe Preview without running the input application or its callbacks
- Produce an ordinary, reviewable text-based `.m` source file **rather than a binary file**

## Supported Environment

- MATLAB R2024a

Compatibility with MATLAB releases other than R2024a is not currently guaranteed.

## Getting Started

Clone the repository, or download and extract it from **Code > Download ZIP** on GitHub. Add the repository root to the MATLAB path and start `yamada`.

```matlab
projectRoot = "/path/to/yamada";
addpath(projectRoot);
editor = yamada();
```

If the application object remains after you close the editor, delete it explicitly:

```matlab
delete(editor);
```

## Basic Usage

### Create a new application

1. Select **File > New** and enter a MATLAB class name.
2. Add components from the palette on the left.
3. Select a component on the canvas or in the hierarchy browser, then edit its supported properties in the Property Inspector on the right.
4. Select **Tools > Validate** to validate the document model.
5. Select **Tools > Diff Preview** to review the generated source, then use **File > Save As** to save it as a `.m` file.
   Save As asks before replacing an existing target; after a successful Save As,
   **File > Save** writes to that confirmed path without another replacement prompt.

An untouched empty document starts clean. The title gains an asterisk after the
first edit that has not been saved.

### Edit a Grid Layout

Select a Grid Layout or one of its children. The canvas activates the nearest
Grid Layout and shows its immediate rows, columns, and child occupancy without
changing the selected component in the Inspector.

- Click a row or column settings button beside the grid to choose **Fit**, a
  fixed pixel value, or a flexible `x` weight. The same popover inserts and
  deletes tracks.
- Drag the selected child to move its occupied cells. Drag one of its edge or
  corner handles to change its row or column span. The candidate is cell-snapped
  and commits only when released.
- For a selected nested Grid Layout, drag its frame or empty background to move
  it within the parent grid. Its handles change the parent-cell span while its
  row and column settings continue to edit the inner grid.
- Use the Inspector for `RowSpacing`, `ColumnSpacing`, `Padding` (in MATLAB
  order `[left bottom right top]`), `BackgroundColor`, `Visible`, and
  `Scrollable`. It also remains the exact-value fallback for a child's
  `Layout.Row` and `Layout.Column`.

Track editing accepts supported literal values and Preview defaults; a
source-backed track list remains read-only. Moving or resizing a child
requires editable, explicit `Layout.Row` and `Layout.Column` values and
unambiguous realized geometry. Track insertion or deletion is rejected when an
affected child has an implicit or expression-backed placement, or the change
would leave a child without a valid track. Stale canvas actions are also rejected.
Moving and resizing children may create overlapping placements, as MATLAB allows.
Source-backed values are preserved.

### Edit an existing application

1. Select **File > Open** and choose a `.m` file whose class derives from `matlab.apps.AppBase`.
2. Review the parsed hierarchy, Safe Preview, and diagnostics.
3. Modify supported components and properties.
4. Validate the document and review the diff. Save to a new file if you want to preserve the original.

### Rename a component

Select a component in **Hierarchy** and press **F2**, click the same selected node
again, or choose **Edit > Rename Component** (**F2**). Edit the name within the
hierarchy view; **Enter** commits and **Escape** cancels. Invalid or conflicting
names remain in the editor with an explanation so you can correct them.

Renaming changes the MATLAB property identifier and its static `app.Name`
references. Component IDs, displayed `Text` or `Title`, and the app class name
stay unchanged. Exclusively owned callback methods follow only when their names
match the editor's default generated naming convention; custom or shared handler
names stay unchanged. Class, property, and method help comments follow renamed
identifiers, including callback H1 lines and help examples. Ordinary comments and
code string literals are preserved. Undo and Redo treat the rename as one edit.
Source using dynamic dispatch or unresolved app aliases is rejected with an
explanation; references in other files are outside this operation's scope.

### Copy, cut, and paste components

Select a component in Hierarchy and use **Edit > Copy / Cut / Paste**, or
**Ctrl+C / Ctrl+X / Ctrl+V**. The same commands are available by right-clicking
a Hierarchy node. Right-click Copy targets that node without changing selection.
The same shortcuts work in Safe Preview. Edit menu shortcut hints use a separate
column, including F2 for Rename. Text fields retain their normal clipboard shortcuts.

The component and all descendants form one unit. Copy captures independent data;
later edits to the original do not change it. Cut removes the subtree immediately.
Paste creates fresh IDs and unique MATLAB property names and selects the inserted
root. Copy adds `Copy` to names; Cut retains the original names when available
and adds a numeric suffix only on collision. Cut and Paste each take one Undo
step. Repeated Paste is supported.

Paste uses the nearest compatible container, starting with the selected or
right-clicked node and walking up its ancestors. Absolute copies receive a small
offset; grid copies use a free rectangle while retaining their span. Hover over
the status line to see command availability, reasons, and the resolved Paste
destination. The clipboard belongs to this editor document; successful New,
Open, or Reload Source clears it. OS and cross-document clipboards are not used.

### Move a subtree to another container

In Safe Preview, drag a selected component into another visible container.
A dashed guide shows the proposed placement; red indicates an invalid target.
Grid destinations snap to cells and retain spans. Occupied or out-of-range
rectangles are rejected. Drop commits the parent and placement together as one
Undo step. Escape or pointer cancellation discards the draft. Moving within the
same parent continues to use the existing position or grid-placement tools.

Subtree operations require catalog-compatible parents and provable source
ownership. The root UIFigure, programmatic-only construction families, and native
FigureTools subtrees are excluded. Copy/Cut accept supported literals and static
`SelectedTab`/`ContextMenu` references: internal references follow the copies;
external context menus retain their identity in the same document. Other
expressions, executable callback bindings, and ambiguous source are rejected
without dropping their contents. Reparenting preserves existing callback methods;
pending callback edits on parsed moved nodes currently require Save and Reload
Source, or Undo, before moving. Review the generated diff before saving.

### Manage callbacks

Right-click a component in **Hierarchy** and choose **Manage Callbacks...**.
Right-clicking an unselected component leaves the current selection, Properties,
and Preview selection unchanged. The popup title identifies the component being
managed; its scrollable rows list callbacks supported by that component's catalog
variant.

- **Add** creates an assignment and a uniquely named empty method together.
- **Delete** removes the assignment and the entire handler method, including its
  body. Each action is one Undo/Redo operation and applies immediately; **Close**
  only closes the popup.
- Existing shared methods, arbitrary anonymous functions, constructor bindings,
  conditional/repeated assignments, dynamic references, and source whose ownership
  cannot be established have both buttons disabled. Hover over the row or buttons
  to read the reason.

Review the source diff before saving. To edit a handler body in MATLAB, first save
in yamada, edit and save the `.m` file in MATLAB, then use the toolbar **Refresh**
button, **Edit > Reload Source (F5)**, or **F5**. Reload reads the saved file; it
cannot read unsaved MATLAB editor buffers. New documents need to be saved first.
Local unsaved changes prompt Save/Discard/Cancel. If the file also changed outside
yamada, Save As must use a different file so external edits remain intact.
Successful reload resets Undo/Redo, closes the callback popup and retains the
selected component by a unique name where possible. Failed reload keeps the
current document.
The opened application's callbacks are never run by the editor or Safe Preview.

## Scope and Limitations

`yamada` catalogs standard persistent MATLAB R2024a UI components, containers, axes, instrumentation controls, menus, and toolbar tools. See the [product specification](SPECIFICATION.md) for the detailed component and property scope.

The following boundaries protect the input source:

- `.mlapp` files and their internal format are not supported.
- The input application's constructor, callbacks, helper methods, and arbitrary expressions are never executed.
- Initial property values follow statically resolved same-class calls from the constructor, including AppBase startup methods. Method names are unrestricted; callback registrations and anonymous callback bodies are excluded. Repeated calls retain their order. Dynamic calls, recursion, and unsupported call expressions produce diagnostics without executing source. For constructor-free fragments, a single identifiable factory-owning method is used with a warning. Runtime-only writes do not replace initial values or make those properties read-only; initialization expressions remain source-backed and read-only.
- Dynamic component creation and ambiguous source structures are restricted when they cannot be edited safely; diagnostics explain the restriction.
- Inclusion in the catalog does not mean that every component or property can be previewed, inserted, and edited to the same extent. Unsupported values may remain visible but read-only.
- Full App Designer compatibility and complete round-tripping of arbitrary MATLAB syntax are not goals.

See the [product specification](SPECIFICATION.md) for the current supported behavior, input and output contract, and safety limitations.

## Documentation

- [Product specification](SPECIFICATION.md) - Current scope, input and output contract, and safety limitations
- [Roadmap](ROADMAP.md) - Independent tasks planned beyond the current supported behavior
- [Architecture reference](doc/ARCHITECTURE.md) - Implemented layers, data flow, safety boundaries, and extension points
- [Contributing guide](CONTRIBUTING.md) - Issues, development setup, tests, and pull requests

## Feedback and Contributions

Bug reports, feature proposals, documentation improvements, and code contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening an issue or pull request. Please discuss large features and design changes in an issue before starting implementation.

## License

This project is licensed under the GNU General Public License version 3 or later (`GPL-3.0-or-later`). See [LICENSE](LICENSE) for details.
