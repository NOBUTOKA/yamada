classdef (TestTags = {'ui', 'dialog'}) CallbackManagerDialogTest < matlab.unittest.TestCase
    % CallbackManagerDialogTest Verify callback row availability and command lifecycle.
    %   Hidden native dialogs exercise authoritative refresh, immediate commands,
    %   failure reporting, and target expiry independently of source transactions.

    properties (Access = private)
        States macd.model.CallbackState = macd.model.CallbackState.empty
        TargetValid logical = true
        Fail logical = false
        Calls double = 0
    end

    methods (Test)
        function showsOrderedMutuallyExclusiveStates(testCase)
            % showsOrderedMutuallyExclusiveStates Display absent, existing and unsafe rows in order.
            dialog = testCase.fixture();
            cleanup = onCleanup(@() delete(dialog));
            figure = findall(0, "Tag", "macd-callback-manager");
            add = findall(figure, "Tag", "macd-callback-add");
            remove = findall(figure, "Tag", "macd-callback-delete");
            testCase.verifyEqual(numel(add), 3);
            testCase.verifyEqual(string(figure.WindowStyle), "modal");
            testCase.verifyEqual(string(add(arrayfun(@(button) button.Layout.Row == 1, add)).Enable), "on");
            testCase.verifyEqual(string(remove(arrayfun(@(button) button.Layout.Row == 1, remove)).Enable), "off");
            testCase.verifyEqual(string(add(arrayfun(@(button) button.Layout.Row == 2, add)).Enable), "off");
            testCase.verifyEqual(string(remove(arrayfun(@(button) button.Layout.Row == 2, remove)).Enable), "on");
            testCase.verifyEqual(string(add(arrayfun(@(button) button.Layout.Row == 3, add)).Enable), "off");
            testCase.verifyEqual(string(remove(arrayfun(@(button) button.Layout.Row == 3, remove)).Enable), "off");
            testCase.verifyEqual(string(add(arrayfun(@(button) button.Layout.Row == 3, add)).Tooltip), "Shared method");
        end

        function refreshesAfterSuccessAndReportsFailure(testCase)
            % refreshesAfterSuccessAndReportsFailure Avoid optimistic state changes on rejected commands.
            dialog = testCase.fixture();
            cleanup = onCleanup(@() delete(dialog));
            figure = findall(0, "Tag", "macd-callback-manager");
            add = findall(figure, "Tag", "macd-callback-add", "UserData", "FirstFcn");
            testCase.Fail = true;
            add.ButtonPushedFcn(add, []);
            message = findall(figure, "Tag", "macd-callback-message");
            testCase.verifyEqual(string(message.Text), "Rejected");
            add = findall(figure, "Tag", "macd-callback-add", "UserData", "FirstFcn");
            testCase.verifyEqual(string(add.Enable), "on");
            testCase.Fail = false;
            add.ButtonPushedFcn(add, []);
            remove = findall(figure, "Tag", "macd-callback-delete", "UserData", "FirstFcn");
            testCase.verifyEqual(string(remove.Enable), "on");
            testCase.verifyEqual(testCase.Calls, 2);
        end

        function closesExpiredTargetAndSupportsLongLists(testCase)
            % closesExpiredTargetAndSupportsLongLists Exercise scrolling and expired document closure.
            dialog = testCase.fixture();
            for index = 4:40
                testCase.States(end + 1) = macd.model.CallbackState("Fcn" + index, "absent");
            end
            dialog.refresh();
            figure = findall(0, "Tag", "macd-callback-manager");
            testCase.verifyEqual(numel(findall(figure, "Tag", "macd-callback-add")), 40);
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
                dialog (1, 1) macd.ui.CallbackManagerDialog
            end
            testCase.TargetValid = true;
            testCase.Fail = false;
            testCase.Calls = 0;
            testCase.States = [macd.model.CallbackState("FirstFcn", "absent"), ...
                macd.model.CallbackState("SecondFcn", "editable"), ...
                macd.model.CallbackState("ThirdFcn", "unsupported", "Shared method")];
            dialog = macd.ui.CallbackManagerDialog("Button", @() testCase.States, ...
                @(name, action) testCase.commit(name, action), @() testCase.TargetValid, false);
        end

        function message = commit(testCase, name, action)
            % commit Emulate immediate model results without coupling UI tests to source generation.
            arguments (Input)
                testCase (1, 1) CallbackManagerDialogTest
                name (1, 1) string
                action (1, 1) string
            end
            arguments (Output)
                message (1, 1) string
            end
            testCase.Calls = testCase.Calls + 1;
            message = "";
            if testCase.Fail, message = "Rejected"; return, end
            state = "editable";
            if action == "Delete", state = "absent"; end
            index = find(string({testCase.States.Name}) == name);
            testCase.States(index) = macd.model.CallbackState(name, state);
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
