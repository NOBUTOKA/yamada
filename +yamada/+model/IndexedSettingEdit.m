classdef IndexedSettingEdit
    % IndexedSettingEdit Derive canonical setting updates from primary editor edits and maintained indexes.
    %   The editor supplies values and placement recipes. Source text is not parsed to
    %   rediscover occurrences, ownership, method membership or execution order.
    methods (Static)
        function [state, settings, factoryArguments, execution] = prepare(document, source, component, batch, changes, placements, registry, removedIds, restoredStateId)
            % prepare Apply one known literal edit to settings, statements, layout and execution indexes.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                source (1, 1) yamada.model.CurrentSourceState
                component (1, 1) yamada.model.ComponentRecord
                batch (1, 1) yamada.source.SourcePatchBatch
                changes (1, :) struct
                placements (1, :) struct
                registry (1, 1) yamada.model.ComponentRegistry
                removedIds (1, :) double = zeros(1, 0)
                restoredStateId (1, 1) string = ""
            end
            arguments (Output)
                state (1, 1) yamada.model.CurrentSourceState
                settings yamada.model.PropertySetting
                factoryArguments cell
                execution (1, 1) struct
            end
            spec = struct("ComponentId", component.Id, "Changes", changes, "Placements", placements, "RemovedIds", removedIds);
            [state, bindings, execution] = yamada.model.IndexedSettingEdit.prepareMany(document, source, spec, batch, registry, restoredStateId);
            settings = bindings.Settings;
            factoryArguments = bindings.FactoryArguments;
        end

        function [state, bindings, execution] = prepareMany(document, source, specs, batch, registry, restoredStateId)
            % prepareMany Project one atomic patch across independently owned setting lists using shared execution indexes.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                source (1, 1) yamada.model.CurrentSourceState
                specs (1, :) struct
                batch (1, 1) yamada.source.SourcePatchBatch
                registry (1, 1) yamada.model.ComponentRegistry
                restoredStateId (1, 1) string = ""
            end
            arguments (Output)
                state (1, 1) yamada.model.CurrentSourceState
                bindings (1, :) struct
                execution (1, 1) struct
            end
            analysis = source.Analysis;
            execution = yamada.model.SourceSettingRebinder.executionSequences(document, source, ...
                yamada.source.SourcePatchBatch(source.Text), registry);
            additions = yamada.source.SourceStatement.empty;
            anchors = zeros(1, 0); removedStatements = zeros(1, 0);
            constructorDelta = zeros(size(execution.Trace.Order));
            addedOwners = strings(1, 0);
            bindings = struct("ComponentId", {}, "Settings", {}, "FactoryArguments", {});
            for spec = specs
                component = document.getComponent(spec.ComponentId);
                changes = spec.Changes; placements = spec.Placements; removedIds = spec.RemovedIds;
                original = component.Settings;
                remove = ismember([original.Id], removedIds);
                for setting = original(remove & string({original.Method}) == "assignment")
                    removedStatements(end + 1) = analysis.statementIndices(setting.SourceSpan); %#ok<AGROW>
                end
                settings = original(~remove);
                creationIndex = analysis.statementIndices(component.SourceSpans.Creation);
                creationVisit = find(execution.Trace.Order == creationIndex);
                assert(isscalar(creationVisit), "yamada:SourceLiteralTransaction:WiderProof", "Creation needs one owned execution visit.");
                [creationSpan, valid] = batch.mapSpan(component.SourceSpans.Creation); assert(valid);
                % Existing records retain identities; only their numeric positions and requested payloads change.
                fields = ["SourceSpan", "ValueSpan", "NameSpan", "PairSpan", "ScopeSpan"];
                for index = 1:numel(settings)
                    record = settings(index).toStruct();
                    for field = fields
                        [record.Location.(field), valid] = batch.mapSpan(record.Location.(field));
                        assert(valid, "yamada:SourceLiteralTransaction:WiderProof", "An edit crossed another owned token boundary.");
                    end
                    change = find(string({changes.Path}) == settings(index).Path, 1);
                    entry = component.getProperty(settings(index).Path);
                    if ~isempty(change) && ~isempty(entry) && isfield(entry.Metadata, "SourceSettingId") && ...
                            entry.Metadata.SourceSettingId == settings(index).Id
                        record.Value = changes(change).Value;
                    end
                    settings(index) = yamada.model.PropertySetting(record.Path, record.Value, record.Location);
                end
                constructorDelta(creationVisit) = constructorDelta(creationVisit) - nnz(remove & string({original.Method}) == "nameValue");
                sourceName = document.sourceComponentName(component.Id);
                for placement = placements
                    change = find(string({changes.Path}) == placement.Path, 1);
                    assert(isscalar(change)); value = changes(change).Value;
                    encoded = yamada.source.LiteralEncoder.encode(value);
                    location = struct("Method", placement.Method, "Syntax", "dot", ...
                        "SourceSnapshotId", source.StateId, "OwnerMethod", placement.OwnerMethod);
                    method = analysis.Layout.Methods(string({analysis.Layout.Methods.Name}) == placement.OwnerMethod);
                    assert(isscalar(method));
                    [location.ScopeSpan, valid] = batch.mapSpan(method.Span); assert(valid);
                    if placement.Method == "assignment"
                        prefix = "app." + sourceName + "." + placement.Path + " = ";
                        raw = prefix + encoded;
                        first = yamada.model.IndexedSettingEdit.insertedOffset(batch, raw + ";");
                        location.SourceSpan = yamada.model.SourceSpan(first, first + strlength(raw));
                        location.PairSpan = location.SourceSpan;
                        nameStart = first + strlength("app." + sourceName + ".");
                        location.NameSpan = yamada.model.SourceSpan(nameStart, nameStart + strlength(placement.Path) - 1);
                        location.ValueSpan = yamada.model.SourceSpan(first + strlength(prefix), first + strlength(raw) - 1);
                        addedOwners(end + 1) = sourceName; %#ok<AGROW>
                        additions(end + 1) = yamada.source.SourceStatement(raw, location.SourceSpan, first + (0:strlength(raw) - 1)); %#ok<AGROW>
                        [anchor, ~] = analysis.statementNeighbors(placement.Offset);
                        assert(isscalar(anchor), "yamada:SourceLiteralTransaction:WiderProof", "Insertion has no retained statement anchor.");
                        anchors(end + 1) = anchor; %#ok<AGROW>
                    else
                        constructor = original(string({original.Method}) == "nameValue");
                        assert(~isempty(constructor)); style = constructor(1);
                        location.Syntax = style.Syntax;
                        if style.Syntax == "nameEquals"
                            name = placement.Path; separator = "=";
                        else
                            quote = extractBetween(source.Text, style.NameSpan.StartOffset, style.NameSpan.StartOffset);
                            if quote == "'", name = yamada.source.LiteralEncoder.encode(char(placement.Path));
                            else, name = yamada.source.LiteralEncoder.encode(placement.Path); end
                            separator = ", ";
                        end
                        raw = name + separator + encoded;
                        first = yamada.model.IndexedSettingEdit.insertedOffset(batch, raw);
                        location.SourceSpan = creationSpan;
                        location.PairSpan = yamada.model.SourceSpan(first, first + strlength(raw) - 1);
                        location.NameSpan = yamada.model.SourceSpan(first, first + strlength(name) - 1);
                        location.ValueSpan = yamada.model.SourceSpan(first + strlength(name + separator), first + strlength(raw) - 1);
                        location.StatementId = style.StatementId;
                        location.InitializationScopeId = style.InitializationScopeId;
                        constructorDelta(creationVisit) = constructorDelta(creationVisit) + 1;
                    end
                    setting = yamada.model.PropertySetting(placement.Path, value, location);
                    settings(end + 1) = document.canonicalizeSettings(setting); %#ok<AGROW>
                end
                bindings(end + 1) = struct("ComponentId", component.Id, "Settings", settings, ...
                    "FactoryArguments", {component.CreationArguments}); %#ok<AGROW>
            end
            [analysis, execution] = analysis.withLiteralPatches(batch, additions, anchors, removedStatements, constructorDelta, execution, addedOwners);
            state = source.withBatch(batch, restoredStateId, analysis);
            for ownerIndex = 1:numel(bindings)
                component = document.getComponent(bindings(ownerIndex).ComponentId);
                original = component.Settings; settings = bindings(ownerIndex).Settings;
                % Project execution order numerically, retaining constructor argument order separately.
                starts = arrayfun(@(item) item.SourceSpan.StartOffset, settings);
                values = arrayfun(@(item) item.ValueSpan.StartOffset, settings);
                [~, order] = sortrows([starts(:) values(:)], [1 2]); settings = settings(order);
                constructor = string({settings.Method}) == "nameValue";
                oldConstructor = original([original.FactoryArgumentIndex] > 0);
                factoryArguments = component.CreationArguments;
                if ~isempty(oldConstructor), factoryArguments = factoryArguments(1:min([oldConstructor.FactoryArgumentIndex]) - 2); end
                ordinal = 0;
                for index = 1:numel(settings)
                    record = settings(index).toStruct();
                    statement = analysis.statementIndices(settings(index).SourceSpan);
                    visit = find(execution.Trace.Order == statement);
                    previous = find([original.Id] == settings(index).Id, 1);
                    if ~isempty(previous) && ~constructor(index) && isfield(execution, "SequenceMap")
                        record.Location.Sequence = execution.SequenceMap(original(previous).Sequence);
                        settings(index) = yamada.model.PropertySetting(record.Path, record.Value, record.Location);
                        continue
                    end
                    assert(isscalar(visit), "yamada:SourceLiteralTransaction:WiderProof", "A setting needs one owned execution visit.");
                    record.Location.IsCertain = execution.Trace.Certain(visit);
                    if constructor(index)
                        ordinal = ordinal + 1;
                        record.Location.Sequence = execution.Creation(visit) + ordinal;
                        isNew = ~any([original.Id] == settings(index).Id);
                        if settings(index).FactoryArgumentIndex > 0 || isNew
                            record.Location.FactoryArgumentIndex = numel(factoryArguments) + 2;
                            factoryArguments(end + 1:end + 2) = {record.Path, record.Value};
                        end
                    else
                        record.Location.Sequence = execution.Assignment(visit);
                    end
                    settings(index) = yamada.model.PropertySetting(record.Path, record.Value, record.Location);
                end
                [~, order] = sort([settings.Sequence]); settings = settings(order);
                bindings(ownerIndex).Settings = settings;
                bindings(ownerIndex).FactoryArguments = factoryArguments;
            end
        end
    end
    methods (Static, Access = private)
        function offset = insertedOffset(batch, text)
            % insertedOffset Locate editor-emitted syntax within its own patch, never in the application body.
            arguments (Input)
                batch (1, 1) yamada.source.SourcePatchBatch
                text (1, 1) string
            end
            arguments (Output)
                offset (1, 1) double
            end
            matches = zeros(1, 0); shift = 0;
            for edit = batch.Edits
                local = strfind(edit.Text, text);
                matches = [matches edit.Start + shift + local - 1]; %#ok<AGROW>
                shift = shift + strlength(edit.Text) - (edit.End - edit.Start + 1);
            end
            assert(isscalar(matches), "yamada:SourceLiteralTransaction:WiderProof", "Generated syntax needs an unambiguous patch-local location.");
            offset = matches;
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
