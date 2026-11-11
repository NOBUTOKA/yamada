# yamada - Yet Another MATLAB App Designer Alternative

`yamada` is a visual editor for GUI classes that inherit from `handle` and own a `uifigure`. You can create or open ordinary MATLAB `.m` class files and edit their UI components graphically.

## Important

`yamada` is under active development. Development and verification currently target MATLAB R2024a, and no versioned release is available yet. Review the generated diff before saving, and keep the target file under version control or make a backup.

## Features

- Create a new MATLAB GUI app or open a supported `.m` class for editing.
- Add components, edit properties, and arrange components on the canvas or in a Grid Layout.
- Rename, copy, cut, paste, and move supported components and their children. Undo or redo edits.
- Connect callbacks to new or existing methods and disconnect them while retaining the method bodies.
- Preview supported UI components without running the input app or its callbacks.
- Review diagnostics and source changes before saving an ordinary MATLAB `.m` file.

## Supported Environment

- MATLAB R2024a on 64-bit Windows, with a graphical session, JVM enabled, and MATLAB .NET support

The 1.0.0 release target is R2024a on Windows only. Other MATLAB releases, macOS, Linux, and MATLAB Online are not supported release targets. MATLAB is required; this is not a standalone application. The editor requires MATLAB without additional toolboxes.

## Getting Started

Clone the repository, or download and extract it from **Code > Download ZIP** on GitHub. Add the repository root to the MATLAB path and start `yamada`.

```matlab
projectRoot = "/path/to/yamada";
addpath(projectRoot);
yamada
```

The normal launch command requires neither parentheses nor an output assignment. Development and tests may retain the returned handle for inspection and explicit cleanup.

## Basic Usage

### Create a new application

1. Select **File > New** and enter a MATLAB class name, such as `MyApp`.
2. Add components from the palette on the left.
3. Select a component on the canvas or in **Hierarchy**, then change its settings in the Property Inspector on the right. Drag components to move them, or drag their resize handles to change their size.
4. Select **Tools > Validate** and review any reported problems.
5. Select **Tools > Diff Preview** to see the code changes before saving.
6. Select **File > Save** and choose where to save the `.m` file. Use **File > Save As** to save another copy.

An asterisk in the window title means you have unsaved changes. **Undo** and **Redo** let you step backward and forward through your edits.

### Edit an existing application

