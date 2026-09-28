classdef (TestTags = {'selectionContract'}) TestSelectionContractTest < matlab.unittest.TestCase
    % TestSelectionContractTest Verify documented quick and area test selection.
    %   This class guards the test-tag taxonomy so new tests cannot silently fall
    %   outside the quick profile or broaden its UI smoke coverage by accident.

    methods (Test)
        function quickProfileContainsEveryNonUiTestAndOnlyTheUiSmoke(testCase)
            % quickProfileContainsEveryNonUiTestAndOnlyTheUiSmoke Verify fast coverage.

            [allSuite, uiSuite] = TestSelectionContractTest.discoverSuites();
            quickSuite = selectYamadaTests("quick");
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
                "PropertyEditorFactoryTest/createsOnOffCheckBox", ...
                "PropertyEditorFactoryTest/createsEnumDropDownFromSchema", ...
                "PropertyEditorFactoryTest/createsNativeDateTimeEditors", ...
                "PropertyEditorFactoryTest/itemSelectionDropDownMapsItemsDataAndRefreshesItems", ...
                "PropertyEditorFactoryTest/tableDataRowsShareOneTypedTableEditor", ...
                "DialogTransactionTest/structuredDataApplyEmitsOneTypedBatch", ...
                "TableDataEditorDialogTest/addDeleteAndApplyCommitOneTableBatch", ...
                "EditorInteractionTest/editorBuildsEditingSurfaces", ...
                "EditorInteractionTest/hierarchySelectionCallbackUpdatesInspector", ...
                "EditorInteractionTest/gridOverlayTrackActionCommitsOneValidatedTrackChange", ...
                "EditorInteractionTest/fontStyleButtonCommitsCatalogChoice"];

            % Keep all model and source checks in quick while bounding UI startup.
            testCase.verifyEqual(sort(quickNames), sort([ ...
                setdiff(allNames, [uiNames, contractNames]), expectedUiSmoke]));
            testCase.verifyEqual(sort(intersect(quickNames, uiNames)), sort(expectedUiSmoke));
            testCase.verifyEqual(numel(uiNames), 96);
        end

        function areaProfilesAlwaysContainQuickCoverage(testCase)
            % areaProfilesAlwaysContainQuickCoverage Verify additive area selection.

            [allSuite, ~] = TestSelectionContractTest.discoverSuites();
            quickSuite = selectYamadaTests("quick");
            quickNames = string({quickSuite.Name});
            areas = ["parser", "catalog", "model", "generation", "preview", ...
                "gridOverlay", "inspector", "dialog", "editorShell", "previewTab", ...
                "lifecycle"];
            allNames = string({allSuite.Name});
            for area = areas
                taggedSuite = testsuite(TestSelectionContractTest.testRoot(), ...
                    "Tag", area);
                selectedSuite = selectYamadaTests("area", area);
                taggedNames = string({taggedSuite.Name});
                selectedNames = string({selectedSuite.Name});
                testCase.verifyNotEmpty(taggedNames, area);
                testCase.verifyTrue(all(ismember(quickNames, selectedNames)), area);
                testCase.verifyTrue(all(ismember(taggedNames, selectedNames)), area);
                testCase.verifyTrue(all(ismember(selectedNames, allNames)), area);
            end
        end

        function fullProfileMatchesUnfilteredUnitSuite(testCase)
            % fullProfileMatchesUnfilteredUnitSuite Verify the release gate remains complete.

            [allSuite, ~] = TestSelectionContractTest.discoverSuites();
            fullSuite = selectYamadaTests("full");
            testCase.verifyEqual(sort(string({fullSuite.Name})), ...
                sort(string({allSuite.Name})));
        end

        function profilesRejectMissingUnknownAndIrrelevantAreas(testCase)
            % profilesRejectMissingUnknownAndIrrelevantAreas Verify request diagnostics.

            testCase.verifyError(@() selectYamadaTests("area"), ...
                "yamada:TestSelection:AreasRequired");
            testCase.verifyError(@() selectYamadaTests("area", "unknown"), ...
                "yamada:TestSelection:UnsupportedArea");
            testCase.verifyError(@() selectYamadaTests("quick", "parser"), ...
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
