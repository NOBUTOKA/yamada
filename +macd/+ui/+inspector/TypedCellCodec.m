classdef TypedCellCodec
    % TypedCellCodec Parse and format finite literal text in native table cells.
    %   This static adapter preserves supported scalar numeric, logical, and
    %   string values while reporting an exact malformed-cell coordinate. It is
    %   UI-independent and intentionally does not validate a component contract.

    methods (Static)
        function [values, errorRow, errorColumn, message] = parse(data, allowPlainText)
            % parse Decode a string-like table matrix into typed cell values.
            arguments (Input)
                data
                allowPlainText (1, 1) logical = false
            end
            arguments (Output)
                values cell
                errorRow (1, 1) double
                errorColumn (1, 1) double
                message (1, 1) string
            end

            source = string(data);
            values = cell(size(source));
            errorRow = 0;
            errorColumn = 0;
            message = "";
            for row = 1:size(source, 1)
                for column = 1:size(source, 2)
                    text = source(row, column);
                    if strlength(strtrim(text)) == 0
                        values{row, column} = [];
                        continue
                    end
                    [value, isLiteral] = macd.source.MatlabLiteralParser.parse(text);
                    if ~isLiteral
                        if allowPlainText && macd.ui.inspector.TypedCellCodec.isPlainText(text)
                            value = text;
                        else
                            errorRow = row;
                            errorColumn = column;
                            message = "This cell has an invalid MATLAB literal.";
                            return
                        end
                    end
                    values{row, column} = value;
                end
            end
        end

        function value = packVector(values)
            % packVector Preserve homogeneous scalar vector types where they are safe.
            arguments (Input)
                values cell
            end
            arguments (Output)
                value
            end

            values = reshape(values, 1, []);
            if all(cellfun(@(item) isnumeric(item) && isscalar(item), values))
                value = cell2mat(values);
            elseif all(cellfun(@(item) islogical(item) && isscalar(item), values))
                value = logical(cell2mat(values));
            elseif all(cellfun(@(item) isstring(item) && isscalar(item), values))
                value = string([values{:}]);
            else
                value = values;
            end
        end

        function value = packMatrix(values)
            % packMatrix Preserve homogeneous scalar matrix types where safe after table-cell parsing.
            arguments (Input)
                values cell
            end
            arguments (Output)
                value
            end

            if isempty(values)
                value = [];
            elseif all(cellfun(@(item) isnumeric(item) && isscalar(item), values), "all")
                value = cell2mat(values);
            elseif all(cellfun(@(item) islogical(item) && isscalar(item), values), "all")
                value = logical(cell2mat(values));
            elseif all(cellfun(@(item) isstring(item) && isscalar(item), values), "all")
                value = strings(size(values));
                for index = 1:numel(values)
                    value(index) = values{index};
                end
            else
                value = values;
            end
        end

        function kind = inferTableDataKind(value)
            % inferTableDataKind Classify imported UITable Data for the explicit editor selector.
            arguments (Input)
                value
            end
            arguments (Output)
                kind (1, 1) string
            end

            if isempty(value)
                kind = "cell";
            elseif islogical(value)
                kind = "logical";
            elseif isnumeric(value)
                kind = "numeric";
            elseif isstring(value)
                kind = "string";
            elseif iscell(value) && all(cellfun(@(item) ischar(item) && isrow(item), value), "all")
                kind = "charCell";
            elseif iscell(value)
                kind = "cell";
            else
                kind = "cell";
            end
        end

        function [value, errorRow, errorColumn, message] = parseTableMatrix(data, kind)
            % parseTableMatrix Decode table cells according to one explicit documented Data representation.
            arguments (Input)
                data
                kind (1, 1) string
            end
            arguments (Output)
                value
                errorRow (1, 1) double
                errorColumn (1, 1) double
                message (1, 1) string
            end

            source = string(data);
            values = cell(size(source));
            errorRow = 0;
            errorColumn = 0;
            message = "";
            for row = 1:size(source, 1)
                for column = 1:size(source, 2)
                    [cellValue, isValid, cellMessage] = ...
                        macd.ui.inspector.TypedCellCodec.parseTableCell(source(row, column), kind);
                    if ~isValid
                        value = [];
                        errorRow = row;
                        errorColumn = column;
                        message = cellMessage;
                        return
                    end
                    values{row, column} = cellValue;
                end
            end
            value = macd.ui.inspector.TypedCellCodec.packTableMatrix(values, kind);
        end

        function text = literalText(value)
            % literalText Format one typed value without evaluating user text.
            arguments (Input)
                value
            end
            arguments (Output)
                text (1, 1) string
            end

            try
                text = macd.source.LiteralEncoder.encode(value);
            catch
                text = "<unsupported>";
            end
        end
    end

    methods (Static, Access = private)
        function [value, isValid, message] = parseTableCell(text, kind)
            % parseTableCell Decode one visible table cell for its selected output representation.
            isBlank = strlength(strtrim(text)) == 0;
            if isBlank
                switch kind
                    case "numeric"
                        value = NaN;
                    case "cell"
                        value = [];
                    case "logical"
                        value = false;
                    case "string"
                        value = "";
                    case "charCell"
                        value = '';
                    otherwise
                        value = [];
                end
                isValid = true;
                message = "";
                return
            end

            if kind == "charCell"
                [value, isLiteral] = macd.source.MatlabLiteralParser.parse(text);
                if isLiteral && ischar(value) && isrow(value)
                    % Retain explicitly quoted character text without its delimiters.
                elseif isLiteral && isstring(value) && isscalar(value)
                    value = char(value);
                else
                    % Interpret numeric-looking and all other unquoted text as character data.
                    value = char(text);
                end
                isValid = true;
                message = "";
                return
            end

            [value, isLiteral] = macd.source.MatlabLiteralParser.parse(text);
            if ~isLiteral && macd.ui.inspector.TypedCellCodec.isPlainText(text)
                value = text;
                isLiteral = true;
            end
            if ~isLiteral
                isValid = false;
                message = "This cell has an invalid MATLAB literal.";
                return
            end
            switch kind
                case "numeric"
                    isValid = isnumeric(value) && isscalar(value);
                    message = "Numeric cells must contain a scalar number.";
                case "logical"
                    isValid = islogical(value) && isscalar(value);
                    message = "Logical cells must contain true or false.";
                case "string"
                    if ischar(value) && isrow(value)
                        value = string(value);
                    end
                    isValid = isstring(value) && isscalar(value);
                    message = "String cells must contain text.";
                case "cell"
                    if isstring(value) && isscalar(value)
                        value = char(value);
                    end
                    isValid = isempty(value) || (isnumeric(value) && isscalar(value)) || ...
                        (islogical(value) && isscalar(value)) || (ischar(value) && isrow(value));
                    message = "Cell values must be scalar numeric, logical, char, or [].";
                otherwise
                    isValid = false;
                    message = "Select a supported table data type.";
            end
        end

        function value = packTableMatrix(values, kind)
            % packTableMatrix Emit the documented UITable Data representation selected by the user.
            if isempty(values)
                value = [];
                return
            end
            switch kind
                case "numeric"
                    value = cell2mat(values);
                case "logical"
                    value = logical(cell2mat(values));
                case "string"
                    value = strings(size(values));
                    for index = 1:numel(values)
                        value(index) = values{index};
                    end
                case {"cell", "charCell"}
                    value = values;
                otherwise
                    value = values;
            end
        end

        function result = isPlainText(value)
            % isPlainText Identify unquoted text that intentionally becomes a string scalar.
            result = ~contains(value, ["'", '"', "[", "]", "{", "}"]);
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
