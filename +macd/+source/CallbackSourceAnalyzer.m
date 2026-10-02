classdef CallbackSourceAnalyzer
    % CallbackSourceAnalyzer Prove callback assignment and method ownership without execution.
    %   The analyzer recognizes direct initialization assignments and whole instance
    %   methods. Unsupported scope, constructor bindings, sharing, and dynamic
    %   references remain visible with both mutation actions unavailable.

    methods (Static)
        function states = analyze(document, componentId, registry)
            % analyze Return catalog-ordered callback states for the current source snapshot.
            arguments (Input)
                document (1, 1) macd.model.DocumentModel
                componentId (1, 1) string
                registry (1, 1) macd.model.ComponentRegistry
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
            source = document.OriginalText;
            statements = macd.source.MatlabLexicalScanner.splitStatements(source);
            layout = macd.source.CallbackSourceAnalyzer.layout(statements);

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
                    [state, reason, handler, bindingSpan, methodSpan, bindingAnchor, methodAnchor] = ...
                        macd.source.CallbackSourceAnalyzer.classify(component, name, statements, layout);
                end
                states(end + 1) = macd.model.CallbackState(name, state, reason, handler, ...
                    bindingSpan, methodSpan, bindingAnchor, methodAnchor); %#ok<AGROW>
            end
        end
    end

    methods (Static, Access = private)
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
                "Methods", struct("Name", {}, "Span", {}), "MethodAnchor", 0);
            stack = struct("Kind", {}, "Name", {}, "Start", {}, "Instance", {});
            for index = 1:numel(statements)
                text = char(strtrim(statements(index).Text));
                token = regexp(text, '^([A-Za-z]\w*)(?!\w)', 'tokens', 'once');
                if isempty(token), continue, end
                keyword = string(token{1});
                if keyword == "end" && ~isempty(regexp(text, '^end\s*$', 'once'))
                    if isempty(stack), layout.Valid = false; break, end
                    block = stack(end);
                    stack(end) = [];
                    if block.Kind == "function" && block.Instance
                        layout.Methods(end + 1) = struct("Name", block.Name, ...
                            "Span", macd.model.SourceSpan(block.Start, statements(index).Span.EndOffset));
                    elseif block.Kind == "methods" && block.Instance && layout.MethodAnchor == 0
                        layout.MethodAnchor = statements(index).Span.StartOffset - 1;
                    end
                    continue
                end
                layout.Direct(index) = numel(stack) == 3 && ...
                    stack(1).Kind == "classdef" && stack(2).Kind == "methods" && ...
                    stack(2).Instance && stack(3).Kind == "function" && ...
                    stack(3).Name == "createComponents";
                if any(keyword == ["classdef", "methods", "properties", "events", "enumeration", ...
                        "function", "arguments", "if", "for", "parfor", "while", "switch", "try", "spmd"])
                    name = "";
                    instance = false;
                    if keyword == "methods"
                        instance = isempty(regexp(text, '(?<!\w)(Static|Abstract|External)(?!\w)', 'once'));
                    elseif keyword == "function"
                        declaration = regexp(text, '^function\s+(?:(?:\[[^\]]*\]|\w+)\s*=\s*)?(\w+)\s*(?:\(|$)', 'tokens', 'once');
                        if isempty(declaration), layout.Valid = false; break, end
                        name = string(declaration{1});
                        instance = numel(stack) == 2 && stack(2).Kind == "methods" && stack(2).Instance;
                    end
                    stack(end + 1) = struct("Kind", keyword, "Name", name, ...
                        "Start", statements(index).Span.StartOffset, "Instance", instance); %#ok<AGROW>
                end
            end
            layout.Valid = layout.Valid && isempty(stack);
        end

        function [state, reason, handler, bindingSpan, methodSpan, bindingAnchor, methodAnchor] = classify(component, name, statements, layout)
            % classify Validate a direct binding, unique method, and exclusive source references.
            arguments (Input)
                component (1, 1) macd.model.ComponentRecord
                name (1, 1) string
                statements macd.source.SourceStatement
                layout (1, 1) struct
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
            creationIndex = find(arrayfun(@(statement) statement.Span.StartOffset == creation.StartOffset, statements));
            if numel(creationIndex) ~= 1 || ~layout.Direct(creationIndex), return, end
            bindingAnchor = creation.EndOffset;
            target = "app\s*\.\s*" + component.Name + "\s*\.\s*" + name;
            occurrences = [];
            for index = 1:numel(statements)
                text = statements(index).Text;
                % Dynamic dispatch prevents proving exclusive ownership of any handler.
                if ~isempty(regexp(text, '(?<!\w)(eval|evalc|evalin|feval|str2func|subsref|subsasgn)\s*\(|app\s*\.\s*\(', 'once'))
                    reason = "Dynamic source references prevent safe callback editing.";
                    return
                end
                if ~isempty(regexp(text, target + '(?!\w)', 'once')) || ...
                        (index == creationIndex && contains(text, name))
                    occurrences(end + 1) = index; %#ok<AGROW>
                elseif contains(text, name) && isempty(regexp(text, ...
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
            match = regexp(expression, '^createCallbackFcn\s*\(\s*app\s*,\s*@(\w+)\s*,\s*true\s*\)$', 'tokens', 'once');
            if isempty(match)
                match = regexp(expression, '^@app\.(\w+)$', 'tokens', 'once');
            end
            reason = "The callback expression does not have supported method ownership.";
            if isempty(match), return, end
            handler = string(match{1});
            if any(handler == ["createComponents", "delete"]), return, end
            methods = layout.Methods(string({layout.Methods.Name}) == handler);
            reason = "The callback method is missing, shared, or referenced elsewhere.";
            if numel(methods) ~= 1, return, end
            count = 0;
            for statement = statements(:)'
                count = count + numel(regexp(statement.Text, '(?<!\w)' + handler + '(?!\w)', 'match'));
            end
            if count ~= 2, return, end
            methodSpan = methods.Span;
            state = "editable";
            reason = "";
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
