classdef SourceWriter
    % SourceWriter Write generated MATLAB source with required byte formatting.
    %   This static utility normalizes CRLF line endings and writes UTF-8 bytes
    %   without a BOM. It does not validate or generate the supplied source text.
    %
    %   Example:
    %       macd.source.SourceWriter.write("ExampleApp.m", source);

    methods (Static)
        function write(filePath, source)
            % write Save MATLAB source as UTF-8 without BOM using CRLF lines.
            arguments (Input)
                filePath string
                source string
            end

            % Normalize lines before performing byte-level UTF-8 encoding.
            source = regexprep(source, "\r\n|\r|\n", newline);
            source = replace(source, newline, sprintf("\r\n"));
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
end

%{
MatlabAppClassDesigner - UTF-8 without BOM and CRLF source writer.
Copyright (C) 2026 MatlabAppClassDesigner contributors

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
