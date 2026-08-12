classdef SourceWriter
    % SourceWriter Write generated MATLAB source with controlled byte formatting.
    %   This static utility normalizes a requested line-ending convention and
    %   writes UTF-8 bytes without a BOM. It does not validate or generate source.
    %
    %   Example:
    %       macd.source.SourceWriter.write("ExampleApp.m", source);

    methods (Static)
        function write(filePath, source, lineEnding)
            % write Save UTF-8 source without BOM using one named line convention.
            arguments (Input)
                filePath string
                source string
                lineEnding string = macd.source.SourceWriter.defaultLineEnding()
            end

            % Normalize lines before performing byte-level UTF-8 encoding.
            source = regexprep(source, "\r\n|\r|\n", newline);
            source = replace(source, newline, ...
                macd.source.SourceWriter.lineEndingText(lineEnding));
            bytes = unicode2native(char(source), "UTF-8");
            % Use binary mode to prevent a second Windows newline translation.
            [fileId, message] = fopen(filePath, "wb");
            if fileId < 0
                error("macd:SourceWriter:OpenFailed", "%s", message);
            end
            cleanup = onCleanup(@() fclose(fileId));
            % Verify that the complete encoded buffer reaches the target.
            count = fwrite(fileId, bytes, "uint8");
            if count ~= numel(bytes)
                error("macd:SourceWriter:WriteFailed", ...
                    "Not all source bytes were written.");
            end
            % Close eagerly so callers can immediately read or move the file.
            clear cleanup
        end
    end

    methods (Static, Access = private)
        function result = defaultLineEnding()
            % defaultLineEnding Return the host platform convention for new output.
            arguments (Output)
                result (1, 1) string
            end

            % Match conventional defaults without using platform text-mode I/O.
            if ispc
                result = "CRLF";
            else
                result = "LF";
            end
        end

        function result = lineEndingText(convention)
            % lineEndingText Convert one named output convention into its text.
            arguments (Input)
                convention (1, 1) string
            end
            arguments (Output)
                result (1, 1) string
            end

            % Keep binary output explicit and reject unsupported conventions.
            switch convention
                case "CRLF"
                    result = sprintf("\r\n");
                case "LF"
                    result = newline;
                otherwise
                    error("macd:SourceWriter:UnsupportedLineEnding", ...
                        "Line ending convention ""%s"" is not supported.", convention);
            end
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
