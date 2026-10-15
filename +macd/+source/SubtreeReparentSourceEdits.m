classdef SubtreeReparentSourceEdits
    % SubtreeReparentSourceEdits Relocate proven initialization statements for moved subtrees.
    %   Existing callback methods remain untouched. Only direct createComponents
    %   statements with known ownership can be relocated.

    methods (Static)
        function [edits, movedIds] = build(document, registry)
            % build Generate subtree relocation edits against the original source snapshot.
            arguments (Input)
                document (1, 1) macd.model.DocumentModel
                registry (1, 1) macd.model.ComponentRegistry
            end
            arguments (Output)
                edits struct
                movedIds string
            end

            edits = struct("Start", {}, "End", {}, "Text", {});
            movedIds = strings(1, 0);
            originals = struct([]);
            for index = 1:numel(document.PendingEdits)
                pending = document.PendingEdits{index};
                if ~isstruct(pending) || ~isfield(pending, "Kind") || pending.Kind ~= "reparent-subtree", continue, end
                for record = pending.OriginalRecords
                    if record.Origin ~= "parsed" || isempty(document.getComponent(record.Id)), continue, end
                    if ~any(movedIds == record.Id)
                        movedIds(end + 1) = record.Id; %#ok<AGROW>
                        if isempty(originals), originals = record; else, originals(end + 1) = record; end %#ok<AGROW>
                    end
                end
            end
            if isempty(movedIds), return, end
            source = document.OriginalText;
            statements = macd.source.MatlabLexicalScanner.splitStatements(source);
            [direct, methodSpan] = macd.source.SubtreeReparentSourceEdits.directScope(statements);
            spans = macd.model.SourceSpan.empty;
            names = strings(1, 0);
            for record = originals
                own = record.SourceSpans.Creation;
                for property = record.Properties
                    if ~isempty(property.SourceSpan), own = [own property.SourceSpan]; end %#ok<AGROW>
                end
                for span = own
                    matches = find(arrayfun(@(statement) statement.Span.StartOffset == span.StartOffset && ...
                        statement.Span.EndOffset == span.EndOffset, statements));
                    if ~span.isKnown() || numel(matches) ~= 1 || ~direct(matches)
                        error("macd:SubtreeReparentSourceEdits:UnsafeSource", "Initialization ownership is not a unique direct createComponents statement.");
                    end
                end
                spans = [spans own]; %#ok<AGROW>
                creation = extractBetween(source, record.SourceSpans.Creation.StartOffset, record.SourceSpans.Creation.EndOffset);
                token = regexp(creation, '^app\.(\w+)\s*=', 'tokens', 'once');
                if isempty(token), error("macd:SubtreeReparentSourceEdits:UnsafeSource", "Creation identity is unknown."); end
                names(end + 1) = string(token{1}); %#ok<AGROW>
            end

            % Insert after owned initialization, with all destination parents already created.
            anchor = 0;
            for statementIndex = find(direct)
                statement = statements(statementIndex);
                text = char(statement.Text);
                if ~isempty(regexp(text, '^app\.\w+\s*=\s*\w+\s*\(|^app\.\w+\.\w+(?:\.\w+)*\s*=', 'once'))
                    anchor = max(anchor, statement.Span.EndOffset);
                end
            end
            if anchor == 0, error("macd:SubtreeReparentSourceEdits:UnsafeSource", "Initialization insertion anchor is unavailable."); end
            code = macd.source.SubtreeSourceEdits.codeMask(source);
            if ~isempty(regexp(code, 'app\s*\.\s*\(|\w+\s*=\s*app\s*(?:;|\n)|(?:subsref|subsasgn|eval|feval)\s*\(', 'once'))
                error("macd:SubtreeReparentSourceEdits:UnsafeSource", "Dynamic or aliased references prevent proving relocation safety.");
            end
            for name = names
                positions = regexp(code, '(?<!\w)app\s*\.\s*' + name + '(?!\w)', 'start');
                for position = positions
                    owned = any([spans.StartOffset] <= position & [spans.EndOffset] >= position);
                    if ~owned && position >= methodSpan.StartOffset && position <= anchor
                        error("macd:SubtreeReparentSourceEdits:UnsafeSource", "Initialization outside the moved subtree depends on its original order.");
                    end
                end
            end
            pendingCallbacks = document.CallbackEdits;
            if any(ismember(string({pendingCallbacks.ComponentId}), movedIds))
                error("macd:SubtreeReparentSourceEdits:UnsafeSource", "Pending callback edits require a combined relocation plan.");
            end
            ending = string(newline);
            if document.LineEnding == "CRLF", ending = string(sprintf("\r\n")); end
            block = "";
            deferredParsedReferences = strings(1, 0);

            % Emit moved initialization in the candidate's parent-before-child order.
            for component = document.Components
                if component.Origin == "generated"
                    block = block + macd.source.SubtreeReparentSourceEdits.generatedInitialization(document, component, registry, ending);
                    continue
                end
                if ~any(movedIds == component.Id), continue, end
                record = originals(string({originals.Id}) == component.Id);
                parent = document.getComponent(component.ParentId);
                if isempty(parent)
                    error("macd:SubtreeReparentSourceEdits:UnsafeSource", "Destination parent no longer exists.");
                end
                creation = extractBetween(source, record.SourceSpans.Creation.StartOffset, record.SourceSpans.Creation.EndOffset);
                pattern = '^(app\.\w+\s*=\s*\w+\s*\(\s*)app\.\w+';
                if isempty(regexp(creation, pattern, 'once'))
                    error("macd:SubtreeReparentSourceEdits:UnsafeSource", "The creation parent is not a static component reference.");
                end
                parentName = parent.Name;
                if parent.Origin == "parsed"
                    parentCreation = extractBetween(source, parent.SourceSpans.Creation.StartOffset, parent.SourceSpans.Creation.EndOffset);
                    token = regexp(parentCreation, '^app\.(\w+)\s*=', 'tokens', 'once');
                    parentName = string(token{1});
                end
                creation = regexprep(creation, pattern, "$1app." + parentName, 'once');
                block = block + ending + "            " + creation;
                name = names(string({originals.Id}) == component.Id);
                for entry = component.Properties
                    if registry.isReadOnlyProperty(component.Factory, entry.Path, component.CreationArguments), continue, end
                    if entry.ValueKind == "literal"
                        assignment = "app." + name + "." + entry.Path + " = " + macd.source.LiteralEncoder.encode(entry.LiteralValue) + ";";
                    elseif entry.ValueKind == "expression" && ~isempty(entry.SourceSpan) && entry.SourceSpan.isKnown()
                        assignment = extractBetween(source, entry.SourceSpan.StartOffset, entry.SourceSpan.EndOffset);
                        if any(entry.Path == ["SelectedTab", "ContextMenu"])
                            macd.model.SubtreeReferencePolicy.resolve(document, component, entry.Path, entry.SourceExpression, registry);
                            deferredParsedReferences(end + 1) = assignment; %#ok<AGROW>
                            continue
                        end
                        references = regexp(macd.source.SubtreeSourceEdits.codeMask(entry.SourceExpression), ...
                            '(?<!\w)app\s*\.\s*([A-Za-z]\w*)', 'tokens');
                        for reference = references
                            if any(names == string(reference{1}{1}))
                                error("macd:SubtreeReparentSourceEdits:UnsafeSource", ...
                                    "An unsupported internal component reference prevents safe relocation.");
                            end
                        end
                    else
                        error("macd:SubtreeReparentSourceEdits:UnsafeSource", "A property has no proven source representation.");
                    end
                    block = block + ending + "            " + assignment;
                end
            end
            generated = document.Components([document.Components.Origin] == "generated");
            references = macd.model.SubtreeReferencePolicy.assignments(document, generated, registry);
            for reference = [deferredParsedReferences references], block = block + ending + "            " + reference; end
            for span = spans
                edits(end + 1) = struct("Start", span.StartOffset, "End", span.EndOffset, "Text", ""); %#ok<AGROW>
            end
            edits(end + 1) = struct("Start", anchor + 1, "End", anchor, "Text", block);
        end

        function text = generatedInitialization(document, component, registry, ending)
            % generatedInitialization Emit new nodes in the same ordering plan as relocated parsed nodes.
            arguments (Input)
                document (1, 1) macd.model.DocumentModel
                component (1, 1) macd.model.ComponentRecord
                registry (1, 1) macd.model.ComponentRegistry
                ending (1, 1) string
            end
            arguments (Output)
                text (1, 1) string
            end
            parent = document.getComponent(component.ParentId);
            if isempty(parent)
                error("macd:SubtreeReparentSourceEdits:UnsafeSource", "Generated initialization has no parent.");
            end
            argumentsText = "app." + parent.Name;
            for index = 1:numel(component.CreationArguments)
                argumentsText = argumentsText + ", " + macd.source.LiteralEncoder.encode(component.CreationArguments{index});
            end
            text = ending + "            app." + component.Name + " = " + component.Factory + "(" + argumentsText + ");";
            pending = document.CallbackEdits(string({document.CallbackEdits.ComponentId}) == component.Id);
            for callback = pending(:)'
                if callback.Action == "Add"
                    text = text + ending + "            app." + component.Name + "." + callback.Name + ...
                        " = createCallbackFcn(app, @" + callback.HandlerName + ", true);";
                end
            end
            for entry = component.Properties
                if registry.isReadOnlyProperty(component.Factory, entry.Path, component.CreationArguments), continue, end
                if isfield(entry.Metadata, "SubtreeReferenceId"), continue, end
                if entry.ValueKind ~= "literal"
                    error("macd:SubtreeReparentSourceEdits:UnsafeSource", "Generated properties require a literal representation.");
                end
                text = text + ending + "            app." + component.Name + "." + entry.Path + ...
                    " = " + macd.source.LiteralEncoder.encode(entry.LiteralValue) + ";";
            end
        end

        function [direct, methodSpan] = directScope(statements)
            % directScope Recognize direct initialization scope with explicit block nesting.
            arguments (Input)
                statements macd.source.SourceStatement
            end
            arguments (Output)
                direct logical
                methodSpan (1, 1) macd.model.SourceSpan
            end
            direct = false(1, numel(statements));
            methodSpan = macd.model.SourceSpan();
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
                    if isempty(stack), error("macd:SubtreeReparentSourceEdits:UnsafeSource", "Source block nesting is ambiguous."); end
                    if createDepth > 0 && numel(stack) == createDepth
                        methodSpan = macd.model.SourceSpan(start, statements(index).Span.EndOffset);
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
                            error("macd:SubtreeReparentSourceEdits:UnsafeSource", "Initialization must be an instance method.");
                        end
                        count = count + 1;
                        createDepth = numel(stack);
                        start = statements(index).Span.StartOffset;
                    end
                end
            end
            if ~isempty(stack) || count ~= 1 || ~methodSpan.isKnown()
                error("macd:SubtreeReparentSourceEdits:UnsafeSource", "Unique initialization method ownership cannot be proven.");
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
