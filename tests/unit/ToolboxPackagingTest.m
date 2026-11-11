classdef (TestTags = {'packaging', 'lifecycle', 'ui'}) ToolboxPackagingTest < matlab.unittest.TestCase
    % ToolboxPackagingTest Verify shipped inputs and generated Toolbox registration.
    %   A real package build checks archive bytes and native metadata instead of
    %   asserting only the settings passed to the packaging function.

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
            testCase.Artifacts = buildYamadaToolbox(fullfile(string(folder.Folder), "candidate"));
            testCase.ExtractedRoot = fullfile(string(folder.Folder), "extracted");
            unzip(testCase.Artifacts.toolbox, testCase.ExtractedRoot);
        end
    end

    methods (Test)
        function includedExampleRunsAndCloses(testCase)
            % includedExampleRunsAndCloses Exercise the tutorial's real callback and owner cleanup.
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(testCase.ProjectRoot, "examples")));
            app = WelcomeApp;
            testCase.addTeardown(@() deleteIfValid(app));
            figure = findall(0, "Type", "figure", "Name", "Welcome to yamada");
            testCase.assertNumElements(figure, 1);
            button = findall(figure, "Text", "Say hello");
            testCase.assertNumElements(button, 1);
            button.ButtonPushedFcn(button, struct());
            testCase.verifyNumElements(findall(figure, "Text", "Hello from your app!"), 1);
            close(figure);
            testCase.verifyFalse(isvalid(app));
            testCase.verifyEmpty(findall(0, "Type", "figure", "Name", "Welcome to yamada"));
        end

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
            bytes = readBytes(testCase.Artifacts.toolbox);
            digest = System.Security.Cryptography.SHA256.Create();
            digestCleanup = onCleanup(@() digest.Dispose());
            hash = uint8(digest.ComputeHash(NET.convertArray(bytes, "System.Byte")));
            expected = lower(string(reshape(dec2hex(hash, 2)', 1, [])));
            testCase.verifyEqual(string(manifest.toolboxSha256), expected);
            testCase.verifyEqual(numel(manifest.files), numel(testCase.Files));
            checksums = strip(string(fileread(testCase.Artifacts.checksums)));
            testCase.verifyEqual(checksums, expected + "  yamada-" + testCase.Metadata.version + ".mltbx");
            testCase.verifyError(@() buildYamadaToolbox(fileparts(testCase.Artifacts.toolbox)), ...
                "yamada:Release:OutputExists");
            testCase.verifyEqual(readBytes(testCase.Artifacts.toolbox), bytes);
        end

        function includedExampleIsEditableWithoutExecution(testCase)
            % includedExampleIsEditableWithoutExecution Parse the owned tutorial app without creating its window.
            registry = yamada.model.ComponentRegistry.createDefault();
            before = findall(0, "Type", "figure");
            [document, diagnostics] = yamada.source.AppSourceParser.parseFile( ...
                fullfile(testCase.ProjectRoot, "examples", "WelcomeApp.m"), registry);
            testCase.verifyFalse(yamada.validation.ModelValidator.hasErrors(diagnostics));
            testCase.verifyEqual(document.ClassName, "WelcomeApp");
            testCase.verifyNotEmpty(document.getComponentByName("GreetingLabel"));
            testCase.verifyNotEmpty(document.getComponentByName("GreetButton"));
            testCase.verifyEqual(findall(0, "Type", "figure"), before);
        end
    end
end

function deleteIfValid(object)
% deleteIfValid Release a tutorial owner only if a failed test left it alive.
arguments (Input)
    object (1, 1) handle
end
if isvalid(object), delete(object); end
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
