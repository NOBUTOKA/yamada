classdef SourceSettingRebinder
    % SourceSettingRebinder Rebind one component's settings from current lexical statements.
    %   This utility reuses the parser's factory/assignment syntax without reparsing
    %   other component models. Existing physical occurrences keep their identities.

    methods (Static)
        function [settings, creationSequence, factoryArguments, sequences] = rebind(document, component, state, batch, registry)
            % rebind Recover actual current setting order and preserve surviving occurrence identities.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                component (1, 1) yamada.model.ComponentRecord
                state (1, 1) yamada.model.CurrentSourceState
                batch (1, 1) yamada.source.SourcePatchBatch
                registry (1, 1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                settings yamada.model.PropertySetting
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
                assert(valid, "yamada:SourceSettingRebinder:NeedsModelParse", "Factory ownership changed.");
                offsets(end + 1) = current.StartOffset; %#ok<AGROW>
            end
            projectedTrace = analysis.inheritInitialization(document.sourceAnalysis(), batch, offsets, component.Name);
            trace = analysis.initialization(offsets);
            [creation, valid] = batch.mapSpan(component.SourceSpans.Creation);
            assert(valid);
            index = analysis.statementIndices(creation);
            assert(isscalar(index), "yamada:SourceSettingRebinder:NeedsModelParse", "Factory ownership is not unique.");
            visits = find(trace.Order == index);
            assert(isscalar(visits), "yamada:SourceSettingRebinder:NeedsModelParse", "Factory execution is not unique.");
            sequences = yamada.model.SourceSettingRebinder.executionSequences(document, state, batch, registry);
            sequences.ProjectedInitialization = projectedTrace;
            creationSequence = sequences.Creation(visits);
            definition = registry.get(component.Factory, component.CreationArguments);
            [~, factoryArguments, factory, ~, supported] = yamada.source.PropertySettingSyntax.factory( ...
                analysis.Statements(index), definition, state.StateId);
            assert(supported, "yamada:SourceSettingRebinder:NeedsModelParse", "Factory syntax requires a wider proof.");
            settings = yamada.model.PropertySetting.empty;
            for originalSetting = factory
                record = originalSetting.toStruct();
                record.Location.Sequence = creationSequence + numel(settings) + 1;
                setting = yamada.model.PropertySetting(record.Path, record.Value, record.Location);
                setting = yamada.model.SourceSettingRebinder.scoped(setting, analysis.Layout, index);
                settings(end + 1) = yamada.model.SourceSettingRebinder.identity(setting, component.Settings, batch); %#ok<AGROW>
            end
            pattern = "^app\." + regexptranslate("escape", component.Name) + "\.[A-Za-z]\w*(?:\.\w+)*\s*=";
            texts = string({analysis.Statements(trace.Order).Text});
            candidates = find(startsWith(texts, "app." + component.Name + "."));
            for visit = candidates
                index = trace.Order(visit);
                statement = analysis.Statements(index);
                if isempty(regexp(statement.Text, pattern, "once")), continue, end
                setting = yamada.source.PropertySettingSyntax.assignment(statement, state.StateId, sequences.Assignment(visit), trace.Certain(visit));
                setting = yamada.model.SourceSettingRebinder.scoped(setting, analysis.Layout, index);
                settings(end + 1) = yamada.model.SourceSettingRebinder.identity(setting, component.Settings, batch); %#ok<AGROW>
            end
            settings = document.canonicalizeSettings(settings);
            % New constructor arguments belong to the surviving factory occurrence group.
            constructor = settings(string({settings.Method}) == "nameValue");
            previous = component.Settings(string({component.Settings.Method}) == "nameValue");
            if ~isempty(constructor) && ~isempty(previous)
                for index = find(string({settings.Method}) == "nameValue")
                    record = settings(index).toStruct();
                    record.Location.StatementId = previous(1).StatementId;
                    settings(index) = yamada.model.PropertySetting(record.Path, record.Value, record.Location);
                end
            end
        end

        function result = executionSequences(document, state, batch, registry)
            % executionSequences Count recognized execution events exactly as the full parser does.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                state (1, 1) yamada.model.CurrentSourceState
                batch (1, 1) yamada.source.SourcePatchBatch
                registry (1, 1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                result (1, 1) struct
            end
            analysis = state.Analysis;
            result = analysis.executionIndex();
            if ~isempty(fieldnames(result)), return, end
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
                    [~, ~, settings, ~, supported] = yamada.source.PropertySettingSyntax.factory( ...
                        analysis.Statements(owners(index)), definition, state.StateId);
                    assert(supported);
                    counts(index) = numel(settings);
                else
                    counts(index) = nnz(string({component.Settings.Method}) == "nameValue");
                end
            end
            trace = analysis.initialization(offsets);
            result = struct("Trace", trace, "Creation", zeros(size(trace.Order)), ...
                "Assignment", zeros(size(trace.Order)), "Owners", owners, "Counts", zeros(size(trace.Order)));
            % Index unique execution visits once for every owner's position projection.
            [uniqueStatements, ~, groups] = unique(trace.Order);
            occurrences = accumarray(groups(:), 1);
            uniqueStatements = uniqueStatements(occurrences == 1);
            [~, visits] = ismember(uniqueStatements, trace.Order);
            spans = [analysis.Statements(uniqueStatements).Span];
            result.RangeStarts = [spans.StartOffset];
            result.RangeEnds = [spans.EndOffset];
            result.Visits = visits;
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
                    result.Counts(visit) = 1 + counts(owner);
                    created(end + 1) = names(owner); %#ok<AGROW>
                    continue
                end
                assignment = regexp(analysis.Statements(index).Text, ...
                    "^app\.([A-Za-z]\w*)\.[A-Za-z]\w*(?:\.\w+)*\s*=", "tokens", "once");
                if isempty(assignment) || ~any(created == string(assignment{1})), continue, end
                sequence = sequence + 1;
                result.Assignment(visit) = sequence;
                result.Counts(visit) = 1;
            end
            analysis.rememberExecution(result);
        end
    end

    methods (Static, Access = private)
        function setting = scoped(setting, layout, index)
            % scoped Attach current initializer ownership using the same boundaries as full parsing.
            arguments (Input)
                setting (1, 1) yamada.model.PropertySetting
                layout (1, 1) struct
                index (1, 1) double
            end
            arguments (Output)
                setting (1, 1) yamada.model.PropertySetting
            end
            owner = layout.Owner(index);
            span = yamada.model.SourceSpan.empty;
            match = find(string({layout.Methods.Name}) == owner);
            if isscalar(match), span = layout.Methods(match).Span; end
            setting = setting.withScope(owner, span);
        end

        function current = identity(current, previous, batch)
            % identity Retain IDs for physical occurrences whose mapped ranges match current syntax.
            arguments (Input)
                current (1, 1) yamada.model.PropertySetting
                previous yamada.model.PropertySetting
                batch (1, 1) yamada.source.SourcePatchBatch
            end
            arguments (Output)
                current (1, 1) yamada.model.PropertySetting
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
                    current = yamada.model.PropertySetting(record.Path, record.Value, record.Location);
                    return
                end
            end
            % A newly inserted setting shares its existing owner's scope identity.
            for old = previous
                if old.OwnerMethod == current.OwnerMethod && strlength(old.InitializationScopeId) > 0
                    record = current.toStruct();
                    record.Location.InitializationScopeId = old.InitializationScopeId;
                    current = yamada.model.PropertySetting(record.Path, record.Value, record.Location);
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
