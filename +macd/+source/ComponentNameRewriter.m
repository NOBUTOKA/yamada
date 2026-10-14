classdef ComponentNameRewriter
    % ComponentNameRewriter Rename proven component and callback identifiers.
    %   This utility masks literals and comments before rewriting static app
    %   references and class members. Dynamic dispatch and app aliases are
    %   rejected before mutation. Only member help comments follow a rename.

    methods (Static)
        function code = codeMask(source)
            % codeMask Preserve code offsets while hiding comments and literals.
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
                elseif index + 2 <= numel(text) && strcmp(text(index:index + 2), '...')
                    % Continuations and their trailing text do not participate in references.
                    while index <= numel(text) && ~ismember(text(index), [char(10) char(13)])
                        code(index) = ' ';
                        index = index + 1;
                    end
                elseif text(index) == '%'
                    if index < numel(text) && text(index + 1) == '{'
                        block = true;
                    end
                    while index <= numel(text) && ~ismember(text(index), [char(10) char(13)])
                        code(index) = ' ';
                        index = index + 1;
                    end
                elseif text(index) == '"' || (text(index) == '''' && ...
                        ~(index > 1 && ~isempty(regexp(text(index - 1), '[\w\]\)}."]', 'once'))))
                    % An adjacent expression-ending character makes a quote a transpose.
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

        function names = memberNames(source)
            % memberNames Collect class property and method declarations without executing source.
            arguments (Input)
                source (1, 1) string
            end
            arguments (Output)
                names string
            end

            code = macd.source.ComponentNameRewriter.codeMask(source);
            lines = regexp(code, '\r\n|\n|\r', 'split');
            names = strings(1, 0);
            inProperties = false;
            for index = 1:numel(lines)
                line = strtrim(lines{index});
                if ~isempty(regexp(line, '^properties(?:\s*\([^)]*=[^)]*\))?\s*$', 'once'))
                    inProperties = true;
                elseif inProperties && strcmp(line, 'end')
                    inProperties = false;
                elseif inProperties
                    name = regexp(line, '^[A-Za-z]\w*', 'match', 'once');
                    if ~isempty(name), names(end + 1) = string(name); end %#ok<AGROW>
                else
                    match = regexp(line, '^function\s+(?:(?:\[[^\]]*\]|\w+)\s*=\s*)?(\w+)', 'tokens', 'once');
                    if ~isempty(match), names(end + 1) = string(match{1}); end %#ok<AGROW>
                end
            end
        end

        function validate(source, oldName, newName)
            % validate Reject invalid names, class member collisions and unresolved app references.
            arguments (Input)
                source (1, 1) string
                oldName (1, 1) string
                newName (1, 1) string
            end

            if ~isvarname(newName) || iskeyword(newName)
                error("macd:DocumentModel:InvalidComponentName", "Use a valid MATLAB identifier (at most %d characters).", namelengthmax);
            end
            if newName ~= oldName && any(macd.source.ComponentNameRewriter.memberNames(source) == newName)
                error("macd:DocumentModel:ComponentNameCollision", "The name '%s' is already a class member.", newName);
            end
            code = macd.source.ComponentNameRewriter.codeMask(source);
            if ~isempty(regexp(code, '(?<![\w.])(?!app(?!\w))\w+\s*\.\s*' + regexptranslate('escape', oldName) + '(?!\w)', 'once'))
                error("macd:DocumentModel:UnsafeComponentRename", "A reference through another object cannot be renamed safely.");
            end
            if ~isempty(regexp(code, '(?<!\w)(eval|evalc|evalin|feval|str2func|subsref|subsasgn)\s*\(|(?<!\w)app\s*\.\s*\(', 'once'))
                error("macd:DocumentModel:UnsafeComponentRename", "Dynamic references prevent safe component renaming.");
            end
            if ~isempty(regexp(code, '(?<!\w)\w+\s*=\s*app\s*(?=[;,\r\n]|$)', 'once'))
                error("macd:DocumentModel:UnsafeComponentRename", "An alias of app prevents safe component renaming.");
            end
        end

        function stem = defaultHandler(componentName, callbackName)
            % defaultHandler Return the same bounded stem used by callback generation.
            arguments (Input)
                componentName (1, 1) string
                callbackName (1, 1) string
            end
            arguments (Output)
                stem (1, 1) string
            end

            stem = string(matlab.lang.makeValidName(componentName + erase(callbackName, "Fcn")));
            stem = extractBefore(stem, min(strlength(stem) + 1, namelengthmax - 8));
        end

        function result = canRenameHandler(source, handler)
            % canRenameHandler Reject local identifiers that shadow a candidate callback method.
            arguments (Input)
                source (1, 1) string
                handler (1, 1) string
            end
            arguments (Output)
                result (1, 1) logical
            end

            code = macd.source.ComponentNameRewriter.codeMask(source);
            declaration = regexp(code, '^\s*classdef(?:\s*\([^)]*\))?\s+(\w+)', 'tokens', 'once');
            className = "";
            if ~isempty(declaration), className = string(declaration{1}); end
            [starts, ends] = regexp(code, '(?<!\w)' + regexptranslate('escape', handler) + '(?!\w)');
            [starts, ends] = macd.source.ComponentNameRewriter.excludeForeignMembers(code, starts, ends, className);
            result = true;
            for index = 1:numel(starts)
                prefix = code(1:starts(index) - 1);
                suffix = code(ends(index) + 1:end);
                declarationName = ~isempty(regexp(prefix, ...
                    '(?m)^[ \t]*function\s+(?:(?:\[[^\]]*\]|\w+)\s*=\s*)?$', 'once'));
                handleName = ~isempty(regexp(prefix, '@\s*$', 'once'));
                qualifiedName = ~isempty(regexp(prefix, '\.\s*$', 'once'));
                directCall = ~isempty(regexp(suffix, '^\s*\(\s*app(?!\w)', 'once'));
                if ~(declarationName || handleName || qualifiedName || directCall)
                    result = false;
                    return
                end
            end
        end

        function rewritten = rewrite(source, mappings)
            % rewrite Apply simultaneous member renames and update their H1 help lines.
            arguments (Input)
                source (1, 1) string
                mappings struct
            end
            arguments (Output)
                rewritten (1, 1) string
            end

            rewritten = source;
            if isempty(mappings), return, end
            text = char(source);
            code = macd.source.ComponentNameRewriter.codeMask(source);
            documentation = macd.source.ComponentNameRewriter.documentationMask(source);
            declaration = regexp(code, '^\s*classdef(?:\s*\([^)]*\))?\s+(\w+)', 'tokens', 'once');
            className = "";
            if ~isempty(declaration), className = string(declaration{1}); end
            edits = struct("Start", {}, "End", {}, "Text", {});
            for mapping = mappings(:)'
                if mapping.OldName == mapping.NewName, continue, end
                token = regexptranslate('escape', char(mapping.OldName));
                if mapping.Kind == "method"
                    % Proven unique handler names can also occur in calls and handles.
                    pattern = ['(?<!\w)' token '(?!\w)'];
                    [starts, ends] = regexp(code, pattern);
                    [starts, ends] = macd.source.ComponentNameRewriter.excludeForeignMembers(code, starts, ends, className);
                else
                    [starts, ends] = regexp(code, ['(?<=\.)\s*' token '(?!\w)']);
                    keep = false(size(starts));
                    for index = 1:numel(starts)
                        prefix = code(1:starts(index) - 1);
                        keep(index) = ~isempty(regexp(prefix, '(?<!\w)app\s*\.$', 'once'));
                        starts(index) = ends(index) - numel(token) + 1;
                    end
                    starts = starts(keep);
                    ends = ends(keep);
                    % Property declarations belong to properties blocks, not local variables.
                    [lineStarts, lineEnds] = regexp(code, '[^\r\n]+');
                    inProperties = false;
                    for index = 1:numel(lineStarts)
                        line = code(lineStarts(index):lineEnds(index));
                        if ~isempty(regexp(line, '^\s*properties(?:\s*\([^)]*=[^)]*\))?\s*$', 'once'))
                            inProperties = true;
                        elseif inProperties && ~isempty(regexp(line, '^\s*end\s*$', 'once'))
                            inProperties = false;
                        elseif inProperties
                            [first, last] = regexp(line, ['^\s*' token '(?!\w)'], 'once');
                            if ~isempty(first)
                                starts(end + 1) = lineStarts(index) + last - numel(token); %#ok<AGROW>
                                ends(end + 1) = lineStarts(index) + last - 1; %#ok<AGROW>
                            end
                        end
                    end
                end
                for index = 1:numel(starts)
                    edits(end + 1) = struct("Start", starts(index), "End", ends(index), "Text", mapping.NewName); %#ok<AGROW>
                end
                % Update identifiers in class, method and property help, including examples.
                [helpStarts, helpEnds] = regexp(documentation, ['(?<!\w)' token '(?!\w)']);
                [helpStarts, helpEnds] = macd.source.ComponentNameRewriter.excludeForeignMembers(documentation, helpStarts, helpEnds, className);
                for index = 1:numel(helpStarts)
                    edits(end + 1) = struct("Start", helpStarts(index), "End", helpEnds(index), "Text", mapping.NewName); %#ok<AGROW>
                end
            end
            if ~isempty(edits)
                [~, order] = sort([edits.Start], 'descend');
                for edit = edits(order)
                    text = [text(1:edit.Start - 1) char(edit.Text) text(edit.End + 1:end)];
                end
            end
            rewritten = string(text);
        end
    end

    methods (Static, Access = private)
        function [starts, ends] = excludeForeignMembers(text, starts, ends, className)
            % excludeForeignMembers Preserve identically named members of other objects or namespaces.
            arguments (Input)
                text char
                starts double
                ends double
                className (1, 1) string
            end
            arguments (Output)
                starts double
                ends double
            end

            keep = true(size(starts));
            owner = "app";
            if strlength(className) > 0, owner = owner + "|" + regexptranslate('escape', className); end
            for index = 1:numel(starts)
                prefix = text(1:starts(index) - 1);
                if ~isempty(regexp(prefix, '\.\s*$', 'once'))
                    keep(index) = ~isempty(regexp(prefix, '(?<![\w.])(' + owner + ')\s*\.\s*$', 'once'));
                end
            end
            starts = starts(keep);
            ends = ends(keep);
        end

        function documentation = documentationMask(source)
            % documentationMask Identify help immediately following declarations or preceding properties.
            arguments (Input)
                source (1, 1) string
            end
            arguments (Output)
                documentation char
            end

            text = char(source);
            code = macd.source.ComponentNameRewriter.codeMask(source);
            documentation = code;
            documentation(~ismember(documentation, [char(10) char(13)])) = ' ';
            [starts, ends] = regexp(text, '[^\r\n]+');
            inHelp = false;
            inProperties = false;
            pending = [];
            for index = 1:numel(starts)
                line = text(starts(index):ends(index));
                codeLine = strtrim(code(starts(index):ends(index)));
                comment = ~isempty(regexp(line, '^\s*%(?![{}])', 'once'));
                if index > 1 && numel(regexp(text(ends(index - 1) + 1:starts(index) - 1), '\r\n|\n|\r', 'match')) > 1
                    inHelp = false;
                    pending = [];
                end
                if comment && inHelp
                    documentation(starts(index):ends(index)) = line;
                elseif ~comment
                    inHelp = ~isempty(regexp(codeLine, '^(classdef|function)(?!\w)', 'once'));
                end
                if ~isempty(regexp(codeLine, '^properties(?:\s*\([^)]*=[^)]*\))?\s*$', 'once'))
                    inProperties = true;
                elseif inProperties && strcmp(codeLine, 'end')
                    inProperties = false;
                    pending = [];
                elseif inProperties && comment
                    pending(end + 1) = index; %#ok<AGROW>
                elseif inProperties && ~isempty(codeLine)
                    for previous = pending
                        documentation(starts(previous):ends(previous)) = text(starts(previous):ends(previous));
                    end
                    pending = [];
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
