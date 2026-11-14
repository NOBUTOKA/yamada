classdef (TestTags = {'packaging', 'lifecycle', 'ui'}) ToolboxPackagingTest < matlab.unittest.TestCase
    % ToolboxPackagingTest Verify shipped inputs and generated Toolbox registration.
    %   A real package build checks archive bytes and native metadata instead of
    %   asserting only the settings passed to the packaging function. The build
    %   uses a fixed source identity, so these checks do not depend on Git; the
    %   Git provenance itself belongs to buildYamadaToolbox and the release gate.

    properties (Constant, Access = private)
        SourceCommit = string(repmat('0', 1, 40))
    end

    properties (Access = private)
        ProjectRoot string
        Artifacts struct
        Metadata struct
        Files string
        ExtractedRoot string
    end

    methods (TestClassSetup)
        function buildCandidate(testCase)
            % buildCandidate Build one isolated archive for all distribution contract checks.
            testCase.ProjectRoot = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(testCase.ProjectRoot, "dev", "release")));
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            [testCase.Files, testCase.Metadata] = yamadaToolboxFiles(testCase.ProjectRoot);
            testCase.Artifacts = packageYamadaToolbox(fullfile(string(folder.Folder), "candidate"), ...
                @() testCase.fixedSource());
            testCase.ExtractedRoot = fullfile(string(folder.Folder), "extracted");
            unzip(testCase.Artifacts.toolbox, testCase.ExtractedRoot);
        end
    end

    methods (Test)
        function payloadMatchesSelectedSourceExactly(testCase)
            % payloadMatchesSelectedSourceExactly Reject undeclared or changed archive payload files.
            entries = dir(fullfile(testCase.ExtractedRoot, "fsroot", "**", "*"));
            entries = entries(~[entries.isdir]);
            payloadRoot = fullfile(testCase.ExtractedRoot, "fsroot");
            actual = replace(string(fullfile({entries.folder}, {entries.name})), "\", "/");
            actual = extractAfter(actual, strlength(payloadRoot) + 1);
            relative = replace(extractAfter(testCase.Files, strlength(testCase.ProjectRoot) + 1), "\", "/");
            testCase.verifyEqual(sort(actual(:)), sort([relative; "DesktopToolset.xml"]));
            for filePath = testCase.Files'
                name = extractAfter(filePath, strlength(testCase.ProjectRoot) + 1);
                shipped = fullfile(payloadRoot, name);
                testCase.verifyEqual(readBytes(shipped), readBytes(filePath), name);
            end
            testCase.verifyFalse(any(startsWith(actual, ["tests/", "dev/", ".git/", "testResults/", "build/"])));
        end

        function metadataAndGalleryDescribeTheSupportedRelease(testCase)
            % metadataAndGalleryDescribeTheSupportedRelease Check installed identity and no-output launch metadata.
            root = testCase.ExtractedRoot;
            core = string(fileread(fullfile(root, "metadata", "coreProperties.xml")));
            addon = string(fileread(fullfile(root, "metadata", "addonProperties.xml")));
            requirements = string(fileread(fullfile(root, "metadata", "systemRequirements.xml")));
            paths = string(fileread(fullfile(root, "metadata", "configuration.xml")));
            gallery = string(fileread(fullfile(root, "fsroot", "DesktopToolset.xml")));
            testCase.verifySubstring(core, "<dc:creator>Nobuto Kaitoh</dc:creator>");
            testCase.verifySubstring(core, "<cp:version>" + testCase.Metadata.version + "</cp:version>");
            testCase.verifySubstring(addon, string(testCase.Metadata.identifier));
            testCase.verifySubstring(addon, "<contact>nobutoka@gmail.com</contact>");
            testCase.verifySubstring(requirements, 'MATLABOnline="false" linux="false" mac="false" win="true"');
            testCase.verifySubstring(requirements, 'end="R2024a" start="R2024a"');
            testCase.verifySubstring(paths, "<matlabPath>/</matlabPath>");
            testCase.verifySubstring(gallery, '<callback>yamada</callback>');
            testCase.verifySubstring(gallery, 'label="yamada"');
            testCase.verifyFalse(contains(core + addon + requirements + paths + gallery, testCase.ProjectRoot));
        end

        function manifestAndChecksumMatchActualArtifact(testCase)
            % manifestAndChecksumMatchActualArtifact Check independent SHA-256 and immutable candidate output.
            manifest = jsondecode(fileread(testCase.Artifacts.manifest));
            testCase.verifyEqual(string(manifest.sourceCommit), testCase.SourceCommit);
            testCase.verifyFalse(manifest.sourceDirty);
            bytes = readBytes(testCase.Artifacts.toolbox);
            digest = System.Security.Cryptography.SHA256.Create();
            digestCleanup = onCleanup(@() digest.Dispose());
            hash = uint8(digest.ComputeHash(NET.convertArray(bytes, "System.Byte")));
            expected = lower(string(reshape(dec2hex(hash, 2)', 1, [])));
            testCase.verifyEqual(string(manifest.toolboxSha256), expected);
            testCase.verifyEqual(numel(manifest.files), numel(testCase.Files));
            checksums = strip(string(fileread(testCase.Artifacts.checksums)));
            testCase.verifyEqual(checksums, expected + "  yamada-" + testCase.Metadata.version + ".mltbx");
            testCase.verifyError(@() packageYamadaToolbox(fileparts(testCase.Artifacts.toolbox), ...
                @() testCase.fixedSource()), "yamada:Release:OutputExists");
            testCase.verifyEqual(readBytes(testCase.Artifacts.toolbox), bytes);
        end
    end

    methods (Access = private)
        function source = fixedSource(testCase)
            % fixedSource Return the deterministic clean source identity used by these builds.
            arguments (Input)
                testCase (1, 1) ToolboxPackagingTest
            end
            arguments (Output)
                source (1, 1) struct
            end
            source = struct("commit", testCase.SourceCommit, "dirty", false);
        end
    end
end

function bytes = readBytes(filePath)
% readBytes Read exact payload bytes for independent archive comparison.
arguments (Input)
    filePath (1, 1) string
end
arguments (Output)
    bytes (:, 1) uint8
end
[fileId, message] = fopen(filePath, "rb");
assert(fileId >= 0, "%s", message);
cleanup = onCleanup(@() fclose(fileId));
bytes = fread(fileId, Inf, "*uint8");
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
