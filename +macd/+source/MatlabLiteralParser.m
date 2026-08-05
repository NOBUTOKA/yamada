classdef MatlabLiteralParser
    % MatlabLiteralParser Parse a conservative non-evaluating literal subset.
    %   This static utility accepts scalar text, logicals, real numeric and string
    %   matrices, and row cell arrays of supported literals. All other expressions are
    %   rejected so callers can retain them as source-backed text.
    %
    %   Example:
    %       [value, isLiteral] = macd.source.MatlabLiteralParser.parse("[1 2]");

    methods (Static)
        function [value, isLiteral] = parse(text)
            % parse Convert a supported MATLAB literal without evaluating source.
            arguments (Input)
                text string
            end
            arguments (Output)
                value
                isLiteral logical
            end

            % Normalize whitespace before checking the limited literal grammar.
            value = [];
            isLiteral = false;
            source = char(strtrim(text));
            if isempty(source)
                return
            end

            % Parse quoted text before recognizing operators or delimiters.
            if source(1) == '''' && source(end) == '''' && numel(source) >= 2
                value = string(strrep(source(2:end - 1), '''''', ''''));
                isLiteral = true;
                return
            end
            if source(1) == '"' && source(end) == '"' && numel(source) >= 2
                value = string(strrep(source(2:end - 1), '""', '"'));
                isLiteral = true;
                return
            end

            % Handle scalar logical values without accepting arbitrary names.
            if strcmp(source, 'true')
                value = true;
                isLiteral = true;
                return
            end
            if strcmp(source, 'false')
                value = false;
                isLiteral = true;
                return
            end

            % Support numeric scalar and bracketed real matrix forms.
            if macd.source.MatlabLiteralParser.isNumber(source)
                value = str2double(source);
                isLiteral = true;
                return
            end
            if source(1) == '[' && source(end) == ']'
                [value, isLiteral] = macd.source.MatlabLiteralParser.parseMatrix( ...
                    source(2:end - 1));
                if ~isLiteral
                    [value, isLiteral] = macd.source.MatlabLiteralParser.parseStringMatrix( ...
                        source(2:end - 1));
                end
                return
            end
            if source(1) == '{' && source(end) == '}'
                [value, isLiteral] = macd.source.MatlabLiteralParser.parseCell( ...
                    source(2:end - 1));
            end
        end
    end

    methods (Static, Access = private)
        function result = isNumber(text)
            % isNumber Return true for one finite real decimal representation.
            arguments (Input)
                text char
            end
            arguments (Output)
                result logical
            end

            % Keep the grammar explicit so str2double never receives an expression.
            pattern = '^[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?$';
            result = ~isempty(regexp(text, pattern, 'once'));
        end

        function [value, isLiteral] = parseMatrix(text)
            % parseMatrix Parse a rectangular real matrix with safe separators.
            arguments (Input)
                text char
            end
            arguments (Output)
                value
                isLiteral logical
            end

            % Parse rows independently and require a consistent column count.
            value = [];
            isLiteral = false;
            rows = strsplit(text, ';');
            rowValues = cell(1, numel(rows));
            numberPattern = '[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?';
            columnCount = [];
            for index = 1:numel(rows)
                row = strtrim(rows{index});
                tokens = regexp(row, numberPattern, 'match');
                remainder = regexprep(row, numberPattern, '');
                if isempty(tokens) || ~isempty(regexprep(remainder, '[\s,]', ''))
                    return
                end
                values = str2double(tokens);
                if any(~isfinite(values))
                    return
                end
                if isempty(columnCount)
                    columnCount = numel(values);
                elseif numel(values) ~= columnCount
                    return
                end
                rowValues{index} = values;
            end

            % Concatenate only after every row satisfies the safe grammar.
            value = vertcat(rowValues{:});
            isLiteral = true;
        end

        function [value, isLiteral] = parseCell(text)
            % parseCell Parse a row cell array of recursively supported literals.
            arguments (Input)
                text char
            end
            arguments (Output)
                value cell
                isLiteral logical
            end

            % Split only on top-level commas so quoted text stays intact.
            value = {};
            isLiteral = false;
            if isempty(strtrim(text))
                isLiteral = true;
                return
            end
            elements = macd.source.MatlabLiteralParser.splitTopLevel(text, ',');
            value = cell(1, numel(elements));
            for index = 1:numel(elements)
                [element, isElementLiteral] = macd.source.MatlabLiteralParser.parse( ...
                    string(elements{index}));
                if ~isElementLiteral
                    value = {};
                    return
                end
                value{index} = element;
            end
            isLiteral = true;
        end

        function [value, isLiteral] = parseStringMatrix(text)
            % parseStringMatrix Parse a rectangular matrix of quoted text literals.
            arguments (Input)
                text char
            end
            arguments (Output)
                value string
                isLiteral logical
            end

            % Keep each element quoted so no identifiers or expressions are accepted.
            value = strings(0, 0);
            isLiteral = false;
            rows = macd.source.MatlabLiteralParser.splitTopLevel(text, ';');
            rowValues = cell(1, numel(rows));
            columnCount = [];
            for rowIndex = 1:numel(rows)
                elements = macd.source.MatlabLiteralParser.splitTopLevel(rows{rowIndex}, ',');
                if isscalar(elements)
                    elements = regexp(strtrim(rows{rowIndex}), '(?:''(?:[^'']|'''')*''|"(?:[^"]|"")*")', ...
                        'match');
                    remainder = regexprep(strtrim(rows{rowIndex}), ...
                        '(?:''(?:[^'']|'''')*''|"(?:[^"]|"")*")', '');
                    if isempty(elements) || ~isempty(regexprep(remainder, '\s', ''))
                        return
                    end
                end
                values = strings(1, numel(elements));
                for elementIndex = 1:numel(elements)
                    [element, isElementLiteral] = macd.source.MatlabLiteralParser.parse( ...
                        string(elements{elementIndex}));
                    if ~isElementLiteral || ~isstring(element) || ~isscalar(element)
                        return
                    end
                    values(elementIndex) = element;
                end
                if isempty(columnCount)
                    columnCount = numel(values);
                elseif numel(values) ~= columnCount
                    return
                end
                rowValues{rowIndex} = values;
            end

            % Concatenate only after every row is composed entirely of text literals.
            value = vertcat(rowValues{:});
            isLiteral = true;
        end

        function elements = splitTopLevel(text, separator)
            % splitTopLevel Split text while ignoring quoted and nested regions.
            arguments (Input)
                text char
                separator char
            end
            arguments (Output)
                elements cell
            end

            % Track quotes and delimiters before accepting a separator boundary.
            elements = {};
            startOffset = 1;
            parenDepth = 0;
            bracketDepth = 0;
            braceDepth = 0;
            inCharacterVector = false;
            inString = false;
            index = 1;
            while index <= numel(text)
                character = text(index);
                nextCharacter = char(0);
                if index < numel(text)
                    nextCharacter = text(index + 1);
                end
                if character == '''' && ~inString
                    if inCharacterVector && nextCharacter == ''''
                        index = index + 2;
                        continue
                    end
                    inCharacterVector = ~inCharacterVector;
                elseif character == '"' && ~inCharacterVector
                    if inString && nextCharacter == '"'
                        index = index + 2;
                        continue
                    end
                    inString = ~inString;
                elseif ~inCharacterVector && ~inString
                    switch character
                        case '('
                            parenDepth = parenDepth + 1;
                        case ')'
                            parenDepth = max(parenDepth - 1, 0);
                        case '['
                            bracketDepth = bracketDepth + 1;
                        case ']'
                            bracketDepth = max(bracketDepth - 1, 0);
                        case '{'
                            braceDepth = braceDepth + 1;
                        case '}'
                            braceDepth = max(braceDepth - 1, 0);
                    end
                end
                if character == separator && ~inCharacterVector && ~inString && ...
                        parenDepth == 0 && bracketDepth == 0 && braceDepth == 0
                    elements{end + 1} = text(startOffset:index - 1); %#ok<AGROW>
                    startOffset = index + 1;
                end
                index = index + 1;
            end
            elements{end + 1} = text(startOffset:end);
        end
    end
end

%{
MatlabAppClassDesigner - Conservative non-evaluating MATLAB literal parser.
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
