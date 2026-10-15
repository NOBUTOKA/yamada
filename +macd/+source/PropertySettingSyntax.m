classdef PropertySettingSyntax
    % PropertySettingSyntax Recover explicit setting tokens with original offsets.
    %   This utility shares the lexical scanner's code-to-source mapping. It
    %   recognizes factory arguments and assignments without evaluating code.

    methods (Static)
        function [parent, factoryArguments, settings, skipped, supported] = factory(statement, definition, snapshotId)
            % factory Parse positional arguments and both name-value argument spellings.
            arguments (Input)
                statement (1, 1) macd.source.SourceStatement
                definition (1, 1) macd.model.ComponentDefinition
                snapshotId (1, 1) string
            end
            arguments (Output)
                parent (1, 1) string
                factoryArguments cell
                settings macd.model.PropertySetting
                skipped (1, :) string
                supported (1, 1) logical
            end

            parent = "";
            factoryArguments = {};
            settings = macd.model.PropertySetting.empty;
            skipped = strings(1, 0);
            supported = true;
            text = char(statement.Text);
            opening = find(text == '(', 1);
            ranges = macd.source.PropertySettingSyntax.argumentRanges(text, opening + 1, numel(text) - 1);
            index = 1;
            while index <= size(ranges, 1)
                first = ranges(index, 1);
                last = ranges(index, 2);
                token = string(text(first:last));
                parentToken = regexp(token, '^app\.(\w+)$', 'tokens', 'once');
                if index == 1 && ~isempty(parentToken)
                    parent = string(parentToken{1});
                    index = index + 1;
                    continue
                end

                % Named syntax is recognized before attempting safe positional literals.
                named = regexp(token, '^(?<name>[A-Za-z]\w*)\s*=(?!=)', 'names', 'once');
                if ~isempty(named)
                    path = string(named.name);
                    separator = first + find(text(first:last) == '=', 1) - 1;
                    nameLast = first + strlength(path) - 1;
                    valueFirst = separator + 1;
                    while valueFirst <= last && isspace(text(valueFirst)), valueFirst = valueFirst + 1; end
                    nameSpan = macd.source.PropertySettingSyntax.span(statement, first, nameLast);
                    syntax = "nameEquals";
                    consumed = 1;
                else
                    [literal, safe] = macd.source.MatlabLiteralParser.parse(token);
                    if ~safe
                        supported = false;
                        return
                    end
                    scalarText = (isstring(literal) && isscalar(literal)) || ...
                        (ischar(literal) && isrow(literal));
                    isName = scalarText && ~any(definition.SupportedStyles == string(literal)) && ...
                        index < size(ranges, 1);
                    if ~isName
                        factoryArguments{end + 1} = literal; %#ok<AGROW>
                        index = index + 1;
                        continue
                    end
                    path = string(literal);
                    nameSpan = macd.source.PropertySettingSyntax.span(statement, first, last);
                    valueFirst = ranges(index + 1, 1);
                    last = ranges(index + 1, 2);
                    syntax = "quotedPair";
                    consumed = 2;
                end

                % Unsupported values retain their precise source ownership as expressions.
                valueText = string(text(valueFirst:last));
                [value, safe] = macd.source.MatlabLiteralParser.parse(valueText);
                property = definition.getProperty(path);
                location = struct("Method", "nameValue", "Syntax", syntax, ...
                    "SourceSpan", statement.Span, "NameSpan", nameSpan, ...
                    "ValueSpan", macd.source.PropertySettingSyntax.span(statement, valueFirst, last), ...
                    "PairSpan", macd.source.PropertySettingSyntax.span(statement, first, last), ...
                    "SourceSnapshotId", snapshotId, "IsEditable", ~isempty(property) && property.IsEditable);
                if ~safe, location.SourceExpression = valueText; end
                if safe && ~isempty(property)
                    location.FactoryArgumentIndex = numel(factoryArguments) + 2;
                    factoryArguments(end + 1:end + 2) = {path, value};
                else
                    skipped(end + 1) = path; %#ok<AGROW>
                end
                settings(end + 1) = macd.model.PropertySetting(path, value, location); %#ok<AGROW>
                index = index + consumed;
            end

            % Duplicate keys in one constructor are not treated as ordinary sequential writes.
            paths = string({settings.Path});
            for index = 1:numel(settings)
                if nnz(paths == paths(index)) > 1
                    record = settings(index).toStruct();
                    record.Location.IsCertain = false;
                    settings(index) = macd.model.PropertySetting(record.Path, record.Value, record.Location);
                end
            end
        end

        function setting = assignment(statement, snapshotId, sequence, certain)
            % assignment Capture one direct component-property assignment and its value range.
            arguments (Input)
                statement (1, 1) macd.source.SourceStatement
                snapshotId (1, 1) string
                sequence (1, 1) double
                certain (1, 1) logical = true
            end
            arguments (Output)
                setting (1, 1) macd.model.PropertySetting
            end

            text = char(statement.Text);
            match = regexp(text, '^app\.\w+\.(?<path>[A-Za-z]\w*(?:\.[A-Za-z]\w*)*)\s*=', 'names', 'once');
            if isempty(match)
                error("macd:PropertySettingSyntax:InvalidAssignment", "Expected a direct property assignment.");
            end
            separator = find(text == '=', 1);
            valueFirst = separator + 1;
            while valueFirst <= numel(text) && isspace(text(valueFirst)), valueFirst = valueFirst + 1; end
            valueText = string(text(valueFirst:end));
            [value, safe] = macd.source.MatlabLiteralParser.parse(valueText);
            prefixEnd = regexp(text, '^app\.\w+\.', 'end', 'once');
            location = struct("Method", "assignment", "Syntax", "dot", ...
                "SourceSpan", statement.Span, "PairSpan", statement.Span, ...
                "ValueSpan", macd.source.PropertySettingSyntax.span(statement, valueFirst, numel(text)), ...
                "NameSpan", macd.source.PropertySettingSyntax.span(statement, prefixEnd + 1, prefixEnd + strlength(match.path)), ...
                "SourceSnapshotId", snapshotId, "Sequence", sequence, "IsCertain", certain);
            if ~safe, location.SourceExpression = valueText; end
            setting = macd.model.PropertySetting(string(match.path), value, location);
        end
    end

    methods (Static, Access = private)
        function result = span(statement, first, last)
            % span Translate normalized token offsets into the original source snapshot.
            arguments (Input)
                statement (1, 1) macd.source.SourceStatement
                first (1, 1) double
                last (1, 1) double
            end
            arguments (Output)
                result (1, 1) macd.model.SourceSpan
            end

            if isempty(statement.CodeOffsets) || first > last
                error("macd:PropertySettingSyntax:MissingOffsets", "Token ownership requires scanner-provided offsets.");
            end
            result = macd.model.SourceSpan(statement.CodeOffsets(first), statement.CodeOffsets(last));
        end

        function ranges = argumentRanges(text, first, last)
            % argumentRanges Split top-level arguments while retaining normalized token ranges.
            arguments (Input)
                text char
                first (1, 1) double
                last (1, 1) double
            end
            arguments (Output)
                ranges (:, 2) double
            end

            ranges = zeros(0, 2);
            start = first;
            depth = 0;
            quote = char(0);
            index = first;
            while index <= last
                character = text(index);
                if quote ~= char(0)
                    if character == quote
                        if index < last && text(index + 1) == quote
                            index = index + 2;
                            continue
                        end
                        quote = char(0);
                    end
                elseif character == '"' || character == ''''
                    transpose = character == '''' && index > first && ...
                        ~isempty(regexp(text(index - 1), '[\w\]\)}."]', 'once'));
                    if ~transpose, quote = character; end
                elseif any(character == '([{')
                    depth = depth + 1;
                elseif any(character == ')]}')
                    depth = depth - 1;
                elseif character == ',' && depth == 0
                    ranges(end + 1, :) = [start index - 1]; %#ok<AGROW>
                    start = index + 1;
                end
                index = index + 1;
            end
            ranges(end + 1, :) = [start last];
            for index = size(ranges, 1):-1:1
                left = ranges(index, 1);
                right = ranges(index, 2);
                while left <= right && isspace(text(left)), left = left + 1; end
                while right >= left && isspace(text(right)), right = right - 1; end
                if left > right, ranges(index, :) = []; else, ranges(index, :) = [left right]; end
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
