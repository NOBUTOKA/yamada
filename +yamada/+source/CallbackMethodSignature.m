classdef CallbackMethodSignature
    % CallbackMethodSignature Retain fixed positional callback inputs without evaluating source.
    %   Layout compilation builds this value once per method. Known editor edits
    %   preserve it alongside the method span; UI discovery reads cached values.

    properties (SetAccess = private)
        % Inputs - Declared input identifiers, including the instance receiver.
        Inputs string = strings(1, 0)
        % Classes - Textual input class constraints, empty when untyped.
        Classes string = strings(1, 0)
        % Unchecked - Constraints requiring runtime knowledge or arbitrary validation.
        Unchecked logical = false(1, 0)
        % Eligible - Whether this is a fixed one-to-three-input method declaration.
        Eligible logical = false
    end

    methods
        function obj = CallbackMethodSignature(statements)
            % CallbackMethodSignature Read one method declaration and its input validation blocks.
            arguments (Input)
                statements yamada.source.SourceStatement = yamada.source.SourceStatement.empty
            end
            arguments (Output)
                obj (1, 1) yamada.source.CallbackMethodSignature
            end
            if isempty(statements), return, end
            header = regexp(statements(1).Text, ...
                '^function\s+(?:(?:\[[^\]]*\]|\w+)\s*=\s*)?(?<name>[A-Za-z]\w*)\s*\((?<inputs>[^()]*)\)\s*$', 'names', 'once');
            if isempty(header), return, end
            inputs = strtrim(split(string(header.inputs), ','))';
            if numel(inputs) < 1 || numel(inputs) > 3 || ...
                    any(arrayfun(@(item) item ~= "~" && (~isvarname(item) || iskeyword(item)), inputs)) || ...
                    any(inputs == "varargin") || numel(unique(inputs(inputs ~= "~"))) ~= nnz(inputs ~= "~")
                return
            end
            obj.Inputs = inputs;
            obj.Classes = strings(size(inputs));
            obj.Unchecked = false(size(inputs));
            obj.Eligible = true;

            % Only argument blocks immediately following the declaration describe its inputs.
            index = 2;
            inputPosition = 0;
            while index < numel(statements) && startsWith(strtrim(statements(index).Text), "arguments")
                declaration = strtrim(statements(index).Text);
                output = ~isempty(regexp(declaration, '^arguments\s*\(\s*Output\s*\)$', 'once'));
                if ~output && isempty(regexp(declaration, '^arguments(?:\s*\(\s*Input\s*\))?$', 'once'))
                    obj.Eligible = false; return
                end
                index = index + 1;
                while index < numel(statements) && strtrim(statements(index).Text) ~= "end"
                    if ~output
                        text = strtrim(statements(index).Text);
                        inputPosition = inputPosition + 1;
                        if inputPosition > numel(inputs), obj.Eligible = false; return, end
                        if text == "~"
                            if inputs(inputPosition) ~= "~", obj.Eligible = false; return, end
                            index = index + 1;
                            continue
                        end
                        argument = regexp(text, '^(?<name>[A-Za-z]\w*)(?<rest>.*)$', 'names', 'once');
                        if isempty(argument), obj.Eligible = false; return, end
                        position = find(inputs == string(argument.name));
                        rest = strtrim(string(argument.rest));
                        if ~isscalar(position) || position ~= inputPosition || startsWith(rest, ".")
                            obj.Eligible = false; return
                        end
                        % Dimensions and validators are retained as unchecked constraints, never executed.
                        if startsWith(rest, "(")
                            shape = regexp(rest, '^\([^()]*\)', 'match', 'once');
                            if isempty(shape), obj.Eligible = false; return, end
                            obj.Unchecked(position) = true;
                            rest = strtrim(extractAfter(rest, strlength(shape)));
                        end
                        type = regexp(rest, '^(?<class>[A-Za-z]\w*(?:\.[A-Za-z]\w*)*)(?=\s|\{|=|$)', 'names', 'once');
                        if ~isempty(type)
                            obj.Classes(position) = string(type.class);
                            rest = strtrim(extractAfter(rest, strlength(string(type.class))));
                        end
                        if startsWith(rest, "{")
                            obj.Unchecked(position) = true;
                        elseif rest ~= "" && ~startsWith(rest, "=")
                            obj.Eligible = false; return
                        end
                    end
                    index = index + 1;
                end
                index = index + 1;
            end
        end

        function text = binding(obj, name)
            % binding Emit the fixed forwarding convention for a validated method name.
            arguments (Input)
                obj (1, 1) yamada.source.CallbackMethodSignature
                name (1, 1) string
            end
            arguments (Output)
                text (1, 1) string
            end
            assert(obj.Eligible && isvarname(name) && ~iskeyword(name), ...
                "yamada:CallbackMethodSignature:Ineligible", "The method is not an eligible callback target.");
            switch numel(obj.Inputs)
                case 1, text = "@(~, ~) app." + name + "()";
                case 2, text = "@(~, event) app." + name + "(event)";
                case 3, text = "@app." + name;
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
