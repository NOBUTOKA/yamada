classdef SubtreeSourceEdits
    % SubtreeSourceEdits Prove complete-subtree deletion ownership without execution.
    %   This utility treats child construction references as internal uses while
    %   rejecting references outside the owned subtree statements.

    methods (Static)
        function edits = deletion(source, components, rewrittenReferences)
            % deletion Return source removals only after proving complete ownership.
            arguments (Input)
                source (1, 1) string
                components macd.model.ComponentRecord
                rewrittenReferences macd.model.SourceSpan = macd.model.SourceSpan.empty
            end
            arguments (Output)
                edits struct
            end

            % Collect complete owned spans before checking any references.
            spans = macd.model.SourceSpan.empty;
            names = strings(1, 0);
            for component = components
                if component.Origin ~= "parsed", continue, end
                own = [component.SourceSpans.Declaration component.SourceSpans.Creation];
                if numel(own) ~= 2 || any(~arrayfun(@(span) span.isKnown(), own))
                    error("macd:SubtreeSourceEdits:UnsafeDeletion", "Declaration or creation ownership is unknown.");
                end
                creation = extractBetween(source, own(2).StartOffset, own(2).EndOffset);
                token = regexp(creation, '^app\.(\w+)\s*=', 'tokens', 'once');
                if isempty(token)
                    error("macd:SubtreeSourceEdits:UnsafeDeletion", "Creation statement identity is ambiguous.");
                end
                names(end + 1) = string(token{1}); %#ok<AGROW>
                for entry = component.Properties
                    if isempty(entry.SourceSpan) || ~entry.SourceSpan.isKnown()
                        % Generated literal assignments do not exist in original source.
                        if entry.Origin == "generated", continue, end
                        error("macd:SubtreeSourceEdits:UnsafeDeletion", "Property ownership is unknown.");
                    end
                    own(end + 1) = entry.SourceSpan; %#ok<AGROW>
                end
                spans = [spans own]; %#ok<AGROW>
            end
            edits = struct("Start", {}, "End", {}, "Text", {});
            if isempty(spans), return, end

            % Mask text and comments without changing offsets; reject indirect app access.
            code = macd.source.SubtreeSourceEdits.codeMask(source);
            if ~isempty(regexp(code, 'app\s*\.\s*\(|\w+\s*=\s*app\s*(?:;|\n)|(?:subsref|subsasgn|eval|feval)\s*\(', 'once'))
                error("macd:SubtreeSourceEdits:UnsafeDeletion", "Dynamic or aliased references prevent safe subtree deletion.");
            end
            for name = names
                positions = regexp(code, '(?<!\w)app\s*\.\s*' + name + '(?!\w)', 'start');
                for position = positions
                    allowed = [spans rewrittenReferences];
                    if ~any([allowed.StartOffset] <= position & [allowed.EndOffset] >= position)
                        error("macd:SubtreeSourceEdits:UnsafeDeletion", "The subtree is referenced outside its owned statements.");
                    end
                end
            end
            for span = spans
                edits(end + 1) = struct("Start", span.StartOffset, "End", span.EndOffset, "Text", ""); %#ok<AGROW>
            end
        end

        function spans = detachedParentReferences(document, deletedIds)
            % detachedParentReferences Identify only constructor parent tokens already scheduled for reparenting.
            arguments (Input)
                document (1, 1) macd.model.DocumentModel
                deletedIds string
            end
            arguments (Output)
                spans macd.model.SourceSpan
            end
            spans = macd.model.SourceSpan.empty;
            visited = strings(1, 0);
            for index = 1:numel(document.PendingEdits)
                pending = document.PendingEdits{index};
                if ~isstruct(pending) || ~isfield(pending, "Kind") || pending.Kind ~= "reparent-subtree", continue, end
                for record = pending.OriginalRecords
                    if any(visited == record.Id), continue, end
                    visited(end + 1) = record.Id; %#ok<AGROW>
                    component = document.getComponent(record.Id);
                    if record.Origin ~= "parsed" || isempty(component) || any(deletedIds == record.Id) || ...
                            ~any(deletedIds == record.ParentId) || component.ParentId == record.ParentId
                        continue
                    end
                    sourceSpan = record.SourceSpans.Creation;
                    creation = extractBetween(document.OriginalText, sourceSpan.StartOffset, sourceSpan.EndOffset);
                    pattern = '^app\.\w+\s*=\s*\w+\s*\(\s*(?<reference>app\s*\.\s*\w+)';
                    token = regexp(creation, pattern, 'names', 'once');
                    prefix = regexp(creation, pattern, 'match', 'once');
                    if isempty(token)
                        error("macd:SubtreeSourceEdits:UnsafeDeletion", "The moved child's constructor parent token is ambiguous.");
                    end
                    spans(end + 1) = macd.model.SourceSpan( ...
                        sourceSpan.StartOffset + strlength(prefix) - strlength(token.reference), ...
                        sourceSpan.StartOffset + strlength(prefix) - 1); %#ok<AGROW>
                end
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
