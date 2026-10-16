classdef (TestTags = {'ui', 'model', 'generation', 'preview'}) ButtonSelectionRuntimeTest < matlab.unittest.TestCase
    % ButtonSelectionRuntimeTest Verify native group semantics on isolated owned controls.
    %   Neither represented applications nor input callbacks are executed.

    methods (Test)
        function radioAndToggleSettersFollowCreationOrder(testCase)
            % radioAndToggleSettersFollowCreationOrder Check defaults, sibling clearing, and zero fallback.
            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() delete(figure));
            for factory = ["uiradiobutton", "uitogglebutton"]
                group = uibuttongroup(figure);
                first = feval(factory, group);
                second = feval(factory, group);
                testCase.verifyEqual(double([first.Value second.Value]), [1 0]);
                second.Value = 1;
                testCase.verifyEqual(double([first.Value second.Value]), [0 1]);
                testCase.verifyEqual(group.SelectedObject, second);
                first.Value = 0;
                testCase.verifyEqual(double([first.Value second.Value]), [0 1]);
                second.Value = 0;
                testCase.verifyEqual(double([first.Value second.Value]), [1 0]);
                testCase.verifyError(@() set(group, 'SelectedObject', []), 'MATLAB:hg:InvalidSelectedObjectType');
                delete(second);
                expectedError = "MATLAB:ui:RadioButton:noButtonSelected";
                if factory == "uitogglebutton", expectedError = "MATLAB:ui:ToggleButton:noButtonSelected"; end
                testCase.verifyError(@() set(first, 'Value', 0), expectedError);
                testCase.verifyEqual(double(first.Value), 1);
                delete(group);
            end
        end

        function pastedPanelRetainsPositionAfterParentInitialization(testCase)
            % pastedPanelRetainsPositionAfterParentInitialization Execute only an owned copied-container fixture.
            registry = macd.model.ComponentRegistry.createDefault();
            className = "OwnedAncestor" + erase(string(java.util.UUID.randomUUID()), "-");
            original = macd.model.NewAppFactory.createEmpty(className, registry);
            original.getComponent(original.RootComponentId).setProperty("Visible", "off");
            left = original.insertComponent(registry, "uipanel", original.RootComponentId);
            left.setProperty("Position", [20 20 100 80]);
            original.insertComponent(registry, "uilabel", left.Id);
            right = original.insertComponent(registry, "uipanel", original.RootComponentId);
            right.setProperty("Position", [200 20 300 200]);
            source = macd.source.NewAppGenerator(registry).generate(original);
            document = macd.source.AppSourceParser.parseText(source, registry);
            left = document.getComponentByName(left.Name);
            right = document.getComponentByName(right.Name);
            snapshot = document.copySubtree(left.Id, registry);
            pasted = document.pasteSubtree(snapshot, right.Id, registry);
            source = macd.source.RoundTripGenerator(registry).generate(document);
            testCase.verifyLessThan(strfind(source, "app." + right.Name + ".Position ="), ...
                strfind(source, "app." + pasted.Name + " = uipanel"));
            folder = string(tempname());
            mkdir(folder);
            originalPath = string(path);
            cleanup = onCleanup(@() cleanupOwnedFolder(folder, originalPath));
            addpath(folder);
            macd.source.SourceWriter.write(fullfile(folder, className + ".m"), source);
            app = feval(className);
            appCleanup = onCleanup(@() delete(app));
            drawnow;
            testCase.verifyEqual(app.(pasted.Name).Position, pasted.getProperty("Position").LiteralValue);
            % Release native handles before removing the owned source directory.
            clear appCleanup cleanup
        end

        function verticalSliderRetainsItsNativeFixedWidth(testCase)
            % verticalSliderRetainsItsNativeFixedWidth Verify the finite vertical position normalization.
            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() delete(figure));
            for style = ["slider", "range"]
                slider = uislider(figure, style, Orientation="vertical");
                slider.Position = [10 20 130 35];
                testCase.verifyEqual(slider.Position, [10 20 3 35]);
                delete(slider);
            end
        end

        function constructorsRejectMixedFamiliesAndExcludeStateButtons(testCase)
            % constructorsRejectMixedFamiliesAndExcludeStateButtons Verify constructor values and state-button exclusion.
            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() delete(figure));
            group = uibuttongroup(figure);
            first = uiradiobutton(group, "Value", 0);
            testCase.verifyEqual(double(first.Value), 1);
            testCase.verifyError(@() uitogglebutton(group, Value=1), 'MATLAB:ui:ToggleButton:unknownInput');
            second = uiradiobutton(group, Value=1);
            testCase.verifyEqual(double([first.Value second.Value]), [0 1]);
            state = uibutton(group, "state", Value=true);
            testCase.verifyEqual(group.SelectedObject, second);
            testCase.verifyTrue(state.Value);
            first.Value = 1;
            testCase.verifyEqual(double([first.Value second.Value]), [1 0]);
            testCase.verifyTrue(state.Value);
        end
    end
end

function cleanupOwnedFolder(folder, originalPath)
% cleanupOwnedFolder Restore the path and remove only the test-owned fixture directory.
arguments (Input)
    folder (1, 1) string
    originalPath (1, 1) string
end
path(char(originalPath));
if isfolder(folder), rmdir(folder, "s"); end
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
