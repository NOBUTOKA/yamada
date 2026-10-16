classdef SubtreeCopyPlanner
    % SubtreeCopyPlanner Freeze effective literal configuration for independent copies.
    %   Original snapshot records retain every source occurrence. Fresh output
    %   uses positional factory arguments and one canonical setting per property.
    %   Automatic ticks retain their last literal input and known automatic mode;
    %   the plan never claims that a runtime-computed array is statically known.

    methods (Static)
        function configuration = prepare(document, snapshot, registry)
            % prepare Resolve frozen source records without running input code or mutating the source document.
            arguments (Input)
                document (1, 1) macd.model.DocumentModel
                snapshot (1, 1) macd.model.SubtreeSnapshot
                registry (1, 1) macd.model.ComponentRegistry
            end
            arguments (Output)
                configuration (1, :) struct
            end
            context = document.structuralCandidate();
            frozen = snapshot.materialize();
            for component = frozen
                sources = component.Settings(string({component.Settings.Method}) ~= "generated");
                if component.Origin == "parsed" && ~isempty(sources) && ...
                        isfield(context.Metadata, "SourceSnapshotId") && ...
                        any(string({sources.SourceSnapshotId}) ~= string(context.Metadata.SourceSnapshotId))
                    error("macd:DocumentModel:UnsafeSubtreeCopy", "The unprepared snapshot belongs to a different source version.");
                end
                index = find(string({context.Components.Id}) == component.Id, 1);
                if isempty(index), context.Components(end + 1) = component; else, context.Components(index) = component; end
            end
            configuration = struct("ComponentId", {}, "CreationArguments", {}, "Properties", {}, "Expected", {});
            for index = 1:numel(snapshot.Records)
                record = snapshot.Records(index);
                component = frozen(index);
                [states, diagnostics] = context.getEffectivePropertyStates(registry, component.Id);
                if macd.validation.ModelValidator.hasErrors(diagnostics)
                    error("macd:DocumentModel:UnsafeSubtreeCopy", "%s", strjoin(string({diagnostics.Message}), newline));
                end
                values = record.Properties;
                expected = struct("Path", {}, "Value", {});
                % Copy the resulting values, keeping expression references for the existing remapping policy.
                for property = record.Properties
                    if property.ValueKind == "expression", continue, end
                    state = find(arrayfun(@(item) item.Definition.Path == property.Path, states), 1);
                    if isempty(state)
                        error("macd:DocumentModel:UnsafeSubtreeCopy", "Property %s is unsupported in the source context.", property.Path);
                    end
                    resolution = states(state).Resolution;
                    if resolution.IsKnown
                        selected = find(string({values.Path}) == property.Path, 1);
                        values(selected).LiteralValue = resolution.EffectiveValue;
                    elseif ~macd.model.SubtreeCopyPlanner.isAutomatic(states(state), states)
                        error("macd:DocumentModel:UnsafeSubtreeCopy", ...
                            "Cannot reproduce %s: %s", property.Path, resolution.Reason);
                    end
                end
                % Implicit setter effects may determine properties with no explicit source write.
                for state = states
                    resolution = state.Resolution;
                    explicit = any(string({record.Properties.Path}) == state.Definition.Path);
                    affected = strlength(resolution.EffectSettingId) > 0;
                    if ~explicit && ~affected, continue, end
                    if ~resolution.IsKnown
                        if macd.model.SubtreeCopyPlanner.isAutomatic(state, states), continue, end
                        if explicit && any(string({values.Path}) == state.Definition.Path) && ...
                                values(find(string({values.Path}) == state.Definition.Path, 1)).ValueKind == "expression"
                            continue
                        end
                        error("macd:DocumentModel:UnsafeSubtreeCopy", ...
                            "Cannot reproduce %s: %s", state.Definition.Path, resolution.Reason);
                    end
                    if ~any(string({values.Path}) == state.Definition.Path) && state.Definition.IsEditable && ...
                            ~macd.model.SubtreeCopyPlanner.isDerivedWidth(state, states)
                        entry = macd.model.PropertyEntry(state.Definition.Path, resolution.EffectiveValue, "generated");
                        values(end + 1) = entry.toStruct(); %#ok<AGROW>
                    end
                    expected(end + 1) = struct("Path", state.Definition.Path, "Value", {resolution.EffectiveValue}); %#ok<AGROW>
                end
                factoryArguments = record.CreationArguments;
                removed = false(1, numel(factoryArguments));
                % Named constructor values are already represented by effective property entries.
                for setting = record.Settings
                    valueIndex = setting.Location.FactoryArgumentIndex;
                    if valueIndex == 0, continue, end
                    if valueIndex < 2 || valueIndex > numel(factoryArguments)
                        error("macd:DocumentModel:UnsafeSubtreeCopy", "Constructor argument ownership is inconsistent.");
                    end
                    removed(valueIndex - 1:valueIndex) = true;
                end
                configuration(end + 1) = struct("ComponentId", record.Id, ...
                    "CreationArguments", {factoryArguments(~removed)}, "Properties", values, "Expected", expected); %#ok<AGROW>
            end
        end

        function verify(document, configuration, inserted, changes, registry)
            % verify Check every frozen known value after source generation and independent reparsing.
            arguments (Input)
                document (1, 1) macd.model.DocumentModel
                configuration (1, :) struct
                inserted macd.model.ComponentRecord
                changes (1, :) struct
                registry (1, 1) macd.model.ComponentRegistry
            end
            for index = 1:numel(configuration)
                component = document.getComponentByName(inserted(index).Name);
                if isempty(component)
                    error("macd:DocumentModel:UnsafeSubtreeEdit", "The generated copy is missing.");
                end
                states = document.getEffectivePropertyStates(registry, component.Id);
                for expected = configuration(index).Expected
                    if index == 1 && any(string({changes.Path}) == expected.Path), continue, end
                    state = find(arrayfun(@(item) item.Definition.Path == expected.Path, states), 1);
                    if isempty(state) || ~macd.model.PropertyStateResolver.matchesRequested(states(state).Resolution, expected.Value)
                        error("macd:DocumentModel:UnsafeSubtreeEdit", ...
                            "The generated copy does not retain effective property %s on %s.", expected.Path, inserted(index).Name);
                    end
                end
            end
        end
    end

    methods (Static, Access = private)
        function result = isDerivedWidth(state, states)
            % isDerivedWidth Avoid freezing an implicit auto width with a setter that would select manual mode.
            arguments (Input)
                state (1, 1) struct
                states (1, :) struct
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = false;
            if state.Definition.Application.EffectPolicy ~= "axisWidth" || ...
                    ~any(state.Definition.Path == ["GridLineWidth", "MinorGridLineWidth"]), return, end
            mode = find(arrayfun(@(item) item.Definition.Path == state.Definition.Path + "Mode", states), 1);
            if isempty(mode) || ~states(mode).Resolution.IsKnown, return, end
            value = states(mode).Resolution.EffectiveValue;
            result = ((ischar(value) && isrow(value)) || (isstring(value) && isscalar(value))) && string(value) == "auto";
        end

        function result = isAutomatic(state, states)
            % isAutomatic Recognize audited runtime-computed data controlled by a known automatic mode.
            arguments (Input)
                state (1, 1) struct
                states (1, :) struct
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = false;
            if state.Resolution.ReasonCode ~= "automatic" || ...
                    ~any(state.Definition.Application.EffectPolicy == ["tickMode", "valueMode"]), return, end
            mode = find(arrayfun(@(item) item.Definition.Path == state.Definition.Path + "Mode", states), 1);
            if isempty(mode) || ~states(mode).Resolution.IsKnown, return, end
            value = states(mode).Resolution.EffectiveValue;
            result = ((ischar(value) && isrow(value)) || (isstring(value) && isscalar(value))) && string(value) == "auto";
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
