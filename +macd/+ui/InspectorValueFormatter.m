classdef InspectorValueFormatter
    % InspectorValueFormatter Render property values safely for inspector cells.
    %   This static utility shows source expressions unchanged and encodes only
    %   conservative MATLAB literals. Values outside that literal subset are
    %   represented by a non-editing-safe, type-oriented placeholder.

    methods (Static)
        function text = format(entry)
            % format Convert one property entry to safe, display-only text.
            arguments (Input)
                entry (1, 1) macd.model.PropertyEntry
            end
            arguments (Output)
                text (1, 1) string
            end

            % Preserve nonliteral source without evaluating or reformatting it.
            if entry.ValueKind ~= "literal"
                text = entry.SourceExpression;
                return
            end

            % Reuse source encoding while keeping unsupported values nonblocking.
            try
                text = macd.source.LiteralEncoder.encode(entry.LiteralValue);
            catch exception
                if exception.identifier ~= "macd:LiteralEncoder:UnsupportedValue"
                    rethrow(exception)
                end
                text = "<unsupported: " + ...
                    macd.ui.InspectorValueFormatter.describeType(entry.LiteralValue) + ">";
            end
        end
    end

    methods (Static, Access = private)
        function description = describeType(value)
            % describeType Return a concise type label for an unsupported literal.
            arguments (Input)
                value
            end
            arguments (Output)
                description (1, 1) string
            end

            % Distinguish the string arrays that cannot use scalar literal syntax.
            if isstring(value) && ~isscalar(value)
                description = "string array";
            elseif ischar(value) && ~isrow(value)
                description = "char array";
            elseif iscell(value) && ~isrow(value)
                description = "cell array";
            else
                description = string(class(value));
            end
        end
    end
end

%{
MatlabAppClassDesigner - Safe inspector rendering for unsupported literals.
Copyright (C) 2026 MatlabAppClassDesigner contributors

This file is part of MatlabAppClassDesigner.

MatlabAppClassDesigner is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

MatlabAppClassDesigner is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with MatlabAppClassDesigner. If not, see <https://www.gnu.org/licenses/>.
%}
