classdef SubtreeSourceEdits
    % SubtreeSourceEdits Prove complete-subtree deletion ownership without execution.
    %   Deletion removes owned initialization and declaration spans.

    methods (Static)
        function edits = deletion(components)
            % deletion Return source removals only after proving complete ownership.
            arguments (Input)
                components
            end
            arguments (Output)
                edits struct
            end

            % Accept live API inputs at the boundary; command state retains source-only values.
            if ~isstruct(components), components = yamada.model.SourceOwnership.snapshot(components); end
            % Collect complete owned spans before checking any references.
            spans = yamada.model.SourceSpan.empty;
            for component = components
                if ~yamada.model.SourceOwnership.hasSource(component), continue, end
                own = [component.SourceSpans.Declaration component.SourceSpans.Creation];
                if numel(own) ~= 2 || any(~arrayfun(@(span) span.isKnown(), own))
                    error("yamada:SubtreeSourceEdits:UnsafeDeletion", "Declaration or creation ownership is unknown.");
                end
                for entry = component.Properties
                    if isempty(entry.SourceSpan) || ~entry.SourceSpan.isKnown()
                        % Generated literal assignments do not exist in original source.
                        if isempty(entry.SourceSpan), continue, end
                        error("yamada:SubtreeSourceEdits:UnsafeDeletion", "Property ownership is unknown.");
                    end
                    own(end + 1) = entry.SourceSpan; %#ok<AGROW>
                end
                for setting = component.Settings
                    if ~isempty(setting.SourceSpan), own(end + 1) = setting.SourceSpan; end %#ok<AGROW>
                end
                spans = [spans own]; %#ok<AGROW>
            end
            edits = struct("Start", {}, "End", {}, "Text", {});
            if isempty(spans), return, end
            [~, uniqueSpans] = unique([[spans.StartOffset]' [spans.EndOffset]'], "rows", "stable");
            spans = spans(uniqueSpans);

            for span = spans
                edits(end + 1) = struct("Start", span.StartOffset, "End", span.EndOffset, "Text", ""); %#ok<AGROW>
            end
        end

        function code = codeMask(source)
            % codeMask Hide literals and comments while preserving source offsets.
            arguments (Input)
                source (1, 1) string
            end
            arguments (Output)
                code char
            end

            text = char(source);
            code = text;
            index = 1;
            block = false;
            while index <= numel(text)
                if block
                    if index < numel(text) && strcmp(text(index:index + 1), '%}')
                        code(index:index + 1) = '  ';
                        index = index + 2;
                        block = false;
                    else
                        if ~ismember(text(index), [char(10) char(13)]), code(index) = ' '; end
                        index = index + 1;
                    end
                elseif text(index) == '%'
                    if index < numel(text) && text(index + 1) == '{', block = true; end
                    while index <= numel(text) && ~ismember(text(index), [char(10) char(13)])
                        code(index) = ' ';
                        index = index + 1;
                    end
                elseif text(index) == '"' || (text(index) == '''' && ...
                        ~(index > 1 && ~isempty(regexp(text(index - 1), '[\w\]\)}."]', 'once'))))
                    quote = text(index);
                    code(index) = ' ';
                    index = index + 1;
                    while index <= numel(text)
                        character = text(index);
                        if ~ismember(character, [char(10) char(13)]), code(index) = ' '; end
                        index = index + 1;
                        if character == quote
                            if index <= numel(text) && text(index) == quote
                                code(index) = ' ';
                                index = index + 1;
                            else
                                break
                            end
                        end
                    end
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
