classdef GridLayoutStatePolicy
    % GridLayoutStatePolicy Resolve reviewed tracks and direct-child grid placements.
    %   The finite policy replays proven creation and placement events without
    %   executing source. Requested tracks remain separate from occupancy-driven
    %   1x padding. Computed pixel geometry and fit measurements are not inferred.

    methods (Static)
        function paths = inputPropertyPaths()
            % inputPropertyPaths Declare source settings that can change this policy's document-dependent result.
            arguments (Output)
                paths (1, :) string
            end
            paths = ["RowHeight", "ColumnWidth", "Layout", "Layout.Row", "Layout.Column"];
        end

        function result = requiresCombinedPlan(component, document, registry)
            % requiresCombinedPlan Identify grid states needing a complete emitted candidate.
            arguments (Input)
                component (1, 1) macd.model.ComponentRecord
                document (1, 1) macd.model.DocumentModel
                registry macd.model.ComponentRegistry = macd.model.ComponentRegistry.empty
            end
            arguments (Output)
                result (1, 1) logical
            end
            grids = macd.model.ComponentRecord.empty;
            if component.Factory == "uigridlayout", grids(end + 1) = component; end
            parent = document.getComponent(component.ParentId);
            if ~isempty(parent) && parent.Factory == "uigridlayout", grids(end + 1) = parent; end
            result = false;
            for grid = grids
                members = [grid, document.Components(string({document.Components.ParentId}) == grid.Id)];
                planned = macd.model.GridLayoutStatePolicy.pendingGridPlans(members, document, registry);
                result = result || nnz(planned) > 1 || ...
                    (any(planned) && any(~arrayfun(@macd.model.SourceOwnership.hasSource, members)));
            end
        end

        function states = resolve(states, component, document, registry)
            % resolve Project grid tracks or direct-child coordinates into shared states.
            arguments (Input)
                states macd.model.PropertyState
                component (1, 1) macd.model.ComponentRecord
                document (1, 1) macd.model.DocumentModel
                registry (1, 1) macd.model.ComponentRegistry
            end
            arguments (Output)
                states macd.model.PropertyState
            end
            grids = macd.model.ComponentRecord.empty;
            if component.Factory == "uigridlayout", grids(end + 1) = component; end
            parent = document.getComponent(component.ParentId);
            if ~isempty(parent) && parent.Factory == "uigridlayout", grids(end + 1) = parent; end
            for grid = grids
                definition = registry.get(grid.Factory, grid.CreationArguments);
                property = definition.getProperty("RowHeight");
                if isempty(property) || property.Application.EffectPolicy ~= "gridTracks", continue, end
                unresolved = macd.model.GridLayoutStatePolicy.unresolvedGridEffect(grid, document, registry);
                if strlength(unresolved) > 0
                    for index = 1:numel(states)
                        if ~any(states(index).Path == ["RowHeight", "ColumnWidth", "Layout.Row", "Layout.Column"]), continue, end
                        states(index) = states(index).withEffective([], false, unresolved, ...
                            "An unreviewed grid member setter may affect placement or tracks.", "unreviewed-effect");
                    end
                    continue
                end
                result = macd.model.GridLayoutStatePolicy.configuration(grid, document, registry);
                for axis = 1:2
                    if component.Id == grid.Id
                        paths = ["RowHeight", "ColumnWidth"];
                        value = result.Tracks{axis};
                        known = result.TrackKnown(axis);
                        id = result.TrackIds(axis);
                    else
                        paths = ["Layout.Row", "Layout.Column"];
                        child = find(result.ChildIds == component.Id, 1);
                        value = result.Coordinates{child, axis};
                        known = result.CoordinateKnown(child, axis) && result.Certain(child);
                        id = result.CoordinateIds(child, axis);
                    end
                    index = find(string({states.Path}) == paths(axis), 1);
                    if isempty(index), continue, end
                    states(index) = states(index).withEffective(value, known, id, ...
                        "Grid tracks or child placement depend on an uncertain initialization event.", "grid-layout");
                    if known, states(index) = states(index).withEffective(value, true, id); end
                end
            end
        end

        function result = equivalent(first, second)
            % equivalent Compare supported track representations by their normalized tokens.
            arguments (Input)
                first
                second
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = false;
            if strlength(macd.model.GridTrackList.validate(first)) > 0 || ...
                    strlength(macd.model.GridTrackList.validate(second)) > 0, return, end
            result = isequaln(macd.model.GridTrackList.describe(first), macd.model.GridTrackList.describe(second));
        end

        function [entries, reason] = forPreview(entries, component, document, registry)
            % forPreview Project known final tracks and placements without changing explicit records.
            arguments (Input)
                entries macd.model.PropertyEntry
                component (1, 1) macd.model.ComponentRecord
                document (1, 1) macd.model.DocumentModel
                registry (1, 1) macd.model.ComponentRegistry
            end
            arguments (Output)
                entries macd.model.PropertyEntry
                reason (1, 1) string
            end
            reason = "";
            parent = document.getComponent(component.ParentId);
            paths = strings(1, 0);
            if component.Factory == "uigridlayout"
                definition = registry.get(component.Factory, component.CreationArguments);
                property = definition.getProperty("RowHeight");
                if ~isempty(property) && property.Application.EffectPolicy == "gridTracks"
                    paths = ["RowHeight", "ColumnWidth"];
                end
            end
            if ~isempty(parent) && parent.Factory == "uigridlayout"
                definition = registry.get(parent.Factory, parent.CreationArguments);
                property = definition.getProperty("RowHeight");
                if ~isempty(property) && property.Application.EffectPolicy == "gridTracks"
                    paths = [paths "Layout.Row" "Layout.Column"];
                end
            end
            if isempty(paths), return, end
            states = document.getEffectivePropertyStates(registry, component.Id);
            for path = paths
                index = find(arrayfun(@(state) state.Definition.Path == path, states), 1);
                if isempty(index), continue, end
                entries = entries(string({entries.Path}) ~= path);
                resolution = states(index).Resolution;
                if resolution.IsKnown
                    entries(end + 1) = macd.model.PropertyEntry(path, resolution.EffectiveValue, "generated"); %#ok<AGROW>
                else
                    reason = "Cannot resolve " + path + ": " + resolution.Reason;
                end
            end
        end
    end

    methods (Static, Access = ?macd.model.EvaluationContext)
        function result = projectConfiguration(grid, document, configuration, registry)
            % projectConfiguration Map private configured grid values back to original source identities.
            arguments (Input)
                grid (1, 1) macd.model.ComponentRecord
                document (1, 1) macd.model.DocumentModel
                configuration (1, 1) macd.model.DocumentModel
                registry (1, 1) macd.model.ComponentRegistry
            end
            arguments (Output)
                result (1, 1) struct
            end
            children = document.Components(string({document.Components.ParentId}) == grid.Id);
            configuredGrid = configuration.getComponentByName(document.sourceComponentName(grid.Id));
            result = macd.model.GridLayoutStatePolicy.configuration(configuredGrid, configuration, registry);
            for axis = 1:2
                result.TrackIds(axis) = macd.model.PropertyStateResolver.originalEffectId(grid, configuredGrid, ...
                    result.TrackIds(axis), document, configuration);
            end
            for index = 1:numel(result.ChildIds)
                configured = configuration.getComponent(result.ChildIds(index));
                for child = children
                    if document.sourceComponentName(child.Id) == configured.Name
                        result.ChildIds(index) = child.Id;
                        for axis = 1:2
                            result.CoordinateIds(index, axis) = macd.model.PropertyStateResolver.originalEffectId(child, configured, ...
                                result.CoordinateIds(index, axis), document, configuration);
                        end
                        break
                    end
                end
            end
        end
    end

    methods (Static, Access = private)
        function id = unresolvedGridEffect(grid, document, registry)
            % unresolvedGridEffect Share the unchanged member scan for one exact grid input.
            arguments (Input)
                grid (1, 1) macd.model.ComponentRecord
                document (1, 1) macd.model.DocumentModel
                registry (1, 1) macd.model.ComponentRegistry
            end
            arguments (Output)
                id (1, 1) string
            end
            context = document.evaluationContext(registry);
            key = "grid-unresolved-effect:" + grid.Id;
            [id, found] = context.lookup(key);
            if found, return, end

            % Preserve member order and all existing uncertainty checks.
            scope = context.readScope(); %#ok<NASGU>
            members = document.Components(string({document.Components.ParentId}) == grid.Id | ...
                string({document.Components.Id}) == grid.Id);
            id = macd.model.PropertyStateResolver.unresolvedEffectId(members, ...
                ["RowHeight", "ColumnWidth", "Layout.Row", "Layout.Column"], registry);
            context.remember(key, id);
        end

        function result = configuration(grid, document, registry)
            % configuration Share one independent grid result for the current document inputs.
            arguments (Input)
                grid (1, 1) macd.model.ComponentRecord
                document (1, 1) macd.model.DocumentModel
                registry (1, 1) macd.model.ComponentRegistry
            end
            arguments (Output)
                result (1, 1) struct
            end
            context = document.evaluationContext(registry);
            key = "grid-configuration:" + grid.Id;
            [result, found] = context.lookup(key);
            if found, return, end

            % Cache value data only; direct writes and catalog changes replace the context.
            scope = context.readScope(); %#ok<NASGU>
            result = macd.model.GridLayoutStatePolicy.evaluateConfiguration(grid, document, registry);
            context.remember(key, result);
        end

        function result = evaluateConfiguration(grid, document, registry)
            % evaluateConfiguration Replay one grid and its direct children in initialization order.
            arguments (Input)
                grid (1, 1) macd.model.ComponentRecord
                document (1, 1) macd.model.DocumentModel
                registry (1, 1) macd.model.ComponentRegistry
            end
            arguments (Output)
                result (1, 1) struct
            end
            children = document.Components(string({document.Components.ParentId}) == grid.Id);
            members = [grid children];
            planned = macd.model.GridLayoutStatePolicy.pendingGridPlans(members, document, registry);
            if nnz(planned) == 1 && all(arrayfun(@macd.model.SourceOwnership.hasSource, members))
                % Reuse actual source placement when a different member owns the pending setting.
                try
                    context = document.evaluationContext(registry);
                    [result, found] = context.configurationGridState("combined", grid, document, members(planned));
                    if found, return, end
                    plan = macd.source.PropertySourcePlan.plan(document, members(planned), registry);
                    result = macd.model.GridLayoutStatePolicy.projectConfiguration(grid, document, plan.Document, registry);
                    return
                catch
                    % The owning resolver reports placement errors; related states stay unknown below.
                end
            end
            count = numel(children);
            result = struct("Tracks", {{{"1x", "1x"}, {"1x", "1x"}}}, ...
                "TrackKnown", [true true], "TrackIds", ["" ""], ...
                "ChildIds", string({children.Id}), "Coordinates", {cell(count, 2)}, ...
                "CoordinateKnown", false(count, 2), "CoordinateIds", strings(count, 2), ...
                "Present", false(1, count), "Certain", true(1, count));
            requested = result.Tracks;
            requestedKnown = [true true];
            requestedIds = ["" ""];
            events = macd.model.GridLayoutStatePolicy.events(members, document, registry);
            for event = events
                child = event.Member - 1;
                if event.Path == "creation"
                    if child == 0
                        requestedKnown(:) = event.Known;
                        args = grid.CreationArguments;
                        if ~isempty(args) && isnumeric(args{1}) && numel(args{1}) == 2 && ...
                                all(isfinite(args{1})) && all(args{1} >= 0) && all(fix(args{1}) == args{1})
                            for axis = 1:2, requested{axis} = repmat({"1x"}, 1, args{1}(axis)); end
                        end
                        % Legacy generated constructor arguments have no source settings.
                        if ~any(string({grid.Settings.Method}) == "nameValue")
                            for index = 1:numel(args) - 1
                                if ~((ischar(args{index}) && isrow(args{index})) || ...
                                        (isstring(args{index}) && isscalar(args{index}))), continue, end
                                axis = find(["RowHeight", "ColumnWidth"] == string(args{index}), 1);
                                if isempty(axis), continue, end
                                requestedKnown(axis) = strlength(macd.model.GridTrackList.validate(args{index + 1})) == 0;
                                if requestedKnown(axis), requested{axis} = macd.model.GridTrackList.items(args{index + 1}); end
                            end
                        end
                    else
                        % Default placement follows the last occupied cell, including spans.
                        known = result.TrackKnown(2) && all(result.Certain(result.Present)) && ...
                            all(result.CoordinateKnown(result.Present, :), "all");
                        columns = max(1, numel(result.Tracks{2}));
                        last = 0;
                        for previous = find(result.Present)
                            if ~known, break, end
                            rows = result.Coordinates{previous, 1};
                            cols = result.Coordinates{previous, 2};
                            last = max(last, (rows(end) - 1) * columns + cols(end));
                        end
                        result.Coordinates(child, :) = {floor(last / columns) + 1, mod(last, columns) + 1};
                        result.CoordinateKnown(child, :) = known;
                        result.CoordinateIds(child, :) = event.Id;
                        result.Present(child) = true;
                        result.Certain(child) = event.Known;
                    end
                elseif child == 0
                    axis = find(["RowHeight", "ColumnWidth"] == event.Path, 1);
                    if isempty(axis), continue, end
                    requestedKnown(axis) = event.Known && strlength(macd.model.GridTrackList.validate(event.Value)) == 0;
                    if requestedKnown(axis), requested{axis} = macd.model.GridTrackList.items(event.Value); end
                    requestedIds(axis) = event.Id;
                else
                    if event.Path == "Layout"
                        result.CoordinateKnown(child, :) = false;
                        result.CoordinateIds(child, :) = event.Id;
                    end
                    axis = find(["Layout.Row", "Layout.Column"] == event.Path, 1);
                    if ~isempty(axis)
                        value = event.Value;
                        known = event.Known && isnumeric(value) && isreal(value) && isvector(value) && ...
                            any(numel(value) == [1 2]) && all(isfinite(value)) && ...
                            all(value >= 1) && all(fix(value) == value) && value(end) >= value(1);
                        result.CoordinateKnown(child, axis) = known;
                        result.Coordinates{child, axis} = value;
                        result.CoordinateIds(child, axis) = event.Id;
                    end
                end

                % Occupancy adds flexible tracks; moving out releases only implicit padding.
                for axis = 1:2
                    known = requestedKnown(axis) && all(result.Certain(result.Present)) && ...
                        all(result.CoordinateKnown(result.Present, axis));
                    result.Tracks{axis} = requested{axis};
                    result.TrackKnown(axis) = known;
                    result.TrackIds(axis) = requestedIds(axis);
                    if ~known, continue, end
                    for occupied = find(result.Present)
                        coordinate = result.Coordinates{occupied, axis};
                        if coordinate(end) > numel(result.Tracks{axis})
                            result.Tracks{axis}(end + 1:coordinate(end)) = {"1x"};
                            result.TrackIds(axis) = result.CoordinateIds(occupied, axis);
                        end
                    end
                end
            end
            if any(planned)
                % Multiple independent pending plans require a combined emitted candidate.
                result.TrackKnown(:) = false;
                result.CoordinateKnown(:) = false;
            end
        end

        function events = events(members, document, registry)
            % events Merge source-owned global sequences with canonical generated records.
            arguments (Input)
                members macd.model.ComponentRecord
                document (1, 1) macd.model.DocumentModel
                registry (1, 1) macd.model.ComponentRegistry
            end
            arguments (Output)
                events (1, :) struct
            end
            events = struct("Sequence", {}, "Member", {}, "Path", {}, "Value", {}, "Known", {}, "Id", {});
            tail = 0;
            for member = members
                if ~isempty(member.Settings), tail = max(tail, max([member.Settings.Sequence])); end
                if macd.model.SourceOwnership.hasSource(member) && isfield(member.Metadata, "InitializationCreationSequence")
                    tail = max(tail, member.Metadata.InitializationCreationSequence);
                end
            end
            for index = 1:numel(members)
                member = members(index);
                sequence = tail + 1;
                known = ~macd.model.SourceOwnership.hasSource(member);
                if macd.model.SourceOwnership.hasSource(member) && isfield(member.Metadata, "InitializationCreationSequence")
                    sequence = member.Metadata.InitializationCreationSequence;
                    known = member.Metadata.InitializationCreationCertain;
                end
                events(end + 1) = struct("Sequence", sequence, "Member", index, "Path", "creation", ...
                    "Value", [], "Known", known, "Id", "creation:" + member.Id); %#ok<AGROW>
                tail = max(tail, sequence);
                for setting = member.Settings
                    if setting.Method == "generated" || ...
                            ~any(setting.Path == ["RowHeight", "ColumnWidth", "Layout.Row", "Layout.Column", "Layout"]), continue, end
                    value = setting.LiteralValue;
                    entry = member.getProperty(setting.Path);
                    if ~isempty(entry) && entry.ValueKind == "literal" && ...
                            isfield(entry.Metadata, "SourceSettingId") && entry.Metadata.SourceSettingId == setting.Id
                        value = entry.LiteralValue;
                    end
                    events(end + 1) = struct("Sequence", setting.Sequence, "Member", index, "Path", setting.Path, ...
                        "Value", {value}, "Known", setting.IsCertain && setting.ValueKind == "literal", "Id", setting.Id); %#ok<AGROW>
                end
                entries = member.Properties;
                if macd.model.SourceOwnership.hasSource(member), entries = entries(arrayfun(@(entry) isempty(entry.SourceSpan), entries)); end
                definition = registry.getEffectiveProperties(member.Factory, "uigridlayout", member.CreationArguments);
                entries = macd.model.PropertyApplicationPlanner.order(entries, definition);
                for entry = entries
                    if ~any(entry.Path == ["RowHeight", "ColumnWidth", "Layout.Row", "Layout.Column"]), continue, end
                    tail = tail + 1;
                    events(end + 1) = struct("Sequence", tail, "Member", index, "Path", entry.Path, ...
                        "Value", {entry.LiteralValue}, "Known", entry.ValueKind == "literal" && entry.IsEditable, ...
                        "Id", "pending:" + member.Id + ":" + entry.Path); %#ok<AGROW>
                end
            end
            generated = ~arrayfun(@macd.model.SourceOwnership.hasSource, members);
            if any(generated) && any(~generated)
                % Use the generator's shared anchor, including later ancestor geometry.
                certain = true;
                sequence = 0;
                try
                    [~, sequence] = macd.model.AncestorGeometryPolicy.creationAnchor(document);
                catch
                    certain = false;
                end
                if certain
                    inserted = find(generated([events.Member]));
                    for index = 1:numel(inserted)
                        events(inserted(index)).Sequence = sequence + index / (numel(inserted) + 1);
                    end
                else
                    for index = find(generated([events.Member])), events(index).Known = false; end
                end
            end
            [~, order] = sort([events.Sequence]);
            events = events(order);
        end
    end
    methods (Static, Access = private)
        function planned = pendingGridPlans(members, document, registry)
            % pendingGridPlans Retain source plans that may change shared logical grid state.
            arguments (Input)
                members (1, :) macd.model.ComponentRecord
                document (1, 1) macd.model.DocumentModel
                registry macd.model.ComponentRegistry
            end
            arguments (Output)
                planned (1, :) logical
            end
            % Unchanged source and calls without a catalog keep the original cheap path.
            planned = arrayfun(@(member) macd.source.PropertySourcePlan.needsPlan(document, member), members);
            if isempty(registry) || ~any(planned), return, end
            context = document.evaluationContext(registry);
            key = "grid-source-plans:" + members(1).Id;
            [cached, found] = context.lookup(key);
            if found, planned = cached; return, end
            scope = context.readScope(); %#ok<NASGU>
            for index = find(planned)
                member = members(index);
                if macd.source.SubtreeReparentSourceEdits.contains(document, member.Id) || ...
                        ~registry.contains(member.Factory)
                    continue
                end
                % Individual insertion checks still validate ownership, literals, and source order.
                entries = member.Properties;
                entries = entries(arrayfun(@(entry) isempty(entry.SourceSpan) && entry.ValueKind == "literal" && ...
                    ~isfield(entry.Metadata, "SubtreeReferenceId"), entries));
                if isempty(entries), continue, end
                parent = document.getComponent(member.ParentId);
                parentFactory = "";
                if ~isempty(parent), parentFactory = parent.Factory; end
                definitions = registry.getEffectiveProperties(member.Factory, parentFactory, member.CreationArguments);
                independent = true;
                for entry = entries
                    definition = definitions(string({definitions.Path}) == entry.Path);
                    if numel(definition) ~= 1 || ~entry.IsEditable || ~definition.IsEditable || ...
                            definition.Application.EffectStatus ~= "independent" || ...
                            definition.Application.EffectPolicy ~= "none" || ...
                            ~isempty(definition.Application.ApplyAfter) || ...
                            any(arrayfun(@(other) any(other.Application.ApplyAfter == entry.Path), definitions))
                        independent = false;
                        break
                    end
                end
                % Font and text can affect native fit geometry without changing logical track events.
                if independent, planned(index) = false; end
            end
            context.remember(key, planned);
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
