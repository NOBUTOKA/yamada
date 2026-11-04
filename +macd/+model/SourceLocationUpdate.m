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
        BeforeSettingValues macd.model.PropertySetting = macd.model.PropertySetting.empty
        CentralSettings logical = false
        BeforeProperties struct = struct([])
        AfterSettingValues macd.model.PropertySetting = macd.model.PropertySetting.empty
        Properties struct = struct("Path", {}, "SourceSpan", {}, "Metadata", {}, "ValueChanged", {})
    end

    methods
        function obj = SourceLocationUpdate(component, batch, literalChanges, execution, analysis, settingProjection)
            % SourceLocationUpdate Stage source positions and already validated literal replacements.
            arguments (Input)
                component (1, 1) macd.model.ComponentRecord
                batch (1, 1) macd.source.SourcePatchBatch
                literalChanges struct = struct("SettingId", {}, "Value", {})
                execution struct = struct()
                analysis macd.source.SourceAnalysis = macd.source.SourceAnalysis.empty
                settingProjection (1, 1) struct = struct()
            end
            arguments (Output)
                obj (1, 1) macd.model.SourceLocationUpdate
            end
            obj.ComponentId = component.Id;
            obj.BeforeSpans = component.SourceSpans;
            obj.BeforeMetadata = component.Metadata;
            obj.AfterMetadata = component.Metadata;
            obj.BeforeSettingValues = component.Settings;
            obj.BeforeProperties = macd.model.SourceLocationUpdate.captureProperties(component);

            obj.AfterSettingValues = obj.BeforeSettingValues;
            obj.CentralSettings = isfield(settingProjection, "Before");
            groups = {component.SourceSpans};
            records = struct("Path", {}, "Value", {}, "Location", {});
            if obj.CentralSettings
                assert(isequaln(obj.BeforeSettingValues, settingProjection.Before));
                obj.AfterSettingValues = settingProjection.After;
            else
                records = component.settingSnapshot();
                for record = records, groups{end + 1} = record.Location; end %#ok<AGROW>
            end
            settingCount = numel(groups);
            for entry = component.Properties
                ranges = struct("SourceSpan", entry.SourceSpan);
                if isfield(entry.Metadata, "ValueSpan"), ranges.ValueSpan = entry.Metadata.ValueSpan; end
                groups{end + 1} = ranges; %#ok<AGROW>
            end
            [mapped, valid] = macd.model.SourceLocationUpdate.mapGroups(groups, batch);
            obj.AfterSpans = mapped{1};
            obj.CanApply = obj.CanApply && valid;
            preparedVisits = zeros(1, settingCount);
            if isfield(execution, "RangeStarts")
                starts = zeros(1, settingCount);
                ends = starts;
                for index = 1:settingCount
                    if index == 1, span = mapped{index}.Creation; else, span = mapped{index}.SourceSpan; end
                    if isempty(span), continue, end
                    starts(index) = span.StartOffset;
                    ends(index) = span.EndOffset;
                end
                [found, positions] = ismember([starts(:) ends(:)], ...
                    [execution.RangeStarts(:) execution.RangeEnds(:)], "rows");
                preparedVisits(found) = execution.Visits(positions(found));
            end
            for index = 1:numel(records)
                record = records(index);
                location = mapped{index + 1};
                valid = obj.CanApply;
                obj.CanApply = obj.CanApply && valid;
                record.Location = location;
                if isfield(execution, "Trace") && isempty(location.SourceSpan)
                    obj.CanApply = false;
                elseif isfield(execution, "Trace") && valid
                    if isfield(execution, "SequenceMap") && record.Location.Sequence > 0
                        record.Location.Sequence = execution.SequenceMap(record.Location.Sequence);
                        visits = [];
                    elseif isfield(execution, "RangeStarts")
                        visits = preparedVisits(index + 1);
                        if visits == 0, visits = []; end
                    else
                        indices = analysis.statementIndices(location.SourceSpan);
                        visits = find(ismember(execution.Trace.Order, indices));
                    end
                    if isscalar(visits)
                        if record.Location.Method == "nameValue"
                            peers = records(1:index);
                            ordinal = nnz(arrayfun(@(item) item.Location.Method == "nameValue" && ...
                                item.Location.StatementId == record.Location.StatementId, peers));
                            record.Location.Sequence = execution.Creation(visits) + ordinal;
                        else
                            record.Location.Sequence = execution.Assignment(visits);
                        end
                    elseif ~isfield(execution, "SequenceMap")
                        obj.CanApply = false;
                    end
                end
                change = find([literalChanges.SettingId] == record.Location.Id, 1);
                if ~isempty(change), record.Value = literalChanges(change).Value; end
                projected = obj.AfterSettingValues(index).withProjectedLocation(record.Location);
                if ~isempty(change), projected = projected.withLiteral(record.Value); end
                obj.AfterSettingValues(index) = projected;
            end
            if isfield(execution, "Trace") && obj.CanApply
                if isfield(execution, "RangeStarts")
                    visits = preparedVisits(1);
                    if visits == 0, visits = []; end
                else
                    indices = analysis.statementIndices(obj.AfterSpans.Creation);
                    visits = find(ismember(execution.Trace.Order, indices));
                end
                if isscalar(visits)
                    obj.AfterMetadata.InitializationCreationSequence = execution.Creation(visits);
                    obj.AfterMetadata.InitializationCreationCertain = execution.Trace.Certain(visits);
                else
                    obj.CanApply = false;
                end
            end
            if ~isempty(literalChanges)
                ids = string({obj.AfterSettingValues.Id});
                assert(all(ismember(string({literalChanges.SettingId}), ids)), ...
                    "macd:SourceLocationUpdate:UnknownSetting", "Literal changes must target an existing owned occurrence.");
            end
            propertyIndex = settingCount;
            for entry = component.Properties
                propertyIndex = propertyIndex + 1;
                ranges = mapped{propertyIndex};
                span = ranges.SourceSpan;
                metadata = entry.Metadata;
                if isfield(ranges, "ValueSpan"), metadata.ValueSpan = ranges.ValueSpan; end
                valueChanged = isfield(metadata, "SourceSettingId") && ...
                    any(string({literalChanges.SettingId}) == string(metadata.SourceSettingId));
                obj.Properties(end + 1) = struct("Path", entry.Path, "SourceSpan", span, ...
                    "Metadata", metadata, "ValueChanged", valueChanged);
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
                isequaln(component.Settings, obj.BeforeSettingValues) && ...
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
            obj.applyValidated(component);
        end
    end

    methods (Access = {?macd.model.SourceLiteralTransaction, ?macd.model.SourceLiteralBatchTransaction, ?macd.model.DocumentModel})
        function applyToCandidate(obj, component)
            % applyToCandidate Project prepared positions into an independent candidate without its live central-store publication.
            arguments (Input)
                obj (1, 1) macd.model.SourceLocationUpdate
                component (1, 1) macd.model.ComponentRecord
            end
            obj.applyValidated(component);
            if obj.CentralSettings, component.applyProjectedSettings(obj.AfterSettingValues); end
        end

        function applyValidated(obj, component)
            % applyValidated Publish a member after the transaction validated every owner without yielding.
            arguments (Input)
                obj (1, 1) macd.model.SourceLocationUpdate
                component (1, 1) macd.model.ComponentRecord
            end
            if ~isequaln(component.SourceSpans, obj.AfterSpans), component.SourceSpans = obj.AfterSpans; end
            if ~isequaln(component.Metadata, obj.AfterMetadata), component.Metadata = obj.AfterMetadata; end
            if ~obj.CentralSettings && ~isequaln(obj.BeforeSettingValues, obj.AfterSettingValues)
                component.applyProjectedSettings(obj.AfterSettingValues);
            end
            for projected = obj.Properties
                entry = component.getProperty(projected.Path);
                if ~projected.ValueChanged && isequaln(entry.SourceSpan, projected.SourceSpan) && ...
                        isequaln(entry.Metadata, projected.Metadata), continue, end
                if ~isequaln(entry.SourceSpan, projected.SourceSpan), entry.SourceSpan = projected.SourceSpan; end
                if ~isequaln(entry.Metadata, projected.Metadata), entry.Metadata = projected.Metadata; end
                if projected.ValueChanged && isfield(projected.Metadata, "SourceSettingId")
                    settings = component.getSettings(projected.Path);
                    match = find(string({settings.Id}) == string(projected.Metadata.SourceSettingId), 1);
                    if ~isempty(match), entry.applySourceSetting(settings(match)); end
                end
            end
        end
    end

    methods (Access = ?macd.model.EvaluationContext)
        function record = projectInputs(obj, record)
            % projectInputs Carry prepared source locations into a previously independent component snapshot.
            arguments (Input)
                obj (1, 1) macd.model.SourceLocationUpdate
                record (1, 1) struct
            end
            arguments (Output)
                record (1, 1) struct
            end
            assert(obj.CanApply && record.Id == obj.ComponentId && ~any([obj.Properties.ValueChanged]));
            record.SourceSpans = obj.AfterSpans;
            record.Metadata = obj.AfterMetadata;
            settings = struct("Path", {}, "Value", {}, "Location", {});
            for setting = obj.AfterSettingValues, settings(end + 1) = setting.toStruct(); end %#ok<AGROW>
            record.Settings = settings;
            for projected = obj.Properties
                index = find(string({record.Properties.Path}) == projected.Path, 1);
                assert(~isempty(index));
                record.Properties(index).SourceSpan = projected.SourceSpan;
                record.Properties(index).Metadata = projected.Metadata;
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
            diagnostics = macd.model.SourceLocationUpdate.relocateDiagnostics(document.Diagnostics, batch);
            regions = macd.model.UnknownSourceRegion.empty;
            for previous = document.UnknownRegions
                [span, valid] = batch.mapSpan(previous.Span);
                if ~valid && any(arrayfun(@(edit) strlength(edit.Text) == 0 && edit.Start <= previous.Span.StartOffset && ...
                        edit.End >= previous.Span.EndOffset, batch.Edits)), continue, end
                assert(valid, "macd:SourceLiteralTransaction:WiderProof", "Opaque statement ownership changed.");
                regions(end + 1) = macd.model.UnknownSourceRegion(previous.Text, span, previous.Reason); %#ok<AGROW>
            end
        end

        function diagnostics = relocateDiagnostics(previousDiagnostics, batch)
            % relocateDiagnostics Retain immutable diagnostic positions across a proven literal patch.
            arguments (Input)
                previousDiagnostics macd.model.Diagnostic
                batch (1, 1) macd.source.SourcePatchBatch
            end
            arguments (Output)
                diagnostics macd.model.Diagnostic
            end
            diagnostics = macd.model.Diagnostic.empty;
            for previous = previousDiagnostics
                [span, valid] = batch.mapSpan(previous.SourceSpan);
                if ~valid && any(arrayfun(@(edit) strlength(edit.Text) == 0 && edit.Start <= previous.SourceSpan.StartOffset && ...
                        edit.End >= previous.SourceSpan.EndOffset, batch.Edits)), continue, end
                assert(valid, "macd:SourceLiteralTransaction:WiderProof", "Diagnostic ownership changed.");
                diagnostics(end + 1) = macd.model.Diagnostic(previous.Code, previous.Severity, ...
                    previous.Message, previous.ComponentId, span); %#ok<AGROW>
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

        function [groups, valid] = mapGroups(groups, batch)
            % mapGroups Transform only direct range fields together, excluding literal data and identities.
            arguments (Input)
                groups cell
                batch (1, 1) macd.source.SourcePatchBatch
            end
            arguments (Output)
                groups cell
                valid (1, 1) logical
            end
            spans = {};
            owners = zeros(1, 0);
            names = strings(1, 0);
            for index = 1:numel(groups)
                fields = reshape(string(fieldnames(groups{index})), 1, []);
                for field = fields
                    if ~isa(groups{index}.(field), "macd.model.SourceSpan"), continue, end
                    spans{end + 1} = groups{index}.(field); %#ok<AGROW>
                    owners(end + 1) = index; %#ok<AGROW>
                    names(end + 1) = field; %#ok<AGROW>
                end
            end
            [spans, flags] = batch.mapSpanCells(spans);
            valid = all(flags);
            for index = 1:numel(spans)
                groups{owners(index)}.(names(index)) = spans{index};
            end
        end

        function [value, valid] = mapRanges(value, batch)
            % mapRanges Transform named range records without walking literal payloads.
            arguments (Input)
                value (1, 1) struct
                batch (1, 1) macd.source.SourcePatchBatch
            end
            arguments (Output)
                value (1, 1) struct
                valid (1, 1) logical
            end
            [groups, valid] = macd.model.SourceLocationUpdate.mapGroups({value}, batch);
            value = groups{1};
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
