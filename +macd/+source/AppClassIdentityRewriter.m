classdef AppClassIdentityRewriter
    % AppClassIdentityRewriter Align an AppBase class identity with its saved filename.
    %   This utility changes the class declaration, constructor declaration,
    %   self types in arguments blocks, and class help examples. Other source
    %   text, including string literals and component properties, is preserved.

    methods (Static)
        function [rewritten, diagnostics] = rewrite(source, className)
            % rewrite Return source with its class identity changed to className.
            arguments (Input)
                source (1, 1) string
                className (1, 1) string
            end
            arguments (Output)
                rewritten (1, 1) string
                diagnostics macd.model.Diagnostic
            end

            rewritten = source;
            diagnostics = macd.model.Diagnostic.empty;
            if ~isvarname(className) || iskeyword(className)
                diagnostics(end + 1) = macd.model.Diagnostic( ...
                    "invalid-class-name", "error", ...
                    "The Save As filename must be a valid MATLAB class name.");
                return
            end

            % Locate the supported AppBase declaration without changing line endings.
            original = char(source);
            lines = regexp(original, '\r\n|\n|\r', 'split');
            separators = regexp(original, '\r\n|\n|\r', 'match');
            declaration = [];
            for index = 1:numel(lines)
                tokens = regexp(lines{index}, ...
                    '^(?<prefix>[ \t]*classdef[ \t]+)(?<name>[A-Za-z]\w*)(?<suffix>[ \t]*<[ \t]*matlab\.apps\.AppBase(?:[ \t]*%.*)?)$', ...
                    'names', 'once');
                if ~isempty(tokens)
                    declaration = index;
                    oldName = string(tokens.name);
                    break
                end
            end
            if isempty(declaration)
                diagnostics(end + 1) = macd.model.Diagnostic( ...
                    "class-rename-unsupported", "error", ...
                    "The AppBase class declaration could not be renamed safely.");
                return
            end
            if oldName == className
                return
            end

            % Rewrite only declaration and type positions belonging to this class.
            oldToken = char(oldName);
            newToken = char(className);
            escapedName = regexptranslate('escape', oldToken);
            inArguments = false;
            for index = 1:numel(lines)
                line = lines{index};
                if index == declaration
                    line = macd.source.AppClassIdentityRewriter.replaceAfterPrefix( ...
                        line, tokens.prefix, oldToken, newToken);
                else
                    if ~isempty(regexp(line, ...
                            '^[ \t]*arguments(?:[ \t]*\([^)]*\))?[ \t]*(?:%.*)?$', 'once'))
                        inArguments = true;
                    elseif inArguments && ~isempty(regexp(line, ...
                            '^[ \t]*end[ \t]*(?:%.*)?$', 'once'))
                        inArguments = false;
                    elseif inArguments
                        typeTokens = regexp(line, ...
                            ['^(?<prefix>[ \t]*[A-Za-z]\w*(?:[ \t]*\([^)]*\))?[ \t]+)' ...
                            '(?<name>' escapedName ')(?=[ \t,{;]|$)'], 'names', 'once');
                        if ~isempty(typeTokens)
                            line = macd.source.AppClassIdentityRewriter.replaceAfterPrefix( ...
                                line, typeTokens.prefix, oldToken, newToken);
                        end
                    end
                    constructorPrefix = regexp(line, ...
                        '^[ \t]*function[ \t]+[A-Za-z][A-Za-z0-9_]*[ \t]*=[ \t]*', ...
                        'match', 'once');
                    if ~isempty(constructorPrefix)
                        remainder = line(numel(constructorPrefix) + 1:end);
                        followsName = numel(remainder) == numel(oldToken) || ...
                            (numel(remainder) > numel(oldToken) && ...
                            ismember(remainder(numel(oldToken) + 1), [' ' char(9) '(']));
                        if startsWith(remainder, oldToken) && followsName
                            line = macd.source.AppClassIdentityRewriter.replaceAfterPrefix( ...
                                line, constructorPrefix, oldToken, newToken);
                        end
                    end
                    helpLine = regexp(line, ...
                        ['^(?<prefix>[ \t]*%[ \t]+)(?<name>' escapedName ...
                        ')(?=[ \t]|$)'], 'names', 'once');
                    if ~isempty(helpLine)
                        line = macd.source.AppClassIdentityRewriter.replaceAfterPrefix( ...
                            line, helpLine.prefix, oldToken, newToken);
                    end
                    example = regexp(line, ...
                        ['^(?<prefix>[ \t]*%[ \t]+[A-Za-z]\w*[ \t]*=[ \t]*)' ...
                        '(?<name>' escapedName ')(?=\()'], 'names', 'once');
                    if ~isempty(example)
                        line = macd.source.AppClassIdentityRewriter.replaceAfterPrefix( ...
                            line, example.prefix, oldToken, newToken);
                    end
                end
                lines{index} = line;
            end

            % Reassemble the original sequence of CRLF, LF, and CR separators.
            pieces = cell(1, 2 * numel(lines));
            for index = 1:numel(lines)
                pieces{2 * index - 1} = lines{index};
                if index <= numel(separators)
                    pieces{2 * index} = separators{index};
                end
            end
            rewritten = string([pieces{:}]);
        end
    end

    methods (Static, Access = private)
        function line = replaceAfterPrefix(line, prefix, oldName, newName)
            % replaceAfterPrefix Replace one known identifier after its lexical prefix.
            arguments (Input)
                line char
                prefix char
                oldName char
                newName char
            end
            arguments (Output)
                line char
            end

            boundary = numel(prefix);
            line = [line(1:boundary) newName line(boundary + numel(oldName) + 1:end)];
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
