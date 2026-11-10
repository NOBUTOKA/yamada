classdef (TestTags = {'fast', 'generation', 'lifecycle'}) SourceWriterTest < matlab.unittest.TestCase
    % SourceWriterTest Verify protected native saves and exact source bytes.
    %   Real Windows locks and attributes exercise failure without replacing the writer.

    methods (Test)
        function relativeUnicodePathAndEmptyOutputUseMatlabFolder(testCase)
            % relativeUnicodePathAndEmptyOutputUseMatlabFolder Resolve relative names using MATLAB's folder.
            fixture = testCase.applyFixture(matlab.unittest.fixtures.WorkingFolderFixture);
            target = "空の app.m";
            yamada.source.SourceWriter.write(target, "");
            absolute = fullfile(string(fixture.Folder), target);
            testCase.verifyTrue(isfile(absolute));
            testCase.verifyEqual(System.IO.File.ReadAllBytes(absolute).Length, int32(0));
            yamada.source.SourceWriter.write(target, "日本語");
            testCase.verifyEqual(string(fileread(absolute)), "日本語");
        end

        function replacementPreservesCreationTimeAndPermissions(testCase)
            % replacementPreservesCreationTimeAndPermissions Retain native destination metadata.
            target = string(tempname) + ".m";
            cleanup = onCleanup(@() System.IO.File.Delete(target));
            yamada.source.SourceWriter.write(target, "original");
            System.IO.File.SetCreationTimeUtc(target, System.DateTime(2001, 1, 1));
            creation = System.IO.File.GetCreationTimeUtc(target).ToFileTimeUtc();
            section = System.Security.AccessControl.AccessControlSections.Access;
            permissions = string(System.IO.File.GetAccessControl(target).GetSecurityDescriptorSddlForm(section));
            yamada.source.SourceWriter.write(target, "replacement");
            testCase.verifyEqual(System.IO.File.GetCreationTimeUtc(target).ToFileTimeUtc(), creation);
            testCase.verifyEqual(string(System.IO.File.GetAccessControl(target).GetSecurityDescriptorSddlForm(section)), permissions);
        end

        function writesExactUtf8AndReplacesExistingFile(testCase)
            % writesExactUtf8AndReplacesExistingFile Preserve encoding and remove staging files.
            folder = string(tempname);
            mkdir(folder);
            cleanup = onCleanup(@() rmdir(folder, "s"));
            target = fullfile(folder, "Example.m");
            source = "日本語" + newline + "end" + newline;
            for ending = ["CRLF", "LF"]
                yamada.source.SourceWriter.write(target, source, ending);
                expected = unicode2native(char(yamada.source.SourceWriter.normalize(source, ending)), "UTF-8");
                actual = reshape(uint8(System.IO.File.ReadAllBytes(target)), 1, []);
                testCase.verifyEqual(actual, expected);
                testCase.verifyEqual(string({dir(fullfile(folder, "*")).name}), ["." ".." "Example.m"]);
            end
        end

        function lockedDestinationRetainsEveryOriginalByte(testCase)
            % lockedDestinationRetainsEveryOriginalByte Refuse replacement while another reader denies deletion.
            folder = string(tempname);
            mkdir(folder);
            cleanup = onCleanup(@() rmdir(folder, "s"));
            target = fullfile(folder, "Example.m");
            original = uint8([0 255 13 10 65 0]);
            System.IO.File.WriteAllBytes(target, NET.convertArray(original, "System.Byte"));
            stream = System.IO.FileStream(target, System.IO.FileMode.Open, ...
                System.IO.FileAccess.Read, System.IO.FileShare.Read);
            streamCleanup = onCleanup(@() stream.Dispose());
            failed = false;
            try
                yamada.source.SourceWriter.write(target, "replacement");
            catch
                failed = true;
            end
            testCase.verifyTrue(failed);
            testCase.verifyEqual(reshape(uint8(System.IO.File.ReadAllBytes(target)), 1, []), original);
            testCase.verifyEmpty(dir(fullfile(folder, ".yamada-*")));
            clear streamCleanup
        end

        function readOnlyDestinationIsNotOverwritten(testCase)
            % readOnlyDestinationIsNotOverwritten Keep read-only source intact after refusal.
            folder = string(tempname);
            mkdir(folder);
            cleanup = onCleanup(@() rmdir(folder, "s"));
            target = fullfile(folder, "Example.m");
            yamada.source.SourceWriter.write(target, "original");
            System.IO.File.SetAttributes(target, System.IO.FileAttributes.ReadOnly);
            attributeCleanup = onCleanup(@() System.IO.File.SetAttributes(target, System.IO.FileAttributes.Normal));
            failed = false;
            try
                yamada.source.SourceWriter.write(target, "replacement");
            catch
                failed = true;
            end
            testCase.verifyTrue(failed);
            testCase.verifyEqual(string(fileread(target)), "original");
            testCase.verifyEmpty(dir(fullfile(folder, ".yamada-*")));
            clear attributeCleanup
        end

        function invalidOutputLeavesExistingFileUntouched(testCase)
            % invalidOutputLeavesExistingFileUntouched Reject invalid formatting before opening output.
            target = string(tempname) + ".m";
            cleanup = onCleanup(@() System.IO.File.Delete(target));
            yamada.source.SourceWriter.write(target, "original");
            testCase.verifyError(@() yamada.source.SourceWriter.write(target, "replacement", "invalid"), ...
                "yamada:SourceWriter:UnsupportedLineEnding");
            testCase.verifyEqual(string(fileread(target)), "original");
        end

        function directoryDestinationAndMissingParentAreSafe(testCase)
            % directoryDestinationAndMissingParentAreSafe Refuse invalid targets without leaving staged files.
            folder = string(tempname);
            mkdir(folder);
            cleanup = onCleanup(@() rmdir(folder, "s"));
            for target = [folder, fullfile(folder, "missing", "Example.m")]
                failed = false;
                try
                    yamada.source.SourceWriter.write(target, "replacement");
                catch
                    failed = true;
                end
                testCase.verifyTrue(failed);
            end
            testCase.verifyTrue(isfolder(folder));
            testCase.verifyEmpty(dir(fullfile(folder, ".yamada-*")));
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
