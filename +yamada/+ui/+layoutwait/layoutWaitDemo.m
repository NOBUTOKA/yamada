function layoutWaitDemo(useBrowserWait, trials)
% layoutWaitDemo Compare a grid child's position after a resize burst and 0.5 s later.
%   Run layoutWaitDemo(false) for the MATLAB-only baseline.
%   Run layoutWaitDemo(true) with waitForFigureLayout.m and waitForFigureLayout.js in the same folder.
arguments (Input)
    useBrowserWait (1, 1) logical = false
    trials (1, 1) double {mustBeInteger, mustBePositive} = 8
end
changed = 0;
elapsed = zeros(1, trials);
for trial = 1:trials
    % Create a fresh grid so each trial starts from the same layout.
    fig = uifigure("Position", [100 100 700 600]);
    figureCleanup = onCleanup(@() delete(fig));
    outer = uipanel(fig, "AutoResizeChildren", "off", "Position", [20 20 500 400]);
    grid = uigridlayout(outer, [1 1]);
    child = uipanel(grid, "BackgroundColor", "red");
    drawnow;
    if useBrowserWait
        waitForFigureLayout(fig); % Install resize hooks before the first change.
    end
    pause(0.5);

    % Give the grid two parent-size changes within its throttle interval.
    outer.Position(3:4) = [250 200];
    drawnow;
    pause(0.05);
    outer.Position(3:4) = [650 550];
    drawnow;
    clock = tic;
    if useBrowserWait
        waitForFigureLayout(fig);
        drawnow;
    end
    elapsed(trial) = toc(clock);

    % A later read is a reference for this fixture, with no new changes.
    first = child.Position;
    pause(0.5);
    drawnow;
    later = child.Position;
    changed = changed + ~isequal(first, later);
    fprintf("%d: %s -> %s\n", trial, mat2str(first), mat2str(later));
    clear figureCleanup
end
fprintf("Position changed after first read: %d/%d. Median extra wait: %.3f s.\n", ...
    changed, trials, median(elapsed));
end

%{
Copyright (C) 2026 Nobuto Kaitoh

This file is part of waitForFigureLayout.

waitForFigureLayout is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

yamada is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with yamada. If not, see <https://www.gnu.org/licenses/>.
%}