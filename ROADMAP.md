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

- **Edit ruler details.** Add focused controls for tick formats, exponents, secondary labels, and supported rotations.
- **Edit geographic limits.** Set requested latitude and longitude together and surface the extent MATLAB displays.
- **Recognize more axes setup calls.** Support reviewed `axis` forms, aspect ratios, and absolute camera settings. Extend coverage of compound and data-dependent calls as their effects and ownership can be established.

## More control when saving

- **Choose line endings in Save As.** Offer CRLF or LF as an explicit choice. Keep the current default for new files and preserve the detected convention of existing files unless the user chooses another.

## More responsive editing

Reduce the time spent selecting components, updating properties, and refreshing the preview, particularly in large or deeply nested apps. Keep source preservation, validation, and Undo/Redo guarantees. Contributors can use the [performance guide](tests/performance/README.md) to compare changes under matching conditions.
