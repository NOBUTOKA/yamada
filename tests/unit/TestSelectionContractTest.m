classdef (TestTags = {'selectionContract'}) TestSelectionContractTest < matlab.unittest.TestCase
    % TestSelectionContractTest Verify the tags that define documented test profiles.
    %   This class guards the test-tag taxonomy so new tests cannot silently fall
    %   outside the quick profile or broaden its UI smoke coverage by accident.
    %   Catalog-wide sweeps carry the exhaustive tag and run in full and area
    %   profiles only.

    methods (Test)
        % Guarantee: test tags and runner arguments implement the documented profiles.
        % Failure mode: a new test lacks a profile tag and silently never runs, or a mistyped area runs nothing without an error.
        function quickTagCoversNonUiTestsAndABoundedUiSmoke(testCase)
            % quickTagCoversNonUiTestsAndABoundedUiSmoke Verify fast coverage.

            [allSuite, uiSuite] = TestSelectionContractTest.discoverSuites();
            quickSuite = testsuite(TestSelectionContractTest.testRoot(), ...
                "Tag", "fast");
            contractSuite = testsuite(TestSelectionContractTest.testRoot(), ...
                "Tag", "selectionContract");
            exhaustiveSuite = testsuite(TestSelectionContractTest.testRoot(), ...
                "Tag", "exhaustive");
            allNames = string({allSuite.Name});
            uiNames = string({uiSuite.Name});
            quickNames = string({quickSuite.Name});
            contractNames = string({contractSuite.Name});
            exhaustiveNames = string({exhaustiveSuite.Name});
            % Cover all ordinary non-UI tests and retain a bounded UI smoke subset.
            expectedNonUi = setdiff(allNames, [uiNames, contractNames, exhaustiveNames]);
            testCase.verifyEqual(sort(setdiff(quickNames, uiNames)), sort(expectedNonUi));
            uiSmoke = intersect(quickNames, uiNames);
            testCase.verifyNotEmpty(uiSmoke);
            testCase.verifyLessThan(numel(uiSmoke), numel(uiNames));

            % Catalog-wide sweeps stay out of quick but remain in the full suite.
            testCase.verifyNotEmpty(exhaustiveNames);
            testCase.verifyEmpty(intersect(quickNames, exhaustiveNames));

            % Keep documented areas populated without reconstructing the selector in tests.
            areas = ["parser", "catalog", "model", "generation", "preview", ...
                "gridOverlay", "inspector", "dialog", "editorShell", "previewTab", "lifecycle", ...
                "exhaustive"];
            for area = areas
                testCase.verifyTrue(any(arrayfun(@(test) any(strcmp(test.Tags, area)), allSuite)), area);
            end
        end

        function runnerRejectsMissingUnknownAndIrrelevantAreas(testCase)
            % runnerRejectsMissingUnknownAndIrrelevantAreas Verify request diagnostics.

            % Preserve folders that the caller had already registered before this test.
            originalPath = path;
            pathCleanup = onCleanup(@() path(originalPath));
            runnerFolder = fileparts(TestSelectionContractTest.testRoot());
            addpath(runnerFolder);

            testCase.verifyError(@() runYamadaTests("area"), ...
                "yamada:TestSelection:AreasRequired");
            testCase.verifyError(@() runYamadaTests("area", "unknown"), ...
                "yamada:TestSelection:UnsupportedArea");
            testCase.verifyError(@() runYamadaTests("quick", "parser"), ...
                "yamada:TestSelection:UnexpectedAreas");
            testCase.verifyError(@() runYamadaTests("quick", Workers=0), ...
                "MATLAB:validators:mustBePositive");
        end

        function workerRunsEachClaimedClassOnce(testCase)
            % workerRunsEachClaimedClassOnce Verify queue claims, saved results, and repeat safety.
            % Guarantee: parallel workers run each claimed class exactly once and keep results.
            % Failure mode: queue races run a class twice or drop its results, misreporting the suite.

            % Expose the developer runner folder for the worker entry point.
            originalPath = path;
            pathCleanup = onCleanup(@() path(originalPath));
            addpath(fileparts(TestSelectionContractTest.testRoot()));
            fixture = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            queue = string(fixture.Folder);
            mkdir(fullfile(queue, "claims"));
            mkdir(fullfile(queue, "results"));
            writelines("InspectorValueFormatterTest", fullfile(queue, "classes.txt"));

            % The first worker claims and runs the listed class.
            runYamadaTestWorker("quick", "", queue);
            saved = load(fullfile(queue, "results", "1.mat"), "results");
            names = string({saved.results.Name});
            testCase.verifyNotEmpty(names);
            testCase.verifyTrue(all(startsWith(names, "InspectorValueFormatterTest/")));
            testCase.verifyTrue(all([saved.results.Passed]));

            % A later worker finds the claim and leaves the saved results untouched.
            before = dir(fullfile(queue, "results", "1.mat"));
            runYamadaTestWorker("quick", "", queue);
            after = dir(fullfile(queue, "results", "1.mat"));
            testCase.verifyEqual(after.datenum, before.datenum);
            testCase.verifyNumElements(dir(fullfile(queue, "results", "*.mat")), 1);
        end

    end

    methods (Static, Access = private)
        function [allSuite, uiSuite] = discoverSuites()
            % discoverSuites Create the complete and UI-tagged unit suites.

            testRoot = TestSelectionContractTest.testRoot();
            allSuite = testsuite(testRoot);
            uiSuite = testsuite(testRoot, "Tag", "ui");
        end

        function testRoot = testRoot()
            % testRoot Resolve the unit-test directory independently of pwd.

            testPath = mfilename("fullpath");
            projectRoot = fileparts(fileparts(fileparts(testPath)));
            testRoot = fullfile(projectRoot, "tests", "unit");
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
