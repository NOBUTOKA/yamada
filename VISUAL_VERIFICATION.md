# Visual verification procedure

Until Safe Preview can represent the editor application with no material layout
or component omissions, perform this manual comparison after parser or preview
renderer changes.

## Targets

- `tests/fixtures/SimpleCalculatorApp.m`
- `tests/fixtures/ControlGalleryApp.m`
- `tests/fixtures/AxesExplorerApp.m`
- `tests/fixtures/NavigationDataApp.m`
- `tests/fixtures/FigureToolsApp.m`
- `MatlabAppClassDesigner.m`

## Capture procedure

1. Start `MatlabAppClassDesigner` and use **File > Open** to load one target.
2. Wait for Safe Preview and the diagnostics drawer to finish laying out, then
   capture the full editor window. Include the hierarchy and diagnostics drawer.
3. For maintained fixtures only, run the named class from `tests/fixtures` in
   MATLAB, capture its application window, and close it. For the final target,
   start a separate `MatlabAppClassDesigner` instance and capture its window.
4. Compare the two captures at the same desktop scaling. Check root bounds,
   panel and grid placement, visible text, table headers, axes, and ordinary
   controls.
5. Record intentional omissions separately: callbacks must not execute, and
   native menus/toolbars are retained in source/model diagnostics but omitted
   from Safe Preview.

## Acceptance notes

- Save screenshots outside the repository unless they are needed as a reviewed
  regression artifact.
- A parser or preview change is not accepted based only on unit tests when a
  target has visible UI. Capture and compare the relevant target before closing
  the change.
- Do not execute arbitrary user-supplied classes for comparison. Runtime
  captures are limited to the maintained fixtures above and the editor itself.
