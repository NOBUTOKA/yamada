classdef (TestTags = {'fast', 'testInfrastructure'}) ProjectConventionsTest < matlab.unittest.TestCase
    % ProjectConventionsTest Verify invariant MATLAB project file conventions.
    %   This test class checks encoding, line endings, and required GPL notices in
    %   project-owned MATLAB source and test files. It does not inspect user output.

    methods (Test)
        function matlabFilesUseRequiredEncodingAndLineEndings(testCase)
            % matlabFilesUseRequiredEncodingAndLineEndings Check project bytes.

            % Inspect every project-owned MATLAB source and test file.
            files = ProjectConventionsTest.projectMatlabFiles();
            for index = 1:numel(files)
                filePath = fullfile(files(index).folder, files(index).name);
                bytes = ProjectConventionsTest.readBytes(filePath);
                testCase.verifyFalse(numel(bytes) >= 3 && ...
                    isequal(bytes(1:3), uint8([239 187 191])), filePath);
                text = string(native2unicode(bytes, "UTF-8"));
                testCase.verifyEmpty(regexp(text, "(?<!\r)\n", "once"), filePath);
            end
        end

        function excludesGeneratedRecordsWithoutExcludingSiblingSources(testCase)
            % excludesGeneratedRecordsWithoutExcludingSiblingSources Keep output and preserved input outside ownership.
            fixture = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            projectRoot = string(fixture.Folder);
            owned = ["Owned.m", fullfile("+macd", "Owned.m"), ...
                fullfile("tests", "unit", "OwnedTest.m"), ...
                fullfile("tests", "fixturesExtra", "OwnedHelper.m"), ...
                fullfile("testResultsExtra", "OwnedHelper.m")];
            excluded = [fullfile("tests", "fixtures", "Preserved.m"), ...
                fullfile("testResults", "nested", "UserOutput.m"), ...
                fullfile("coverage", "Instrumented.m"), fullfile("slprj", "Generated.m"), ...
                fullfile(".git", "Stored.m"), fullfile(".codex", "Scratch.m"), ...
                fullfile(".agents", "Scratch.m")];
            % Empty files are unexecuted directory-enumeration fixtures.
            for relative = [owned excluded]
                path = fullfile(projectRoot, relative);
                parent = fileparts(path);
                if ~isfolder(parent), mkdir(parent); end
                fileId = fopen(path, "w");
                testCase.assertGreaterThanOrEqual(fileId, 0);
                fclose(fileId);
            end
            files = ProjectConventionsTest.projectMatlabFiles(projectRoot);
            actual = string(fullfile(string({files.folder}), string({files.name})));
            actual = erase(actual, projectRoot + filesep);
            testCase.verifyEqual(sort(actual), sort(owned));
        end

        function projectMatlabFilesCarryGplNotice(testCase)
            % projectMatlabFilesCarryGplNotice Check trailing license blocks.

            % Verify invariant text and MRST-style placement in every owned file.
            files = ProjectConventionsTest.projectMatlabFiles();
            for index = 1:numel(files)
                filePath = fullfile(files(index).folder, files(index).name);
                text = string(native2unicode( ...
                    ProjectConventionsTest.readBytes(filePath), "UTF-8"));
                startsWithDeclaration = startsWith(text, "classdef") || ...
                    startsWith(text, "function ");
                testCase.verifyTrue(startsWithDeclaration, filePath);
                testCase.verifySubstring(text, ...
                    "Copyright (C) 2026 Nobuto Kaitoh", filePath);
                testCase.verifySubstring(text, ...
                    "GNU General Public License for more details.", filePath);
                licensePattern = ...
                    "\r\n%\{\r\nCopyright \(C\) 2026 Nobuto Kaitoh\r\n" + ...
                    "\r\nThis file is part of yamada\.\r\n" + ...
                    "[\s\S]*\r\n%\}\r\n$";
                testCase.verifyNotEmpty( ...
                    regexp(text, licensePattern, "once"), filePath);
            end
        end
    end

    methods (Static, Access = private)
        function files = projectMatlabFiles(projectRoot)
            % projectMatlabFiles Locate owned MATLAB files while pruning metadata and generated records.
            arguments (Input)
                projectRoot (1, 1) string = ""
            end
            arguments (Output)
                files (:, 1) struct
            end

            % Resolve the default checkout without traversing stored output or cached snapshots.
            if strlength(projectRoot) == 0
                projectRoot = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
            end
            files = dir(fullfile(projectRoot, "*.m"));
            folders = dir(projectRoot);
            excluded = [".", "..", "testResults", "coverage", "slprj", ".git", ".codex", ".agents"];
            for index = 1:numel(folders)
                name = string(folders(index).name);
                if ~folders(index).isdir || any(strcmpi(name, excluded)), continue, end
                files = [files; dir(fullfile(projectRoot, name, "**", "*.m"))]; %#ok<AGROW>
            end

            % Preserved fixtures are excluded by a directory boundary, not a shared prefix.
            fixtureRoot = fullfile(projectRoot, "tests", "fixtures") + filesep;
            isFixture = startsWith(string({files.folder}) + filesep, fixtureRoot, "IgnoreCase", ispc);
            files = files(~isFixture & ~[files.isdir]);
        end

        function bytes = readBytes(filePath)
            % readBytes Read a complete file without text-mode transformations.
            arguments (Input)
                filePath
            end
            arguments (Output)
                bytes (1, :) uint8
            end

            % Guarantee closure even when the test assertion interrupts reading.
            fileId = fopen(filePath, "rb");
            cleanup = onCleanup(@() fclose(fileId));
            bytes = fread(fileId, Inf, "*uint8")';
            clear cleanup
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
