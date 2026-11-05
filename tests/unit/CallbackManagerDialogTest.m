classdef (TestTags = {'ui', 'dialog'}) CallbackManagerDialogTest < matlab.unittest.TestCase
    % CallbackManagerDialogTest Verify callback row availability and command lifecycle.
    %   Hidden native dialogs exercise authoritative refresh, immediate commands,
    %   failure reporting, and target expiry independently of source transactions.

    properties (Access = private)
        States yamada.model.CallbackState = yamada.model.CallbackState.empty
        TargetValid logical = true
        Fail logical = false
        Calls double = 0
        NameResponse string = "ChosenHandler"
    end

    methods (Test)
        function showsOrderedMutuallyExclusiveStates(testCase)
            % showsOrderedMutuallyExclusiveStates Display absent, existing and unsafe rows in order.
            dialog = testCase.fixture();
            cleanup = onCleanup(@() delete(dialog));
            figure = findall(0, "Tag", "yamada-callback-manager");
            controls = findall(figure, "Tag", "yamada-callback-target");
            testCase.verifyEqual(numel(controls), 3);
            testCase.verifyEqual(string(figure.WindowStyle), "modal");
            for row = 1:2
                control = controls(arrayfun(@(item) item.Layout.Row == row, controls));
                testCase.verifyEqual(string(control.Enable), "on");
                testCase.verifyEqual(string(control.ItemsData(1:2)), ["<New...>", "<Disconnect>"]);
            end
            control = controls(arrayfun(@(item) item.Layout.Row == 3, controls));
            testCase.verifyEqual(string(control.Enable), "off");
            testCase.verifyEqual(string(control.Tooltip), "Unsupported expression");
            testCase.verifyEmpty(findall(figure, "Tag", "yamada-callback-add"));
            testCase.verifyEmpty(findall(figure, "Tag", "yamada-callback-delete"));
        end

        function refreshesAfterSuccessAndReportsFailure(testCase)
            % refreshesAfterSuccessAndReportsFailure Avoid optimistic state changes on rejected commands.
            dialog = testCase.fixture();
            cleanup = onCleanup(@() delete(dialog));
            figure = findall(0, "Tag", "yamada-callback-manager");
            testCase.Fail = true;
            testCase.choose(figure, "FirstFcn", "<New...>");
            message = findall(figure, "Tag", "yamada-callback-message");
            testCase.verifyEqual(string(message.Text), "Rejected");
            control = findall(figure, "Tag", "yamada-callback-target", "UserData", "FirstFcn");
            testCase.verifyEqual(string(control.Value), "<Disconnect>");
            testCase.Fail = false;
            testCase.choose(figure, "FirstFcn", "<New...>");
            control = findall(figure, "Tag", "yamada-callback-target", "UserData", "FirstFcn");
            testCase.verifyEqual(string(control.Value), "ChosenHandler");
            testCase.verifyEqual(testCase.Calls, 2);
        end

        function cancellationPreservesSelectionAndDoesNotDispatch(testCase)
            % cancellationPreservesSelectionAndDoesNotDispatch Keep the authoritative binding on name-popup cancellation.
            dialog = testCase.fixture();
            cleanup = onCleanup(@() delete(dialog));
            figure = findall(0, "Tag", "yamada-callback-manager");
            testCase.NameResponse = "";
            testCase.choose(figure, "SecondFcn", "<New...>");
            control = findall(figure, "Tag", "yamada-callback-target", "UserData", "SecondFcn");
            testCase.verifyEqual(string(control.Value), "existing");
            testCase.verifyEqual(testCase.Calls, 0);
            testCase.choose(figure, "SecondFcn", "<Disconnect>");
            control = findall(figure, "Tag", "yamada-callback-target", "UserData", "SecondFcn");
            testCase.verifyEqual(string(control.Value), "<Disconnect>");
        end

        function closesExpiredTargetAndSupportsLongLists(testCase)
            % closesExpiredTargetAndSupportsLongLists Exercise scrolling and expired document closure.
            dialog = testCase.fixture();
            for index = 4:40
                testCase.States(end + 1) = yamada.model.CallbackState("Fcn" + index, "absent");
            end
            dialog.refresh();
            figure = findall(0, "Tag", "yamada-callback-manager");
            testCase.verifyEqual(numel(findall(figure, "Tag", "yamada-callback-target")), 40);
            testCase.TargetValid = false;
            dialog.refresh();
            testCase.verifyFalse(isvalid(figure));
        end
    end

    methods (Access = private)
        function dialog = fixture(testCase)
            % fixture Create a hidden popup with controllable authoritative callback states.
            arguments (Input)
                testCase (1, 1) CallbackManagerDialogTest
            end
            arguments (Output)
                dialog (1, 1) yamada.ui.CallbackManagerDialog
            end
            testCase.TargetValid = true;
            testCase.Fail = false;
            testCase.Calls = 0;
            testCase.NameResponse = "ChosenHandler";
            testCase.States = [yamada.model.CallbackState("FirstFcn", "absent"), ...
                yamada.model.CallbackState("SecondFcn", "editable", "", "existing"), ...
                yamada.model.CallbackState("ThirdFcn", "unsupported", "Unsupported expression")];
            dialog = yamada.ui.CallbackManagerDialog("Button", @() testCase.States, ...
                @(name, action, handler) testCase.commit(name, action, handler), @() testCase.TargetValid, false, @() [], ...
                @(~) struct("Name", "existing", "Label", "existing(app)"), ...
                @(~) "DefaultPushed", @(~) testCase.NameResponse);
        end

        function choose(~, figure, name, value)
            % choose Dispatch the actual dropdown callback with a chosen item.
            arguments (Input)
                ~
                figure (1, 1) matlab.ui.Figure
                name (1, 1) string
                value (1, 1) string
            end
            control = findall(figure, "Tag", "yamada-callback-target", "UserData", name);
            control.Value = value;
            control.ValueChangedFcn(control, []);
        end

        function message = commit(testCase, name, action, handler)
            % commit Emulate immediate model results without coupling UI tests to source generation.
            arguments (Input)
                testCase (1, 1) CallbackManagerDialogTest
                name (1, 1) string
                action (1, 1) string
                handler (1, 1) string
            end
            arguments (Output)
                message (1, 1) string
            end
            testCase.Calls = testCase.Calls + 1;
            message = "";
            if testCase.Fail, message = "Rejected"; return, end
            state = "editable";
            if action == "Disconnect", state = "absent"; end
            index = find(string({testCase.States.Name}) == name);
            testCase.States(index) = yamada.model.CallbackState(name, state, "", handler);
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
