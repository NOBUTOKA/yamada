classdef (TestTags = {'compatibility', 'ui'}) NativeBehaviorTest < matlab.unittest.TestCase
    % NativeBehaviorTest Observe MATLAB behavior outside the product regression suite.
    %   Run these owned native fixtures explicitly when reviewing a MATLAB release.
    %   They do not validate yamada model, source, or Preview behavior.

    methods (Test)
        function pushButtonContextMenuRegistrationKeepsStoredInputs(testCase)
            % pushButtonContextMenuRegistrationKeepsStoredInputs Verify bounded registration without opening callbacks.
            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() delete(figure));
            setappdata(figure, "ContextOpened", false);
            menu = uicontextmenu(figure, ContextMenuOpeningFcn=@(~,~) setappdata(figure, "ContextOpened", true));
            button = uibutton(figure, Text="retained", Position=[10 20 130 35]);
            drawnow;
            property = findprop(button, "ContextMenu");
            testCase.verifyEqual(string(property.SetAccess), "public");
            before = get(button);
            button.ContextMenu = menu;
            drawnow;
            testCase.verifyEqual(button.ContextMenu, menu);
            after = get(button);
            fields = intersect(fieldnames(before), {'ContextMenu', 'UIContextMenu'});
            testCase.verifyEqual(rmfield(after, fields), rmfield(before, fields));
            testCase.verifyFalse(getappdata(figure, "ContextOpened"));
            button.ContextMenu = [];
            testCase.verifyEmpty(button.ContextMenu);
            testCase.verifyFalse(getappdata(figure, "ContextOpened"));
        end

        function parentReassignmentChangesDestinationGroupSelection(testCase)
            % parentReassignmentChangesDestinationGroupSelection Confirm cross-component effects outside the modeled constructor hierarchy.
            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() delete(figure));
            left = uibuttongroup(figure);
            right = uibuttongroup(figure);
            moved = uiradiobutton(left);
            other = uiradiobutton(right);
            testCase.verifyTrue(other.Value);
            moved.Parent = right;
            moved.Value = true;
            testCase.verifyFalse(other.Value);
            testCase.verifyEqual(right.SelectedObject, moved);
        end

        function toggleToolCallbacksDependOnFigureContext(testCase)
            % toggleToolCallbacksDependOnFigureContext Distinguish native context behavior from registration.
            for factory = ["uifigure", "figure"]
                parent = feval(factory, "Visible", "off");
                cleanup = onCleanup(@() delete(parent));
                tools = uitoolbar(parent);
                setappdata(parent, "CallbackCount", 0);
                tool = uitoggletool(tools, OnCallback=@(~,~) setappdata(parent, "CallbackCount", ...
                    getappdata(parent, "CallbackCount") + 1));
                drawnow;
                tool.State = "on";
                drawnow;
                count = getappdata(parent, "CallbackCount");
                testCase.verifyEqual(string(tool.State), "on");
                testCase.verifyTrue(any(count == [0 1]));
                fprintf("TOGGLE_CALLBACK_CONTEXT Factory=%s Count=%d\n", factory, count);
                % Readiness-dependent execution is not promoted to a static callback policy.
                feval(tool.OnCallback, tool, []);
                testCase.verifyEqual(getappdata(parent, "CallbackCount"), count + 1);
                clear cleanup
            end
        end

        function implicitValueChangesAreSeparateFromExplicitWrites(testCase)
            % implicitValueChangesAreSeparateFromExplicitWrites Pin documented side effects for future state resolution.
            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() delete(figure));
            slider = uislider(figure, "Value", 20);
            slider.Limits = [50 100];
            testCase.verifyEqual(slider.Value, 50);
            field = uieditfield(figure, "numeric", "Value", 2.4);
            field.RoundFractionalValues = "on";
            testCase.verifyEqual(field.Value, 2);
            textField = uieditfield(figure, "text", "Value", "Hello");
            textField.CharacterLimits = [6 Inf];
            testCase.verifyEqual(string(textField.Value), "");
        end

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

        function nativeUITableAcceptsMixedCellDataWithCharacterVectors(testCase)
            % nativeUITableAcceptsMixedCellDataWithCharacterVectors Verify the runtime cell-array contract.

            owner = uifigure("Visible", "off");
            cleanup = onCleanup(@() delete(owner));
            data = {1, 'Text'; [], true};
            control = uitable(owner, "Data", data);

            testCase.verifyEqual(control.Data, data);
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
