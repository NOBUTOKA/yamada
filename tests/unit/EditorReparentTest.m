classdef (TestTags = {'ui', 'editorShell'}) EditorReparentTest < matlab.uitest.TestCase
    % EditorReparentTest Verify hierarchy parent-choice commands and document lifecycle.
    %   Real editor fixtures preserve explicit targets and atomic model history.

    methods (Test)
        function editMenuMovesAndUndoRestoresParent(testCase)
            % editMenuMovesAndUndoRestoresParent Commit an explicit destination as one undoable edit.
            [app, figure, button, left, right] = testCase.fixture();
            cleanup = onCleanup(@() delete(app));
            testCase.select(figure, button.Id);
            history = app.Document.HistoryIndex;
            item = findall(figure, "Tag", "macd-edit-reparent");
            testCase.assertEqual(string(item.Enable), "on");
            item.MenuSelectedFcn(item, []);
            popup = findall(0, "Tag", "macd-parent-selection");
            table = findall(popup, "Tag", "macd-parent-destinations");
            row = find(string(table.Data(:, 1)) == right.Name, 1);
            testCase.assertTrue(table.Data{row, 2});
            table.CellSelectionCallback(table, struct("Indices", [row 1]));
            move = findall(popup, "Tag", "macd-parent-move");
            move.ButtonPushedFcn(move, []);
            testCase.verifyEqual(button.ParentId, right.Id);
            testCase.verifyEqual(app.SelectedComponentId, button.Id);
            testCase.verifyEqual(app.Document.HistoryIndex, history + 1);
            testCase.verifyFalse(isvalid(popup));
            menus = findall(figure, "Type", "uimenu");
            undo = menus(erase(string({menus.Text}), "&") == "Undo");
            undo.MenuSelectedFcn(undo, []);
            testCase.verifyEqual(button.ParentId, left.Id);
        end

        function nativeContextTargetDoesNotChangeSelection(testCase)
            % nativeContextTargetDoesNotChangeSelection Open parent choices for an unselected component.
            [app, figure, button, left] = testCase.fixture();
            cleanup = onCleanup(@() delete(app));
            testCase.select(figure, app.Document.RootComponentId);
            tree = findall(figure, "Type", "uitree");
            nodes = findall(tree, "Type", "uitreenode");
            node = nodes(arrayfun(@(value) string(value.NodeData) == button.Id, nodes));
            leftNode = nodes(arrayfun(@(value) string(value.NodeData) == left.Id, nodes));
            expand(tree.Children(1));
            expand(leftNode);
            drawnow;
            item = findall(tree.ContextMenu, "Tag", "macd-context-reparent");
            testCase.chooseContextMenu(node, item);
            testCase.verifyEqual(app.SelectedComponentId, app.Document.RootComponentId);
            popup = findall(0, "Tag", "macd-parent-selection");
            testCase.verifySubstring(string(popup.Name), button.Name);
            history = app.Document.HistoryIndex;
            cancel = findall(popup, "Tag", "macd-parent-cancel");
            cancel.ButtonPushedFcn(cancel, []);
            testCase.verifyEqual(app.Document.HistoryIndex, history);
            testCase.verifyEqual(button.ParentId, left.Id);
        end

        function replacementClosesParentChoices(testCase)
            % replacementClosesParentChoices Invalidate a popup when its document is replaced.
            [app, figure, button] = testCase.fixture();
            cleanup = onCleanup(@() delete(app));
            testCase.select(figure, button.Id);
            item = findall(figure, "Tag", "macd-edit-reparent");
            item.MenuSelectedFcn(item, []);
            popup = findall(0, "Tag", "macd-parent-selection");
            app.Document.markSaved();
            menus = findall(figure, "Type", "uimenu");
            item = menus(erase(string({menus.Text}), "&") == "New");
            item.MenuSelectedFcn(item, []);
            testCase.verifyFalse(isvalid(popup));
            testCase.verifyEqual(app.Document.ClassName, "ReplacementApp");
        end
    end

    methods (Access = private)
        function select(~, figure, id)
            % select Dispatch a real tree selection through the editor callback.
            arguments (Input)
                ~
                figure (1, 1) matlab.ui.Figure
                id (1, 1) string
            end
            tree = findall(figure, "Type", "uitree");
            nodes = findall(tree, "Type", "uitreenode");
            node = nodes(arrayfun(@(value) string(value.NodeData) == id, nodes));
            tree.SelectedNodes = node;
            tree.SelectionChangedFcn(tree, struct("SelectedNodes", node));
        end

        function [app, figure, button, left, right] = fixture(testCase)
            % fixture Build two panels and a movable child through palette insertion.
            arguments (Input)
                testCase (1, 1) EditorReparentTest
            end
            arguments (Output)
                app (1, 1) yamada
                figure (1, 1) matlab.ui.Figure
                button (1, 1) macd.model.ComponentRecord
                left (1, 1) macd.model.ComponentRecord
                right (1, 1) macd.model.ComponentRecord
            end
            lifecycle = macd.ui.DocumentLifecycleService(struct( ...
                "RequestNewClassNameFcn", @() deal(true, "ReplacementApp"), ...
                "ConfirmUnsavedChangesFcn", @() "discard"));
            app = yamada(lifecycle);
            figure = findall(0, "Type", "figure", "Tag", "macd-yamada-editor");
            tables = findall(figure, "Type", "uitable");
            palette = tables(arrayfun(@(table) any(string(table.ColumnName) == "Category"), tables));
            row = find(string(palette.Data(:, 1)) == "Panel", 1);
            palette.DoubleClickedFcn(palette, struct("InteractionInformation", struct("Row", row)));
            left = app.Document.getComponent(app.SelectedComponentId);
            buttonRow = find(string(palette.Data(:, 1)) == "Button", 1);
            palette.DoubleClickedFcn(palette, struct("InteractionInformation", struct("Row", buttonRow)));
            button = app.Document.getComponent(app.SelectedComponentId);
            testCase.select(figure, app.Document.RootComponentId);
            palette.DoubleClickedFcn(palette, struct("InteractionInformation", struct("Row", row)));
            right = app.Document.getComponent(app.SelectedComponentId);
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
