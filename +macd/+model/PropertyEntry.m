classdef PropertyEntry < handle
    % PropertyEntry Retain one component property in the intermediate model.
    %   This handle class distinguishes editable literals from unevaluated,
    %   source-backed expressions and retains related diagnostics and metadata.
    %   It does not validate component-specific property support.

    properties (SetAccess = private)
        % Path - Full component property path, including nested property names.
        Path string = ""
        % ValueKind - Storage form: unset, literal, or expression.
        ValueKind string {mustBeMember(ValueKind, ["unset", "literal", "expression"])} = "unset"
        % LiteralValue - Safely editable literal value when ValueKind is literal.
        LiteralValue = []
        % SourceExpression - Unevaluated MATLAB expression retained from source.
        SourceExpression string = ""
        % IsEditable - Whether the editor may replace the stored value.
        IsEditable logical = true
        % Origin - Provenance label such as generated or parsed.
        Origin string = "generated"
    end

    properties
        % SourceSpan - Optional macd.model.SourceSpan for the source assignment.
        SourceSpan macd.model.SourceSpan = macd.model.SourceSpan.empty
        % Diagnostics - Diagnostics associated with this property value.
        Diagnostics macd.model.Diagnostic = macd.model.Diagnostic.empty
        % Metadata - Extensible property data not interpreted by the core model.
        Metadata struct = struct()
    end

    methods
        function obj = PropertyEntry(path, value, origin)
            % PropertyEntry Create a literal component property entry.
            arguments (Input)
                path string = ""
                value = []
                origin string = "generated"
            end
            arguments (Output)
                obj (1, 1) macd.model.PropertyEntry
            end

            % Preserve property defaults for the no-input constructor.
            if nargin == 0
                return
            end

            % Store a new entry as an editable literal by default.
            obj.Path = path;
            obj.ValueKind = "literal";
            obj.LiteralValue = value;
            obj.Origin = origin;
        end

        function setLiteral(obj, value)
            % setLiteral Replace this entry with a safely representable value.
            arguments (Input)
                obj (1, 1) macd.model.PropertyEntry
                value
            end

            % Clear any prior source expression when the literal is edited.
            obj.ValueKind = "literal";
            obj.LiteralValue = value;
            obj.SourceExpression = "";
        end

        function setSourceExpression(obj, expression)
            % setSourceExpression Retain an unevaluated expression as read-only.
            arguments (Input)
                obj (1, 1) macd.model.PropertyEntry
                expression string
            end

            % Source expressions must never be treated as editable literals.
            obj.ValueKind = "expression";
            obj.LiteralValue = [];
            obj.SourceExpression = expression;
            obj.IsEditable = false;
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
