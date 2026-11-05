function results = ProbeGridLayoutInteractions(outputPath)
% ProbeGridLayoutInteractions Observe track and child-placement effects on owned grids.
%   Literal-only fixtures supplement the documented R2024a grid contracts.
arguments (Input)
    outputPath (1, 1) string
end
arguments (Output)
    results (1, :) struct
end

% Keep every native object inside a hidden figure owned by this fixture.
figure = uifigure("Visible", "off");
cleanup = onCleanup(@() delete(figure));
results = struct("Case", {}, "Rows", {}, "Columns", {}, "Children", {}, "Error", {});
for axis = ["Row", "Column"]
    for scenario = ["grow", "shrinkOccupied", "shrinkMoved", "expandPlacement", ...
            "span", "deleteChild", "shrinkPartial", "empty", "constructor", ...
            "moveBack", "fillHole", "overlap", "zeroColumns", "zeroRows", "emptyOccupied", "shrinkThenMove"]
        grid = uigridlayout(figure, [2 2]);
        grid.RowHeight = {100, 200};
        grid.ColumnWidth = {110, 210};
        path = "RowHeight";
        if axis == "Column", path = "ColumnWidth"; end
        errorText = "";
        try
            switch scenario
                case "grow"
                    for index = 1:5, uibutton(grid, "Tag", string(index)); end
                case {"shrinkOccupied", "shrinkMoved", "shrinkPartial", "deleteChild"}
                    child = uibutton(grid);
                    child.Layout.(axis) = 2;
                    if scenario == "shrinkMoved", child.Layout.(axis) = 1; end
                    if scenario == "deleteChild", delete(child); end
                    grid.(path) = {50};
                    if scenario == "shrinkPartial", grid.(path) = {60, 70, 80}; grid.(path) = {40}; end
                case "expandPlacement"
                    child = uibutton(grid);
                    child.Layout.(axis) = 4;
                case "span"
                    child = uibutton(grid);
                    child.Layout.(axis) = [2 4];
                    grid.(path) = {50};
                case "empty"
                    grid.(path) = {};
                case "constructor"
                    delete(grid);
                    grid = uigridlayout(figure, [3 4], "RowHeight", {55}, "ColumnWidth", {65, 75});
                case "moveBack"
                    child = uibutton(grid);
                    child.Layout.(axis) = 4;
                    child.Layout.(axis) = 1;
                case {"fillHole", "overlap"}
                    first = uibutton(grid, "Tag", "first");
                    first.Layout.Row = 2;
                    first.Layout.Column = 2;
                    second = uibutton(grid, "Tag", "second");
                    if scenario == "overlap"
                        second.Layout.Row = 2;
                        second.Layout.Column = 2;
                    end
                    uibutton(grid, "Tag", "third");
                case "zeroColumns"
                    grid.ColumnWidth = {};
                    uibutton(grid);
                case "zeroRows"
                    grid.RowHeight = {};
                    uibutton(grid);
                case "emptyOccupied"
                    child = uibutton(grid);
                    child.Layout.(axis) = 2;
                    grid.(path) = {};
                case "shrinkThenMove"
                    child = uibutton(grid);
                    child.Layout.(axis) = 2;
                    grid.(path) = {50};
                    child.Layout.(axis) = 1;
            end
            drawnow;
        catch exception
            errorText = string(exception.identifier) + ": " + string(exception.message);
        end
        children = struct("Tag", {}, "Row", {}, "Column", {});
        for child = reshape(flipud(grid.Children), 1, [])
            children(end + 1) = struct("Tag", child.Tag, "Row", child.Layout.Row, "Column", child.Layout.Column); %#ok<AGROW>
        end
        results(end + 1) = struct("Case", axis + ":" + scenario, "Rows", {grid.RowHeight}, ...
            "Columns", {grid.ColumnWidth}, "Children", children, "Error", errorText); %#ok<AGROW>
        delete(grid);
    end
end

% Record getter values separately from source occurrences and policy decisions.
file = fopen(outputPath, "w", "n", "UTF-8");
assert(file >= 0, "yamada:ProbeGridLayoutInteractions:WriteFailed", "Cannot open probe output.");
fileCleanup = onCleanup(@() fclose(file));
fprintf(file, "%s\n", jsonencode(struct("matlabRelease", "R2024a", "results", results), "PrettyPrint", true));
fprintf("GRID_LAYOUT_PROBE Cases=%d Errors=%d\n", numel(results), sum(strlength(string({results.Error})) > 0));
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
