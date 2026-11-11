# yamada Roadmap

For users following planned features and contributors choosing work, this roadmap describes what each improvement would let users do and the limits to preserve. The [product specification](SPECIFICATION.md) describes current behavior.

## Easier property editing

- **Reset properties from the Inspector.** Show when a property can be reset and let users undo the reset. Explain when an existing source expression prevents the change.
- **Choose related components from the Inspector.** Add selectors for supported references such as `ContextMenu` and `SelectedTab`, with choices limited to valid targets in the same application.
- **Choose component styles in the palette.** Offer a distinct creation choice for each supported style, with the correct initial settings and allowed parents.

## More ways to arrange components

- **Select multiple components.** Support rectangle selection on the canvas and range selection in the hierarchy. Keep one active component for existing Inspector and geometry tools until group editing is available.
- **Edit native hierarchies.** Add, reorder, move, and remove supported menus, toolbar tools, and tree nodes in the hierarchy. Provide a focused editing view for menu bars, submenus, context menus, and toolbar items, including context-menu assignment.

## Broader axes support

- **Create and edit programmatic axes.** Extend the supported palette and Inspector operations for Cartesian, geographic, and polar axes where creation and source generation can be verified.
- **Recognize axes setup calls.** Read settings expressed through calls such as `xlabel`, `ylabel`, `title`, and `xlim`. Support edits where the target and affected settings can be determined from source.

## More control when saving

- **Choose line endings in Save As.** Offer CRLF or LF as an explicit choice. Keep the current default for new files and preserve the detected convention of existing files unless the user chooses another.

## More responsive editing

Reduce the time spent selecting components, updating properties, and refreshing the preview, particularly in large or deeply nested apps. Keep source preservation, validation, and Undo/Redo guarantees. Contributors can use the [performance guide](tests/performance/README.md) to compare changes under matching conditions.

## Install and launch from MATLAB

Validate the `.mltbx` installer and both launch paths on the final release candidate. Check that the installed copy can create and open apps, edit and save source, and uninstall. The [release procedure](doc/RELEASING.md) describes the package contents and acceptance checks.
