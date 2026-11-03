classdef PropertyApplicationPlanner
    % PropertyApplicationPlanner Order explicit settings using catalog dependencies.
    %   This stateless planner projects a validated full property graph onto
    %   the entries being applied. It neither changes source history nor
    %   predicts implicit setter effects. Parsed source placement is separate.
    %
    %   Example:
    %       entries = macd.model.PropertyApplicationPlanner.forComponent( ...
    %           component, document, registry);

    methods (Static)
        function first = nameValueStart(definition, values)
            % nameValueStart Locate named pairs after actual optional style or grid-size arguments.
            arguments (Input)
                definition (1, 1) macd.model.ComponentDefinition
                values cell
            end
            arguments (Output)
                first (1, 1) double
            end
            first = 1;
            if isempty(values), return, end
            value = values{1};
            text = (ischar(value) && isrow(value)) || (isstring(value) && isscalar(value));
            if text && any(string(value) == definition.SupportedStyles)
                first = 2;
            elseif definition.Factory == "uigridlayout" && isnumeric(value) && numel(value) == 2
                first = 2;
            end
        end

        function values = forPreviewArguments(component, registry)
            % forPreviewArguments Remove source-owned skipped properties before native construction.
            arguments (Input)
                component (1, 1) macd.model.ComponentRecord
                registry (1, 1) macd.model.ComponentRegistry
            end
            arguments (Output)
                values cell
            end
            values = component.CreationArguments;
            definition = registry.get(component.Factory, values);
            removed = false(size(values));
            % Legacy generated pairs have no source-setting records but obey the same policy.
            first = macd.model.PropertyApplicationPlanner.nameValueStart(definition, values);
            for index = first:2:numel(values) - 1
                if ~((ischar(values{index}) && isrow(values{index})) || ...
                        (isstring(values{index}) && isscalar(values{index}))), continue, end
                property = definition.getProperty(string(values{index}));
                if isempty(property) || ~property.IsEditable || ...
                        any(property.PreviewPolicy == ["skip", "notRendered"]) || ...
                        property.Path == "ImageSource" || macd.model.PositionAliasPolicy.applies(property)
                    removed(index:index + 1) = true;
                end
            end
            for setting = component.Settings
                index = setting.FactoryArgumentIndex;
                if index < 2 || index > numel(values), continue, end
                property = definition.getProperty(setting.Path);
                allowed = ~isempty(property) && property.IsEditable && ...
                    ~any(property.PreviewPolicy == ["skip", "notRendered"]);
                % Assets and reviewed aliases are adapted once after construction.
                if ~allowed || setting.Path == "ImageSource" || ...
                        (~isempty(property) && macd.model.PositionAliasPolicy.applies(property))
                    removed(index - 1:index) = true;
                end
            end
            values = values(~removed);
        end

        function [entries, positionReason, gridReason] = forPreview(component, document, registry)
            % forPreview Replay parsed literal writes and canonically order pending additions.
            arguments (Input)
                component (1, 1) macd.model.ComponentRecord
                document (1, 1) macd.model.DocumentModel
                registry (1, 1) macd.model.ComponentRegistry
            end
            arguments (Output)
                entries macd.model.PropertyEntry
                positionReason (1, 1) string
                gridReason (1, 1) string
            end

            % Native preview construction already consumes projected name-value arguments.
            canonical = macd.model.PropertyApplicationPlanner.forComponent(component, document, registry);
            if ~macd.model.SourceOwnership.hasSource(component) || isempty(canonical)
                entries = canonical;
                [entries, positionReason] = macd.model.PositionAliasPolicy.forPreview(entries, component, document, registry);
                [entries, gridReason] = macd.model.GridLayoutStatePolicy.forPreview(entries, component, document, registry);
                return
            end
            entries = macd.model.PropertyEntry.empty;
            settings = component.Settings;
            [~, order] = sort([settings.Sequence]);
            for setting = settings(order)
                if setting.Method ~= "assignment", continue, end
                current = component.getProperty(setting.Path);
                if isempty(current) || current.ValueKind ~= "literal" || ~current.IsEditable
                    continue
                end
                entry = macd.model.PropertyEntry(setting.Path, setting.LiteralValue, "parsed");
                entry.applySourceSetting(setting);
                if setting.IsEditable && isfield(current.Metadata, "SourceSettingId") && ...
                        string(current.Metadata.SourceSettingId) == string(setting.Id) && current.ValueKind == "literal"
                    entry.setLiteral(current.LiteralValue);
                end
                entries(end + 1) = entry; %#ok<AGROW>
            end

            % Source ownership is fixed; pending source placement is planned separately.
            pending = canonical(arrayfun(@(entry) isempty(entry.SourceSpan), canonical));
            entries = [entries pending];
            image = canonical(string({canonical.Path}) == "ImageSource");
            if ~isempty(image) && ~any(string({entries.Path}) == "ImageSource")
                % Named image values follow the same asset checks as assignment values.
                entries(end + 1) = image;
            end
            [entries, positionReason] = macd.model.PositionAliasPolicy.forPreview(entries, component, document, registry);
            [entries, gridReason] = macd.model.GridLayoutStatePolicy.forPreview(entries, component, document, registry);
        end

        function entries = forComponent(component, document, registry)
            % forComponent Plan canonical initialization in the direct parent context.
            arguments (Input)
                component (1, 1) macd.model.ComponentRecord
                document (1, 1) macd.model.DocumentModel
                registry (1, 1) macd.model.ComponentRegistry
            end
            arguments (Output)
                entries macd.model.PropertyEntry
            end

            % Parent contexts can add or suppress properties independently of type.
            parent = document.getComponent(component.ParentId);
            parentFactory = "";
            if ~isempty(parent), parentFactory = parent.Factory; end
            definitions = registry.getEffectiveProperties(component.Factory, ...
                parentFactory, component.CreationArguments);
            entries = macd.model.PropertyApplicationPlanner.order( ...
                component.Properties, definitions);
        end

        function entries = order(entries, definitions)
            % order Stably order a subset while retaining transitive dependencies.
            arguments (Input)
                entries macd.model.PropertyEntry
                definitions macd.model.PropertyDefinition
            end
            arguments (Output)
                entries macd.model.PropertyEntry
            end

            % Validate the full graph before projecting onto explicit settings.
            macd.model.PropertyApplicationPolicy.orderDefinitions(definitions);
            paths = string({definitions.Path});
            entryPaths = string({entries.Path});
            if numel(unique(entryPaths)) ~= numel(entryPaths)
                error("macd:PropertyApplicationPlanner:DuplicateProperty", ...
                    "Canonical initialization requires one entry per property.");
            end
            count = numel(definitions);
            reaches = false(count, count);
            for index = 1:count
                prerequisites = definitions(index).Application.ApplyAfter;
                reaches(ismember(paths, prerequisites), index) = true;
            end
            for intermediate = 1:count
                reaches = reaches | (reaches(:, intermediate) & reaches(intermediate, :));
            end

            % Omitted prerequisites keep defaults; uncataloged entries add no graph edges.
            entryCount = numel(entries);
            edges = false(entryCount, entryCount);
            [known, indices] = ismember(entryPaths, paths);
            edges(known, known) = reaches(indices(known), indices(known));
            remaining = true(1, numel(entries));
            order = zeros(1, numel(entries));
            for index = 1:numel(entries)
                ready = find(remaining & ~any(edges, 1), 1);
                order(index) = ready;
                remaining(ready) = false;
                edges(ready, :) = false;
            end
            entries = entries(order);
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
