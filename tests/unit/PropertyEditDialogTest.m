classdef (TestTags = {'dialog', 'inspector', 'ui'}) PropertyEditDialogTest < matlab.unittest.TestCase
    % PropertyEditDialogTest Verify the shared property edit dialog owns the only commit path.
    %   These tests show a minimal one-field editor hidden and invoke the bound
    %   callbacks, without opening a visible window.

    methods (Test)
        % Guarantee: Apply commits the read draft exactly once as one batch, and Cancel or closing the window commits nothing.
        % Failure mode: a dialog commits on each edit, commits twice, or leaks an unapplied draft when it is dismissed.
        function applyCommitsOnceAndDismissalCommitsNothing(testCase)
            % applyCommitsOnceAndDismissalCommitsNothing Check Apply, Cancel, and close request.
            for dismissal = ["apply", "cancel", "close"]
                [dialog, owner, cleanup] = showStub(@(~) "");
                field = findall(dialog, "Tag", "text-edit-dialog-stub-field");
                field.Value = "Edited";
                if dismissal == "apply"
                    press(dialog, "text-edit-dialog-stub-apply");
                    commits = getappdata(owner, "commits");
                    testCase.verifySize(commits, [1 1], dismissal);
                    testCase.verifyEqual(commits{1}.Path, "Text", dismissal);
                    testCase.verifyEqual(commits{1}.Value, "Edited", dismissal);
                elseif dismissal == "cancel"
                    press(dialog, "text-edit-dialog-stub-cancel");
                    testCase.verifyEmpty(getappdata(owner, "commits"), dismissal);
                else
                    dialog.CloseRequestFcn(dialog, struct());
                    testCase.verifyEmpty(getappdata(owner, "commits"), dismissal);
                end
                testCase.verifyFalse(isvalid(dialog), dismissal);
                clear cleanup
            end
        end

        % Guarantee: a rejected read or commit keeps the dialog and its draft open, and a later Apply commits the edited draft.
        % Failure mode: an invalid draft still reaches the commit function, or a rejection closes the dialog and loses the draft.
        function rejectionKeepsDraftForAnotherApply(testCase)
            % rejectionKeepsDraftForAnotherApply Reject an empty read, then a commit, then accept.
            [dialog, owner, cleanup] = showStub(@(changes) rejectFirst(changes));
            field = findall(dialog, "Tag", "text-edit-dialog-stub-field");

            % An editor-reported problem never reaches the commit function.
            field.Value = "";
            press(dialog, "text-edit-dialog-stub-apply");
            testCase.verifyEmpty(getappdata(owner, "commits"));
            testCase.verifyTrue(isvalid(dialog));

            % A rejected commit keeps the draft for another attempt.
            field.Value = "Rejected";
            press(dialog, "text-edit-dialog-stub-apply");
            testCase.verifySize(getappdata(owner, "commits"), [1 1]);
            testCase.verifyTrue(isvalid(dialog));
            testCase.verifyEqual(string(field.Value), "Rejected");

            field.Value = "Accepted";
            press(dialog, "text-edit-dialog-stub-apply");
            commits = getappdata(owner, "commits");
            testCase.verifySize(commits, [1 2]);
            testCase.verifyEqual(commits{2}.Value, "Accepted");
            testCase.verifyFalse(isvalid(dialog));
            clear cleanup
        end
    end
end

function [dialog, owner, cleanup] = showStub(responseFcn)
% showStub Show a hidden one-field editor and record each commit.
arguments (Input)
    responseFcn (1, 1) function_handle
end
arguments (Output)
    dialog (1, 1) matlab.ui.Figure
    owner (1, 1) matlab.ui.Figure
    cleanup (1, 1) onCleanup
end

owner = uifigure("Visible", "off");
setappdata(owner, "commits", {});
dialog = yamada.ui.inspector.PropertyEditDialog.show(TextEditDialogStub("Initial"), ...
    @(changes) recordCommit(owner, changes, responseFcn), false);
cleanup = onCleanup(@() deleteAll([dialog owner]));
end

function message = recordCommit(owner, changes, responseFcn)
% recordCommit Record one committed batch and return the scripted response.
arguments (Input)
    owner (1, 1) matlab.ui.Figure
    changes (1, :) struct
    responseFcn (1, 1) function_handle
end
arguments (Output)
    message (1, 1) string
end

commits = getappdata(owner, "commits");
commits{end + 1} = changes;
setappdata(owner, "commits", commits);
message = responseFcn(changes);
end

function message = rejectFirst(changes)
% rejectFirst Reject the value "Rejected" and accept every other value.
arguments (Input)
    changes (1, :) struct
end
arguments (Output)
    message (1, 1) string
end

message = "";
if changes(1).Value == "Rejected"
    message = "The value was rejected.";
end
end

function press(dialog, tag)
% press Invoke the callback of the dialog button with the given tag.
arguments (Input)
    dialog (1, 1) matlab.ui.Figure
    tag (1, 1) string
end

button = findall(dialog, "Tag", tag);
button.ButtonPushedFcn(button, struct());
end

function deleteAll(values)
% deleteAll Delete each UI fixture that remains valid.
arguments (Input)
    values
end

for index = 1:numel(values)
    if isvalid(values(index))
        delete(values(index));
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
