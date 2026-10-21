function snapshots = probeYamadaGridGeometry(options)
% probeYamadaGridGeometry Compare fresh boundary reconstruction with settled native measurements.
%   Parse a fixture and render registered controls without executing its handle-based class.
arguments (Input)
    options.FixturePath (1, 1) string
    options.OutputFolder (1, 1) string
    options.GridName (1, 1) string = "Grid1"
end
arguments (Output)
    snapshots (1, :) struct
end
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(root);
if ~isfolder(options.OutputFolder), mkdir(options.OutputFolder); end
registry = macd.model.ComponentRegistry.createDefault();
document = macd.source.AppSourceParser.parseFile(options.FixturePath, registry);
grid = document.getComponentByName(options.GridName);
assert(~isempty(grid) && grid.Factory == "uigridlayout");
figure = uifigure("Visible", "on", "Position", [100 100 1100 800]);
cleanup = onCleanup(@() delete(figure));
panel = uipanel(figure, "Position", [1 1 1060 760], "AutoResizeChildren", "off");
renderer = macd.ui.PreviewRenderer(registry);
[handles, diagnostics, canvas] = renderer.render(document, panel);
assert(isempty(diagnostics), "The geometry probe requires a fully rendered fixture.");
preview = handles(char(grid.Id));
builder = macd.ui.GridLayoutOverlayDataBuilder();
snapshots = struct("seconds", {}, "grid", {}, "native", {}, "fitMinimumHeight", {}, "remainingForFlexible", {});
clock = tic;
% Rebuild directly each time; no application geometry cache participates.
for requested = [0 1 3 6]
    while toc(clock) < requested, drawnow; pause(0.05); end
    drawnow;
    data = builder.build(document, handles, canvas, grid.Id, grid.Id, numel(snapshots) + 1, registry);
    children = struct("id", {}, "row", {}, "column", {}, "position", {}, "outer", {});
    for id = grid.Children
        child = handles(char(id));
        outer = double(child.Position);
        if isprop(child, "OuterPosition"), outer = double(child.OuterPosition); end
        children(end + 1) = struct("id", id, "row", double(child.Layout.Row), ...
            "column", double(child.Layout.Column), "position", double(child.Position), "outer", outer); %#ok<AGROW>
    end
    native = struct("position", double(preview.Position), "innerPosition", double(preview.InnerPosition), ...
        "rowHeight", {preview.RowHeight}, "columnWidth", {preview.ColumnWidth}, ...
        "rowSpacing", double(preview.RowSpacing), "columnSpacing", double(preview.ColumnSpacing), ...
        "padding", double(preview.Padding), "children", children);
    tracks = macd.model.GridTrackList.describe(preview.RowHeight);
    minimum = preview.RowSpacing * max(numel(tracks) - 1, 0);
    for index = 1:numel(tracks)
        if tracks(index).kind == "fixed"
            minimum = minimum + tracks(index).value;
        elseif tracks(index).kind == "fit"
            matching = children(arrayfun(@(item) isscalar(item.row) && item.row == index, children));
            if ~isempty(matching)
                lower = min(arrayfun(@(item) item.outer(2), matching));
                upper = max(arrayfun(@(item) item.outer(2) + item.outer(4), matching));
                minimum = minimum + upper - lower;
            end
        end
    end
    snapshots(end + 1) = struct("seconds", toc(clock), "grid", data, "native", native, ...
        "fitMinimumHeight", minimum, "remainingForFlexible", native.innerPosition(4) - minimum); %#ok<AGROW>
end
fid = fopen(fullfile(options.OutputFolder, "geometry-probe.json"), "w", "n", "UTF-8");
assert(fid >= 0);
fileCleanup = onCleanup(@() fclose(fid));
fprintf(fid, "%s", jsonencode(struct("matlab", version, "snapshots", snapshots)));
end

%{
Copyright (C) 2026 Nobuto Kaitoh

This file is part of yamada.

yamada is free software: you can redistribute it and/or modify
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
