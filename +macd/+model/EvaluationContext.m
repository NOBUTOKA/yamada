classdef EvaluationContext < handle
    % EvaluationContext Cache independent results for one exact document input state.
    %   Publicly mutable records are compared by value, not history position.
    %   Parsed configuration handles remain private and are copied on retrieval.
    %
    %   Example:
    %       context = document.evaluationContext(registry);
    properties (Access = private)
        Key struct
        Registry macd.model.ComponentRegistry
        RegistryRevision uint64
        Values containers.Map
        Plans containers.Map
        Cacheable logical = false
        ReadDepth double = 0
    end

    methods
        function [inputs, safe] = inputs(obj)
            % inputs Return independent semantic inputs for conservative view invalidation.
            arguments (Input)
                obj (1, 1) macd.model.EvaluationContext
            end
            arguments (Output)
                inputs (1, 1) struct
                safe (1, 1) logical
            end
            safe = obj.Cacheable;
            inputs = struct();
            if safe, inputs = obj.Key; end
        end

        function result = isReading(obj, registry)
            % isReading Identify nested pure evaluation in the same registry version.
            arguments (Input)
                obj (1, 1) macd.model.EvaluationContext
                registry (1, 1) macd.model.ComponentRegistry
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = obj.Cacheable && obj.ReadDepth > 0 && ...
                obj.Registry == registry && obj.RegistryRevision == registry.Revision;
        end

        function cleanup = readScope(obj)
            % readScope Amortize input capture within a synchronous read-only computation.
            %   Do not hold this scope across native UI dispatch or model mutations.
            arguments (Input)
                obj (1, 1) macd.model.EvaluationContext
            end
            arguments (Output)
                cleanup (1, 1) onCleanup
            end
            obj.ReadDepth = obj.ReadDepth + 1;
            cleanup = onCleanup(@() obj.finishRead());
        end

        function obj = EvaluationContext(document, registry)
            % EvaluationContext Capture semantic inputs without retaining live component records.
            arguments (Input)
                document (1, 1) macd.model.DocumentModel
                registry (1, 1) macd.model.ComponentRegistry
            end
            [obj.Key, obj.Cacheable] = macd.model.EvaluationContext.capture(document);
            obj.Registry = registry;
            obj.RegistryRevision = registry.Revision;
            obj.Values = containers.Map("KeyType", "char", "ValueType", "any");
            obj.Plans = containers.Map("KeyType", "char", "ValueType", "any");
        end

        function result = matches(obj, document, registry)
            % matches Reject stale results after direct edits, history branches, or registry changes.
            arguments (Input)
                obj (1, 1) macd.model.EvaluationContext
                document (1, 1) macd.model.DocumentModel
                registry (1, 1) macd.model.ComponentRegistry
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = obj.Cacheable && obj.Registry == registry && obj.RegistryRevision == registry.Revision;
            if result
                [key, cacheable] = macd.model.EvaluationContext.capture(document);
                result = cacheable && isequaln(obj.Key, key);
            end
        end

        function [value, found] = lookup(obj, name)
            % lookup Return cached value-only results, never shared mutable model handles.
            arguments (Input)
                obj (1, 1) macd.model.EvaluationContext
                name (1, 1) string
            end
            arguments (Output)
                value
                found (1, 1) logical
            end
            found = obj.Cacheable && isKey(obj.Values, char(name));
            value = [];
            if found, value = obj.Values(char(name)); end
        end

        function remember(obj, name, value)
            % remember Retain independent evaluation values only when their classes are safe.
            arguments (Input)
                obj (1, 1) macd.model.EvaluationContext
                name (1, 1) string
                value
            end
            [independent, safe] = macd.model.EvaluationContext.freeze(value);
            if obj.Cacheable && safe
                obj.Values(char(name)) = independent;
            end
        end

        function [plan, found] = configuration(obj, name, componentName)
            % configuration Materialize a private parsed plan into an isolated caller-owned document.
            arguments (Input)
                obj (1, 1) macd.model.EvaluationContext
                name (1, 1) string
                componentName (1, 1) string
            end
            arguments (Output)
                plan (1, 1) struct
                found (1, 1) logical
            end
            found = obj.Cacheable && isKey(obj.Plans, char(name));
            plan = struct();
            if ~found, return, end
            saved = obj.Plans(char(name));
            document = saved.structuralCandidate();
            component = document.getComponentByName(componentName);
            found = ~isempty(component);
            if found, plan = struct("Document", document, "Component", component); end
        end

        function rememberConfiguration(obj, name, document)
            % rememberConfiguration Hide an independent configuration from subsequent caller mutations.
            arguments (Input)
                obj (1, 1) macd.model.EvaluationContext
                name (1, 1) string
                document (1, 1) macd.model.DocumentModel
            end
            if obj.Cacheable
                obj.Plans(char(name)) = document.structuralCandidate();
            end
        end
    end

    methods (Access = private)
        function finishRead(obj)
            % finishRead Release a synchronous evaluation scope, including on errors.
            arguments (Input)
                obj (1, 1) macd.model.EvaluationContext
            end
            obj.ReadDepth = max(0, obj.ReadDepth - 1);
        end
    end

    methods (Static, Access = private)
        function [key, safe] = capture(document)
            % capture Snapshot all source and model inputs while excluding derived output diagnostics.
            arguments (Input)
                document (1, 1) macd.model.DocumentModel
            end
            arguments (Output)
                key (1, 1) struct
                safe (1, 1) logical
            end
            [components, ownedSafe] = macd.model.EvaluationContext.freeze(document.Components, true);
            key = struct("ClassName", document.ClassName, "FilePath", document.FilePath, ...
                "OriginalText", document.OriginalText, "RootComponentId", document.RootComponentId, ...
                "Encoding", document.Encoding, "LineEnding", document.LineEnding, ...
                "Metadata", document.Metadata, "UnknownRegions", document.UnknownRegions, ...
                "PendingEdits", {document.PendingEdits}, "CallbackEdits", document.CallbackEdits, ...
                "RenameEdits", document.RenameEdits, "Components", components);
            [key, safe] = macd.model.EvaluationContext.freeze(key);
            safe = safe && ownedSafe;
        end

        function [value, safe] = freeze(value, owned)
            % freeze Convert known records by value and bypass caching for unrecognized live data.
            arguments (Input)
                value
                owned (1, 1) logical = false
            end
            arguments (Output)
                value
                safe (1, 1) logical
            end
            safe = true;
            if isa(value, "macd.model.ComponentRecord")
                if ~owned, value = []; safe = false; return, end
                records = struct([]);
                for index = 1:numel(value)
                    component = value(index);
                    [properties, independent] = macd.model.EvaluationContext.freeze(component.Properties, true);
                    safe = safe && independent;
                    record = struct("Id", component.Id, "Name", component.Name, ...
                        "Factory", component.Factory, "DeclaredType", component.DeclaredType, ...
                        "Origin", component.Origin, "ParentId", component.ParentId, ...
                        "Children", component.Children, "CreationArguments", {component.CreationArguments}, ...
                        "IsEditable", component.IsEditable, "Metadata", component.Metadata, ...
                        "SourceSpans", component.SourceSpans, "Properties", properties, ...
                        "Settings", component.settingSnapshot());
                    if isempty(records), records = record; else, records(end + 1) = record; end %#ok<AGROW>
                end
                [value, independent] = macd.model.EvaluationContext.freeze(records);
                safe = safe && independent;
            elseif isa(value, "macd.model.PropertyEntry")
                if ~owned, value = []; safe = false; return, end
                records = struct([]);
                for index = 1:numel(value)
                    record = value(index).toStruct();
                    record = rmfield(record, "Diagnostics");
                    if isempty(records), records = record; else, records(end + 1) = record; end %#ok<AGROW>
                end
                [value, safe] = macd.model.EvaluationContext.freeze(records);
            elseif isstruct(value)
                fields = fieldnames(value);
                for index = 1:numel(value)
                    for field = 1:numel(fields)
                        [value(index).(fields{field}), valid] = macd.model.EvaluationContext.freeze(value(index).(fields{field}));
                        safe = safe && valid;
                    end
                end
            elseif iscell(value)
                for index = 1:numel(value)
                    [value{index}, valid] = macd.model.EvaluationContext.freeze(value{index});
                    safe = safe && valid;
                end
            else
                safe = isnumeric(value) || islogical(value) || ischar(value) || isstring(value) || ...
                    isa(value, "datetime") || isa(value, "duration") || isa(value, "calendarDuration") || ...
                    isa(value, "categorical") || isa(value, "macd.model.SourceSpan") || ...
                    isa(value, "macd.model.UnknownSourceRegion") || isa(value, "macd.model.Diagnostic") || ...
                    isa(value, "macd.model.PropertyState") || isa(value, "macd.model.PropertyDefinition") || ...
                    isa(value, "macd.model.CallbackEdit");
                if ~safe, value = []; end
            end
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
