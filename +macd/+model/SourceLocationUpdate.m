classdef SourceLocationUpdate
    % SourceLocationUpdate Prepare current ranges and source-value bindings for one live component.
    %   The document publishes these private candidates together with source text.
    %   This helper preserves component/property handles and never interprets user code.

    properties (SetAccess = private)
        % ComponentId - Stable owner whose existing occurrences were prepared.
        ComponentId string = ""
        % CanApply - Whether all owned ranges survived or were exactly replaced.
        CanApply logical = true
    end

    properties (Access = private)
        BeforeSpans struct = struct()
        AfterSpans struct = struct()
        BeforeMetadata struct = struct()
        AfterMetadata struct = struct()
        BeforeSettings struct = struct([])
        BeforeProperties struct = struct([])
        AfterSettings struct = struct([])
        Properties struct = struct("Path", {}, "SourceSpan", {}, "Metadata", {})
    end

    methods
        function obj = SourceLocationUpdate(component, batch, literalChanges, execution, analysis)
            % SourceLocationUpdate Stage source positions and already validated literal replacements.
            arguments (Input)
                component (1, 1) macd.model.ComponentRecord
                batch (1, 1) macd.source.SourcePatchBatch
                literalChanges struct = struct("SettingId", {}, "Value", {})
                execution struct = struct()
                analysis macd.source.SourceAnalysis = macd.source.SourceAnalysis.empty
            end
            arguments (Output)
                obj (1, 1) macd.model.SourceLocationUpdate
            end
            obj.ComponentId = component.Id;
            obj.BeforeSpans = component.SourceSpans;
            obj.BeforeMetadata = component.Metadata;
            obj.AfterMetadata = component.Metadata;
            obj.BeforeSettings = component.settingSnapshot();
            obj.BeforeProperties = macd.model.SourceLocationUpdate.captureProperties(component);
            [obj.AfterSpans, obj.CanApply] = macd.model.SourceLocationUpdate.mapRanges(component.SourceSpans, batch);
            obj.AfterSettings = obj.BeforeSettings;
            for index = 1:numel(obj.AfterSettings)
                record = obj.AfterSettings(index);
                [location, valid] = macd.model.SourceLocationUpdate.mapRanges(record.Location, batch);
                obj.CanApply = obj.CanApply && valid;
                record.Location = location;
                if isfield(execution, "Trace") && valid
                    indices = analysis.statementIndices(location.SourceSpan);
                    visits = find(ismember(execution.Trace.Order, indices));
                    if isscalar(visits)
                        if record.Location.Method == "nameValue"
                            peers = obj.BeforeSettings(1:index);
                            ordinal = nnz(arrayfun(@(item) item.Location.Method == "nameValue" && ...
                                item.Location.StatementId == record.Location.StatementId, peers));
                            record.Location.Sequence = execution.Creation(visits) + ordinal;
                        else
                            record.Location.Sequence = execution.Assignment(visits);
                        end
                    else
                        obj.CanApply = false;
                    end
                end
                change = find(string({literalChanges.SettingId}) == record.Location.Id, 1);
                if ~isempty(change), record.Value = literalChanges(change).Value; end
                obj.AfterSettings(index) = record;
            end
            if isfield(execution, "Trace") && obj.CanApply
                indices = analysis.statementIndices(obj.AfterSpans.Creation);
                visits = find(ismember(execution.Trace.Order, indices));
                if isscalar(visits)
                    obj.AfterMetadata.InitializationCreationSequence = execution.Creation(visits);
                    obj.AfterMetadata.InitializationCreationCertain = execution.Trace.Certain(visits);
                else
                    obj.CanApply = false;
                end
            end
            if ~isempty(literalChanges)
                ids = strings(1, numel(obj.AfterSettings));
                for index = 1:numel(ids), ids(index) = obj.AfterSettings(index).Location.Id; end
                assert(all(ismember(string({literalChanges.SettingId}), ids)), ...
                    "macd:SourceLocationUpdate:UnknownSetting", "Literal changes must target an existing owned occurrence.");
            end
            for entry = component.Properties
                [span, valid] = batch.mapSpan(entry.SourceSpan);
                obj.CanApply = obj.CanApply && valid;
                metadata = entry.Metadata;
                if isfield(metadata, "ValueSpan")
                    [metadata.ValueSpan, valid] = batch.mapSpan(metadata.ValueSpan);
                    obj.CanApply = obj.CanApply && valid;
                end
                obj.Properties(end + 1) = struct("Path", entry.Path, "SourceSpan", span, "Metadata", metadata);
            end
        end

        function assertCurrent(obj, component)
            % assertCurrent Validate every component input before any transaction member is published.
            arguments (Input)
                obj (1, 1) macd.model.SourceLocationUpdate
                component (1, 1) macd.model.ComponentRecord
            end
            assert(obj.CanApply, "macd:SourceLocationUpdate:NeedsRescan", "Changed token ownership requires syntax rebinding.");
            assert(component.Id == obj.ComponentId && isequaln(component.SourceSpans, obj.BeforeSpans) && ...
                isequaln(component.Metadata, obj.BeforeMetadata) && ...
                isequaln(component.settingSnapshot(), obj.BeforeSettings) && ...
                isequaln(macd.model.SourceLocationUpdate.captureProperties(component), obj.BeforeProperties), ...
                "macd:SourceLocationUpdate:StaleComponent", "The component changed after preparing its location update.");
        end

        function apply(obj, component)
            % apply Publish a prevalidated range/value projection without recreating live property handles.
            arguments (Input)
                obj (1, 1) macd.model.SourceLocationUpdate
                component (1, 1) macd.model.ComponentRecord
            end
            obj.assertCurrent(component);
            component.SourceSpans = obj.AfterSpans;
            component.Metadata = obj.AfterMetadata;
            component.restoreSettings(obj.AfterSettings);
            for projected = obj.Properties
                entry = component.getProperty(projected.Path);
                entry.SourceSpan = projected.SourceSpan;
                entry.Metadata = projected.Metadata;
                if isfield(projected.Metadata, "SourceSettingId")
                    settings = component.getSettings(projected.Path);
                    match = find(string({settings.Id}) == string(projected.Metadata.SourceSettingId), 1);
                    if ~isempty(match), entry.applySourceSetting(settings(match)); end
                end
            end
        end
    end

    methods (Static)
        function [diagnostics, regions] = annotations(document, batch)
            % annotations Relocate preserved diagnostic and opaque-statement boundaries before publication.
            arguments (Input)
                document (1, 1) macd.model.DocumentModel
                batch (1, 1) macd.source.SourcePatchBatch
            end
            arguments (Output)
                diagnostics macd.model.Diagnostic
                regions macd.model.UnknownSourceRegion
            end
            diagnostics = macd.model.Diagnostic.empty;
            for previous = document.Diagnostics
                [span, valid] = batch.mapSpan(previous.SourceSpan);
                assert(valid, "macd:SourceLiteralTransaction:WiderProof", "Diagnostic ownership changed.");
                diagnostics(end + 1) = macd.model.Diagnostic(previous.Code, previous.Severity, ...
                    previous.Message, previous.ComponentId, span); %#ok<AGROW>
            end
            regions = macd.model.UnknownSourceRegion.empty;
            for previous = document.UnknownRegions
                [span, valid] = batch.mapSpan(previous.Span);
                assert(valid, "macd:SourceLiteralTransaction:WiderProof", "Opaque statement ownership changed.");
                regions(end + 1) = macd.model.UnknownSourceRegion(previous.Text, span, previous.Reason); %#ok<AGROW>
            end
        end

        function records = relocateSettings(records, batch)
            % relocateSettings Rebase history-owned setting locations without changing occurrence identities.
            arguments (Input)
                records struct
                batch (1, 1) macd.source.SourcePatchBatch
            end
            arguments (Output)
                records struct
            end
            for index = 1:numel(records)
                [location, valid] = macd.model.SourceLocationUpdate.mapRanges(records(index).Location, batch);
                assert(valid, "macd:SourceLocationUpdate:NeedsRescan", "History source locations cannot be rebased.");
                records(index).Location = location;
            end
        end
    end

    methods (Static, Access = private)
        function records = captureProperties(component)
            % captureProperties Capture private value inputs for stale-candidate checks without cloning handles.
            arguments (Input)
                component (1, 1) macd.model.ComponentRecord
            end
            arguments (Output)
                records struct
            end
            records = struct([]);
            for entry = component.Properties
                record = entry.toStruct();
                if isempty(records), records = record; else, records(end + 1) = record; end %#ok<AGROW>
            end
        end

        function [value, valid] = mapRanges(value, batch)
            % mapRanges Transform owned span fields without touching literal payloads or opaque identities.
            arguments (Input)
                value
                batch (1, 1) macd.source.SourcePatchBatch
            end
            arguments (Output)
                value
                valid (1, 1) logical
            end
            valid = true;
            if isa(value, "macd.model.SourceSpan")
                [value, valid] = batch.mapSpan(value);
            elseif isstruct(value)
                for index = 1:numel(value)
                    for field = reshape(string(fieldnames(value)), 1, [])
                        [value(index).(field), fieldValid] = macd.model.SourceLocationUpdate.mapRanges(value(index).(field), batch);
                        valid = valid && fieldValid;
                    end
                end
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
