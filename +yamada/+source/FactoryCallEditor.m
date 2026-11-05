classdef FactoryCallEditor
    % FactoryCallEditor Insert owned name-value tokens without rebuilding a call.
    %   Existing arguments, expressions, comments, and delimiters retain their
    %   original text. The caller proves eligibility and chooses a token slot.

    methods (Static)
        function edits = remove(statement, settings)
            % remove Delete owned argument code while preserving comments and continuations.
            arguments (Input)
                statement (1, 1) yamada.source.SourceStatement
                settings yamada.model.PropertySetting
            end
            arguments (Output)
                edits struct
            end
            offsets = zeros(1, 0);
            code = char(statement.Text);
            for setting = settings
                pair = setting.PairSpan;
                first = find(statement.CodeOffsets == pair.StartOffset, 1);
                last = find(statement.CodeOffsets == pair.EndOffset, 1);
                if isempty(first) || isempty(last) || setting.Method ~= "nameValue"
                    error("yamada:FactoryCallEditor:UnsafeSource", "The removed argument has no proven token ownership.");
                end
                preceding = first - 1;
                while preceding > 0 && isspace(code(preceding)), preceding = preceding - 1; end
                if preceding == 0 || code(preceding) ~= ','
                    error("yamada:FactoryCallEditor:UnsafeSource", "The argument delimiter cannot be proven.");
                end
                tokens = first:last;
                tokens = tokens(~isspace(code(tokens)));
                offsets = [offsets statement.CodeOffsets([preceding tokens])]; %#ok<AGROW>
            end
            % Separate code runs leave every unmapped comment byte in the source.
            offsets = unique(offsets);
            edits = struct("Start", {}, "End", {}, "Text", {});
            if isempty(offsets), return, end
            starts = [1 find(diff(offsets) > 1) + 1];
            stops = [starts(2:end) - 1 numel(offsets)];
            for index = 1:numel(starts)
                edits(end + 1) = struct("Start", offsets(starts(index)), ...
                    "End", offsets(stops(index)), "Text", ""); %#ok<AGROW>
            end
        end

        function edit = insert(source, statement, entry, style, before)
            % insert Add one pair before an existing named argument or the closing parenthesis.
            arguments (Input)
                source (1, 1) string
                statement (1, 1) yamada.source.SourceStatement
                entry (1, 1) yamada.model.PropertyEntry
                style (1, 1) yamada.model.PropertySetting
                before yamada.model.PropertySetting = yamada.model.PropertySetting.empty
            end
            arguments (Output)
                edit (1, 1) struct
            end

            % Only direct property names can be expressed as constructor keys.
            if isempty(regexp(entry.Path, '^[A-Za-z]\w*$', 'once')) || ...
                    entry.ValueKind ~= "literal" || isempty(statement.CodeOffsets)
                error("yamada:FactoryCallEditor:UnsafeSource", "The new argument has no proven literal token representation.");
            end
            value = yamada.source.LiteralEncoder.encode(entry.LiteralValue);
            if style.Syntax == "nameEquals"
                pair = entry.Path + "=" + value;
            elseif style.Syntax == "quotedPair" && ~isempty(style.NameSpan) && style.NameSpan.isKnown()
                quote = extractBetween(source, style.NameSpan.StartOffset, style.NameSpan.StartOffset);
                if quote == "'"
                    name = yamada.source.LiteralEncoder.encode(char(entry.Path));
                else
                    name = yamada.source.LiteralEncoder.encode(entry.Path);
                end
                pair = name + ", " + value;
            else
                error("yamada:FactoryCallEditor:UnsafeSource", "Constructor argument syntax is not proven.");
            end

            % A token insertion leaves every original byte, including trailing trivia, intact.
            if isempty(before)
                text = char(statement.Text);
                closing = find(text == ')', 1, 'last');
                if isempty(closing)
                    error("yamada:FactoryCallEditor:UnsafeSource", "The factory closing token is missing.");
                end
                offset = statement.CodeOffsets(closing) - 1;
                inserted = ", " + pair;
            else
                if isempty(before.PairSpan) || ~before.PairSpan.isKnown()
                    error("yamada:FactoryCallEditor:UnsafeSource", "The following argument has no token ownership.");
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
