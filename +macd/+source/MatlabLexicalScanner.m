classdef MatlabLexicalScanner
    % MatlabLexicalScanner Split MATLAB source without evaluating it.
    %   This static utility recognizes quoted text, line comments, block comments,
    %   balanced delimiters, and continuations while locating complete statements.
    %   It is lexical only and does not claim to parse arbitrary MATLAB grammar.
    %
    %   Example:
    %       statements = macd.source.MatlabLexicalScanner.splitStatements(source);

    methods (Static)
        function statements = splitStatements(source)
            % splitStatements Return complete statements with original offsets.
            arguments (Input)
                source string
            end
            arguments (Output)
                statements macd.source.SourceStatement
            end

            % Work with code units so every reported offset maps to the source.
            text = char(source);
            statements = macd.source.SourceStatement.empty;
            buffer = '';
            startOffset = 0;
            parenDepth = 0;
            bracketDepth = 0;
            braceDepth = 0;
            inCharacterVector = false;
            inString = false;
            inBlockComment = false;
            index = 1;

            % Scan one code unit at a time while preserving statement boundaries.
            while index <= numel(text)
                character = text(index);
                nextCharacter = char(0);
                if index < numel(text)
                    nextCharacter = text(index + 1);
                end

                % Ignore block comments without treating their delimiters as code.
                if inBlockComment
                    if character == '%' && nextCharacter == '}'
                        inBlockComment = false;
                        index = index + 2;
                    else
                        index = index + 1;
                    end
                    continue
                end
                if ~inCharacterVector && ~inString && ...
                        character == '%' && nextCharacter == '{'
                    inBlockComment = true;
                    index = index + 2;
                    continue
                end

                % Ignore line comments while allowing the newline to finish code.
                if ~inCharacterVector && ~inString && character == '%'
                    while index <= numel(text) && text(index) ~= newline
                        index = index + 1;
                    end
                    continue
                end

                % Establish the span at the first non-whitespace code unit.
                if startOffset == 0 && ~isspace(character)
                    startOffset = index;
                end

                % Respect MATLAB's doubled quote escaping in both text forms.
                if character == '''' && ~inString
                    if inCharacterVector && nextCharacter == ''''
                        buffer = [buffer '''''']; %#ok<AGROW>
                        index = index + 2;
                        continue
                    end
                    inCharacterVector = ~inCharacterVector;
                elseif character == '"' && ~inCharacterVector
                    if inString && nextCharacter == '"'
                        buffer = [buffer '""']; %#ok<AGROW>
                        index = index + 2;
                        continue
                    end
                    inString = ~inString;
                end

                % Count delimiters only outside quoted text.
                if ~inCharacterVector && ~inString
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

                % A top-level semicolon always completes the current statement.
                if character == ';' && ~inCharacterVector && ~inString && ...
                        parenDepth == 0 && bracketDepth == 0 && braceDepth == 0
                    statements = macd.source.MatlabLexicalScanner.appendStatement( ...
                        statements, buffer, startOffset, index);
                    buffer = '';
                    startOffset = 0;
                    index = index + 1;
                    continue
                end

                % Remove continuation markers before considering statement boundaries.
                if character == newline && ~inCharacterVector && ~inString
                    trimmed = strtrim(buffer);
                    if endsWith(string(trimmed), "...")
                        buffer = [extractBefore(trimmed, strlength(trimmed) - 2) ' '];
                        index = index + 1;
                        continue
                    end
                end

                % A top-level newline completes a statement after continuation cleanup.
                if character == newline && ~inCharacterVector && ~inString && ...
                        parenDepth == 0 && bracketDepth == 0 && braceDepth == 0
                    statements = macd.source.MatlabLexicalScanner.appendStatement( ...
                        statements, buffer, startOffset, index - 1);
                    buffer = '';
                    startOffset = 0;
                    index = index + 1;
                    continue
                end

                buffer = [buffer character]; %#ok<AGROW>
                index = index + 1;
            end

            % Retain a final unterminated statement for conservative diagnostics.
            statements = macd.source.MatlabLexicalScanner.appendStatement( ...
                statements, buffer, startOffset, numel(text));
        end
    end

    methods (Static, Access = private)
        function statements = appendStatement(statements, buffer, startOffset, endOffset)
            % appendStatement Append nonempty trimmed text with a valid span.
            arguments (Input)
                statements macd.source.SourceStatement
                buffer char
                startOffset double
                endOffset double
            end
            arguments (Output)
                statements macd.source.SourceStatement
            end

            % Ignore whitespace-only regions created by comments and separators.
            text = string(strtrim(buffer));
            if strlength(text) == 0 || startOffset == 0 || endOffset < startOffset
                return
            end
            statements(end + 1) = macd.source.SourceStatement( ...
                text, macd.model.SourceSpan(startOffset, endOffset));
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
