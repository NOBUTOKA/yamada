classdef GridLayoutStatePolicy
    % GridLayoutStatePolicy Resolve reviewed tracks and direct-child grid placements.
    %   The finite policy replays proven creation and placement events without
    %   executing source. Requested tracks remain separate from occupancy-driven
    %   1x padding. Computed pixel geometry and fit measurements are not inferred.

    methods (Static)
        function result = requiresCombinedPlan(component, document)
            % requiresCombinedPlan Identify grid states needing a complete emitted candidate.
            arguments (Input)
                component (1, 1) macd.model.ComponentRecord
                document (1, 1) macd.model.DocumentModel
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
                members = document.Components(string({document.Components.ParentId}) == grid.Id | ...
                    string({document.Components.Id}) == grid.Id);
                planned = arrayfun(@(member) macd.source.PropertySourcePlan.needsPlan(document, member), members);
                result = result || nnz(planned) > 1 || ...
                    (any(planned) && any(string({members.Origin}) ~= "parsed"));
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

    methods (Static, Access = private)
        function result = configuration(grid, document, registry)
            % configuration Replay one grid and its direct children in initialization order.
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
            planned = arrayfun(@(member) macd.source.PropertySourcePlan.needsPlan(document, member), members);
            if nnz(planned) == 1 && all(string({members.Origin}) == "parsed")
                % Reuse actual source placement when a different member owns the pending setting.
                try
                    plan = macd.source.PropertySourcePlan.plan(document, members(planned), registry);
                    configuredGrid = plan.Document.getComponentByName(document.sourceComponentName(grid.Id));
                    result = macd.model.GridLayoutStatePolicy.configuration(configuredGrid, plan.Document, registry);
                    for axis = 1:2
                        result.TrackIds(axis) = macd.model.PropertyStateResolver.originalEffectId(grid, configuredGrid, ...
                            result.TrackIds(axis), document, plan.Document);
                    end
                    for index = 1:numel(result.ChildIds)
                        configured = plan.Document.getComponent(result.ChildIds(index));
                        for child = children
                            if document.sourceComponentName(child.Id) == configured.Name
                                result.ChildIds(index) = child.Id;
                                for axis = 1:2
                                    result.CoordinateIds(index, axis) = macd.model.PropertyStateResolver.originalEffectId(child, configured, ...
                                        result.CoordinateIds(index, axis), document, plan.Document);
                                end
                                break
                            end
                        end
                    end
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
                if member.Origin == "parsed" && isfield(member.Metadata, "InitializationCreationSequence")
                    tail = max(tail, member.Metadata.InitializationCreationSequence);
                end
            end
            for index = 1:numel(members)
                member = members(index);
                sequence = tail + 1;
                known = member.Origin ~= "parsed";
                if member.Origin == "parsed" && isfield(member.Metadata, "InitializationCreationSequence")
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
                if member.Origin == "parsed", entries = entries(string({entries.Origin}) == "generated"); end
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
            generated = string({members.Origin}) ~= "parsed";
            if any(generated) && any(~generated)
                % RoundTripGenerator appends generated blocks at the last parsed creation span.
                parsed = document.Components(string({document.Components.Origin}) == "parsed");
                spansKnown = arrayfun(@(member) ~isempty(member.SourceSpans.Creation) && ...
                    member.SourceSpans.Creation.isKnown(), parsed);
                certain = false;
                if all(spansKnown)
                    ends = arrayfun(@(member) member.SourceSpans.Creation.EndOffset, parsed);
                    [~, last] = max(ends);
                    anchor = parsed(last);
                    certain = isfield(anchor.Metadata, "InitializationCreationSequence") && ...
                        anchor.Metadata.InitializationCreationCertain;
                end
                if certain
                    sequence = anchor.Metadata.InitializationCreationSequence;
                    named = anchor.Settings(string({anchor.Settings.Method}) == "nameValue");
                    if ~isempty(named), sequence = max(sequence, max([named.Sequence])); end
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
