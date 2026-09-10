classdef GridChildPlacementPlanner
    % GridChildPlacementPlanner Plan safe immediate-child Grid Layout relocation.
    %   This utility preserves the selected child's existing row and column spans,
    %   rejects out-of-range targets and new overlaps, and returns one atomic
    %   DocumentModel grid-edit change set without mutating the document.

    methods (Static)
        function changes = move(document, gridId, childId, rowStart, columnStart, rowCount, columnCount)
            % move Relocate one explicit child while preserving spans and preventing new overlap.
            arguments (Input)
                document (1, 1) macd.model.DocumentModel
                gridId (1, 1) string
                childId (1, 1) string
                rowStart (1, 1) double
                columnStart (1, 1) double
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
            [oldRows, oldColumns] = macd.model.GridChildPlacementPlanner.placement(child);
            if any(~isfinite([rowStart columnStart rowCount columnCount])) || ...
                    any([rowStart columnStart rowCount columnCount] ~= ...
                    floor([rowStart columnStart rowCount columnCount])) || ...
                    any([rowStart columnStart] < 1) || rowCount < oldRows(end) - oldRows(1) + 1 || ...
                    columnCount < oldColumns(end) - oldColumns(1) + 1
                error("macd:GridChildPlacementPlanner:InvalidTarget", ...
                    "Target cell and grid track counts must be positive integers.");
            end
            rowEnd = rowStart + oldRows(end) - oldRows(1);
            columnEnd = columnStart + oldColumns(end) - oldColumns(1);
            if rowEnd > rowCount || columnEnd > columnCount
                error("macd:GridChildPlacementPlanner:OutOfBounds", ...
                    "The preserved child span does not fit within the Grid Layout.");
            end
            for siblingId = grid.Children
                if siblingId == childId, continue, end
                sibling = document.getComponent(siblingId);
                try
                    [siblingRows, siblingColumns] = macd.model.GridChildPlacementPlanner.placement(sibling);
                catch
                    continue
                end
                if rowStart <= siblingRows(end) && rowEnd >= siblingRows(1) && ...
                        columnStart <= siblingColumns(end) && columnEnd >= siblingColumns(1)
                    error("macd:GridChildPlacementPlanner:Overlap", ...
                        "Moving the child would create a new Grid Layout overlap.");
                end
            end
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
