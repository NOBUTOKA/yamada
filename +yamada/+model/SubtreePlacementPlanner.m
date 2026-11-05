classdef SubtreePlacementPlanner
    % SubtreePlacementPlanner Validate destinations and plan parent-dependent placement.
    %   This utility never mutates records. Reparent and Paste share its catalog,
    %   grid occupancy, and absolute/grid conversion rules.

    methods (Static)
        function accepted = accepts(document, parent, definition, excludedIds)
            % accepts Decide catalog and child-family compatibility before constructing a placement edit.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                parent (1, 1) yamada.model.ComponentRecord
                definition (1, 1) yamada.model.ComponentDefinition
                excludedIds (1, :) string = strings(1, 0)
            end
            arguments (Output)
                accepted (1, 1) logical
            end
            accepted = any(definition.AllowedParentFactories == parent.Factory);
            family = ["uiradiobutton", "uitogglebutton"];
            if ~accepted || parent.Factory ~= "uibuttongroup" || ~any(definition.Factory == family), return, end
            members = document.Components;
            members = members(string({members.ParentId}) == parent.Id & ...
                ~ismember(string({members.Id}), excludedIds) & ismember(string({members.Factory}), family));
            accepted = isempty(members) || all(string({members.Factory}) == definition.Factory);
        end

        function plan = prepare(document, snapshot, parentId, registry, excludedIds, measuredPosition, offset, targetCell, targetPosition, allowOverlap)
            % prepare Resolve valid root placement under an explicit destination parent.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                snapshot (1, 1) yamada.model.SubtreeSnapshot
                parentId (1, 1) string
                registry (1, 1) yamada.model.ComponentRegistry
                excludedIds string = strings(1, 0)
                measuredPosition double {mustBeFinite} = []
                offset (1, 2) double {mustBeFinite} = [0 0]
                targetCell double {mustBeFinite} = []
                targetPosition double {mustBeFinite} = []
                allowOverlap (1, 1) logical = false
            end
            arguments (Output)
                plan (1, 1) struct
            end

            % Validate hierarchy and catalog applicability before choosing geometry.
            parent = document.getComponent(parentId);
            if isempty(parent) || ~parent.IsEditable
                error("yamada:SubtreePlacementPlanner:InvalidParent", "Destination parent is missing or read-only.");
            end
            if any(excludedIds == parentId)
                error("yamada:SubtreePlacementPlanner:CyclicParent", "A subtree cannot move under itself or its descendants.");
            end
            root = snapshot.Records(1);
            if root.Id == document.RootComponentId
                error("yamada:SubtreePlacementPlanner:RootOperation", "The document root cannot be moved or pasted.");
            end
            for record = snapshot.Records
                if ~record.IsEditable
                    error("yamada:SubtreePlacementPlanner:ReadOnly", "The subtree contains a read-only component.");
                end
                definition = registry.get(record.Factory, record.CreationArguments);
                if definition.IsProgrammaticOnly || definition.Category == "FigureTools"
                    error("yamada:SubtreePlacementPlanner:UnsupportedFactory", "This construction family is not supported for subtree placement.");
                end
                parentFactory = parent.Factory;
                if record.Id ~= root.Id
                    ancestor = snapshot.Records(string({snapshot.Records.Id}) == record.ParentId);
                    parentFactory = ancestor.Factory;
                end
                if ~any(definition.AllowedParentFactories == parentFactory) || ...
                        record.Id == root.Id && ~yamada.model.SubtreePlacementPlanner.accepts(document, parent, definition, excludedIds)
                    error("yamada:SubtreePlacementPlanner:InvalidParent", "The destination does not accept this construction style.");
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
                    rows = yamada.model.SubtreePlacementPlanner.coordinate(root.Properties, "Layout.Row");
                    columns = yamada.model.SubtreePlacementPlanner.coordinate(root.Properties, "Layout.Column");
                    height = rows(end) - rows(1) + 1;
                    width = columns(end) - columns(1) + 1;
                end
                rowCount = yamada.model.SubtreePlacementPlanner.trackCount(parent, "RowHeight", 1, registry);
                columnCount = yamada.model.SubtreePlacementPlanner.trackCount(parent, "ColumnWidth", 2, registry);
                if allowOverlap
                    % Reparenting permits overlap and clips spans at the chosen destination cell.
                    cell = [1 1];
                    if ~isempty(targetCell), cell = targetCell; end
                    if numel(cell) ~= 2 || any(cell < 1) || any(cell ~= floor(cell)) || ...
                            cell(1) > rowCount || cell(2) > columnCount
                        error("yamada:SubtreePlacementPlanner:InvalidCell", "The requested grid cell is outside the destination tracks.");
                    end
                    row = cell(1);
                    column = cell(2);
                    height = min(height, rowCount - row + 1);
                    width = min(width, columnCount - column + 1);
                else
                    occupied = false(rowCount, columnCount);
                    for childId = parent.Children
                        if any(excludedIds == childId), continue, end
                        child = document.getComponent(childId);
                        values = yamada.model.SubtreeSnapshot.gridCoordinates(document, childId, registry);
                        rows = yamada.model.SubtreePlacementPlanner.coordinate(values, "Layout.Row");
                        columns = yamada.model.SubtreePlacementPlanner.coordinate(values, "Layout.Column");
                        if rows(end) > rowCount || columns(end) > columnCount || isempty(child)
                            error("yamada:SubtreePlacementPlanner:ImplicitPlacement", "Destination child placement is outside explicit tracks.");
                        end
                        occupied(rows(1):rows(end), columns(1):columns(end)) = true;
                    end
                    found = false;
                    requestedRows = 1:rowCount - height + 1;
                    requestedColumns = 1:columnCount - width + 1;
                    if ~isempty(targetCell)
                        if numel(targetCell) ~= 2 || any(targetCell < 1) || any(targetCell ~= floor(targetCell)) || ...
                                targetCell(1) + height - 1 > rowCount || targetCell(2) + width - 1 > columnCount
                            error("yamada:SubtreePlacementPlanner:InvalidCell", "The requested grid rectangle is outside the destination tracks.");
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
                        error("yamada:SubtreePlacementPlanner:NoSpace", "No unoccupied grid rectangle fits the subtree root.");
                    end
                end
                changes(end + 1) = yamada.model.SubtreePlacementPlanner.change("Layout.Row", ...
                    yamada.model.SubtreePlacementPlanner.span(row, height), false);
                changes(end + 1) = yamada.model.SubtreePlacementPlanner.change("Layout.Column", ...
                    yamada.model.SubtreePlacementPlanner.span(column, width), false);
                changes = yamada.model.SubtreePlacementPlanner.removeIfPresent(changes, root.Properties, "Position");
            elseif parent.Factory ~= "uigridlayout"
                changes = yamada.model.SubtreePlacementPlanner.removeIfPresent(changes, root.Properties, "Layout.Row");
                changes = yamada.model.SubtreePlacementPlanner.removeIfPresent(changes, root.Properties, "Layout.Column");
                if any(paths == "Position") && definitions(find(paths == "Position", 1)).IsEditable
                    position = yamada.model.SubtreePlacementPlanner.literal(root.Properties, "Position", []);
                    if (yamada.model.PositionAliasPolicy.applies(definitions(find(paths == "Position", 1))) || ...
                            any(definitions(find(paths == "Position", 1)).Application.EffectPolicy == ...
                            ["positionInput", "sliderPosition", "squarePosition", "switchPosition", "semicircularPosition", "linearPosition"])) && ...
                            ~wasGrid && ~hasGridPlacement && isempty(targetPosition)
                        if ~isempty(snapshot.CopyConfiguration)
                            position = yamada.model.SubtreePlacementPlanner.literal( ...
                                snapshot.CopyConfiguration(1).Properties, "Position", []);
                        else
                            states = document.getEffectivePropertyStates(registry, root.Id);
                            state = states(arrayfun(@(item) item.Definition.Path == "Position", states)).Resolution;
                            if ~state.IsKnown
                                error("yamada:SubtreePlacementPlanner:MissingGeometry", "Cannot place unresolved position: %s", state.Reason);
                            end
                            position = state.EffectiveValue;
                        end
                    end
                    if wasGrid || hasGridPlacement
                        if ~isempty(measuredPosition), position = measuredPosition; end
                    end
                    if ~isempty(targetPosition), position = targetPosition; end
                    zeroAllowed = yamada.model.PositionAliasPolicy.applies(definitions(find(paths == "Position", 1)));
                    if numel(position) ~= 4 || ~isnumeric(position) || any(~isfinite(position)) || ...
                            any(position(3:4) < 0) || (~zeroAllowed && any(position(3:4) == 0))
                        error("yamada:SubtreePlacementPlanner:MissingGeometry", "A verified position is required for absolute placement.");
                    end
                    position = reshape(double(position), 1, 4);
                    % Reject impossible native rectangles while planning, before emitting any placement code.
                    policy = definitions(find(paths == "Position", 1)).Application.EffectPolicy;
                    if yamada.model.PositionGeometry.applies(policy)
                        orientation = ""; known = false;
                        configuration = root.Properties;
                        if ~isempty(snapshot.CopyConfiguration)
                            configuration = snapshot.CopyConfiguration(1).Properties;
                        end
                        entry = configuration(string({configuration.Path}) == "Orientation");
                        if isscalar(entry) && entry.ValueKind == "literal"
                            orientation = string(entry.LiteralValue); known = true;
                        end
                        source = document.getComponent(root.Id);
                        if ~known && ~isempty(source)
                            states = document.getEffectivePropertyStates(registry, root.Id);
                            selected = states(arrayfun(@(item) item.Definition.Path == "Orientation", states));
                            if isscalar(selected) && selected.Resolution.IsKnown
                                orientation = string(selected.Resolution.EffectiveValue); known = true;
                            end
                        end
                        spec = yamada.model.PositionGeometry.constraint(policy, orientation, known);
                        normalized = yamada.model.PositionGeometry.normalize(position, spec);
                        if ~spec.Known || any(abs(normalized - position) > 16 * eps(max(1, max(abs(normalized), abs(position)))))
                            error("yamada:SubtreePlacementPlanner:MissingGeometry", "The requested rectangle conflicts with native size constraints.");
                        end
                    end
                    position(1:2) = position(1:2) + offset;
                    changes(end + 1) = yamada.model.SubtreePlacementPlanner.change("Position", position, false);
                end
            end
            plan = struct("ParentId", parentId, "Changes", changes);
        end
    end

    methods (Static, Access = {?yamada.model.DocumentEditAvailability, ?yamada.model.SourceLiteralTransaction})
        function paths = inputPropertyPaths()
            % inputPropertyPaths Identify stored settings consumed by placement and occupancy planning.
            arguments (Output)
                paths (1, :) string
            end
            paths = ["Position", "Layout.Row", "Layout.Column", "RowHeight", "ColumnWidth"];
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
                error("yamada:SubtreePlacementPlanner:ImplicitPlacement", "Placement must be an editable literal.");
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
            value = yamada.model.SubtreePlacementPlanner.literal(properties, path, []);
            if ~isnumeric(value) || ~isvector(value) || isempty(value) || numel(value) > 2 || ...
                    any(~isfinite(value)) || any(value < 1) || any(value ~= floor(value)) || value(end) < value(1)
                error("yamada:SubtreePlacementPlanner:ImplicitPlacement", "Every grid placement must have explicit positive integer coordinates.");
            end
            value = double(value);
        end

        function count = trackCount(grid, path, axis, registry)
            % trackCount Derive dimensions from literal tracks, construction size or catalog defaults.
            arguments (Input)
                grid (1, 1) yamada.model.ComponentRecord
                path (1, 1) string
                axis (1, 1) double
                registry (1, 1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                count (1, 1) double
            end
            entry = grid.getProperty(path);
            if ~isempty(entry)
                if entry.ValueKind ~= "literal"
                    error("yamada:SubtreePlacementPlanner:ImplicitPlacement", "Grid tracks must be literal.");
                end
                tracks = yamada.model.GridTrackList.describe(entry.LiteralValue);
                count = numel(tracks);
            elseif ~isempty(grid.CreationArguments) && isnumeric(grid.CreationArguments{1}) && numel(grid.CreationArguments{1}) == 2
                dimensions = grid.CreationArguments{1};
                count = dimensions(axis);
            else
                definition = registry.get(grid.Factory, grid.CreationArguments);
                property = definition.Properties(string({definition.Properties.Path}) == path);
                if ~isempty(property) && property.HasDefault
                    count = numel(yamada.model.GridTrackList.describe(property.DefaultValue));
                elseif isempty(grid.CreationArguments)
                    % The documented uigridlayout(parent) construction size is [2 2].
                    count = 2;
                else
                    error("yamada:SubtreePlacementPlanner:ImplicitPlacement", "Grid dimensions cannot be resolved.");
                end
            end
            if ~isfinite(count) || count < 1 || count ~= floor(count)
                error("yamada:SubtreePlacementPlanner:ImplicitPlacement", "Grid dimensions must be positive integers.");
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
            yamada.model.SubtreePlacementPlanner.literal(properties, path, []);
            changes(end + 1) = yamada.model.SubtreePlacementPlanner.change(path, [], true);
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
