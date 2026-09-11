classdef GridLayoutStructuralEditPlanner
    % GridLayoutStructuralEditPlanner Plan atomic insert and delete track changes.
    %   This utility derives only deterministic direct-child Layout.Row or
    %   Layout.Column edits. It never mutates the document; DocumentModel applies
    %   the returned change set atomically after its own source-safety preflight.

    methods (Static)
        function changes = insert(document, gridId, axis, index, trackValue)
            % insert Insert one flexible track and shift or expand explicit child placements.
            [path, childPath, tracks] = macd.model.GridLayoutStructuralEditPlanner.prepare( ...
                document, gridId, axis, trackValue);
            if ~isfinite(index) || index ~= floor(index) || index < 1 || ...
                    index > numel(tracks) + 1
                error("macd:GridLayoutStructuralEditPlanner:InvalidIndex", ...
                    "Insert index must identify a track boundary.");
            end
            values = macd.model.GridTrackList.items(trackValue);
            values = [values(1:index - 1), {"1x"}, values(index:end)];
            changes = macd.model.GridLayoutStructuralEditPlanner.trackChange(gridId, path, values);
            changes = [changes macd.model.GridLayoutStructuralEditPlanner.childChanges( ...
                document, gridId, childPath, index, "insert")];
        end

        function changes = delete(document, gridId, axis, index, trackValue)
            % delete Delete one track when every affected direct child has a safe placement.
            [path, childPath, tracks] = macd.model.GridLayoutStructuralEditPlanner.prepare( ...
                document, gridId, axis, trackValue);
            if numel(tracks) <= 1
                error("macd:GridLayoutStructuralEditPlanner:FinalTrack", ...
                    "The final Grid Layout track cannot be deleted.");
            end
            if ~isfinite(index) || index ~= floor(index) || index < 1 || index > numel(tracks)
                error("macd:GridLayoutStructuralEditPlanner:InvalidIndex", ...
                    "Delete index must identify an existing track.");
            end
            values = macd.model.GridTrackList.items(trackValue);
            values(index) = [];
            changes = macd.model.GridLayoutStructuralEditPlanner.trackChange(gridId, path, values);
            changes = [changes macd.model.GridLayoutStructuralEditPlanner.childChanges( ...
                document, gridId, childPath, index, "delete")];
        end

    end

    methods (Static, Access = private)
        function [path, childPath, tracks] = prepare(document, gridId, axis, trackValue)
            % prepare Validate grid identity, axis, and the supplied literal track list.
            arguments (Input)
                document (1, 1) macd.model.DocumentModel
                gridId (1, 1) string
                axis (1, 1) string
                trackValue
            end
            arguments (Output)
                path (1, 1) string
                childPath (1, 1) string
                tracks (1, :) struct
            end

            grid = document.getComponent(gridId);
            if isempty(grid) || grid.Factory ~= "uigridlayout"
                error("macd:GridLayoutStructuralEditPlanner:InvalidGrid", ...
                    "Grid layout ID must identify a Grid Layout.");
            end
            if axis == "row"
                path = "RowHeight";
                childPath = "Layout.Row";
            elseif axis == "column"
                path = "ColumnWidth";
                childPath = "Layout.Column";
            else
                error("macd:GridLayoutStructuralEditPlanner:InvalidAxis", ...
                    "Track axis must be row or column.");
            end
            tracks = macd.model.GridTrackList.describe(trackValue);
        end

        function changes = childChanges(document, gridId, path, index, operation)
            % childChanges Transform only explicit editable direct-child scalar or span placements.
            grid = document.getComponent(gridId);
            changes = struct("ComponentId", {}, "Path", {}, "Value", {});
            for childId = grid.Children
                child = document.getComponent(childId);
                entry = child.getProperty(path);
                if isempty(entry) || entry.ValueKind ~= "literal" || ~entry.IsEditable
                    error("macd:GridLayoutStructuralEditPlanner:ImplicitPlacement", ...
                        "Every affected child placement must be an editable literal.");
                end
                value = entry.LiteralValue;
                if ~isnumeric(value) || ~isvector(value) || isempty(value) || ...
                        numel(value) > 2 || any(value < 1) || any(value ~= floor(value))
                    error("macd:GridLayoutStructuralEditPlanner:InvalidPlacement", ...
                        "Every child placement must be a positive integer scalar or span.");
                end
                start = value(1);
                finish = value(end);
                if operation == "insert"
                    if start >= index
                        start = start + 1;
                        finish = finish + 1;
                    elseif finish >= index
                        finish = finish + 1;
                    end
                elseif start == index && finish == index
                    error("macd:GridLayoutStructuralEditPlanner:OccupiedTrack", ...
                        "A child occupying only the deleted track would be displaced.");
                elseif finish < index
                    % Keep a preceding placement unchanged.
                elseif start > index
                    start = start - 1;
                    finish = finish - 1;
                else
                    finish = finish - 1;
                end
                newValue = start;
                if finish ~= start
                    newValue = [start finish];
                end
                if ~isequal(newValue, value)
                    changes(end + 1) = struct("ComponentId", child.Id, ...
                        "Path", path, "Value", newValue); %#ok<AGROW>
                end
            end
        end

        function change = trackChange(gridId, path, values)
            % trackChange Pack one structurally changed list into a canonical safe literal.
            if all(cellfun(@isnumeric, values))
                value = cell2mat(values);
            elseif all(cellfun(@(item) ischar(item) || ...
                    (isstring(item) && isscalar(item)), values))
                value = string(values);
            else
                value = values;
            end
            change = struct("ComponentId", gridId, "Path", path, "Value", {value});
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
