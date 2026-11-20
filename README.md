# waitForFigureLayout

Resizing a container can leave a child of a `uigridlayout` reporting its previous position even after `drawnow`.
`waitForFigureLayout(fig)` waits for a MATLAB figure's browser-side layout to settle before you read a component's `Position`.

## Installation

Download and extract the files. Keep `waitForFigureLayout.m`, `waitForFigureLayout.js`, and `FigureLayoutWaitReply.m` together. Make their parent folder your MATLAB current folder or add it to the MATLAB path.

## Usage

```matlab
fig = uifigure;  % Through R2024b
% For R2025a or later, use this line to create the figure:
% fig = matlab.ui.internal.uifigureIsolated;

panel = uipanel(fig, "AutoResizeChildren", "off", "Position", [20 20 300 250]);
grid = uigridlayout(panel, [1 1]);
child = uilabel(grid, "Text", "Grid child");

drawnow;
waitForFigureLayout(fig);  % Install resize hooks before changing the layout.
panel.Position(3:4) = [400 300];
drawnow;
waitForFigureLayout(fig);  % Wait for layout after the change.
drawnow;
position = child.Position
```

Repeat the `drawnow` and wait sequence after later layout changes, before reading the affected components' positions.

Use `info = waitForFigureLayout(fig)` to inspect the wait. The output includes:

| Field | Meaning |
| --- | --- |
| `hooked`, `watched` | Number of newly hooked and total observed resize emitters |
| `quieted` | The resize quiet period completed within 3 seconds |
| `imagesWaited`, `imagesLoaded` | Number of pending images observed and whether all became complete or reported an error within 500 ms |
| `stabilized` | The browser ViewModel's `stabilize()` was available and completed within 500 ms |
| `framed` | The browser delivered an animation frame within 500 ms |
| `matlabSeconds`, `token` | Total elapsed time on the MATLAB side and the request identifier |

When a browser stage reaches its time limit, its flag is false and the wait continues to the next stage. Callers that require a settled layout can check the relevant flags before using the positions.

## Demo

`layoutWaitDemo` applies two quick resizes to a container and compares a grid child's first position reading with one taken half a second later. It reports how often the readings differ and the median time spent in the extra wait step.

```matlab
layoutWaitDemo(false)  % Read after drawnow
layoutWaitDemo(true)   % Wait for the browser layout before reading
```

The demo uses `uifigure` as shipped. For the browser-wait run in R2025a or later, change the figure constructor in `layoutWaitDemo.m` to `matlab.ui.internal.uifigureIsolated`, keeping the existing `Position` argument.

## How it works

The Grid Layout controller in the inspected releases throttles parent resize callbacks to 200 ms. A resize burst can leave a trailing callback on a timer, outside the work tracked by the ViewModel's `stabilize()` method.

The function runs JavaScript inside the figure's browser window and wraps internal container resize event emitters. It waits for 220 ms of quiet, allowing for the 200 ms throttle plus a 20 ms margin. Each observed resize restarts the quiet period, giving nested layouts time to schedule their own resize work. It then waits for pending images, awaits `stabilize()` where available, and waits one animation frame. The completion event goes back to MATLAB through the figure's ViewModel, following position notifications already dispatched on that channel. MATLAB uses `waitfor` and a single-shot timeout timer to receive the result.

The resize hooks stay installed for the life of the figure. The 220 ms quiet period is a heuristic, so layout changes scheduled for later can still change `Position`. The function raises an error if the browser reports a failure or MATLAB times out waiting for the reply.

## Compatibility

The implementation relies on undocumented MATLAB and browser internals that can change between releases. It requires a figure with a CEF browser window. In interactive Windows desktop sessions, use `uifigure` on R2023a–R2024b and the undocumented `matlab.ui.internal.uifigureIsolated` constructor on R2025a–R2026b.

## Validation on Windows

In the [MATLAB Central discussion](https://jp.mathworks.com/matlabcentral/discussions/tips/891776-the-only-hacky-thing-to-do-reliably-reading-component-positions-in-a-matlab-uifigure), I reports that three component rectangles in a nested layout matched readings taken 0.5 seconds later in all 192 interactive desktop trials across R2023a–R2026b.

The same discussion reports results for the smaller two-resize demo on R2023a, R2024b, and R2026b. In each release, the position changed after the first read in 8 of 8 trials with `drawnow` alone and in 0 of 8 trials with the browser wait.

## Background

- [MATLAB Central discussion on the layout-wait mechanism](https://jp.mathworks.com/matlabcentral/discussions/tips/891776-the-only-hacky-thing-to-do-reliably-reading-component-positions-in-a-matlab-uifigure)
- [Qiitaの日本語記事](https://qiita.com/N-Kaitoh/items/4277e55136cf6ad5788b)

## License

GNU General Public License v3.0 or later. See [LICENSE](LICENSE).
