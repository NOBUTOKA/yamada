classdef SubtreeReparentSourceEdits
    % SubtreeReparentSourceEdits Relocate proven initialization statements for moved subtrees.
    %   Existing callback methods remain untouched. Only direct createComponents
    %   statements with known ownership can be relocated.

    methods (Static)
        function [edits, movedIds, candidate] = build(document, registry)
            % build Generate subtree relocation edits against the original source snapshot.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                registry (1, 1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                edits struct
                movedIds string
                candidate yamada.model.DocumentModel
            end

            context = document.evaluationContext(registry);
            key = "relocation";
            [data, found] = context.lookup(key);
            if found
                [configuration, found] = context.configuration(key, ...
                    document.sourceComponentName(document.RootComponentId));
                if found
                    edits = data.Edits;
                    movedIds = data.MovedIds;
                    candidate = configuration.Document;
                    return
                end
            end
            edits = struct("Start", {}, "End", {}, "Text", {});
            movedIds = strings(1, 0);
            candidate = yamada.model.DocumentModel.empty;
            originals = struct([]);
            for index = 1:numel(document.PendingEdits)
                pending = document.PendingEdits{index};
                if ~isstruct(pending) || ~isfield(pending, "Kind") || pending.Kind ~= "reparent-subtree", continue, end
                for record = pending.OriginalRecords
                    if ~yamada.model.SourceOwnership.hasSource(record) || isempty(document.getComponent(record.Id)), continue, end
                    if ~any(movedIds == record.Id)
                        movedIds(end + 1) = record.Id; %#ok<AGROW>
                        if isempty(originals), originals = record; else, originals(end + 1) = record; end %#ok<AGROW>
                    end
                end
            end
            if isempty(movedIds), return, end
            source = document.CurrentText;
            analysis = document.sourceAnalysis();
            statements = analysis.Statements;
            [direct, methodSpan] = analysis.directInitializationScope();
            parsed = document.Components(arrayfun(@yamada.model.SourceOwnership.hasSource, document.Components));
            offsets = arrayfun(@(item) item.SourceSpans.Creation.StartOffset, parsed);
            initialization = analysis.initialization(offsets);
            order = initialization.Order;
            certain = initialization.Certain;
            spans = yamada.model.SourceSpan.empty;
            names = strings(1, 0);
            for record = originals
                own = record.SourceSpans.Creation;
                for property = record.Properties
                    if ~isempty(property.SourceSpan), own = [own property.SourceSpan]; end %#ok<AGROW>
                end
                for setting = record.Settings
                    if ~isempty(setting.Location.SourceSpan), own = [own setting.Location.SourceSpan]; end %#ok<AGROW>
                end
                [~, uniqueSpans] = unique([[own.StartOffset]' [own.EndOffset]'], 'rows', 'stable');
                own = own(uniqueSpans);
                for span = own
                    matches = find(arrayfun(@(statement) statement.Span.StartOffset == span.StartOffset && ...
                        statement.Span.EndOffset == span.EndOffset, statements));
                    visits = find(ismember(order, matches));
                    if ~span.isKnown() || numel(matches) ~= 1 || ~direct(matches) || ...
                            ~isscalar(visits) || ~certain(visits)
                        error("yamada:SubtreeReparentSourceEdits:UnsafeSource", "Initialization ownership is not a unique direct createComponents statement.");
                    end
                end
                for span = own
                    spans(end + 1) = yamada.source.SubtreeReparentSourceEdits.withTrailingComment(source, span); %#ok<AGROW>
                end
                creation = extractBetween(source, record.SourceSpans.Creation.StartOffset, record.SourceSpans.Creation.EndOffset);
                token = regexp(creation, '^app\.(\w+)\s*=', 'tokens', 'once');
                if isempty(token), error("yamada:SubtreeReparentSourceEdits:UnsafeSource", "Creation identity is unknown."); end
                names(end + 1) = string(token{1}); %#ok<AGROW>
            end
            [~, uniqueSpans] = unique([[spans.StartOffset]' [spans.EndOffset]'], 'rows', 'stable');
            spans = spans(uniqueSpans);

            % Insert after owned initialization, with all destination parents already created.
            anchor = 0;
            rootName = document.sourceComponentName(document.RootComponentId);
            ownedIndices = zeros(1, 0);
            for statementIndex = find(direct)
                statement = statements(statementIndex);
                text = char(statement.Text);
                if ~isempty(regexp(text, '^app\.\w+\s*=\s*\w+\s*\(|^app\.\w+\.\w+(?:\.\w+)*\s*=', 'once'))
                    ownedIndices(end + 1) = statementIndex; %#ok<AGROW>
                end
            end
            if ~isempty(ownedIndices) && ~isempty(regexp(statements(ownedIndices(end)).Text, ...
                    '^app\.' + rootName + '\.Visible\s*=', 'once'))
                ownedIndices(end) = [];
            end
            if ~isempty(ownedIndices), anchor = max(arrayfun(@(item) item.Span.EndOffset, statements(ownedIndices))); end
            if anchor == 0, error("yamada:SubtreeReparentSourceEdits:UnsafeSource", "Initialization insertion anchor is unavailable."); end
            anchor = yamada.source.SubtreeReparentSourceEdits.withTrailingComment(source, yamada.model.SourceSpan(anchor, anchor)).EndOffset;
            code = yamada.source.SubtreeSourceEdits.codeMask(source);
            if ~isempty(regexp(code, 'app\s*\.\s*\(|\w+\s*=\s*app\s*(?:;|\n)|(?:subsref|subsasgn|eval|feval)\s*\(', 'once'))
                error("yamada:SubtreeReparentSourceEdits:UnsafeSource", "Dynamic or aliased references prevent proving relocation safety.");
            end
            for name = names
                positions = regexp(code, '(?<!\w)app\s*\.\s*' + name + '(?!\w)', 'start');
                for position = positions
                    owned = any([spans.StartOffset] <= position & [spans.EndOffset] >= position);
                    if ~owned && position >= methodSpan.StartOffset && position <= anchor
                        error("yamada:SubtreeReparentSourceEdits:UnsafeSource", "Initialization outside the moved subtree depends on its original order.");
                    end
                end
            end
            pendingCallbacks = document.CallbackEdits;
            if any(ismember(string({pendingCallbacks.ComponentId}), movedIds))
                error("yamada:SubtreeReparentSourceEdits:UnsafeSource", "Pending callback edits require a combined relocation plan.");
            end
            ending = string(newline);
            if document.LineEnding == "CRLF", ending = string(sprintf("\r\n")); end
            block = "";
            deferredParsedReferences = strings(1, 0);
            events = struct("Id", {}, "ParentId", {}, "Creates", {}, "SourceOrder", {}, "Placement", {}, "Text", {});

            % Preserve original interleaving subject to the destination creation dependencies.
            for component = document.Components
                if ~yamada.model.SourceOwnership.hasSource(component)
                    text = yamada.source.SubtreeReparentSourceEdits.generatedInitialization(document, component, registry, ending);
                    events(end + 1) = struct("Id", component.Id, "ParentId", component.ParentId, ...
                        "Creates", true, "SourceOrder", Inf, "Placement", false, "Text", text); %#ok<AGROW>
                    continue
                end
                if ~any(movedIds == component.Id), continue, end
                record = originals(string({originals.Id}) == component.Id);
                parent = document.getComponent(component.ParentId);
                if isempty(parent)
                    error("yamada:SubtreeReparentSourceEdits:UnsafeSource", "Destination parent no longer exists.");
                end
                [creation, assignments, deferred, positions, placement] = yamada.source.SubtreeReparentSourceEdits.parsedInitialization( ...
                    source, statements, record, component, names, document, registry);
                pattern = '^(app\.\w+\s*=\s*\w+\s*\(\s*)app\.\w+';
                if isempty(regexp(creation, pattern, 'once'))
                    error("yamada:SubtreeReparentSourceEdits:UnsafeSource", "The creation parent is not a static component reference.");
                end
                parentName = parent.Name;
                if yamada.model.SourceOwnership.hasSource(parent)
                    parentCreation = extractBetween(source, parent.SourceSpans.Creation.StartOffset, parent.SourceSpans.Creation.EndOffset);
                    token = regexp(parentCreation, '^app\.(\w+)\s*=', 'tokens', 'once');
                    parentName = string(token{1});
                end
                creation = regexprep(creation, pattern, "$1app." + parentName, 'once');
                events(end + 1) = struct("Id", component.Id, "ParentId", component.ParentId, ...
                    "Creates", true, "SourceOrder", record.SourceSpans.Creation.StartOffset, "Placement", false, ...
                    "Text", ending + "            " + creation); %#ok<AGROW>
                for index = 1:numel(assignments)
                    events(end + 1) = struct("Id", component.Id, "ParentId", component.ParentId, ...
                        "Creates", false, "SourceOrder", positions(index), "Placement", placement(index), ...
                        "Text", ending + "            " + assignments(index)); %#ok<AGROW>
                end
                deferredParsedReferences = [deferredParsedReferences deferred]; %#ok<AGROW>
            end
            for event = yamada.source.SubtreeReparentSourceEdits.orderEvents(events), block = block + event.Text; end
            generated = document.Components(~arrayfun(@yamada.model.SourceOwnership.hasSource, document.Components));
            references = yamada.model.SubtreeReferencePolicy.assignments(document, generated, registry);
            for reference = [deferredParsedReferences references], block = block + ending + "            " + reference; end
            for span = spans
                edits(end + 1) = struct("Start", span.StartOffset, "End", span.EndOffset, "Text", ""); %#ok<AGROW>
            end
            edits = yamada.source.SourceFormatting.cleanDeletions(source, edits);
            [block, candidate] = yamada.source.SubtreeReparentSourceEdits.placePending( ...
                document, registry, edits, anchor, block, movedIds);
            edits(end + 1) = struct("Start", anchor + 1, "End", anchor, "Text", block);
            context.rememberConfiguration(key, candidate);
            context.remember(key, struct("Edits", edits, "MovedIds", movedIds));
        end

        function result = contains(document, componentId)
            % contains Test whether parsed initialization belongs to a pending relocation.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                componentId (1, 1) string
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = false;
            for pending = document.PendingEdits
                edit = pending{1};
                if isstruct(edit) && isfield(edit, "Kind") && edit.Kind == "reparent-subtree" && ...
                        any(string({edit.OriginalRecords.Id}) == componentId)
                    result = true;
                    return
                end
            end
        end

        function text = generatedInitialization(document, component, registry, ending)
            % generatedInitialization Emit new nodes in the same ordering plan as relocated parsed nodes.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                component (1, 1) yamada.model.ComponentRecord
                registry (1, 1) yamada.model.ComponentRegistry
                ending (1, 1) string
            end
            arguments (Output)
                text (1, 1) string
            end
            parent = document.getComponent(component.ParentId);
            if isempty(parent)
                error("yamada:SubtreeReparentSourceEdits:UnsafeSource", "Generated initialization has no parent.");
            end
            argumentsText = "app." + parent.Name;
            for index = 1:numel(component.CreationArguments)
                argumentsText = argumentsText + ", " + yamada.source.LiteralEncoder.encode(component.CreationArguments{index});
            end
            text = ending + "            app." + component.Name + " = " + component.Factory + "(" + argumentsText + ");";
            pending = document.CallbackEdits(string({document.CallbackEdits.ComponentId}) == component.Id);
            for callback = pending(:)'
                if callback.Action == "Add"
                    text = text + ending + "            " + yamada.source.CallbackSourceEdits.bindingText(component.Name, callback.Name, callback.HandlerName);
                end
            end
            entries = yamada.model.PropertyApplicationPlanner.forComponent(component, document, registry);
            for entry = entries
                if registry.isReadOnlyProperty(component.Factory, entry.Path, component.CreationArguments), continue, end
                if isfield(entry.Metadata, "SubtreeReferenceId"), continue, end
                if entry.ValueKind ~= "literal"
                    error("yamada:SubtreeReparentSourceEdits:UnsafeSource", "Generated properties require a literal representation.");
                end
                text = text + ending + "            app." + component.Name + "." + entry.Path + ...
                    " = " + yamada.source.LiteralEncoder.encode(entry.LiteralValue) + ";";
            end
        end

        function [direct, methodSpan] = directScope(statements)
            % directScope Recognize direct initialization scope with explicit block nesting.
            arguments (Input)
                statements yamada.source.SourceStatement
            end
            arguments (Output)
                direct logical
                methodSpan (1, 1) yamada.model.SourceSpan
            end
            direct = false(1, numel(statements));
            methodSpan = yamada.model.SourceSpan();
            stack = strings(1, 0);
            createDepth = 0;
            start = 0;
            count = 0;
            for index = 1:numel(statements)
                text = char(strtrim(statements(index).Text));
                token = regexp(text, '^([A-Za-z]\w*)(?!\w)', 'tokens', 'once');
                if isempty(token), continue, end
                keyword = string(token{1});
                if strcmp(text, 'end')
                    if isempty(stack), error("yamada:SubtreeReparentSourceEdits:UnsafeSource", "Source block nesting is ambiguous."); end
                    if createDepth > 0 && numel(stack) == createDepth
                        methodSpan = yamada.model.SourceSpan(start, statements(index).Span.EndOffset);
                        createDepth = 0;
                    end
                    stack(end) = [];
                    continue
                end
                direct(index) = createDepth > 0 && numel(stack) == createDepth;
                if any(keyword == ["methods", "properties", "events", "enumeration"]) && ...
                        ~(isscalar(stack) && stack(1) == "classdef"), continue, end
                if any(keyword == ["classdef", "methods", "properties", "events", "enumeration", ...
                        "function", "arguments", "if", "for", "parfor", "while", "switch", "try", "spmd"])
                    stack(end + 1) = keyword; %#ok<AGROW>
                    if keyword == "methods" && ~isempty(regexp(text, '(?<!\w)(Static|Abstract|External)(?!\w)', 'once'))
                        stack(end) = "noninstance-methods";
                    end
                    if keyword == "function" && ~isempty(regexp(text, '^function\s+createComponents\s*\(app\)', 'once'))
                        if numel(stack) ~= 3 || stack(2) ~= "methods"
                            error("yamada:SubtreeReparentSourceEdits:UnsafeSource", "Initialization must be an instance method.");
                        end
                        count = count + 1;
                        createDepth = numel(stack);
                        start = statements(index).Span.StartOffset;
                    end
                end
            end
            if ~isempty(stack) || count ~= 1 || ~methodSpan.isKnown()
                error("yamada:SubtreeReparentSourceEdits:UnsafeSource", "Unique initialization method ownership cannot be proven.");
            end
        end
    end

    methods (Static, Access = private)
        function [creation, assignments, deferred, positions, placement] = parsedInitialization(source, statements, record, component, names, document, registry)
            % parsedInitialization Preserve every owned occurrence and update only its bound value token.
            arguments (Input)
                source (1, 1) string
                statements yamada.source.SourceStatement
                record (1, 1) struct
                component (1, 1) yamada.model.ComponentRecord
                names string
                document (1, 1) yamada.model.DocumentModel
                registry (1, 1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                creation (1, 1) string
                assignments (1, :) string
                deferred (1, :) string
                positions (1, :) double
                placement (1, :) logical
            end
            patches = struct("Start", {}, "End", {}, "Text", {});
            removed = yamada.model.PropertySetting.empty;
            assignments = strings(1, 0);
            deferred = strings(1, 0);
            positions = zeros(1, 0); placement = false(1, 0);
            placementPaths = strings(1, 0);
            if record.ParentId ~= component.ParentId, placementPaths = ["Position", "Layout.Row", "Layout.Column"]; end
            terminal = struct("Path", {}, "Text", {});
            settings = component.Settings(string({component.Settings.Method}) ~= "generated");
            [~, order] = sort([settings.Sequence]);
            settings = settings(order);
            % Source settings remain immutable; current entries carry replacement requests.
            for setting = settings
                entry = component.getProperty(setting.Path);
                if isempty(entry)
                    if setting.Method == "nameValue", removed(end + 1) = setting; end %#ok<AGROW>
                    continue
                end
                if ~setting.IsCertain
                    error("yamada:SubtreeReparentSourceEdits:UnsafeSource", "An uncertain occurrence cannot be relocated.");
                end
                if entry.ValueKind == "literal" && isfield(entry.Metadata, "SourceSettingId") && ...
                        string(entry.Metadata.SourceSettingId) == string(setting.Id) && ~isequaln(entry.LiteralValue, setting.LiteralValue)
                    span = setting.ValueSpan;
                    if isempty(span) || ~span.isKnown()
                        error("yamada:SubtreeReparentSourceEdits:UnsafeSource", "A replacement has no proven value token.");
                    end
                    patches(end + 1) = struct("Start", span.StartOffset, "End", span.EndOffset, ...
                        "Text", yamada.source.LiteralEncoder.encode(entry.LiteralValue)); %#ok<AGROW>
                end
                if any(placementPaths == setting.Path) && setting.Method == "assignment" && ...
                        isfield(entry.Metadata, "SourceSettingId") && entry.Metadata.SourceSettingId == setting.Id
                    span = yamada.source.SubtreeReparentSourceEdits.withTrailingComment(source, setting.SourceSpan);
                    terminal(end + 1) = struct("Path", setting.Path, ...
                        "Text", yamada.source.SubtreeReparentSourceEdits.applyRange(source, span, patches)); %#ok<AGROW>
                    continue
                end
                if setting.Method ~= "assignment", continue, end
                span = yamada.source.SubtreeReparentSourceEdits.withTrailingComment(source, setting.SourceSpan);
                assignment = yamada.source.SubtreeReparentSourceEdits.applyRange(source, span, patches);
                if setting.ValueKind == "expression"
                    if any(setting.Path == ["SelectedTab", "ContextMenu"])
                        yamada.model.SubtreeReferencePolicy.resolve(document, component, setting.Path, setting.SourceExpression, registry);
                        deferred(end + 1) = assignment; %#ok<AGROW>
                        continue
                    end
                    references = regexp(yamada.source.SubtreeSourceEdits.codeMask(setting.SourceExpression), ...
                        '(?<!\w)app\s*\.\s*([A-Za-z]\w*)', 'tokens');
                    for reference = references
                        if any(names == string(reference{1}{1}))
                            error("yamada:SubtreeReparentSourceEdits:UnsafeSource", ...
                                "An unsupported internal component reference prevents safe relocation.");
                        end
                    end
                end
                assignments(end + 1) = assignment; %#ok<AGROW>
                positions(end + 1) = setting.SourceSpan.StartOffset; placement(end + 1) = false; %#ok<AGROW>
            end
            % Final placement writes follow this owner's retained settings and precede child creation.
            last = record.SourceSpans.Creation.EndOffset;
            if ~isempty(positions), last = max([last positions]); end
            for path = placementPaths
                entry = component.getProperty(path); if isempty(entry), continue, end
                existing = find(string({terminal.Path}) == path, 1);
                text = "app." + component.Name + "." + path + " = " + yamada.source.LiteralEncoder.encode(entry.LiteralValue) + ";";
                if ~isempty(existing), text = terminal(existing).Text; end
                assignments(end + 1) = text; positions(end + 1) = last + 1; placement(end + 1) = true; %#ok<AGROW>
                last = last + 1;
            end
            statement = statements(arrayfun(@(item) item.Span.StartOffset == record.SourceSpans.Creation.StartOffset, statements));
            patches = [patches yamada.source.FactoryCallEditor.remove(statement, removed)];
            span = yamada.source.SubtreeReparentSourceEdits.withTrailingComment(source, record.SourceSpans.Creation);
            creation = yamada.source.SubtreeReparentSourceEdits.applyRange(source, span, patches);
        end

        function span = withTrailingComment(source, span)
            % withTrailingComment Keep a same-line comment attached to its relocated statement.
            arguments (Input)
                source (1, 1) string
                span (1, 1) yamada.model.SourceSpan
            end
            arguments (Output)
                span (1, 1) yamada.model.SourceSpan
            end
            tail = extractAfter(source, span.EndOffset);
            stop = regexp(char(tail), '\r?\n', 'start', 'once');
            if isempty(stop), stop = strlength(tail) + 1; end
            suffix = extractBefore(tail, stop);
            if ~isempty(regexp(suffix, '^[ \t]*%[^\r\n]*$', 'once'))
                span = yamada.model.SourceSpan(span.StartOffset, span.EndOffset + strlength(suffix));
            end
        end

        function events = orderEvents(events)
            % orderEvents Keep source order while ensuring each owner and parent exists before use.
            arguments (Input)
                events (1, :) struct
            end
            arguments (Output)
                events (1, :) struct
            end
            ids = string({events.Id});
            creates = [events.Creates];
            edges = false(numel(events), numel(events));
            for index = 1:numel(events)
                owner = ids == events(index).Id;
                if events(index).Creates
                    edges(creates & ids == events(index).ParentId, index) = true;
                    edges([events.Placement] & ids == events(index).ParentId, index) = true;
                else
                    edges(owner & (creates | [events.SourceOrder] < events(index).SourceOrder), index) = true;
                end
            end
            remaining = true(1, numel(events));
            order = zeros(1, numel(events));
            for index = 1:numel(events)
                ready = find(remaining & ~any(edges, 1));
                if isempty(ready)
                    error("yamada:SubtreeReparentSourceEdits:UnsafeSource", "Relocated creation dependencies contain a cycle.");
                end
                [~, first] = min([events(ready).SourceOrder]);
                selected = ready(first);
                order(index) = selected;
                remaining(selected) = false;
                edges(selected, :) = false;
            end
            events = events(order);
        end

        function [block, candidate] = placePending(document, registry, removals, anchor, block, movedIds)
            % placePending Use the shared insertion planner inside the independently relocated source block.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                registry (1, 1) yamada.model.ComponentRegistry
                removals struct
                anchor (1, 1) double
                block (1, 1) string
                movedIds string
            end
            arguments (Output)
                block (1, 1) string
                candidate (1, 1) yamada.model.DocumentModel
            end
            prefix = yamada.source.SubtreeReparentSourceEdits.applyRange( ...
                document.CurrentText, yamada.model.SourceSpan(1, anchor), removals);
            suffix = extractAfter(document.CurrentText, anchor);
            source = prefix + block + suffix;
            patches = [removals struct("Start", anchor + 1, "End", anchor, "Text", block)];
            [candidate, ~] = document.editedSourceCandidate(source, patches, registry);
            hasPending = false;
            % All candidates share one source version; only their owned insertions are combined.
            for id = movedIds
                original = document.getComponent(id);
                configured = candidate.getComponentByName(document.sourceComponentName(id));
                pending = original.Properties(arrayfun(@(entry) isempty(entry.SourceSpan), original.Properties));
                records = document.PendingEdits;
                for request = records
                    if isstruct(request{1}) && isfield(request{1}, "Kind") && request{1}.Kind == "reparent-subtree"
                        previous = request{1}.OriginalRecords;
                        old = previous(string({previous.Id}) == id);
                        if isscalar(old) && old.ParentId ~= original.ParentId
                            pending = pending(~ismember(string({pending.Path}), ["Position", "Layout.Row", "Layout.Column"]));
                        end
                    end
                end
                pending = pending(arrayfun(@(entry) isempty(entry.SourceSpan) && entry.ValueKind == "literal" && ...
                    ~isfield(entry.Metadata, "SubtreeReferenceId"), pending));
                if isempty(pending), continue, end
                hasPending = true;
                changes = struct("Path", {}, "Value", {});
                for entry = pending, changes(end + 1) = struct("Path", entry.Path, "Value", {entry.LiteralValue}); end %#ok<AGROW>
                candidate.setPropertyBatch(configured.Id, changes, registry);
            end
            first = strlength(prefix) + 1;
            last = strlength(candidate.CurrentText) - strlength(suffix);
            if hasPending, block = extractBetween(candidate.CurrentText, first, last); end
            diagnostics = candidate.Diagnostics;
            if yamada.validation.ModelValidator.hasErrors(diagnostics)
                error("yamada:SubtreeReparentSourceEdits:UnsafeSource", "%s", strjoin(string({diagnostics.Message}), newline));
            end
        end

        function text = applyRange(source, span, edits)
            % applyRange Apply token edits contained in an original source interval.
            arguments (Input)
                source (1, 1) string
                span (1, 1) yamada.model.SourceSpan
                edits struct
            end
            arguments (Output)
                text (1, 1) string
            end
            text = extractBetween(source, span.StartOffset, span.EndOffset);
            edits = edits([edits.Start] >= span.StartOffset & [edits.End] <= span.EndOffset);
            [~, order] = sort([edits.Start], 'descend');
            for edit = edits(order)
                first = edit.Start - span.StartOffset + 1;
                last = edit.End - span.StartOffset + 1;
                text = extractBefore(text, first) + edit.Text + extractAfter(text, last);
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
