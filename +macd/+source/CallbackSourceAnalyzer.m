classdef CallbackSourceAnalyzer
    % CallbackSourceAnalyzer Prove callback assignment and method ownership without execution.
    %   The analyzer recognizes direct initialization assignments and whole instance
    %   methods. Unsupported scope, constructor bindings, sharing, and dynamic
    %   references remain visible with both mutation actions unavailable.

    methods (Static, Access = ?macd.source.SourceAnalysis)
        function indices = sourceCallbackCandidates(statements, name)
            % sourceCallbackCandidates Retain every possible binding, indirect reference, and dynamic dispatch in source order.
            arguments (Input)
                statements macd.source.SourceStatement
                name (1, 1) string
            end
            arguments (Output)
                indices (1, :) double
            end
            relevant = false(1, numel(statements));
            for index = 1:numel(statements)
                text = statements(index).Text;
                relevant(index) = contains(text, name) || ~isempty(regexp(text, ...
                    '(?<!\w)(eval|evalc|evalin|feval|str2func|subsref|subsasgn)\s*\(|app\s*\.\s*\(', 'once'));
            end
            indices = find(relevant);
        end

        function layout = sourceLayout(statements)
            % sourceLayout Expose the pure layout compiler only to the derived source cache.
            arguments (Input)
                statements macd.source.SourceStatement
            end
            arguments (Output)
                layout (1, 1) struct
            end
            layout = macd.source.CallbackSourceAnalyzer.layout(statements);
        end
    end

    methods (Static)
        function [order, diagnostics, certain, layout, returns] = initializationStatements(statements, creationOffsets)
            % initializationStatements Trace constructor-reachable initializers without executing source.
            arguments (Input)
                statements macd.source.SourceStatement
                creationOffsets double = []
            end
            arguments (Output)
                order double
                diagnostics macd.model.Diagnostic
                certain logical
                layout (1, 1) struct
                returns double
            end

            layout = macd.source.CallbackSourceAnalyzer.layout(statements);
            [order, diagnostics, certain, returns] = macd.source.InitializationSourceAnalyzer.analyze(statements, layout, creationOffsets);
        end

        function states = analyze(document, componentId, registry, bindingOnly)
            % analyze Return catalog-ordered callback states for the current source snapshot.
            arguments (Input)
                document (1, 1) macd.model.DocumentModel
                componentId (1, 1) string
                registry (1, 1) macd.model.ComponentRegistry
                bindingOnly (1, 1) logical = false
            end
            arguments (Output)
                states macd.model.CallbackState
            end

            % Resolve the effective catalog surface independently of active UI selection.
            states = macd.model.CallbackState.empty;
            component = document.getComponent(componentId);
            if isempty(component), return, end
            parentFactory = "";
            if strlength(component.ParentId) > 0
                parent = document.getComponent(component.ParentId);
                if ~isempty(parent), parentFactory = parent.Factory; end
            end
            definitions = registry.getEffectiveCallbacks(component.Factory, parentFactory, component.CreationArguments);
            source = document.CurrentText;
            analysis = document.sourceAnalysis();
            statements = analysis.Statements;
            layout = analysis.Layout;

            % Generated binding anchors are identical for every catalog callback on this component.
            generatedInsertion = ~isempty(definitions) && strlength(source) > 0 && ...
                ~macd.model.SourceOwnership.hasSource(component) && ...
                macd.source.CallbackSourceAnalyzer.canInsertGenerated(document, analysis);

            % Classify each binding using source occurrences rather than the last parsed value.
            for index = 1:numel(definitions)
                name = definitions(index).Path;
                state = "absent";
                reason = "";
                handler = "";
                bindingSpan = macd.model.SourceSpan.empty;
                methodSpan = macd.model.SourceSpan.empty;
                bindingAnchor = 0;
                methodAnchor = 0;
                if strlength(source) > 0
                    if generatedInsertion
                        methodAnchor = layout.MethodAnchor;
                    else
                        sourceName = document.sourceComponentName(componentId);
                        candidates = 1:numel(statements);
                        if ~isempty(regexp(sourceName, '^[A-Za-z]\w*$', 'once')) && ...
                                ~isempty(regexp(name, '^[A-Za-z]\w*$', 'once'))
                            candidates = analysis.callbackCandidates(name);
                        end
                        [state, reason, handler, bindingSpan, methodSpan, bindingAnchor, methodAnchor] = ...
                        macd.source.CallbackSourceAnalyzer.classify(component, sourceName, name, statements, layout, candidates, analysis, bindingOnly);
                    end
                else
                    entry = component.getProperty(name);
                    if ~isempty(entry) && (entry.ValueKind ~= "literal" || ~isempty(entry.LiteralValue))
                        state = "unsupported";
                        reason = "The generated callback has no proven method ownership.";
                    end
                end
                % Pending atomic intentions override availability without changing original source spans.
                pending = document.CallbackEdits(string({document.CallbackEdits.ComponentId}) == componentId & ...
                    string({document.CallbackEdits.Name}) == name);
                if ~isempty(pending)
                    edit = pending(end);
                    state = "absent";
                    if any(edit.Action == ["Add", "New", "Connect"]), state = "editable"; end
                    reason = "";
                    handler = edit.HandlerName;
                    bindingSpan = edit.BindingSpan;
                    methodSpan = edit.MethodSpan;
                    bindingAnchor = edit.BindingAnchor;
                    methodAnchor = edit.MethodAnchor;
                    if edit.OriginalSource ~= source
                        state = "unsupported";
                        reason = "The callback source snapshot changed; reload or undo before editing.";
                    end
                end
                handler = document.effectiveMemberName(handler);
                states(end + 1) = macd.model.CallbackState(name, state, reason, handler, ...
                    bindingSpan, methodSpan, bindingAnchor, methodAnchor); %#ok<AGROW>
            end
        end
    end

    methods (Static, Access = private)
        function result = canInsertGenerated(document, analysis)
            % canInsertGenerated Require direct initialization anchors for generated component bindings.
            arguments (Input)
                document (1, 1) macd.model.DocumentModel
                analysis (1, 1) macd.source.SourceAnalysis
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = analysis.Layout.Valid && analysis.Layout.MethodAnchor > 0;
            if ~result, return, end
            % Source spans are mutable, so capture the current parsed set before sharing its answer.
            parsed = document.Components(arrayfun(@macd.model.SourceOwnership.hasSource, document.Components));
            offsets = zeros(1, numel(parsed));
            for index = 1:numel(parsed)
                span = parsed(index).SourceSpans.Creation;
                if isempty(span), result = false; return, end
                offsets(index) = span.StartOffset;
            end
            result = analysis.canInsertGenerated(offsets);
        end

        function layout = layout(statements)
            % layout Track explicit block scopes and complete instance method spans.
            arguments (Input)
                statements macd.source.SourceStatement
            end
            arguments (Output)
                layout (1, 1) struct
            end

            % Explicit end-delimited scopes avoid interpreting arbitrary expressions as structure.
            layout = struct("Valid", true, "Direct", false(1, numel(statements)), ...
                "StraightLine", false(1, numel(statements)), ...
                "Owner", strings(1, numel(statements)), "ClassName", "", ...
                "InstanceNames", strings(1, 0), ...
                "Methods", struct("Name", {}, "Span", {}, "Signature", {}), "MethodAnchor", 0);
            stack = struct("Kind", {}, "Name", {}, "Start", {}, "Instance", {}, "Index", {});
            constructorTry = zeros(1, numel(statements));
            for index = 1:numel(statements)
                text = char(strtrim(statements(index).Text));
                % Associate branch statements with their method, excluding nested bodies.
                instanceBody = numel(stack) >= 3 && ...
                    stack(1).Kind == "classdef" && stack(2).Kind == "methods" && ...
                    stack(2).Instance && stack(3).Kind == "function" && ...
                    nnz(string({stack.Kind}) == "function") == 1;
                if instanceBody, layout.Owner(index) = stack(3).Name; end
                layout.StraightLine(index) = instanceBody && numel(stack) == 3;
                if instanceBody && numel(stack) == 4 && stack(4).Kind == "try" && ...
                        stack(3).Name == layout.ClassName
                    constructorTry(index) = stack(4).Start;
                end
                token = regexp(text, '^([A-Za-z]\w*)(?!\w)', 'tokens', 'once');
                if isempty(token), continue, end
                keyword = string(token{1});
                if keyword == "classdef"
                    declaration = regexp(text, '^classdef(?:\s*\([^)]*\))?\s+(\w+)', 'tokens', 'once');
                    if ~isempty(declaration), layout.ClassName = string(declaration{1}); end
                end
                if keyword == "end" && ~isempty(regexp(text, '^end\s*$', 'once'))
                    if isempty(stack), layout.Valid = false; break, end
                    block = stack(end);
                    stack(end) = [];
                    if block.Kind == "function" && block.Instance
                        layout.Methods(end + 1) = struct("Name", block.Name, ...
                            "Span", macd.model.SourceSpan(block.Start, statements(index).Span.EndOffset), ...
                            "Signature", macd.source.CallbackMethodSignature(statements(block.Index:index)));
                    elseif block.Kind == "methods" && block.Instance && layout.MethodAnchor == 0
                        layout.MethodAnchor = statements(index).Span.StartOffset - 1;
                    elseif block.Kind == "try"
                        % A cleanup-and-rethrow constructor catch cannot return a live app.
                        owned = find(constructorTry == block.Start);
                        catches = owned(startsWith(strtrim(string({statements(owned).Text})), "catch "));
                        if isscalar(catches)
                            tail = string({statements(catches:index - 1).Text});
                            caught = regexp(tail(1), '^catch\s+(\w+)$', 'tokens', 'once');
                            if numel(tail) == 3 && ~isempty(caught) && ...
                                    ~isempty(regexp(tail(2), '^delete\s*\(\s*app\s*\)$', 'once')) && ...
                                    ~isempty(regexp(tail(3), '^rethrow\s*\(\s*' + string(caught{1}) + '\s*\)$', 'once'))
                                layout.StraightLine(owned(owned < catches)) = true;
                                layout.Owner(catches:index - 1) = "";
                            end
                        end
                    end
                    continue
                end
                layout.Direct(index) = numel(stack) == 3 && ...
                    stack(1).Kind == "classdef" && stack(2).Kind == "methods" && ...
                    stack(2).Instance && stack(3).Kind == "function" && ...
                    stack(3).Name == "createComponents";
                % Class block keywords are also ordinary introspection function names.
                if any(keyword == ["methods", "properties", "events", "enumeration"]) && ...
                        ~(isscalar(stack) && stack(1).Kind == "classdef")
                    continue
                end
                if any(keyword == ["classdef", "methods", "properties", "events", "enumeration", ...
                        "function", "arguments", "if", "for", "parfor", "while", "switch", "try", "spmd"])
                    name = "";
                    instance = false;
                    if keyword == "methods"
                        instance = isempty(regexp(text, '(?<!\w)(Static|Abstract|External)(?!\w)', 'once'));
                    elseif keyword == "function"
                        declaration = regexp(text, '^function\s+(?:(?:\[[^\]]*\]|\w+)\s*=\s*)?((?:get\.|set\.)?\w+)\s*(?:\(|$)', 'tokens', 'once');
                        if isempty(declaration), layout.Valid = false; break, end
                        name = string(declaration{1});
                        instance = numel(stack) == 2 && stack(2).Kind == "methods" && stack(2).Instance;
                        if instance, layout.InstanceNames(end + 1) = name; end
                    end
                    stack(end + 1) = struct("Kind", keyword, "Name", name, ...
                        "Start", statements(index).Span.StartOffset, "Instance", instance, "Index", index); %#ok<AGROW>
                end
            end
            layout.Valid = layout.Valid && isempty(stack);
        end

        function [state, reason, handler, bindingSpan, methodSpan, bindingAnchor, methodAnchor] = classify(component, sourceName, name, statements, layout, candidates, analysis, bindingOnly)
            % classify Validate a direct binding, unique method, and exclusive source references.
            arguments (Input)
                component (1, 1) macd.model.ComponentRecord
                sourceName (1, 1) string
                name (1, 1) string
                statements macd.source.SourceStatement
                layout (1, 1) struct
                candidates (1, :) double
                analysis (1, 1) macd.source.SourceAnalysis
                bindingOnly (1, 1) logical = false
            end
            arguments (Output)
                state (1, 1) string
                reason (1, 1) string
                handler (1, 1) string
                bindingSpan macd.model.SourceSpan
                methodSpan macd.model.SourceSpan
                bindingAnchor (1, 1) double
                methodAnchor (1, 1) double
            end

            % Start disabled and establish every required ownership fact before enabling mutation.
            state = "unsupported";
            reason = "Source structure or insertion anchors cannot be proven safe.";
            handler = "";
            bindingSpan = macd.model.SourceSpan.empty;
            methodSpan = macd.model.SourceSpan.empty;
            bindingAnchor = 0;
            methodAnchor = layout.MethodAnchor;
            if ~layout.Valid || methodAnchor == 0 || isempty(component.SourceSpans.Creation), return, end
            creation = component.SourceSpans.Creation;
            creationIndex = analysis.statementIndices(creation, false);
            if numel(creationIndex) ~= 1 || ~layout.Direct(creationIndex), return, end
            bindingAnchor = creation.EndOffset;
            target = "app\s*\.\s*" + sourceName + "\s*\.\s*" + name;
            callbackToken = "(?<!\w)" + regexptranslate("escape", name) + "(?!\w)";
            occurrences = [];
            % The shared index omits only statements that cannot affect this exact predicate.
            for index = candidates
                text = statements(index).Text;
                % Dynamic dispatch prevents proving exclusive ownership of any handler.
                if ~isempty(regexp(text, '(?<!\w)(eval|evalc|evalin|feval|str2func|subsref|subsasgn)\s*\(|app\s*\.\s*\(', 'once'))
                    reason = "Dynamic source references prevent safe callback editing.";
                    return
                end
                if ~isempty(regexp(text, target + '(?!\w)', 'once')) || ...
                        (index == creationIndex && ~isempty(regexp(text, callbackToken, 'once')))
                    occurrences(end + 1) = index; %#ok<AGROW>
                elseif ~isempty(regexp(text, callbackToken, 'once')) && isempty(regexp(text, ...
                        'app\s*\.\s*\w+\s*\.\s*' + name + '(?!\w)\s*=', 'once'))
                    reason = "Indirect callback access prevents proving assignment ownership.";
                    return
                end
            end
            if isempty(occurrences)
                state = "absent";
                reason = "";
                return
            end
            reason = "Repeated, conditional, constructor, or indirect callback source is preserved.";
            if numel(occurrences) ~= 1, return, end
            index = occurrences(1);
            if ~layout.Direct(index) || index <= creationIndex, return, end
            assignment = regexp(statements(index).Text, '^' + target + '\s*=\s*(.+)$', 'tokens', 'once');
            if isempty(assignment), return, end
            expression = strtrim(string(assignment{1}));
            bindingSpan = statements(index).Span;
            [value, literal] = macd.source.MatlabLiteralParser.parse(expression);
            if literal && isempty(value)
                state = "absent";
                reason = "";
                return
            end

            % Allow only bindings whose referenced method can be identified without execution.
            if component.Factory == "uifigure" && name == "CloseRequestFcn" && ...
                    macd.source.CallbackSourceEdits.isDefaultClose(expression)
                state = "absent";
                reason = "";
                return
            end
            handler = macd.source.CallbackSourceAnalyzer.bindingHandler(expression);
            reason = "The callback expression does not have supported method ownership.";
            if strlength(handler) == 0, return, end
            if bindingOnly
                state = "editable";
                reason = "";
                return
            end
            if any(handler == ["createComponents", "delete"]), return, end
            methods = layout.Methods(string({layout.Methods.Name}) == handler);
            reason = "The callback method is missing, shared, or referenced elsewhere.";
            if numel(methods) ~= 1, return, end
            count = 0;
            for statement = statements(:)'
                code = macd.source.ComponentNameRewriter.codeMask(statement.Text);
                count = count + numel(regexp(code, '(?<!\w)' + handler + '(?!\w)', 'match'));
            end
            if count ~= 2, return, end
            methodSpan = methods.Span;
            state = "editable";
            reason = "";
        end
    end

    methods (Static, Access = ?macd.source.AppSourceParser)
        function handler = bindingHandler(expression)
            % bindingHandler Recognize bound methods or inert two-input forwarding wrappers.
            arguments (Input)
                expression (1, 1) string
            end
            arguments (Output)
                handler (1, 1) string
            end

            % Keep direct handles and forwarding calls confined to the captured app.
            handler = "";
            direct = regexp(expression, "^@\s*app\s*\.\s*([A-Za-z]\w*)$", "tokens", "once");
            if ~isempty(direct)
                handler = string(direct{1});
                return
            end
            parameter = "(?:~|[A-Za-z]\w*)";
            pattern = "^@\s*\(\s*(?<source>" + parameter + ")\s*,\s*(?<event>" + parameter + ...
                ")\s*\)\s*app\s*\.\s*(?<handler>[A-Za-z]\w*)\s*\((?<forwarded>[^()]*)\)$";
            wrapper = regexp(expression, pattern, "names", "once");
            if isempty(wrapper), return, end
            parameters = [string(wrapper.source), string(wrapper.event)];
            named = parameters(parameters ~= "~");
            if any(named == "app") || numel(unique(named)) ~= numel(named) || ...
                    any(arrayfun(@(name) ~isvarname(name) || iskeyword(name), named))
                return
            end

            % Only forward an ordered subset of the wrapper inputs, without evaluating expressions.
            forwarded = strtrim(string(wrapper.forwarded));
            if strlength(forwarded) > 0
                forwarded = strtrim(split(forwarded, ","))';
                [found, indices] = ismember(forwarded, parameters);
                if ~all(found) || any(forwarded == "~") || any(diff(indices) <= 0), return, end
            end
            handler = string(wrapper.handler);
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
