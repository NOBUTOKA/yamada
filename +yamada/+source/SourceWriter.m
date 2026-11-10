classdef SourceWriter
    % SourceWriter Write generated MATLAB source with controlled byte formatting.
    %   This static utility normalizes a requested line-ending convention and
    %   writes UTF-8 bytes without a BOM. It does not validate or generate source.
    %
    %   Example:
    %       yamada.source.SourceWriter.write("ExampleApp.m", source);

    methods (Static)
        function write(filePath, source, lineEnding)
            % write Save UTF-8 source without BOM using one named line convention.
            arguments (Input)
                filePath string
                source string
                lineEnding string = yamada.source.SourceWriter.defaultLineEnding()
            end

            % Normalize lines before performing byte-level UTF-8 encoding.
            source = yamada.source.SourceWriter.normalize(source, lineEnding);
            bytes = unicode2native(char(source), "UTF-8");
            % Stage complete output before asking Windows to replace the destination.
            yamada.source.SourceWriter.writeProtected(filePath, bytes);
        end

        function source = normalize(source, lineEnding)
            % normalize Return the exact text that the UTF-8 writer will encode.
            arguments (Input)
                source (1, 1) string
                lineEnding (1, 1) string
            end
            arguments (Output)
                source (1, 1) string
            end

            % Share byte-format normalization with saved-source position tracking.
            source = regexprep(source, "\r\n|\r|\n", newline);
            source = replace(source, newline, ...
                yamada.source.SourceWriter.lineEndingText(lineEnding));
        end
    end

    methods (Static, Access = private)
        function writeProtected(filePath, bytes)
            % writeProtected Commit flushed bytes through Windows replacement with recovery.
            arguments (Input)
                filePath (1, 1) string
                bytes uint8
            end

            % Refuse unsupported hosts rather than falling back to truncating writes.
            if ~ispc || ~NET.isNETSupported
                error("yamada:SourceWriter:UnsupportedPlatform", ...
                    "Protected source saving requires Windows with .NET support.");
            end
            % Resolve ordinary relative paths against MATLAB's current folder.
            if ~System.IO.Path.IsPathRooted(filePath)
                filePath = fullfile(string(pwd), filePath);
            end
            target = string(System.IO.Path.GetFullPath(filePath));
            folder = string(System.IO.Path.GetDirectoryName(target));
            token = string(System.Guid.NewGuid().ToString("N"));
            staged = fullfile(folder, ".yamada-" + token + ".tmp");
            backup = fullfile(folder, ".yamada-" + token + ".bak");

            % Create exclusively beside the destination and flush before closing.
            stream = System.IO.FileStream(staged, System.IO.FileMode.CreateNew, ...
                System.IO.FileAccess.Write, System.IO.FileShare.None);
            stagedCleanup = onCleanup(@() yamada.source.SourceWriter.closeAndRemove(stream, staged));
            buffer = NET.convertArray(bytes, "System.Byte");
            stream.Write(buffer, 0, buffer.Length);
            stream.Flush(true);
            stream.Dispose();

            % Preserve destination metadata and keep a native recovery copy.
            try
                if System.IO.File.Exists(target)
                    System.IO.File.Replace(staged, target, backup, false);
                else
                    % This move refuses to overwrite a concurrently created file.
                    System.IO.File.Move(staged, target);
                end
            catch exception
                if System.IO.File.Exists(backup)
                    % Windows can move the original to its backup before failing.
                    if ~System.IO.File.Exists(target) && ~System.IO.Directory.Exists(target)
                        try
                            System.IO.File.Move(backup, target);
                        catch recoveryException
                            exception = addCause(exception, recoveryException);
                        end
                    end
                    if System.IO.File.Exists(backup)
                        failure = MException("yamada:SourceWriter:RecoveryRequired", ...
                            "Save failed. The original file is retained at: %s", backup);
                        throw(addCause(failure, exception));
                    end
                end
                rethrow(exception);
            end

            % Cleanup refusal must not turn a committed save into a reported failure.
            yamada.source.SourceWriter.removeTemporary(backup);
            clear stagedCleanup
        end

        function closeAndRemove(stream, filePath)
            % closeAndRemove Close the staging handle before attempting cleanup.
            arguments (Input)
                stream System.IO.FileStream
                filePath (1, 1) string
            end

            try
                stream.Dispose();
            catch
                % Preserve the original write or close error during unwinding.
            end
            yamada.source.SourceWriter.removeTemporary(filePath);
        end

        function removeTemporary(filePath)
            % removeTemporary Remove an owned temporary file without masking save status.
            arguments (Input)
                filePath (1, 1) string
            end

            try
                System.IO.File.Delete(filePath);
            catch exception
                try
                    warning("yamada:SourceWriter:CleanupFailed", ...
                        "Temporary save file retained at %s: %s", filePath, exception.message);
                catch
                    % Warning-as-error settings must not mask the committed save.
                end
            end
        end

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
                    error("yamada:SourceWriter:UnsupportedLineEnding", ...
                        "Line ending convention ""%s"" is not supported.", convention);
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
