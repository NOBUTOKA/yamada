classdef SourceStrategyExperiment < handle
    % SourceStrategyExperiment Compare delayed patches with eager source-position updates.
    %   This isolated model/source prototype shares literal validation, model history,
    %   and saved-source verification between strategies. It does not replace editor code.

    properties (SetAccess = private)
        % Document - Independent editable document retaining ordinary model history.
        Document yamada.model.DocumentModel
        % Mode - Delayed patch accumulation or eager source and position maintenance.
        Mode string
        % Source - Baseline text in deferred mode or current text in eager mode.
        Source string
        % Locations - Complete experiment-owned index of source ranges and insertion anchors.
        Locations struct = struct("Key", {}, "Start", {}, "End", {})
        % Requests - Latest requested values used by independent output verification.
        Requests struct = struct("Name", {}, "Path", {}, "Value", {})
    end

    properties (Access = private)
        Registry yamada.model.ComponentRegistry
        Patches struct = struct("Key", {}, "Start", {}, "End", {}, "Text", {})
        Definitions containers.Map
        Emitted string = ""
    end

    methods
        function obj = SourceStrategyExperiment(source, mode, registry)
            % SourceStrategyExperiment Parse one common starting document and index its ranges.
            arguments (Input)
                source (1, 1) string
                mode (1, 1) string {mustBeMember(mode, ["deferred", "eager"])}
                registry (1, 1) yamada.model.ComponentRegistry
            end
            obj.Registry = registry;
            obj.Mode = mode;
            obj.Source = source;
            [obj.Document, diagnostics] = yamada.source.AppSourceParser.parseText(source, registry);
            assert(~yamada.validation.ModelValidator.hasErrors(diagnostics));
            parsed = obj.Document;
            obj.Document = yamada.model.DocumentModel(parsed.ClassName);
            obj.Document.Components = yamada.model.SubtreeSnapshot(parsed, parsed.RootComponentId).materialize();
            obj.Document.RootComponentId = parsed.RootComponentId;
            obj.Document.OriginalText = source;
            obj.Document.Metadata = parsed.Metadata;
            obj.Document.Diagnostics = parsed.Diagnostics;
            obj.Document.LineEnding = parsed.LineEnding;
            obj.Document.HistoryLimit = 200;
            obj.Definitions = containers.Map("KeyType", "char", "ValueType", "any");
            % Retain every model span, not only the ranges changed by the workload.
            snapshot = yamada.model.SubtreeSnapshot(obj.Document, obj.Document.RootComponentId);
            obj.collect(snapshot.Records, "records");
            analysis = obj.Document.sourceAnalysis();
            for index = 1:numel(analysis.Statements)
                obj.collect(analysis.Statements(index).Span, "statement:" + index);
            end
            for component = obj.Document.Components
                parent = obj.Document.getComponent(component.ParentId);
                factory = "";
                if ~isempty(parent), factory = parent.Factory; end
                obj.Definitions(char(component.Name)) = registry.getEffectiveProperties( ...
                    component.Factory, factory, component.CreationArguments);
                offsets = component.SourceSpans.Creation.EndOffset;
                settingIndex = 0;
                for setting = component.Settings
                    settingIndex = settingIndex + 1;
                    if ~isempty(setting.SourceSpan), offsets(end + 1) = setting.SourceSpan.EndOffset; end %#ok<AGROW>
                    if ~isempty(setting.ValueSpan)
                        obj.add("occurrence:" + component.Name + ":" + settingIndex, ...
                            setting.ValueSpan.StartOffset, setting.ValueSpan.EndOffset);
                        obj.add(component.Name + "." + setting.Path, ...
                            setting.ValueSpan.StartOffset, setting.ValueSpan.EndOffset);
                    end
                end
                % This prototype starts from straight-line project-owned fixtures.
                anchor = max(offsets);
                tail = extractAfter(source, anchor);
                lineEnd = regexp(char(tail), "[\r\n]", "once");
                if ~isempty(lineEnd), anchor = anchor + lineEnd - 1; end
                obj.add("anchor:" + component.Name, anchor, anchor);
            end
        end

        function attach(obj, document)
            % attach Bind the prototype to the real editor document after its ordinary Open flow.
            arguments (Input)
                obj (1, 1) SourceStrategyExperiment
                document (1, 1) yamada.model.DocumentModel
            end
            assert(document.OriginalText == obj.Source && document.HistoryIndex == 0);
            obj.Document = document;
            obj.Document.HistoryLimit = 200;
        end

        function edit(obj, name, path, value)
            % edit Validate a literal locally and commit one common atomic history operation.
            arguments (Input)
                obj (1, 1) SourceStrategyExperiment
                name (1, 1) string
                path (1, 1) string
                value
            end
            component = obj.Document.getComponentByName(name);
            assert(~isempty(component) && component.IsEditable);
            definitions = obj.Definitions(char(name));
            definition = definitions(string({definitions.Path}) == path);
            assert(isscalar(definition) && definition.IsEditable);
            % Start with the same local-proof policies as the existing fast replacement path.
            policy = definition.Application;
            independent = policy.EffectStatus == "independent" && policy.EffectPolicy == "none" && ...
                isempty(policy.ApplyAfter) && isempty(policy.AffectedPaths);
            numeric = policy.EffectStatus == "modeled" && policy.EffectPolicy == "numericValue" && ...
                isa(value, "double") && isscalar(value) && isreal(value) && isfinite(value);
            assert(independent || numeric, "Experiment requires a supported local-proof policy.");
            assert(isempty(component.Children) || ...
                ~(definition.AbsoluteGeometryImpact || definition.GridGeometryImpact == "required"), ...
                "Descendant geometry requires an additional proof outside this prototype.");
            encoded = yamada.source.LiteralEncoder.encode(value);
            [decoded, literal] = yamada.source.MatlabLiteralParser.parse(encoded);
            assert(literal && isequaln(decoded, value));
            assert(~contains(encoded, string(newline)) && ~contains(encoded, string(char(13))));
            states = yamada.model.PropertyStateResolver.resolve(component, definitions);
            transaction = yamada.model.PropertyStateResolver.transaction(states);
            transaction.stage(path, value);
            message = yamada.validation.PropertyBatchValidator.validate(definitions, transaction);
            assert(strlength(message) == 0, "%s", message);
            % Compute the patch before changing either model or source.
            key = name + "." + path;
            location = find(string({obj.Locations.Key}) == key, 1, "last");
            if isempty(location)
                anchor = obj.Locations(string({obj.Locations.Key}) == "anchor:" + name).End;
                prefix = string(sprintf("\r\n")) + "            app." + key + " = ";
                text = prefix + encoded + ";";
                patch = struct("Key", key, "Start", anchor + 1, "End", anchor, "Text", text);
                valueStart = anchor + strlength(prefix) + 1;
                valueEnd = valueStart + strlength(encoded) - 1;
            else
                span = obj.Locations(location);
                patch = struct("Key", key, "Start", span.Start, "End", span.End, "Text", encoded);
                valueStart = patch.Start;
                valueEnd = patch.Start + strlength(encoded) - 1;
            end
            hadSetting = ~isempty(component.getProperty(path));
            obj.Document.setProperty(component.Id, path, value);
            if ~hadSetting
                % Virtual occurrences support local semantic replay without pretending source was emitted.
                records = struct([]);
                for setting = component.Settings
                    if setting.Method == "generated", continue, end
                    item = setting.toStruct();
                    if isempty(records), records = item; else, records(end + 1) = item; end %#ok<AGROW>
                end
                component.restoreSettings(records);
                sequence = 1;
                if ~isempty(component.Settings), sequence = max([component.Settings.Sequence]) + 1; end
                setting = yamada.model.PropertySetting(path, value, struct("Method", "assignment", ...
                    "Syntax", "dot", "Sequence", sequence, "SourceSnapshotId", "experiment"));
                component.recordSetting(setting);
                replacement = component.getProperty(path).toStruct();
                replacement.Origin = "parsed";
                component.restoreProperty(replacement);
                history = obj.Document.History;
                history{end}.TargetSettingId = setting.Id;
                obj.Document.History = history;
            end
            obj.Emitted = "";
            if obj.Mode == "deferred"
                existing = find(string({obj.Patches.Key}) == key, 1);
                if isempty(existing), obj.Patches(end + 1) = patch; else, obj.Patches(existing).Text = patch.Text; end
            else
                obj.applyEager(patch);
                if isempty(location)
                    obj.add(key, valueStart, valueEnd);
                    obj.add("occurrence:" + name + ":" + numel(component.Settings), valueStart, valueEnd);
                    anchorIndex = find(string({obj.Locations.Key}) == "anchor:" + name, 1);
                    obj.Locations(anchorIndex).Start = patch.Start + strlength(patch.Text) - 1;
                    obj.Locations(anchorIndex).End = obj.Locations(anchorIndex).Start;
                end
            end
            request = struct("Name", name, "Path", path, "Value", {value});
            existing = find(string({obj.Requests.Name}) == name & string({obj.Requests.Path}) == path, 1);
            if isempty(existing), obj.Requests(end + 1) = request; else, obj.Requests(existing) = request; end
        end

        function source = emit(obj)
            % emit Materialize all delayed patches or return the already current eager source.
            arguments (Input)
                obj (1, 1) SourceStrategyExperiment
            end
            arguments (Output)
                source (1, 1) string
            end
            source = obj.Source;
            if obj.Mode == "eager", return, end
            if strlength(obj.Emitted) > 0, source = obj.Emitted; return, end
            edits = rmfield(obj.Patches, "Key");
            edits = yamada.source.CallbackSourceEdits.combineInsertions(edits);
            [~, order] = sort([edits.Start], "descend");
            for index = order
                edit = edits(index);
                source = extractBefore(source, edit.Start) + edit.Text + extractAfter(source, edit.End);
            end
            obj.Emitted = source;
        end

        function checkpoint = save(obj, path)
            % save Share full output validation and production UTF-8 writing between prototype strategies.
            arguments (Input)
                obj (1, 1) SourceStrategyExperiment
                path (1, 1) string
            end
            arguments (Output)
                checkpoint (1, 1) struct
            end
            source = obj.emit();
            source = yamada.source.SourceWriter.normalize(source, obj.Document.LineEnding);
            [saved, diagnostics] = yamada.source.AppSourceParser.parseText(source, obj.Registry, path);
            assert(~yamada.validation.ModelValidator.hasErrors(diagnostics));
            assert(numel(saved.Components) == numel(obj.Document.Components));
            for component = obj.Document.Components
                other = saved.getComponentByName(component.Name);
                assert(~isempty(other) && other.Factory == component.Factory);
                parent = obj.Document.getComponent(component.ParentId);
                savedParent = saved.getComponent(other.ParentId);
                assert(isempty(parent) == isempty(savedParent));
                if ~isempty(parent), assert(parent.Name == savedParent.Name); end
                definitions = obj.Definitions(char(component.Name));
                expected = yamada.model.PropertyStateResolver.resolve(component, definitions);
                actual = saved.getEffectivePropertyStates(obj.Registry, other.Id);
                for state = expected
                    if ~state.IsKnown, continue, end
                    match = actual(arrayfun(@(item) item.Definition.Path == state.Path, actual));
                    assert(isscalar(match) && match.Resolution.IsKnown && ...
                        isequaln(state.EffectiveValue, match.Resolution.EffectiveValue));
                end
            end
            for request = obj.Requests
                entry = saved.getComponentByName(request.Name).getProperty(request.Path);
                assert(~isempty(entry) && isequaln(entry.LiteralValue, request.Value));
            end
            snapshot = yamada.model.SubtreeSnapshot(saved, saved.RootComponentId);
            % Re-emission proves that the output still represents current edit intentions.
            assert(source == yamada.source.SourceWriter.normalize(obj.emit(), obj.Document.LineEnding));
            yamada.source.SourceWriter.write(path, source, obj.Document.LineEnding);
            obj.Document.markSaved();
            checkpoint = struct("SourceText", source, "Snapshot", snapshot);

        end
    end

    methods (Access = private)
        function add(obj, key, first, last)
            % add Append a canonical source range or insertion anchor to the experiment index.
            arguments (Input)
                obj (1, 1) SourceStrategyExperiment
                key (1, 1) string
                first (1, 1) double
                last (1, 1) double
            end
            obj.Locations(end + 1) = struct("Key", key, "Start", first, "End", last);
        end

        function collect(obj, value, key)
            % collect Retain every nested model span without sharing mutable model records.
            arguments (Input)
                obj (1, 1) SourceStrategyExperiment
                value
                key (1, 1) string
            end
            if isa(value, "yamada.model.SourceSpan")
                for index = 1:numel(value)
                    if value(index).isKnown(), obj.add(key + ":" + index, value(index).StartOffset, value(index).EndOffset); end
                end
            elseif isstruct(value)
                for index = 1:numel(value)
                    for field = reshape(string(fieldnames(value)), 1, [])
                        obj.collect(value(index).(field), key + ":" + index + ":" + field);
                    end
                end
            elseif iscell(value)
                for index = 1:numel(value), obj.collect(value{index}, key + ":" + index); end
            end
        end

        function applyEager(obj, patch)
            % applyEager Rewrite current text and shift every retained range before the next edit.
            arguments (Input)
                obj (1, 1) SourceStrategyExperiment
                patch (1, 1) struct
            end
            obj.Source = extractBefore(obj.Source, patch.Start) + patch.Text + extractAfter(obj.Source, patch.End);
            delta = strlength(patch.Text) - (patch.End - patch.Start + 1);
            % Update the complete numeric position index in bulk, avoiding per-record handle writes.
            spans = obj.Locations;
            starts = [spans.Start];
            ends = [spans.End];
            following = starts > patch.End;
            enclosing = ~following & ends >= patch.Start;
            starts(following) = starts(following) + delta;
            ends(following | enclosing) = ends(following | enclosing) + delta;
            values = num2cell(starts);
            [spans.Start] = values{:};
            values = num2cell(ends);
            [spans.End] = values{:};
            obj.Locations = spans;
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
