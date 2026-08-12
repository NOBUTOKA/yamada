classdef LiteralEncoder
    % LiteralEncoder Encode a conservative subset of MATLAB literal values.
    %   This static utility converts supported in-memory values to reviewable
    %   MATLAB syntax. It rejects expressions and unsupported types rather than
    %   evaluating or approximating them.

    methods (Static)
        function text = encode(value)
            % encode Convert a supported value to a safe MATLAB literal.
            arguments (Input)
                value
            end
            arguments (Output)
                text string
            end

            % Encode each supported family without evaluating expressions.
            if ischar(value) && isempty(value)
                text = "''";
            elseif ischar(value) && isrow(value)
                escaped = strrep(value, '''', '''''');
                text = "'" + string(escaped) + "'";
            elseif isstring(value) && isscalar(value)
                % Character conversion is confined to escaping generated syntax.
                escaped = strrep(char(string(value)), '"', '""');
                text = string(['"' escaped '"']);
            elseif ischar(value) && ismatrix(value)
                rows = strings(1, size(value, 1));
                for row = 1:size(value, 1)
                    rows(row) = "'" + string(strrep(value(row, :), '''', '''''')) + "'";
                end
                text = "[" + strjoin(rows, "; ") + "]";
            elseif isnumeric(value) && isreal(value) && ismatrix(value)
                text = string(mat2str(value, 17));
            elseif islogical(value) && ismatrix(value)
                text = string(mat2str(value));
            elseif iscell(value) && isrow(value)
                % Recursively encode row-cell elements used by UI properties.
                encoded = strings(1, numel(value));
                for index = 1:numel(value)
                    encoded(index) = macd.source.LiteralEncoder.encode(value{index});
                end
                text = "{" + strjoin(encoded, ", ") + "}";
            else
                % Refuse values that cannot be round-tripped conservatively.
                error("macd:LiteralEncoder:UnsupportedValue", ...
                    "Value cannot be represented as a safe MATLAB literal.");
            end
        end
    end
end

%{
Copyright (C) 2026 Nobuto Kaitoh

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
