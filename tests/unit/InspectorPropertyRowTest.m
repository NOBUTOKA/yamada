classdef InspectorPropertyRowTest < matlab.unittest.TestCase
    % InspectorPropertyRowTest Verify native property-row draft and error behavior.
    %   These tests use the real controls and prove a rejected edit stays in the
    %   editor while the model callback reports an inline error.

    methods (Test)
        function retainsRejectedTextAndShowsInlineError(testCase)
            % retainsRejectedTextAndShowsInlineError Keep an invalid draft out of the model callback.

            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            grid = uigridlayout(figure, [1 1]);
            definition = macd.model.PropertyDefinition("Position", [], false, true, ...
                struct("editor", "numericVector"));
            row = macd.ui.inspector.InspectorPropertyRow(grid, 1, "component-1", ...
                definition, @(~, ~, ~) "Enter a finite numeric vector."); %#ok<NASGU>
            editor = findall(figure, "Tag", "macd-inspector-property-editor");
            editor.Value = "not a vector";
            editor.ValueChangedFcn(editor, struct());
            drawnow;
            testCase.verifyEqual(string(editor.Value), "not a vector");
            testCase.verifyEqual(string(editor.Tooltip), "Enter a finite numeric vector.");
            testCase.verifyEqual(editor.BackgroundColor, [1 0.9 0.9], "AbsTol", 1e-12);
            clear cleanup
        end

        function restoresRejectedDraftAcrossRowReplacement(testCase)
            % restoresRejectedDraftAcrossRowReplacement Restore view-only invalid text.

            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            grid = uigridlayout(figure, [2 1]);
            definition = macd.model.PropertyDefinition("Position", [], false, true, ...
                struct("editor", "numericVector"));
            first = macd.ui.inspector.InspectorPropertyRow(grid, 1, "component-1", ...
                definition, @(~, ~, ~) "Enter a finite numeric vector.");
            firstEditor = findall(grid, "Tag", "macd-inspector-property-editor");
            firstEditor.Value = "bad draft";
            firstEditor.ValueChangedFcn(firstEditor, struct());
            state = first.snapshotTransientState();
            second = macd.ui.inspector.InspectorPropertyRow(grid, 2, "component-1", ...
                definition, @(~, ~, ~) "");
            second.synchronize("[10 20 30 40]", true, [10 20 30 40]);
            second.restoreTransientState(state);
            drawnow;
            restored = second.snapshotTransientState();
            testCase.verifyTrue(restored.HasDraft);
            testCase.verifyEqual(string(restored.Value), "bad draft");
            testCase.verifyEqual(restored.Message, "Enter a finite numeric vector.");
            clear cleanup
        end
    end
end

function deleteIfValid(value)
% deleteIfValid Delete one UI fixture when it remains valid.
arguments (Input)
    value
end

if ~isempty(value) && isvalid(value)
    delete(value);
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
