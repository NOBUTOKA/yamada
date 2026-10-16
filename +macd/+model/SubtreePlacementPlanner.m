classdef SubtreePlacementPlanner
    % SubtreePlacementPlanner Validate destinations and plan parent-dependent placement.
    %   This utility never mutates records. Reparent and Paste share its catalog,
    %   grid occupancy, and absolute/grid conversion rules.

    methods (Static)
        function plan = prepare(document, snapshot, parentId, registry, excludedIds, measuredPosition, offset, targetCell, targetPosition)
            % prepare Resolve valid root placement under an explicit destination parent.
            arguments (Input)
                document (1, 1) macd.model.DocumentModel
                snapshot (1, 1) macd.model.SubtreeSnapshot
                parentId (1, 1) string
                registry (1, 1) macd.model.ComponentRegistry
                excludedIds string = strings(1, 0)
                measuredPosition double {mustBeFinite} = []
                offset (1, 2) double {mustBeFinite} = [0 0]
                targetCell double {mustBeFinite} = []
                targetPosition double {mustBeFinite} = []
            end
            arguments (Output)
                plan (1, 1) struct
            end

            % Validate hierarchy and catalog applicability before choosing geometry.
            parent = document.getComponent(parentId);
            if isempty(parent) || ~parent.IsEditable
                error("macd:SubtreePlacementPlanner:InvalidParent", "Destination parent is missing or read-only.");
            end
            if any(excludedIds == parentId)
                error("macd:SubtreePlacementPlanner:CyclicParent", "A subtree cannot move under itself or its descendants.");
            end
            root = snapshot.Records(1);
            if root.Id == document.RootComponentId
                error("macd:SubtreePlacementPlanner:RootOperation", "The document root cannot be moved or pasted.");
            end
            for record = snapshot.Records
                if ~record.IsEditable
                    error("macd:SubtreePlacementPlanner:ReadOnly", "The subtree contains a read-only component.");
                end
                definition = registry.get(record.Factory, record.CreationArguments);
                if definition.IsProgrammaticOnly || definition.Category == "FigureTools"
                    error("macd:SubtreePlacementPlanner:UnsupportedFactory", "This construction family is not supported for subtree placement.");
                end
                parentFactory = parent.Factory;
                if record.Id ~= root.Id
                    ancestor = snapshot.Records(string({snapshot.Records.Id}) == record.ParentId);
                    parentFactory = ancestor.Factory;
                end
                if ~any(definition.AllowedParentFactories == parentFactory)
                    error("macd:SubtreePlacementPlanner:InvalidParent", "The destination does not accept this construction style.");
                end
            end
            definitions = registry.getEffectiveProperties(root.Factory, parent.Factory, root.CreationArguments);
            paths = string({definitions.Path});
            changes = struct("Path", {}, "Value", {}, "Remove", {});
            originalParent = document.getComponent(root.ParentId);
            wasGrid = ~isempty(originalParent) && originalParent.Factory == "uigridlayout";
            hasGridPlacement = any(string({root.Properties.Path}) == "Layout.Row");

            % Preserve span dimensions while finding an unoccupied destination rectangle.
            if parent.Factory == "uigridlayout" && any(paths == "Layout.Row")
                height = 1;
                width = 1;
                if wasGrid || hasGridPlacement
                    rows = macd.model.SubtreePlacementPlanner.coordinate(root.Properties, "Layout.Row");
                    columns = macd.model.SubtreePlacementPlanner.coordinate(root.Properties, "Layout.Column");
                    height = rows(end) - rows(1) + 1;
                    width = columns(end) - columns(1) + 1;
                end
                rowCount = macd.model.SubtreePlacementPlanner.trackCount(parent, "RowHeight", 1, registry);
                columnCount = macd.model.SubtreePlacementPlanner.trackCount(parent, "ColumnWidth", 2, registry);
                occupied = false(rowCount, columnCount);
                for childId = parent.Children
                    if any(excludedIds == childId), continue, end
                    child = document.getComponent(childId);
                    childSnapshot = macd.model.SubtreeSnapshot(document, childId);
                    values = childSnapshot.Records(1).Properties;
                    rows = macd.model.SubtreePlacementPlanner.coordinate(values, "Layout.Row");
                    columns = macd.model.SubtreePlacementPlanner.coordinate(values, "Layout.Column");
                    if rows(end) > rowCount || columns(end) > columnCount || isempty(child)
                        error("macd:SubtreePlacementPlanner:ImplicitPlacement", "Destination child placement is outside explicit tracks.");
                    end
                    occupied(rows(1):rows(end), columns(1):columns(end)) = true;
                end
                found = false;
                requestedRows = 1:rowCount - height + 1;
                requestedColumns = 1:columnCount - width + 1;
                if ~isempty(targetCell)
                    if numel(targetCell) ~= 2 || any(targetCell < 1) || any(targetCell ~= floor(targetCell)) || ...
                            targetCell(1) + height - 1 > rowCount || targetCell(2) + width - 1 > columnCount
                        error("macd:SubtreePlacementPlanner:InvalidCell", "The requested grid rectangle is outside the destination tracks.");
                    end
                    requestedRows = targetCell(1);
                    requestedColumns = targetCell(2);
                end
                for row = requestedRows
                    for column = requestedColumns
                        if ~any(occupied(row:row + height - 1, column:column + width - 1), 'all')
                            found = true;
                            break
                        end
                    end
                    if found, break, end
                end
                if ~found
                    error("macd:SubtreePlacementPlanner:NoSpace", "No unoccupied grid rectangle fits the subtree root.");
                end
                changes(end + 1) = macd.model.SubtreePlacementPlanner.change("Layout.Row", ...
                    macd.model.SubtreePlacementPlanner.span(row, height), false);
                changes(end + 1) = macd.model.SubtreePlacementPlanner.change("Layout.Column", ...
                    macd.model.SubtreePlacementPlanner.span(column, width), false);
                changes = macd.model.SubtreePlacementPlanner.removeIfPresent(changes, root.Properties, "Position");
            elseif parent.Factory ~= "uigridlayout"
                changes = macd.model.SubtreePlacementPlanner.removeIfPresent(changes, root.Properties, "Layout.Row");
                changes = macd.model.SubtreePlacementPlanner.removeIfPresent(changes, root.Properties, "Layout.Column");
                if any(paths == "Position") && definitions(find(paths == "Position", 1)).IsEditable
                    position = macd.model.SubtreePlacementPlanner.literal(root.Properties, "Position", []);
                    if (macd.model.PositionAliasPolicy.applies(definitions(find(paths == "Position", 1))) || ...
                            any(definitions(find(paths == "Position", 1)).Application.EffectPolicy == ...
                            ["positionInput", "sliderPosition", "squarePosition"])) && ...
                            ~wasGrid && ~hasGridPlacement && isempty(targetPosition)
                        if ~isempty(snapshot.CopyConfiguration)
                            position = macd.model.SubtreePlacementPlanner.literal( ...
                                snapshot.CopyConfiguration(1).Properties, "Position", []);
                        else
                            states = document.getEffectivePropertyStates(registry, root.Id);
                            state = states(arrayfun(@(item) item.Definition.Path == "Position", states)).Resolution;
                            if ~state.IsKnown
                                error("macd:SubtreePlacementPlanner:MissingGeometry", "Cannot place unresolved position: %s", state.Reason);
                            end
                            position = state.EffectiveValue;
                        end
                    end
                    if wasGrid || hasGridPlacement
                        if ~isempty(measuredPosition), position = measuredPosition; end
                    end
                    if ~isempty(targetPosition), position = targetPosition; end
                    zeroAllowed = macd.model.PositionAliasPolicy.applies(definitions(find(paths == "Position", 1)));
                    if numel(position) ~= 4 || ~isnumeric(position) || any(~isfinite(position)) || ...
                            any(position(3:4) < 0) || (~zeroAllowed && any(position(3:4) == 0))
                        error("macd:SubtreePlacementPlanner:MissingGeometry", "A verified position is required for absolute placement.");
                    end
                    position = reshape(double(position), 1, 4);
                    position(1:2) = position(1:2) + offset;
                    changes(end + 1) = macd.model.SubtreePlacementPlanner.change("Position", position, false);
                end
            end
            plan = struct("ParentId", parentId, "Changes", changes);
        end
    end

    methods (Static, Access = private)
        function value = literal(properties, path, fallback)
            % literal Read an explicit literal without interpreting source expressions.
            arguments (Input)
                properties struct
                path (1, 1) string
                fallback
            end
            value = fallback;
            entry = properties(string({properties.Path}) == path);
            if isempty(entry), return, end
            if entry.ValueKind ~= "literal" || ~entry.IsEditable
                error("macd:SubtreePlacementPlanner:ImplicitPlacement", "Placement must be an editable literal.");
            end
            value = entry.LiteralValue;
        end

        function value = coordinate(properties, path)
            % coordinate Validate one explicit scalar or contiguous span coordinate.
            arguments (Input)
                properties struct
                path (1, 1) string
            end
            arguments (Output)
                value double
            end
            value = macd.model.SubtreePlacementPlanner.literal(properties, path, []);
            if ~isnumeric(value) || ~isvector(value) || isempty(value) || numel(value) > 2 || ...
                    any(~isfinite(value)) || any(value < 1) || any(value ~= floor(value)) || value(end) < value(1)
                error("macd:SubtreePlacementPlanner:ImplicitPlacement", "Every grid placement must have explicit positive integer coordinates.");
            end
            value = double(value);
        end

        function count = trackCount(grid, path, axis, registry)
            % trackCount Derive dimensions from literal tracks, construction size or catalog defaults.
            arguments (Input)
                grid (1, 1) macd.model.ComponentRecord
                path (1, 1) string
                axis (1, 1) double
                registry (1, 1) macd.model.ComponentRegistry
            end
            arguments (Output)
                count (1, 1) double
            end
            entry = grid.getProperty(path);
            if ~isempty(entry)
                if entry.ValueKind ~= "literal"
                    error("macd:SubtreePlacementPlanner:ImplicitPlacement", "Grid tracks must be literal.");
                end
                tracks = macd.model.GridTrackList.describe(entry.LiteralValue);
                count = numel(tracks);
            elseif ~isempty(grid.CreationArguments) && isnumeric(grid.CreationArguments{1}) && numel(grid.CreationArguments{1}) == 2
                dimensions = grid.CreationArguments{1};
                count = dimensions(axis);
            else
                definition = registry.get(grid.Factory, grid.CreationArguments);
                property = definition.Properties(string({definition.Properties.Path}) == path);
                if ~isempty(property) && property.HasDefault
                    count = numel(macd.model.GridTrackList.describe(property.DefaultValue));
                elseif isempty(grid.CreationArguments)
                    % The documented uigridlayout(parent) construction size is [2 2].
                    count = 2;
                else
                    error("macd:SubtreePlacementPlanner:ImplicitPlacement", "Grid dimensions cannot be resolved.");
                end
            end
            if ~isfinite(count) || count < 1 || count ~= floor(count)
                error("macd:SubtreePlacementPlanner:ImplicitPlacement", "Grid dimensions must be positive integers.");
            end
        end

        function changes = removeIfPresent(changes, properties, path)
            % removeIfPresent Explicitly remove only safely understood layout properties.
            arguments (Input)
                changes struct
                properties struct
                path (1, 1) string
            end
            arguments (Output)
                changes struct
            end
            entry = properties(string({properties.Path}) == path);
            if isempty(entry), return, end
            macd.model.SubtreePlacementPlanner.literal(properties, path, []);
            changes(end + 1) = macd.model.SubtreePlacementPlanner.change(path, [], true);
        end

        function result = span(start, length)
            % span Represent a one-cell or contiguous multi-cell placement.
            arguments (Input)
                start (1, 1) double
                length (1, 1) double
            end
            arguments (Output)
                result double
            end
            result = start;
            if length > 1, result = [start start + length - 1]; end
        end

        function result = change(path, value, remove)
            % change Create one declarative placement change without mutation.
            arguments (Input)
                path (1, 1) string
                value
                remove (1, 1) logical
            end
            arguments (Output)
                result (1, 1) struct
            end
            result = struct("Path", path, "Value", {value}, "Remove", remove);
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
