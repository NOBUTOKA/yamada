classdef FactoryCallEditor
    % FactoryCallEditor Insert owned name-value tokens without rebuilding a call.
    %   Existing arguments, expressions, comments, and delimiters retain their
    %   original text. The caller proves eligibility and chooses a token slot.

    methods (Static)
        function edit = insert(source, statement, entry, style, before)
            % insert Add one pair before an existing named argument or the closing parenthesis.
            arguments (Input)
                source (1, 1) string
                statement (1, 1) macd.source.SourceStatement
                entry (1, 1) macd.model.PropertyEntry
                style (1, 1) macd.model.PropertySetting
                before macd.model.PropertySetting = macd.model.PropertySetting.empty
            end
            arguments (Output)
                edit (1, 1) struct
            end

            % Only direct property names can be expressed as constructor keys.
            if isempty(regexp(entry.Path, '^[A-Za-z]\w*$', 'once')) || ...
                    entry.ValueKind ~= "literal" || isempty(statement.CodeOffsets)
                error("macd:FactoryCallEditor:UnsafeSource", "The new argument has no proven literal token representation.");
            end
            value = macd.source.LiteralEncoder.encode(entry.LiteralValue);
            if style.Syntax == "nameEquals"
                pair = entry.Path + "=" + value;
            elseif style.Syntax == "quotedPair" && ~isempty(style.NameSpan) && style.NameSpan.isKnown()
                quote = extractBetween(source, style.NameSpan.StartOffset, style.NameSpan.StartOffset);
                if quote == "'"
                    name = macd.source.LiteralEncoder.encode(char(entry.Path));
                else
                    name = macd.source.LiteralEncoder.encode(entry.Path);
                end
                pair = name + ", " + value;
            else
                error("macd:FactoryCallEditor:UnsafeSource", "Constructor argument syntax is not proven.");
            end

            % A token insertion leaves every original byte, including trailing trivia, intact.
            if isempty(before)
                text = char(statement.Text);
                closing = find(text == ')', 1, 'last');
                if isempty(closing)
                    error("macd:FactoryCallEditor:UnsafeSource", "The factory closing token is missing.");
                end
                offset = statement.CodeOffsets(closing) - 1;
                inserted = ", " + pair;
            else
                if isempty(before.PairSpan) || ~before.PairSpan.isKnown()
                    error("macd:FactoryCallEditor:UnsafeSource", "The following argument has no token ownership.");
                end
                offset = before.PairSpan.StartOffset - 1;
                inserted = pair + ", ";
            end
            edit = struct("Start", offset + 1, "End", offset, "Text", inserted);
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