1. Select **File > Open** and choose a supported MATLAB application `.m` file. See [Scope and Limitations](#scope-and-limitations) for the supported application format.
2. Inspect its components on the canvas and in **Hierarchy**. Check any messages shown in the diagnostics area.
3. Edit the components and settings you need. Some settings may be read-only or unavailable for an existing application.
4. Check **Tools > Validate** and **Tools > Diff Preview**, then save. Choose **Save As** if you want to keep the original file.

The canvas shows a preview without running your application or its callbacks. It may not show everything that appears when you run the app in MATLAB.

### Arrange components in a Grid Layout

A Grid Layout arranges components in rows and columns. Select the grid or a component inside it to show its row and column controls.

- Click a row or column settings button beside the grid. Choose **Fit** to size it to its contents, a fixed pixel size, or a flexible weight such as `1x` to share the available space. The same controls let you insert or delete rows and columns.
- Drag a component to another cell. Drag its resize handles to make it cover more or fewer rows or columns.
- Use the Property Inspector to enter exact row and column positions, or to adjust spacing and padding.
- For a grid inside another grid, drag its frame or empty background to move the whole inner grid. Its row and column controls still edit the inner grid.

Some grid changes are unavailable when yamada cannot safely update the existing code. Review the explanation shown for the unavailable or rejected action. Moving components can leave them overlapping, so check the result on the canvas.

### Rename a component

Select a component in **Hierarchy** and press **F2**, or choose **Edit > Rename Component**. Type its new MATLAB name and press **Enter**; press **Escape** to cancel. If the name cannot be used, an explanation appears so you can correct it.

This changes the component's name in the MATLAB code, such as `app.Button`, and updates supported references in the same file. To change the text a user sees on a button or window, edit its **Text** or **Title** setting instead. References in other files are not updated.

### Copy, cut, and paste components

Select a component in **Hierarchy** or on the canvas, then use **Edit > Copy / Cut / Paste**, or **Ctrl+C / Ctrl+X / Ctrl+V**. These commands are also available by right-clicking a component in **Hierarchy**.

- Copying or cutting a container includes the components inside it. **Cut** removes them immediately; **Undo** restores them.
- Select the destination container before pasting. If it cannot contain the copied component, yamada looks for a suitable enclosing container. Hover over the status line to check the destination or read why an action is unavailable.
- Pasted components receive names that do not conflict with existing components. You can paste the same copy more than once.
- **Copy does not copy callbacks.** The original components and their callback code remain unchanged. Add callbacks to the pasted components separately if needed. Cut or Delete may be unavailable for components with callbacks.

The component clipboard works within the current document only. Switching documents or successfully reloading the current one clears it. Shortcuts inside text fields keep their normal text-editing behavior.

### Move components into another container

Drag a component on the canvas into a panel, tab, or other suitable container. Moving a container also moves the components inside it. A dashed guide shows the destination; red means the proposed move is unavailable. Release the mouse to finish, or press **Escape** to cancel.

For a Grid Layout destination, the component snaps to cells. A move into occupied cells is rejected. You can undo a completed move with one **Undo** action. For a move blocked by recent callback changes, save and use **Reload Source** before trying again.

### Choose or disconnect callbacks

Callbacks let you run MATLAB code when a user interacts with your app, such as clicking a button.

1. Right-click the component in **Hierarchy** and select **Manage Callbacks...**.
2. Use the dropdown beside a callback to select an existing method, or choose `<New...>` and enter a name to create one.
3. Choose `<Disconnect>` to stop that callback from calling its method. **The method and its code stay in the file**, so you can reconnect it later. This dialog does not delete methods.

Changes take effect as you make them; **Close** closes the dialog without canceling them. Use **Undo** to reverse a change. Some existing callbacks cannot be changed safely through this dialog; hover over the disabled dropdown to read the reason. Use MATLAB to edit callback code or delete unused methods; yamada does not run the callbacks.


### Edit code in MATLAB and reload it

1. Save your changes in yamada first.
2. Edit and save the app's `.m` file in MATLAB.
3. Return to yamada and use the toolbar **Refresh** button, **Edit > Reload Source**, or **F5**.

Reload reads the saved file, so unsaved changes in MATLAB's editor are not included. A successful reload clears yamada's Undo/Redo history. If you also have unsaved changes in yamada, follow the Save, Discard, or Cancel prompt. When both copies have changed, save your yamada edits under a different filename if you want to keep both versions.


## Scope and Limitations

Supported apps directly inherit from `handle` and own one `uifigure`. All their UI components must be descendants of that figure. Use an ordinary `.m` class with component creation and settings that yamada can read from source. `.mlapp` files and AppBase apps are outside the supported format.

The preview uses supported initialization settings. Some components and properties have limited editing or preview support, especially when their values depend on expressions or runtime code. The editor shows diagnostics when it cannot safely apply a change. See the [product specification](SPECIFICATION.md) for supported syntax, operations, and source-preservation limits.

## Documentation

- [Product specification](SPECIFICATION.md) - Current scope, input and output contract, and safety limitations
- [Roadmap](ROADMAP.md) - Independent tasks planned beyond the current supported behavior
- [Contributing guide](CONTRIBUTING.md) - Issues, development setup, tests, and pull requests

## Feedback and Contributions

Bug reports, feature proposals, documentation improvements, and code contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening an issue or pull request. Please discuss large features and design changes in an issue before starting implementation.

## License

This project is licensed under the GNU General Public License version 3 or later (`GPL-3.0-or-later`). See [LICENSE](LICENSE) for details.
