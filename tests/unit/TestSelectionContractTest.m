classdef (TestTags = {'selectionContract'}) TestSelectionContractTest < matlab.unittest.TestCase
    % TestSelectionContractTest Verify the tags that define documented test profiles.
    %   This class guards the test-tag taxonomy so new tests cannot silently fall
    %   outside the quick profile or broaden its UI smoke coverage by accident.

    methods (Test)
        function quickTagContainsEveryNonUiTestAndOnlyTheUiSmoke(testCase)
            % quickTagContainsEveryNonUiTestAndOnlyTheUiSmoke Verify fast coverage.

            [allSuite, uiSuite] = TestSelectionContractTest.discoverSuites();
            quickSuite = testsuite(TestSelectionContractTest.testRoot(), ...
                "Tag", "fast");
            contractSuite = testsuite(TestSelectionContractTest.testRoot(), ...
                "Tag", "selectionContract");
            allNames = string({allSuite.Name});
            uiNames = string({uiSuite.Name});
            quickNames = string({quickSuite.Name});
            contractNames = string({contractSuite.Name});
            expectedUiSmoke = [ ...
                "PreviewRendererTest/safePreviewMatchesTrustedFixtureProperties", ...
                "GridLayoutOverlayDataBuilderTest/publishesFixedTrackBoundsAndImmediateChildren", ...
                "DefaultValueProviderTest/probesOneFixtureForOneSurface", ...
                "InspectorPropertyRowTest/retainsRejectedTextAndShowsInlineError", ...
                "InspectorViewTest/createsScrollableNativeGrid", ...
                "PositionEditorTest/verticalFieldsAndLinkedSizesCommitOnce", ...
                "PositionEditorTest/fixedDimensionTooltipsFollowOrientation", ...
                "PositionEditorTest/rowRebindingRejectsStaleNumericEvents", ...
                "PropertyEditorFactoryTest/createsOnOffCheckBox", ...
                "PropertyEditorFactoryTest/createsNativeDateTimeEditors", ...
                "PropertyEditorFactoryTest/itemSelectionDropDownMapsItemsDataAndRefreshesItems", ...
                "PropertyEditorFactoryTest/tableDataRowsShareOneTypedTableEditor", ...
                "DialogTransactionTest/structuredDataApplyEmitsOneTypedBatch", ...
                "TableDataEditorDialogTest/addDeleteAndApplyCommitOneTableBatch", ...
                "EditorInteractionTest/editorBuildsEditingSurfaces", ...
                "EditorInteractionTest/deletingTreeLeafSelectsParentWithoutRebuildingBranches", ...
                "EditorInteractionTest/gridOverlayTrackActionCommitsOneValidatedTrackChange", ...
                "EditorInteractionTest/fontStyleButtonCommitsCatalogChoice"];

            % Bound quick's explicit UI smoke list; the full UI suite may grow.
            testCase.verifyEqual(sort(quickNames), sort([ ...
                setdiff(allNames, [uiNames, contractNames]), expectedUiSmoke]));
            testCase.verifyEqual(sort(intersect(quickNames, uiNames)), sort(expectedUiSmoke));

            % Keep documented areas populated without reconstructing the selector in tests.
            areas = ["parser", "catalog", "model", "generation", "preview", ...
                "gridOverlay", "inspector", "dialog", "editorShell", "previewTab", "lifecycle"];
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
