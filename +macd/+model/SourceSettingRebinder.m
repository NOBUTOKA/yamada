classdef SourceSettingRebinder
    % SourceSettingRebinder Rebind one component's settings from current lexical statements.
    %   This utility reuses the parser's factory/assignment syntax without reparsing
    %   other component models. Existing physical occurrences keep their identities.

    methods (Static)
        function [settings, creationSequence, factoryArguments, sequences] = rebind(document, component, state, batch, registry)
            % rebind Recover actual current setting order and preserve surviving occurrence identities.
            arguments (Input)
                document (1, 1) macd.model.DocumentModel
                component (1, 1) macd.model.ComponentRecord
                state (1, 1) macd.model.CurrentSourceState
                batch (1, 1) macd.source.SourcePatchBatch
                registry (1, 1) macd.model.ComponentRegistry
            end
            arguments (Output)
                settings macd.model.PropertySetting
                creationSequence (1, 1) double
                factoryArguments cell
                sequences (1, 1) struct
            end
            assert(state.Text == batch.AfterText);
            analysis = state.Analysis;
            offsets = zeros(1, 0);
            for record = document.Components
                span = record.SourceSpans.Creation;
                if isempty(span) || ~span.isKnown(), continue, end
                [current, valid] = batch.mapSpan(span);
                assert(valid, "macd:SourceSettingRebinder:NeedsModelParse", "Factory ownership changed.");
                offsets(end + 1) = current.StartOffset; %#ok<AGROW>
            end
            trace = analysis.initialization(offsets);
            [creation, valid] = batch.mapSpan(component.SourceSpans.Creation);
            assert(valid);
            index = analysis.statementIndices(creation);
            assert(isscalar(index), "macd:SourceSettingRebinder:NeedsModelParse", "Factory ownership is not unique.");
            visits = find(trace.Order == index);
            assert(isscalar(visits), "macd:SourceSettingRebinder:NeedsModelParse", "Factory execution is not unique.");
            sequences = macd.model.SourceSettingRebinder.executionSequences(document, state, batch, registry);
            creationSequence = sequences.Creation(visits);
            definition = registry.get(component.Factory, component.CreationArguments);
            [~, factoryArguments, factory, ~, supported] = macd.source.PropertySettingSyntax.factory( ...
                analysis.Statements(index), definition, state.StateId);
            assert(supported, "macd:SourceSettingRebinder:NeedsModelParse", "Factory syntax requires a wider proof.");
            settings = macd.model.PropertySetting.empty;
            for originalSetting = factory
                record = originalSetting.toStruct();
                record.Location.Sequence = creationSequence + numel(settings) + 1;
                setting = macd.model.PropertySetting(record.Path, record.Value, record.Location);
                setting = macd.model.SourceSettingRebinder.scoped(setting, analysis.Layout, index);
                settings(end + 1) = macd.model.SourceSettingRebinder.identity(setting, component.Settings, batch); %#ok<AGROW>
            end
            pattern = "^app\." + regexptranslate("escape", component.Name) + "\.[A-Za-z]\w*(?:\.\w+)*\s*=";
            for visit = 1:numel(trace.Order)
                index = trace.Order(visit);
                statement = analysis.Statements(index);
                if isempty(regexp(statement.Text, pattern, "once")), continue, end
                setting = macd.source.PropertySettingSyntax.assignment(statement, state.StateId, sequences.Assignment(visit), trace.Certain(visit));
                setting = macd.model.SourceSettingRebinder.scoped(setting, analysis.Layout, index);
                settings(end + 1) = macd.model.SourceSettingRebinder.identity(setting, component.Settings, batch); %#ok<AGROW>
            end
            % New constructor arguments belong to the surviving factory occurrence group.
            constructor = settings(string({settings.Method}) == "nameValue");
            previous = component.Settings(string({component.Settings.Method}) == "nameValue");
            if ~isempty(constructor) && ~isempty(previous)
                for index = find(string({settings.Method}) == "nameValue")
                    record = settings(index).toStruct();
                    record.Location.StatementId = previous(1).StatementId;
                    settings(index) = macd.model.PropertySetting(record.Path, record.Value, record.Location);
                end
            end
        end

        function result = executionSequences(document, state, batch, registry)
            % executionSequences Count recognized execution events exactly as the full parser does.
            arguments (Input)
                document (1, 1) macd.model.DocumentModel
                state (1, 1) macd.model.CurrentSourceState
                batch (1, 1) macd.source.SourcePatchBatch
                registry (1, 1) macd.model.ComponentRegistry
            end
            arguments (Output)
                result (1, 1) struct
            end
            analysis = state.Analysis;
            offsets = zeros(1, numel(document.Components));
            owners = zeros(size(offsets));
            counts = zeros(size(offsets));
            for index = 1:numel(offsets)
                component = document.Components(index);
                [span, valid] = batch.mapSpan(component.SourceSpans.Creation);
                assert(valid && ~isempty(span));
                offsets(index) = span.StartOffset;
                owners(index) = analysis.statementIndices(span);
                changed = any(arrayfun(@(edit) edit.Start <= component.SourceSpans.Creation.EndOffset && ...
                    edit.End >= component.SourceSpans.Creation.StartOffset, batch.Edits));
                if changed
                    definition = registry.get(component.Factory, component.CreationArguments);
                    [~, ~, settings, ~, supported] = macd.source.PropertySettingSyntax.factory( ...
                        analysis.Statements(owners(index)), definition, state.StateId);
                    assert(supported);
                    counts(index) = numel(settings);
                else
                    counts(index) = nnz(string({component.Settings.Method}) == "nameValue");
                end
            end
            trace = analysis.initialization(offsets);
            result = struct("Trace", trace, "Creation", zeros(size(trace.Order)), ...
                "Assignment", zeros(size(trace.Order)), "Owners", owners);
            sequence = 0;
            created = strings(1, 0);
            names = string({document.Components.Name});
            for visit = 1:numel(trace.Order)
                index = trace.Order(visit);
                owner = find(owners == index, 1);
                if ~isempty(owner)
                    sequence = sequence + 1;
                    result.Creation(visit) = sequence;
                    sequence = sequence + counts(owner);
                    created(end + 1) = names(owner); %#ok<AGROW>
                    continue
                end
                assignment = regexp(analysis.Statements(index).Text, ...
                    "^app\.([A-Za-z]\w*)\.[A-Za-z]\w*(?:\.\w+)*\s*=", "tokens", "once");
                if isempty(assignment) || ~any(created == string(assignment{1})), continue, end
                sequence = sequence + 1;
                result.Assignment(visit) = sequence;
            end
        end
    end

    methods (Static, Access = private)
        function setting = scoped(setting, layout, index)
            % scoped Attach current initializer ownership using the same boundaries as full parsing.
            arguments (Input)
                setting (1, 1) macd.model.PropertySetting
                layout (1, 1) struct
                index (1, 1) double
            end
            arguments (Output)
                setting (1, 1) macd.model.PropertySetting
            end
            owner = layout.Owner(index);
            span = macd.model.SourceSpan.empty;
            match = find(string({layout.Methods.Name}) == owner);
            if isscalar(match), span = layout.Methods(match).Span; end
            setting = setting.withScope(owner, span);
        end

        function current = identity(current, previous, batch)
            % identity Retain IDs for physical occurrences whose mapped ranges match current syntax.
            arguments (Input)
                current (1, 1) macd.model.PropertySetting
                previous macd.model.PropertySetting
                batch (1, 1) macd.source.SourcePatchBatch
            end
            arguments (Output)
                current (1, 1) macd.model.PropertySetting
            end
            for old = previous
                if old.Path ~= current.Path || old.Method ~= current.Method || isempty(old.ValueSpan), continue, end
                [span, valid] = batch.mapSpan(old.ValueSpan);
                if valid && isequaln(span, current.ValueSpan)
                    record = current.toStruct();
                    record.Location.Id = old.Id;
                    record.Location.SourceSnapshotId = old.SourceSnapshotId;
                    record.Location.StatementId = old.StatementId;
                    record.Location.InitializationScopeId = old.InitializationScopeId;
                    current = macd.model.PropertySetting(record.Path, record.Value, record.Location);
                    return
                end
            end
            % A newly inserted setting shares its existing owner's scope identity.
            for old = previous
                if old.OwnerMethod == current.OwnerMethod && strlength(old.InitializationScopeId) > 0
                    record = current.toStruct();
                    record.Location.InitializationScopeId = old.InitializationScopeId;
                    current = macd.model.PropertySetting(record.Path, record.Value, record.Location);
                    return
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
