classdef InitializationSourceAnalyzer
    % InitializationSourceAnalyzer Trace initialization through explicit instance calls.
    %   The constructor is the root. Callback registrations are not calls, and
    %   unsupported dynamic dispatch is reported without executing input source.
    %   Constructor-free fragments retain a diagnosed factory-owner fallback.

    methods (Static)
        function result = isLiteralDataCall(source, blockedNames)
            % isLiteralDataCall Recognize only reviewed data constructors with inert literal inputs.
            arguments (Input)
                source (1, 1) string
                blockedNames string = strings(1, 0)
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = false;
            call = regexp(char(strtrim(source)), '^(?<name>[A-Za-z]\w*)\s*\((?<arguments>[\s\S]*)\)$', 'names', 'once');
            if isempty(call) || any(blockedNames == string(call.name)), return, end
            allowed = ["zeros", "ones", "eye", "linspace", "logspace", "NaN", "nan", "Inf", "inf", ...
                "false", "true", "struct", "cell", "table", "string", "char", "double", "single", ...
                "logical", "int8", "int16", "int32", "int64", "uint8", "uint16", "uint32", "uint64", ...
                "datetime", "duration", "calendarDuration", "categorical", "sprintf", "disp", "fprintf"];
            if ~any(allowed == string(call.name)), return, end
            [~, result] = macd.source.MatlabLiteralParser.parse("{" + string(call.arguments) + "}");
        end

        function [order, diagnostics, certain, returns] = analyze(statements, scopes, creationOffsets)
            % analyze Return statement visits in conservative constructor call order.
            arguments (Input)
                statements macd.source.SourceStatement
                scopes (1, 1) struct
                creationOffsets double
            end
            arguments (Output)
                order double
                diagnostics macd.model.Diagnostic
                certain logical
                returns double
            end

            names = unique(scopes.InstanceNames, 'stable');
            declarations = false(1, numel(statements));
            insideArguments = false;
            for declarationIndex = 1:numel(statements)
                code = strtrim(statements(declarationIndex).Text);
                if ~isempty(regexp(code, '^arguments\s*(?:\(\s*(?:Input|Output|Repeating)\s*\))?\s*$', 'once'))
                    insideArguments = true;
                end
                declarations(declarationIndex) = insideArguments;
                if insideArguments && code == "end", insideArguments = false; end
            end
            blockedNames = names;
            if isfield(scopes, "Methods"), blockedNames = unique([names string({scopes.Methods.Name})]); end
            roots = scopes.ClassName;
            diagnostics = macd.model.Diagnostic.empty;
            order = [];
            certain = false(1, 0);
            returns = zeros(1, 0);
            if ~any(names == roots)
                % Partial class fixtures have no executable entry point; disclose inference.
                creation = ismember(arrayfun(@(statement) statement.Span.StartOffset, statements), creationOffsets);
                roots = unique(scopes.Owner(creation & strlength(scopes.Owner) > 0));
                diagnostics(end + 1) = macd.model.Diagnostic("initialization-constructor-missing", "warning", ...
                    "No explicit constructor is available. Initial values are inferred only when one factory-owning instance method is identifiable.");
                if ~isscalar(roots), return, end
            end
            % Bound repeated calls while retaining their order and detecting recursion.
            queue = struct("Name", roots, "Indices", find(scopes.Owner == roots), "Next", 1, "IsCertain", true, "Visit", 0);
            reported = [];
            while ~isempty(queue)
                frame = queue(end);
                if frame.Next > numel(frame.Indices)
                    if frame.Visit > 0, returns(frame.Visit) = numel(order); end
                    queue(end) = [];
                    continue
                end
                index = frame.Indices(frame.Next);
                queue(end).Next = frame.Next + 1;
                order(end + 1) = index; %#ok<AGROW>
                certain(end + 1) = frame.IsCertain && scopes.Valid && scopes.StraightLine(index); %#ok<AGROW>
                returns(end + 1) = numel(order); %#ok<AGROW>
                if numel(order) > 10000
                    diagnostics(end + 1) = macd.model.Diagnostic("initialization-trace-limit", "warning", ...
                        "Initialization tracing exceeded its static visit limit.", "", statements(index).Span); %#ok<AGROW>
                    return
                end
                % A definite return ends only this frame; a guarded return makes its tail uncertain.
                if ~isempty(regexp(strtrim(statements(index).Text), '^return\s*$', 'once'))
                    if scopes.StraightLine(index)
                        queue(end).Next = numel(frame.Indices) + 1;
                    else
                        queue(end).IsCertain = false;
                    end
                    continue
                end
                % Registered outer factories are decoded separately, including opaque argument effects.
                if ismember(statements(index).Span.StartOffset, creationOffsets) || declarations(index), continue, end
                [target, reason] = macd.source.InitializationSourceAnalyzer.callTarget(statements(index).Text, names, blockedNames);
                if strlength(target) > 0 && any(string({queue.Name}) == target)
                    reason = "Recursive initialization cannot be expanded safely.";
                    target = "";
                end
                if strlength(reason) > 0 && ~ismember(index, reported)
                    diagnostics(end + 1) = macd.model.Diagnostic("unresolved-initialization-call", "warning", ...
                        reason, "", statements(index).Span); %#ok<AGROW>
                    reported(end + 1) = index; %#ok<AGROW>
                end
                if strlength(target) > 0
                    queue(end + 1) = struct("Name", target, "Indices", find(scopes.Owner == target), ...
                        "Next", 1, "IsCertain", certain(end), "Visit", numel(order)); %#ok<AGROW>
                end
            end
        end
    end

    methods (Static, Access = private)
        function [target, reason] = callTarget(source, names, blockedNames)
            % callTarget Resolve supported direct calls while excluding deferred callback bodies.
            arguments (Input)
                source (1, 1) string
                names string
                blockedNames string
            end
            arguments (Output)
                target (1, 1) string
                reason (1, 1) string
            end

            code = strtrim(string(macd.source.ComponentNameRewriter.codeMask(source)));
            target = "";
            reason = "";
            % Argument declarations are structural syntax, never executable instance calls.
            if ~isempty(regexp(code, '^(arguments|function|methods|properties|classdef)(?!\w)', 'once')), return, end
            % AppBase's startup wrapper executes its method during construction.
            startup = regexp(code, '^runStartupFcn\s*\(\s*app\s*,\s*@(?:app\s*\.\s*)?(\w+)\s*\)$', 'tokens', 'once');
            if isempty(startup)
                startup = regexp(code, '^runStartupFcn\s*\(\s*app\s*,\s*@\(\s*app\s*\)\s*(\w+)\s*\(\s*app(?:\s*,[\s\S]*)?\)\s*\)$', 'tokens', 'once');
            end
            if ~isempty(startup)
                if any(names == string(startup{1}))
                    target = string(startup{1});
                else
                    reason = "The startup method cannot be resolved within this class.";
                end
                return
            end
            if ~isempty(regexp(code, '^runStartupFcn\s*\(|^(?:(?:\[[^\]]*\]|\w+|app\s*\.\s*\w+)\s*=\s*)?(?:feval\s*\(|app\s*\.\s*\()', 'once'))
                reason = "Dynamic initialization dispatch cannot be resolved statically.";
                return
            end
            if ~contains(code, "@") && ~isempty(regexp(code, '(?<!\w)(eval|evalc|evalin|feval|str2func|subsref|subsasgn)\s*\(|(?<!\w)app\s*\.\s*\(', 'once'))
                reason = "Dynamic initialization dispatch cannot be resolved statically.";
                return
            end
            pattern = '^(?:(?:\[[^\]]*\]|\w+|app\s*\.\s*\w+)\s*=\s*)?(?<receiver>app\s*\.\s*)?(?<name>\w+)\s*\((?<arguments>[\s\S]*)\)$';
            call = regexp(code, pattern, 'names', 'once');
            if isempty(call)
                % Registration and anonymous bodies are deferred; outer direct calls are not.
                if contains(code, "@"), return, end
                call = regexp(code, '^(?:(?:\[[^\]]*\]|\w+|app\s*\.\s*\w+)\s*=\s*)?(?<receiver>app\s*\.\s*)(?<name>\w+)$', 'names', 'once');
                if ~isempty(call), call.arguments = ''; end
            end
            if isempty(call)
                % Event pumps and unknown command forms can execute callbacks without an app argument.
                command = regexp(code, '^([A-Za-z]\w*)\s*$', 'tokens', 'once');
                structural = ["end", "else", "otherwise", "try", "catch", "return", "break", "continue", "tic", "toc", "clc"];
                if (~isempty(command) && ~any(string(command{1}) == structural)) || ...
                        ~isempty(regexp(code, '^(drawnow|pause|waitfor|uiwait)(?!\w)', 'once'))
                    reason = "An initialization command requires an explicit effect review.";
                    return
                end
                % Do not silently drop same-class calls embedded in unsupported expressions.
                for name = names
                    pattern = '(?<![\w.])app\s*\.\s*' + name + '\s*\(|(?<![\w.@])' + name + '\s*\(\s*app(?!\w)';
                    if ~isempty(regexp(code, pattern, 'once')) && ...
                            isempty(regexp(code, '^function(?!\w)', 'once'))
                        reason = "An embedded initialization call requires manual review.";
                        return
                    end
                end
                return
            end
            % A greedy call match must not absorb chained or compound expressions.
            delimiters = '';
            for character = char(call.arguments)
                if ismember(character, '([{')
                    delimiters(end + 1) = character; %#ok<AGROW>
                elseif ismember(character, ')]}')
                    closing = find(')]}' == character, 1);
                    opening = '([{';
                    if isempty(delimiters) || delimiters(end) ~= opening(closing)
                        reason = "A compound initialization call requires manual review.";
                        return
                    end
                    delimiters(end) = [];
                end
            end
            if ~isempty(delimiters)
                reason = "An incomplete initialization call requires manual review.";
                return
            end
            instance = ~isempty(call.receiver) || ~isempty(regexp(strtrim(call.arguments), '^app\s*(?:,|$)', 'once'));
            if ~instance
                % Passing an owned component permits arbitrary mutation by an opaque callee.
                if ~isempty(regexp(call.arguments, '(?<!\w)app\s*\.\s*\w+', 'once'))
                    reason = "A call receiving a component handle cannot be expanded statically.";
                else
                    raw = regexp(char(strtrim(source)), pattern, 'names', 'once');
                    inert = ~isempty(raw) && macd.source.InitializationSourceAnalyzer.isLiteralDataCall( ...
                        string(raw.name) + "(" + string(raw.arguments) + ")", blockedNames);
                    if ~inert
                        reason = "Initialization call '" + string(call.name) + "' has no reviewed effect contract.";
                    end
                end
                return
            end
            if any(names == string(call.name))
                target = string(call.name);
            elseif ~any(string(call.name) == [string(methods("matlab.apps.AppBase"))', "registerApp", "runStartupFcn", "createCallbackFcn"])
                reason = "Initialization call '" + string(call.name) + "' cannot be resolved within this class.";
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
