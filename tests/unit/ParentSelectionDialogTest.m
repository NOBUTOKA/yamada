classdef (TestTags = {'ui', 'editorShell', 'dialog'}) ParentSelectionDialogTest < matlab.unittest.TestCase
    % ParentSelectionDialogTest Verify parent-choice lifecycle and stale availability.
    %   Hidden native controls exercise injected commands without editing a document.

    properties (Access = private)
        States struct = struct("Id", "parent", "Name", "Panel", "Enabled", true, "Reason", "")
        ReceivedId string = ""
    end

    methods (Test)
        function successfulMoveClosesDialog(testCase)
            % successfulMoveClosesDialog Dispatch one stable destination identity after revalidation.
            dialog = macd.ui.ParentSelectionDialog("Button", @() testCase.States, ...
                @(id) testCase.receive(id), @() true, false);
            cleanup = onCleanup(@() ParentSelectionDialogTest.dispose(dialog));
            figure = findall(0, "Tag", "macd-parent-selection");
            table = findall(figure, "Tag", "macd-parent-destinations");
            move = findall(figure, "Tag", "macd-parent-move");
            table.CellSelectionCallback(table, struct("Indices", [1 1]));
            testCase.verifyEqual(string(move.Enable), "on");
            move.ButtonPushedFcn(move, []);
            testCase.verifyEqual(testCase.ReceivedId, "parent");
            testCase.verifyFalse(dialog.isOpen());
        end

        function changedAvailabilityPreventsMoveAndCancelDoesNotDispatch(testCase)
            % changedAvailabilityPreventsMoveAndCancelDoesNotDispatch Reject a previously enabled destination safely.
            dialog = macd.ui.ParentSelectionDialog("Button", @() testCase.States, ...
                @(id) testCase.receive(id), @() true, false);
            cleanup = onCleanup(@() ParentSelectionDialogTest.dispose(dialog));
            figure = findall(0, "Tag", "macd-parent-selection");
            table = findall(figure, "Tag", "macd-parent-destinations");
            move = findall(figure, "Tag", "macd-parent-move");
            table.CellSelectionCallback(table, struct("Indices", [1 1]));
            testCase.States.Enabled = false;
            testCase.States.Reason = "Destination changed.";
            move.ButtonPushedFcn(move, []);
            testCase.verifyEqual(string(move.Enable), "off");
            testCase.verifyEqual(testCase.ReceivedId, "");
            cancel = findall(figure, "Tag", "macd-parent-cancel");
            cancel.ButtonPushedFcn(cancel, []);
            testCase.verifyFalse(dialog.isOpen());
        end
    end

    methods (Access = private)
        function message = receive(testCase, id)
            % receive Record the requested destination without changing any model.
            arguments (Input)
                testCase (1, 1) ParentSelectionDialogTest
                id (1, 1) string
            end
            arguments (Output)
                message (1, 1) string
            end
            testCase.ReceivedId = id;
            message = "";
        end
    end

    methods (Static, Access = private)
        function dispose(dialog)
            % dispose Release a still-valid hidden dialog after any assertion failure.
            arguments (Input)
                dialog
            end
            if isvalid(dialog), delete(dialog); end
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
