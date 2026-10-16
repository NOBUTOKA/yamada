classdef PropertyInsertionPlanner
    % PropertyInsertionPlanner Place new settings inside proven initialization intervals.
    %   The planner keeps existing settings fixed, preserves factory tokens, and
    %   validates owned candidate text without executing it. Opaque statements
    %   bound an interval rather than becoming an excuse to append at EOF.

    methods (Static)
        function result = needsPlan(document, component)
            % needsPlan Identify source additions owned by this planner rather than relocation.
            arguments (Input)
                document (1, 1) macd.model.DocumentModel
                component (1, 1) macd.model.ComponentRecord
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = component.Origin == "parsed" && ...
                any(arrayfun(@(entry) entry.Origin == "generated" && isempty(entry.SourceSpan) && ...
                entry.ValueKind == "literal" && ~isfield(entry.Metadata, "SubtreeReferenceId"), component.Properties)) && ...
                isscalar(document.OriginalText) && strlength(document.OriginalText) > 0;
            if ~result, return, end
            for pending = document.PendingEdits
                edit = pending{1};
                if isstruct(edit) && isfield(edit, "Kind") && edit.Kind == "reparent-subtree" && ...
                        any(string({edit.OriginalRecords.Id}) == component.Id)
                    result = false;
                    return
                end
            end
        end

        function plan = plan(document, component, registry)
            % plan Return insertions and an independently reparsed candidate component.
            arguments (Input)
                document (1, 1) macd.model.DocumentModel
                component (1, 1) macd.model.ComponentRecord
                registry (1, 1) macd.model.ComponentRegistry
            end
            arguments (Output)
                plan (1, 1) struct
            end
            plan = struct("Edits", struct("Start", {}, "End", {}, "Text", {}), ...
                "Placements", struct("Path", {}, "Method", {}, "Offset", {}, "OwnerMethod", {}), ...
                "Document", macd.model.DocumentModel.empty, "Component", macd.model.ComponentRecord.empty);
            entries = component.Properties([component.Properties.Origin] == "generated");
            entries = entries(arrayfun(@(entry) isempty(entry.SourceSpan) && entry.ValueKind == "literal" && ...
                ~isfield(entry.Metadata, "SubtreeReferenceId"), entries));
            if isempty(entries), return, end
            source = document.OriginalText;
            if isfield(document.Metadata, "SourceSnapshotText") && document.Metadata.SourceSnapshotText ~= source
                error("macd:PropertyInsertionPlanner:UnsafePlacement", "The source baseline changed without reparsing.");
            end
            if ~component.IsEditable || isempty(component.SourceSpans.Creation) || ~component.SourceSpans.Creation.isKnown()
                error("macd:PropertyInsertionPlanner:UnsafePlacement", "New settings require a proven component creation.");
            end
            parent = document.getComponent(component.ParentId);
            parentFactory = "";
            if ~isempty(parent), parentFactory = parent.Factory; end
            definitions = registry.getEffectiveProperties(component.Factory, parentFactory, component.CreationArguments);
            entries = macd.model.PropertyApplicationPlanner.order(entries, definitions);
            sourceSettings = component.Settings(string({component.Settings.Method}) ~= "generated");
            if any(ismember(string({entries.Path}), string({sourceSettings.Path})))
                error("macd:PropertyInsertionPlanner:UnsafePlacement", "A new setting would duplicate an existing source occurrence.");
            end

            % Acquire the same constructor-reachable trace used by the parser.
            statements = macd.source.MatlabLexicalScanner.splitStatements(source);
            creation = find(arrayfun(@(statement) statement.Span.StartOffset == ...
                component.SourceSpans.Creation.StartOffset, statements));
            if ~isscalar(creation)
                error("macd:PropertyInsertionPlanner:UnsafePlacement", "The factory statement is not uniquely owned.");
            end
            parsed = document.Components([document.Components.Origin] == "parsed");
            offsets = arrayfun(@(record) record.SourceSpans.Creation.StartOffset, parsed);
            [order, ~, certain, layout, returns] = ...
                macd.source.CallbackSourceAnalyzer.initializationStatements(statements, offsets);
            created = find(order == creation);
            if ~isscalar(created) || ~certain(created) || ~layout.Valid
                error("macd:PropertyInsertionPlanner:UnsafePlacement", "The factory is conditional, repeated, or outside a proven initializer.");
            end
            [anchors, boundary] = macd.source.PropertyInsertionPlanner.anchors( ...
                source, statements, order, certain, returns, layout, created, sourceSettings);
            paths = string({definitions.Path});
            if any(~ismember(string({entries.Path}), paths))
                error("macd:PropertyInsertionPlanner:UnsafePlacement", "A new property is not supported in this parent context.");
            end
            reaches = macd.source.PropertyInsertionPlanner.dependencies(definitions);
            base = macd.source.PropertyInsertionPlanner.replacements(document);
            constructor = sourceSettings(string({sourceSettings.Method}) == "nameValue");
            nvOnly = ~isempty(constructor) && numel(constructor) == numel(sourceSettings) && ...
                all([constructor.IsCertain]) && isscalar(unique(string({constructor.Syntax}))) && ...
                ~any(string({constructor.Path}) == "CreateFcn");
            nv = false(1, numel(entries));
            for index = 1:numel(entries)
                definition = definitions(paths == entries(index).Path);
                nv(index) = nvOnly && ~isempty(definition) && definition.Application.NameValue == "supported" && ...
                    ~contains(entries(index).Path, ".");
            end
            for index = 1:numel(entries)
                dependencies = reaches(:, paths == entries(index).Path);
                for earlier = 1:index - 1
                    if dependencies(paths == entries(earlier).Path) && ~nv(earlier), nv(index) = false; end
                end
            end
            name = document.sourceComponentName(component.Id);
            requested = macd.model.PropertyEntry.empty;
            for index = 1:numel(entries)
                entry = entries(index);
                requested(end + 1) = entry; %#ok<AGROW>
                accepted = false;
                failure = "No safe interval is available before an initialization boundary.";
                prerequisites = paths(reaches(:, paths == entry.Path));
                protectors = macd.source.PropertyInsertionPlanner.protectedWidths( ...
                    component, definitions(paths == entry.Path), entry.Path);
                for placement = plan.Placements
                    if any(prerequisites == placement.Path) && placement.Method == "assignment", nv(index) = false; end
                end

                % Prefer the existing constructor style only for verified arguments.
                if nv(index)
                    lower = 0;
                    prerequisites = paths(reaches(:, paths == entry.Path));
                    for argument = 1:numel(constructor)
                        if any(prerequisites == constructor(argument).Path) || ...
                                any(string({protectors.Id}) == constructor(argument).Id), lower = argument; end
                    end
                    for slot = lower:numel(constructor)
                        before = macd.model.PropertySetting.empty;
                        if slot < numel(constructor), before = constructor(slot + 1); end
                        edit = macd.source.FactoryCallEditor.insert(source, statements(creation), entry, constructor(1), before);
                        earlier = plan.Placements(ismember(string({plan.Placements.Path}), prerequisites));
                        if any([earlier.Offset] > edit.End), continue, end
                        [accepted, candidate, found, failure] = macd.source.PropertyInsertionPlanner.candidate( ...
                            source, [base plan.Edits edit], name, requested, registry);
                        if accepted
                            plan.Edits(end + 1) = edit;
                            plan.Placements(end + 1) = struct("Path", entry.Path, "Method", "nameValue", ...
                                "Offset", edit.End, "OwnerMethod", layout.Owner(creation));
                            plan.Document = candidate;
                            plan.Component = found;
                            break
                        end
                    end
                end
                if accepted, continue, end
                nv(index) = false;

                % Dependencies set the earliest visit; native-valid later slots remain candidates.
                prerequisites = paths(reaches(:, paths == entry.Path));
                lower = created;
                for setting = sourceSettings
                    if any(prerequisites == setting.Path) || any(string({protectors.Id}) == setting.Id)
                        visits = find(arrayfun(@(statement) statement.Span.StartOffset, statements(order)) == ...
                            setting.SourceSpan.StartOffset);
                        if ~isempty(visits), lower = max(lower, max(visits)); end
                    end
                end
                for placement = plan.Placements
                    if any(prerequisites == placement.Path) && placement.Method == "assignment"
                        match = find([anchors.Offset] == placement.Offset, 1);
                        if ~isempty(match), lower = max(lower, anchors(match).Visit); end
                    end
                end
                for anchor = anchors
                    if anchor.Visit < lower || anchor.Visit >= boundary, continue, end
                    text = macd.source.PropertyInsertionPlanner.assignment(source, document, name, entry, anchor);
                    edit = struct("Start", anchor.Offset + 1, "End", anchor.Offset, "Text", text);
                    [accepted, candidate, found, failure] = macd.source.PropertyInsertionPlanner.candidate( ...
                        source, [base plan.Edits edit], name, requested, registry);
                    if accepted
                        plan.Edits(end + 1) = edit;
                        plan.Placements(end + 1) = struct("Path", entry.Path, "Method", "assignment", ...
                            "Offset", anchor.Offset, "OwnerMethod", anchor.OwnerMethod);
                        plan.Document = candidate;
                        plan.Component = found;
                        break
                    end
                end
                if ~accepted
                    error("macd:PropertyInsertionPlanner:UnsafePlacement", ...
                        "Cannot add %s without moving existing settings or crossing an initialization boundary: %s", entry.Path, failure);
                end
            end
            plan.Edits = macd.source.CallbackSourceEdits.combineInsertions(plan.Edits);
        end
    end

    methods (Static, Access = private)
        function reaches = dependencies(definitions)
            % dependencies Project transitive canonical prerequisites independently of Inspector order.
            arguments (Input)
                definitions macd.model.PropertyDefinition
            end
            arguments (Output)
                reaches logical
            end
            macd.model.PropertyApplicationPolicy.orderDefinitions(definitions);
            paths = string({definitions.Path});
            count = numel(paths);
            reaches = false(count, count);
            for index = 1:count, reaches(ismember(paths, definitions(index).Application.ApplyAfter), index) = true; end
            for index = 1:count, reaches = reaches | (reaches(:, index) & reaches(index, :)); end
        end

        function settings = protectedWidths(component, definition, path)
            % protectedWidths Retain existing manual hold points before newly inserted upstream width writes.
            arguments (Input)
                component (1, 1) macd.model.ComponentRecord
                definition (1, 1) macd.model.PropertyDefinition
                path (1, 1) string
            end
            arguments (Output)
                settings macd.model.PropertySetting
            end
            settings = macd.model.PropertySetting.empty;
            if definition.Application.EffectPolicy ~= "axisWidth", return, end
            modes = strings(1, 0);
            if path == "LineWidth", modes = ["GridLineWidthMode", "MinorGridLineWidthMode"]; end
            if path == "GridLineWidth", modes = "MinorGridLineWidthMode"; end
            for setting = component.Settings
                if ~any(modes == setting.Path) || setting.Method == "generated" || ...
                        ~setting.IsCertain || setting.ValueKind ~= "literal", continue, end
                value = setting.LiteralValue;
                entry = component.getProperty(setting.Path);
                if ~isempty(entry) && entry.ValueKind == "literal" && isfield(entry.Metadata, "SourceSettingId") && ...
                        string(entry.Metadata.SourceSettingId) == setting.Id
                    value = entry.LiteralValue;
                end
                if ((ischar(value) && isrow(value)) || (isstring(value) && isscalar(value))) && string(value) == "manual"
                    settings(end + 1) = setting; %#ok<AGROW>
                end
            end
        end

        function [anchors, boundary] = anchors(source, statements, order, certain, returns, layout, created, settings)
            % anchors Bound proven source slots by the first opaque operation or observable read.
            arguments (Input)
                source (1, 1) string
                statements macd.source.SourceStatement
                order double
                certain logical
                returns double
                layout (1, 1) struct
                created (1, 1) double
                settings macd.model.PropertySetting
            end
            arguments (Output)
                anchors (1, :) struct
                boundary (1, 1) double
            end
            anchors = struct("Offset", {}, "Visit", {}, "OwnerMethod", {}, "Indent", {});
            boundary = numel(order) + 1;
            for visit = created:numel(order)
                index = order(visit);
                statement = statements(index);
                code = char(strtrim(statement.Text));
                structural = ~isempty(regexp(code, '^(end|arguments|function|return)(?!\w)', 'once'));
                call = returns(visit) > visit;
                owned = settings(arrayfun(@(setting) ~isempty(setting.SourceSpan) && ...
                    setting.SourceSpan.StartOffset == statement.Span.StartOffset, settings));
                write = ~isempty(owned) && all([owned.IsCertain]) && all(string({owned.ValueKind}) == "literal");
                if visit > created && ~structural && ~call && ~write
                    % Literal local assignments cannot call or observe a component.
                    local = regexp(code, '^[A-Za-z]\w*\s*=\s*(.*)$', 'tokens', 'once');
                    safe = false;
                    if ~isempty(local), [~, safe] = macd.source.MatlabLiteralParser.parse(string(local{1})); end
                    if ~safe, boundary = visit; break, end
                end
                if ~structural && certain(visit) && nnz(order == index) == 1 && layout.StraightLine(index)
                    offset = statement.Span.EndOffset;
                    tail = extractAfter(source, offset);
                    lineEnd = regexp(char(tail), '\r?\n', 'start', 'once');
                    if isempty(lineEnd), lineEnd = strlength(tail) + 1; end
                    suffix = extractBefore(tail, lineEnd);
                    if ~isempty(regexp(suffix, '^\s*(%[^\r\n]*)?$', 'once')), offset = offset + strlength(suffix); end
                    before = extractBefore(source, statement.Span.StartOffset);
                    starts = regexp(char(before), '\n', 'end');
                    start = 0;
                    if ~isempty(starts), start = starts(end); end
                    indent = string(regexp(char(extractBetween(source, start + 1, statement.Span.StartOffset - 1)), '^\s*', 'match', 'once'));
                    anchors(end + 1) = struct("Offset", offset, "Visit", returns(visit), ...
                        "OwnerMethod", layout.Owner(index), "Indent", indent); %#ok<AGROW>
                end
            end
            [~, sorted] = sort([anchors.Visit]);
            anchors = anchors(sorted);
        end

        function text = assignment(~, document, name, entry, anchor)
            % assignment Emit one literal statement after a source-preserving trailing-trivia anchor.
            arguments (Input)
                ~
                document (1, 1) macd.model.DocumentModel
                name (1, 1) string
                entry (1, 1) macd.model.PropertyEntry
                anchor (1, 1) struct
            end
            arguments (Output)
                text (1, 1) string
            end
            ending = string(newline);
            if document.LineEnding == "CRLF", ending = string(sprintf("\r\n")); end
            text = ending + anchor.Indent + "app." + name + "." + entry.Path + " = " + ...
                macd.source.LiteralEncoder.encode(entry.LiteralValue) + ";";
        end

        function edits = replacements(document)
            % replacements Overlay existing value-token requests without touching unrelated source.
            arguments (Input)
                document (1, 1) macd.model.DocumentModel
            end
            arguments (Output)
                edits struct
            end
            edits = struct("Start", {}, "End", {}, "Text", {});
            for component = document.Components
                for entry = component.Properties
                    if entry.ValueKind ~= "literal" || ~isfield(entry.Metadata, "SourceSettingId"), continue, end
                    settings = component.getSettings(entry.Path);
                    original = settings(string({settings.Id}) == string(entry.Metadata.SourceSettingId));
                    if isempty(original) || isequaln(original(end).LiteralValue, entry.LiteralValue), continue, end
                    span = original(end).ValueSpan;
                    if ~isempty(span) && span.isKnown()
                        edits(end + 1) = struct("Start", span.StartOffset, "End", span.EndOffset, ...
                            "Text", macd.source.LiteralEncoder.encode(entry.LiteralValue)); %#ok<AGROW>
                    end
                end
            end
            if ~isempty(edits)
                [~, uniqueEdits] = unique([[edits.Start]' [edits.End]'], 'rows', 'stable');
                edits = edits(uniqueEdits);
            end
        end

        function [accepted, document, component, reason] = candidate(source, edits, name, requested, registry)
            % candidate Reparse an owned candidate and check intermediate and requested final states.
            arguments (Input)
                source (1, 1) string
                edits struct
                name (1, 1) string
                requested macd.model.PropertyEntry
                registry (1, 1) macd.model.ComponentRegistry
            end
            arguments (Output)
                accepted (1, 1) logical
                document macd.model.DocumentModel
                component macd.model.ComponentRecord
                reason (1, 1) string
            end
            accepted = false;
            component = macd.model.ComponentRecord.empty;
            edits = macd.source.CallbackSourceEdits.combineInsertions(edits);
            [~, order] = sort([edits.Start], 'descend');
            for index = order
                edit = edits(index);
                source = extractBefore(source, edit.Start) + edit.Text + extractAfter(source, edit.End);
            end
            [document, diagnostics] = macd.source.AppSourceParser.parseText(source, registry);
            reason = strjoin(string({diagnostics(string({diagnostics.Severity}) == "error").Message}), newline);
            if macd.validation.ModelValidator.hasErrors(diagnostics), return, end
            component = document.getComponentByName(name);
            if isempty(component), reason = "The original component was not retained."; return, end
            states = document.getEffectivePropertyStates(registry, component.Id);
            for entry = requested
                match = find(arrayfun(@(state) state.Definition.Path == entry.Path, states), 1);
                if isempty(match) || ~macd.model.PropertyStateResolver.matchesRequested(states(match).Resolution, entry.LiteralValue)
                    reason = "The requested " + entry.Path + " does not survive initialization.";
                    return
                end
            end
            accepted = true;
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
