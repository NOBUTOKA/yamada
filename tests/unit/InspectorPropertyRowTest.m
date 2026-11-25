classdef (TestTags = {'inspector', 'ui'}) InspectorPropertyRowTest < matlab.unittest.TestCase
    % InspectorPropertyRowTest Verify native property-row draft and error behavior.
    %   These tests use the real controls and prove a rejected edit stays in the
    %   editor while the model callback reports an inline error.

    methods (Test, TestTags = {'fast'})
        % Guarantee: rejected text stays visible with its error and never reaches the model, even when the row is rebuilt.
        % Failure mode: an invalid draft is committed, silently reverted, or lost when a refresh replaces the row.
        function retainsRejectedTextAndShowsInlineError(testCase)
            % retainsRejectedTextAndShowsInlineError Keep an invalid draft out of the model callback.

            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            grid = uigridlayout(figure, [1 1]);
            definition = yamada.model.PropertyDefinition("Position", [], false, true, ...
                struct("editor", "numericVector"));
            row = yamada.ui.inspector.InspectorPropertyRow(grid, 1, "component-1", ...
                definition, @(~, ~, ~) "Enter a finite numeric vector."); %#ok<NASGU>
            editor = findall(figure, "Tag", "yamada-inspector-property-editor");
            editor.Value = "not a vector";
            editor.ValueChangedFcn(editor, struct());
            drawnow;
            testCase.verifyEqual(string(editor.Value), "not a vector");
            testCase.verifyEqual(string(editor.Tooltip), "Enter a finite numeric vector.");
            clear cleanup
        end
    end

    methods (Test)
        % Guarantee: the Units editor of a child inside a container that resizes its children turns yellow for non-pixel Units.
        % Failure mode: the auto-resize risk appears only in the diagnostics list, or the tint stays after pixels are restored.
        function nonPixelUnitsUnderAutoResizeTintsUnitsEditor(testCase)
            % nonPixelUnitsUnderAutoResizeTintsUnitsEditor Tint and explain the Units dropdown of a figure child.
            app = yamada(Visible="off");
            cleanup = onCleanup(@() deleteIfValid(app));
            figure = findall(0, "Tag", "yamada-editor");
            tables = findall(figure, "Type", "uitable");
            palette = tables(arrayfun(@(item) any(string(item.ColumnName) == "Category"), tables));
            index = find(string(palette.Data(:, 1)) == "Panel", 1);
            palette.DoubleClickedFcn(palette, struct("InteractionInformation", struct("Row", index)));

            % Normalized units under the root figure, whose AutoResizeChildren stays 'on', warn.
            editor = unitsEditor(figure);
            normal = editor.BackgroundColor;
            editor.Value = "normalized";
            editor.ValueChangedFcn(editor, struct());
            editor = unitsEditor(figure);
            testCase.verifyNotEqual(editor.BackgroundColor, normal);
            testCase.verifySubstring(string(editor.Tooltip), "AutoResizeChildren");

            % Pixel units clear the tint.
            editor.Value = "pixels";
            editor.ValueChangedFcn(editor, struct());
            editor = unitsEditor(figure);
            testCase.verifyEqual(editor.BackgroundColor, normal);
            clear cleanup
        end

        function acceptedInspectorEditRetainsNativeEditor(testCase)
            % acceptedInspectorEditRetainsNativeEditor Avoid replacing rows during a value-only refresh.
            % Guarantee: a value-only refresh after an accepted edit reuses the native editor.
            % Failure mode: the row is recreated on each commit, losing focus and flashing the hidden figure.
            app = yamada(Visible="off");
            cleanup = onCleanup(@() deleteIfValid(app));
            figure = findall(0, "Tag", "yamada-editor");
            testCase.verifyEqual(string(figure.Visible), "off");
            tables = findall(figure, "Type", "uitable");
            palette = tables(arrayfun(@(item) any(string(item.ColumnName) == "Category"), tables));
            index = find(string(palette.Data(:, 1)) == "Label", 1);
            palette.DoubleClickedFcn(palette, struct("InteractionInformation", struct("Row", index)));
            labels = findall(figure, "Tag", "yamada-inspector-property-label");
            label = labels(string({labels.Text}) == "FontSize");
            editor = findall(label.Parent, "Tag", "yamada-inspector-property-editor");
            editor.Value = 19;
            editor.ValueChangedFcn(editor, struct());
            testCase.verifyTrue(isvalid(editor));
            testCase.verifyEqual(app.Document.getComponent(app.SelectedComponentId).getProperty("FontSize").LiteralValue, 19);
        end

        function restoresRejectedDraftAcrossRowReplacement(testCase)
            % restoresRejectedDraftAcrossRowReplacement Restore view-only invalid text.
            % Guarantee and failure mode: shared with retainsRejectedTextAndShowsInlineError.

            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            grid = uigridlayout(figure, [2 1]);
            definition = yamada.model.PropertyDefinition("Position", [], false, true, ...
                struct("editor", "numericVector"));
            first = yamada.ui.inspector.InspectorPropertyRow(grid, 1, "component-1", ...
                definition, @(~, ~, ~) "Enter a finite numeric vector.");
            firstEditor = findall(grid, "Tag", "yamada-inspector-property-editor");
            firstEditor.Value = "bad draft";
            firstEditor.ValueChangedFcn(firstEditor, struct());
            state = first.snapshotTransientState();
            second = yamada.ui.inspector.InspectorPropertyRow(grid, 2, "component-1", ...
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

function editor = unitsEditor(figure)
% unitsEditor Return the Inspector editor of the Units row.
arguments (Input)
    figure (1, 1) matlab.ui.Figure
end
arguments (Output)
    editor (1, 1)
end
labels = findall(figure, "Tag", "yamada-inspector-property-label");
row = labels(string({labels.Text}) == "Units");
editor = findall(row(1).Parent, "Tag", "yamada-inspector-property-editor");
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
