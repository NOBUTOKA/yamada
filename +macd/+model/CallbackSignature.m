classdef CallbackSignature
    % CallbackSignature Validate data-only event type metadata for generated handlers.
    %   An empty class name leaves event untyped. This value never loads app classes
    %   or evaluates validation functions, defaults, or callback bodies.
    properties (SetAccess = private)
        % ClassName - Reviewed event class, empty when no safe type is established.
        ClassName string = ""
        % Shape - Reviewed two-dimensional size, empty when no size is established.
        Shape double = []
    end
    methods
        function obj = CallbackSignature(contract)
            % CallbackSignature Read optional reviewed metadata without inventing a common base type.
            arguments (Input)
                contract (1, 1) struct = struct()
            end
            arguments (Output)
                obj (1, 1) macd.model.CallbackSignature
            end
            if isempty(fieldnames(contract)), return, end
            macd.model.CallbackSignature.fields(contract, "eventArgument");
            argument = contract.eventArgument;
            macd.model.CallbackSignature.fields(argument, ["className", "shape"]);
            value = argument.className;
            if ~(isstring(value) && isscalar(value) && ~ismissing(value) || ischar(value) && (isrow(value) || isempty(value)))
                error("macd:CallbackSignature:InvalidContract", "Event class must be scalar text.");
            end
            name = string(value);
            shape = argument.shape;

            % Reject malformed supplied contracts rather than silently dropping validation.
            valid = isnumeric(shape) && isreal(shape) && (isempty(shape) || ...
                isvector(shape) && numel(shape) == 2 && all(isfinite(shape)) && ...
                all(shape >= 0) && all(shape == fix(shape)));
            if name == ""
                valid = valid && isempty(shape);
            else
                valid = valid && ~isempty(regexp(name, '^[A-Za-z]\w*(?:\.[A-Za-z]\w*)*$', 'once'));
                for part = split(name, ".")'
                    valid = valid && isvarname(part) && ~iskeyword(part);
                end
            end
            if ~valid
                error("macd:CallbackSignature:InvalidContract", "Invalid event class or shape.");
            end
            obj.ClassName = name;
            obj.Shape = reshape(double(shape), 1, []);
        end

        function line = argumentLine(obj)
            % argumentLine Format only the reviewed class and optional event size.
            arguments (Input)
                obj (1, 1) macd.model.CallbackSignature
            end
            arguments (Output)
                line (1, 1) string
            end
            line = "event";
            if obj.ClassName == "", return, end
            if ~isempty(obj.Shape)
                line = line + " (" + strjoin(string(obj.Shape), ", ") + ")";
            end
            line = line + " " + obj.ClassName;
        end
    end
    methods (Static, Access = private)
        function fields(value, expected)
            % fields Require exact data-only fields at each contract nesting level.
            arguments (Input)
                value
                expected string
            end
            if ~isstruct(value) || ~isscalar(value) || ...
                    ~isequal(sort(string(fieldnames(value))), sort(expected(:)))
                error("macd:CallbackSignature:InvalidContract", "Invalid callback signature fields.");
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
