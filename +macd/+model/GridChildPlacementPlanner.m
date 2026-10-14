classdef GridChildPlacementPlanner
    % GridChildPlacementPlanner Plan safe immediate-child Grid Layout placement changes.
    %   This utility relocates or resizes explicit child placements, rejects
    %   out-of-range targets, allows overlapping placements, and returns one atomic
    %   DocumentModel grid-edit change set without mutating the document.

    methods (Static)
        function changes = move(document, gridId, childId, rowStart, columnStart, rowCount, columnCount)
            % move Relocate one explicit child while preserving spans within the grid.
            arguments (Input)
                document (1, 1) macd.model.DocumentModel
                gridId (1, 1) string
                childId (1, 1) string
                rowStart (1, 1) double
                columnStart (1, 1) double
                rowCount (1, 1) double
                columnCount (1, 1) double
            end

            child = document.getComponent(childId);
            if isempty(child)
                error("macd:GridChildPlacementPlanner:InvalidChild", ...
                    "Child must be an immediate component of the active Grid Layout.");
            end
            [oldRows, oldColumns] = macd.model.GridChildPlacementPlanner.placement(child);
            rowEnd = rowStart + oldRows(end) - oldRows(1);
            columnEnd = columnStart + oldColumns(end) - oldColumns(1);
            changes = macd.model.GridChildPlacementPlanner.resize(document, gridId, childId, ...
                rowStart, rowEnd, columnStart, columnEnd, rowCount, columnCount);
        end

        function changes = resize(document, gridId, childId, rowStart, rowEnd, ...
                columnStart, columnEnd, rowCount, columnCount)
            % resize Change one explicit child span within the grid, allowing overlap.
            arguments (Input)
                document (1, 1) macd.model.DocumentModel
                gridId (1, 1) string
                childId (1, 1) string
                rowStart (1, 1) double
                rowEnd (1, 1) double
                columnStart (1, 1) double
                columnEnd (1, 1) double
                rowCount (1, 1) double
                columnCount (1, 1) double
            end

            grid = document.getComponent(gridId);
            child = document.getComponent(childId);
            if isempty(grid) || grid.Factory ~= "uigridlayout" || isempty(child) || ...
                    child.ParentId ~= gridId
                error("macd:GridChildPlacementPlanner:InvalidChild", ...
                    "Child must be an immediate component of the active Grid Layout.");
            end
            macd.model.GridChildPlacementPlanner.placement(child);
            target = [rowStart rowEnd columnStart columnEnd rowCount columnCount];
            if any(~isfinite(target)) || any(target ~= floor(target)) || ...
                    any([rowStart columnStart rowCount columnCount] < 1) || ...
                    rowEnd < rowStart || columnEnd < columnStart
                error("macd:GridChildPlacementPlanner:InvalidTarget", ...
                    "Target cell and grid track counts must be positive integers.");
            end
            if rowEnd > rowCount || columnEnd > columnCount
                error("macd:GridChildPlacementPlanner:OutOfBounds", ...
                    "The child span does not fit within the Grid Layout.");
            end
            % MATLAB permits multiple children to occupy the same grid cells.
            rowValue = rowStart;
            if rowEnd ~= rowStart, rowValue = [rowStart rowEnd]; end
            columnValue = columnStart;
            if columnEnd ~= columnStart, columnValue = [columnStart columnEnd]; end
            changes = [struct("ComponentId", childId, "Path", "Layout.Row", "Value", {rowValue}), ...
                struct("ComponentId", childId, "Path", "Layout.Column", "Value", {columnValue})];
        end
    end

    methods (Static, Access = private)
        function [rows, columns] = placement(child)
            % placement Read one editable explicit row/column placement pair.
            rows = macd.model.GridChildPlacementPlanner.coordinate(child, "Layout.Row");
            columns = macd.model.GridChildPlacementPlanner.coordinate(child, "Layout.Column");
        end

        function value = coordinate(child, path)
            % coordinate Validate and return one scalar or contiguous span coordinate.
            entry = child.getProperty(path);
            if isempty(entry) || entry.ValueKind ~= "literal" || ~entry.IsEditable || ...
                    ~isnumeric(entry.LiteralValue) || ~isvector(entry.LiteralValue) || ...
                    isempty(entry.LiteralValue) || numel(entry.LiteralValue) > 2 || ...
                    any(entry.LiteralValue < 1) || any(entry.LiteralValue ~= floor(entry.LiteralValue))
                error("macd:GridChildPlacementPlanner:ImplicitPlacement", ...
                    "The child placement must be an editable literal.");
            end
            value = double(entry.LiteralValue);
        end
    end
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
