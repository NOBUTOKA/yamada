classdef SourceFormatting
    % SourceFormatting Preserve local whitespace around owned source edits.
    %   This utility recovers line indentation and removes vacated source lines.
    %   It preserves comments, inline statements, and unrelated blank lines.

    methods (Static)
        function edits = separateLiteralComponents(source, edits, analysis, name)
            % separateLiteralComponents Format known emitted assignments from indexed neighbors without lexical scanning.
            arguments (Input)
                source (1, 1) string
                edits struct
                analysis (1, 1) macd.source.SourceAnalysis
                name (1, :) string
            end
            arguments (Output)
                edits struct
            end
            assert(analysis.matches(source));
            edits = macd.source.CallbackSourceEdits.combineInsertions(edits);
            for index = 1:numel(edits), edits(index).Text = string(edits(index).Text); end
            ending = string(newline);
            if contains(source, sprintf("\r\n")), ending = string(sprintf("\r\n")); end
            for index = find([edits.Start] > [edits.End])
                edit = edits(index);
                [before, after] = analysis.statementNeighbors(edit.End);
                if ~isempty(after) && analysis.Statements(after).Span.StartOffset < edit.Start, continue, end
                starts = zeros(1, 0); owners = strings(1, 0);
                for owner = name
                    offsets = strfind(edit.Text, "app." + owner + ".");
                    starts = [starts offsets]; owners = [owners repmat(owner, size(offsets))]; %#ok<AGROW>
                end
                if isempty(starts), continue, end
                [first, firstIndex] = min(starts); [~, lastIndex] = max(starts);
                firstOwner = owners(firstIndex); lastOwner = owners(lastIndex);
                last = find(char(edit.Text) == ';', 1, 'last');
                assert(~isempty(last));
                addBefore = false; addAfter = false;
                if ~isempty(before) && strlength(analysis.Facts.ComponentName(before)) > 0 && analysis.Facts.ComponentName(before) ~= firstOwner
                    gap = extractBetween(source, analysis.Statements(before).Span.EndOffset + 1, edit.End) + extractBefore(edit.Text, first);
                    addBefore = ~isempty(regexp(gap, '^[ \t]*(?:%[^\r\n]*)?\r?\n[ \t]*$', 'once'));
                end
                if ~isempty(after) && strlength(analysis.Facts.ComponentName(after)) > 0 && analysis.Facts.ComponentName(after) ~= lastOwner
                    gap = extractAfter(edit.Text, last) + extractBetween(source, edit.Start, analysis.Statements(after).Span.StartOffset - 1);
                    addAfter = ~isempty(regexp(gap, '^[ \t]*(?:%[^\r\n]*)?\r?\n[ \t]*$', 'once'));
                end
                if addBefore, edit.Text = ending + edit.Text; end
                if addAfter, edit.Text = edit.Text + ending; end
                edits(index).Text = edit.Text;
            end
        end

        function edits = separateComponents(source, edits, analysis)
            % separateComponents Add one blank line at component boundaries touched by insertions.
            arguments (Input)
                source (1, 1) string
                edits struct
                analysis macd.source.SourceAnalysis = macd.source.SourceAnalysis.empty
            end
            arguments (Output)
                edits struct
            end
            insertions = find([edits.Start] > [edits.End] & string({edits.Text}) ~= "");
            if isempty(insertions), return, end
            if isempty(analysis)
                statements = macd.source.MatlabLexicalScanner.splitStatements(source);
                starts = zeros(1, 0); ends = starts;
                if ~isempty(statements)
                    spans = [statements.Span];
                    starts = [spans.StartOffset]; ends = [spans.EndOffset];
                end
            else
                assert(isscalar(analysis) && analysis.matches(source), ...
                    "macd:SourceFormatting:StaleAnalysis", "Formatting analysis must own the exact source.");
                statements = analysis.Statements;
            end
            ending = string(newline);
            if contains(source, sprintf("\r\n")) || ...
                    strlength(source) == 0 && any(contains(string({edits.Text}), sprintf("\r\n")))
                ending = string(sprintf("\r\n"));
            end
            pattern = '^app\.(\w+)(?:\.\w+)*\s*=(?!=)';
            % Include the neighboring statements so new blocks also separate from existing code.
            for index = insertions
                edit = edits(index);
                if isempty(analysis)
                    before = find(ends <= edit.End, 1, "last");
                    after = find(starts > edit.End, 1);
                else
                    [before, after] = analysis.statementNeighbors(edit.End);
                end
                prefix = "";
                suffix = "";
                if ~isempty(before)
                    prefix = extractBetween(source, statements(before).Span.StartOffset, edit.End);
                end
                if ~isempty(after)
                    suffix = extractBetween(source, edit.Start, statements(after).Span.EndOffset);
                end
                text = prefix + edit.Text + suffix;
                local = macd.source.MatlabLexicalScanner.splitStatements(text);
                offsets = zeros(1, 0);
                first = strlength(prefix) + 1;
                last = strlength(prefix) + strlength(edit.Text);
                for position = 2:numel(local)
                    previous = local(position - 1);
                    current = local(position);
                    previousInserted = previous.Span.StartOffset >= first && previous.Span.EndOffset <= last;
                    currentInserted = current.Span.StartOffset >= first && current.Span.EndOffset <= last;
                    if ~previousInserted && ~currentInserted, continue, end
                    left = regexp(previous.Text, pattern, 'tokens', 'once');
                    right = regexp(current.Text, pattern, 'tokens', 'once');
                    if isempty(left) || isempty(right) || string(left{1}) == string(right{1}), continue, end
                    gap = extractBetween(text, previous.Span.EndOffset + 1, current.Span.StartOffset - 1);
                    % Preserve inline code and comments; an existing blank line already separates blocks.
                    if isempty(regexp(gap, '^[ \t]*(?:%[^\r\n]*)?\r?\n[ \t]*$', 'once')), continue, end
                    indent = macd.source.SourceFormatting.indent(text, current.Span.StartOffset);
                    offset = current.Span.StartOffset - strlength(indent) - 1;
                    offset = min(max(offset, strlength(prefix)), strlength(prefix) + strlength(edit.Text));
                    offsets(end + 1) = offset - strlength(prefix); %#ok<AGROW>
                end
                % Apply only within the inserted text, leaving original source bytes untouched.
                for offset = sort(unique(offsets), "descend")
                    edit.Text = extractBefore(edit.Text, offset + 1) + ending + extractAfter(edit.Text, offset);
                end
                edits(index).Text = edit.Text;
            end
        end

        function result = indent(source, offset)
            % indent Return the leading spaces or tabs on the containing source line.
            arguments (Input)
                source (1, 1) string
                offset (1, 1) double {mustBePositive, mustBeInteger}
            end
            arguments (Output)
                result (1, 1) string
            end
            text = char(source);
            first = find(text(1:offset - 1) == newline, 1, "last");
            if isempty(first), first = 0; end
            result = string(regexp(text(first + 1:offset), '^[ \t]*', 'match', 'once'));
        end

        function edits = completeLineDeletions(source, edits)
            % completeLineDeletions Remove owned lines while preserving the preceding statement's CRLF boundary.
            arguments (Input)
                source (1, 1) string
                edits (1, :) struct
            end
            arguments (Output)
                edits (1, :) struct
            end
            edits = macd.source.SourceFormatting.cleanDeletions(source, edits);
            text = char(source);
            for index = 1:numel(edits)
                edit = edits(index);
                if edit.Text ~= "", continue, end
                if text(edit.Start) == char(13) && edit.Start < numel(text) && text(edit.Start + 1) == newline
                    edit.Start = edit.Start + 2;
                elseif text(edit.Start) == newline
                    edit.Start = edit.Start + 1;
                end
                preceding = find(text(1:edit.Start - 1) == newline, 1, "last");
                if isempty(preceding), preceding = 0; end
                following = find(text(edit.End + 1:end) == newline, 1);
                if ~isempty(following) && isempty(regexp(text(preceding + 1:edit.Start - 1), '[^ \t\r]', 'once')) && ...
                        isempty(regexp(text(edit.End + 1:edit.End + following - 1), '[^ \t\r]', 'once'))
                    edit.End = edit.End + following;
                end
                edits(index) = edit;
            end
        end

        function edits = cleanDeletions(source, edits)
            % cleanDeletions Remove trivia only when owned removals vacate a whole line.
            arguments (Input)
                source (1, 1) string
                edits struct
            end
            arguments (Output)
                edits struct
            end
            text = char(source);
            % Merge removals separated solely by trivia, including fully removed inline statements.
            [~, order] = sort([edits.Start]);
            edits = edits(order);
            index = 1;
            while index < numel(edits)
                gap = text(edits(index).End + 1:edits(index + 1).Start - 1);
                if edits(index).Text == "" && edits(index + 1).Text == "" && ...
                        isempty(regexp(gap, '[^ \t\r\n]', 'once'))
                    edits(index).End = max(edits(index).End, edits(index + 1).End);
                    edits(index + 1) = [];
                else
                    index = index + 1;
                end
            end
            % Keep the following newline so insertions at a removed end stay valid.
            for index = 1:numel(edits)
                edit = edits(index);
                if edit.Text ~= "" || edit.Start > edit.End, continue, end
                first = find(text(1:edit.Start - 1) == newline, 1, "last");
                if isempty(first), first = 0; end
                following = find(text(edit.End + 1:end) == newline, 1);
                last = numel(text);
                if ~isempty(following), last = edit.End + following - 1; end
                prefix = text(first + 1:edit.Start - 1);
                suffix = text(edit.End + 1:last);
                if ~isempty(regexp(prefix, '[^ \t\r]', 'once')) || ...
                        ~isempty(regexp(suffix, '[^ \t\r]', 'once')), continue, end
                if last > 0 && text(last) == char(13), last = last - 1; end
                % Avoid consuming offsets needed by other replacements or insertions.
                others = edits;
                others(index) = [];
                start = first;
                if start == 0
                    start = 1;
                    if ~isempty(following), last = edit.End + following; end
                else
                    % Retain one separator when removing a block between two blank lines.
                    tail = '';
                    if ~isempty(following), tail = text(edit.End + following + 1:end); end
                    if ~isempty(following) && ~isempty(regexp(tail, '^[ \t]*\r?\n', 'once'))
                        while start > 1
                            previous = find(text(1:start - 1) == newline, 1, "last");
                            if isempty(previous), break, end
                            if ~isempty(regexp(text(previous + 1:start - 1), '[^ \t\r]', 'once')), break, end
                            start = previous;
                        end
                    end
                    if start > 1 && text(start - 1) == char(13), start = start - 1; end
                end
                if any([others.Start] <= last & [others.End] >= start & ...
                        ([others.Start] < edit.Start | [others.End] > edit.End)), continue, end
                edits(index).Start = start;
                edits(index).End = last;
            end
            % Consecutive removals can share trivia; merge empty replacements only.
            [~, order] = sort([edits.Start]);
            edits = edits(order);
            index = 1;
            while index < numel(edits)
                if edits(index).Text == "" && edits(index + 1).Text == "" && ...
                        edits(index + 1).Start <= edits(index).End + 1
                    edits(index).End = max(edits(index).End, edits(index + 1).End);
                    edits(index + 1) = [];
                else
                    index = index + 1;
                end
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
