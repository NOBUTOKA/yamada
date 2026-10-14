classdef (TestTags = {'ui', 'editorShell'}) EditorClipboardTest < matlab.uitest.TestCase
    % EditorClipboardTest Verify the three shared clipboard command entry points.
    %   Real editor fixtures exercise menus, keyboard focus and native context targets.

    methods (Test)
        function editMenuUsesAtomicSubtreeCommands(testCase)
            % editMenuUsesAtomicSubtreeCommands Exercise Copy, Paste and Cut through Edit menus.
            testCase.exerciseRoute("menu");
        end

        function keyboardUsesAtomicSubtreeCommands(testCase)
            % keyboardUsesAtomicSubtreeCommands Exercise all clipboard keys on the hierarchy surface.
            testCase.exerciseRoute("keyboard");
        end

        function contextUsesIndependentTargets(testCase)
            % contextUsesIndependentTargets Exercise native right-click commands without selection changes on copy.
            testCase.exerciseRoute("context");
        end

        function textAndTabFocusDoNotTriggerComponentCommands(testCase)
            % textAndTabFocusDoNotTriggerComponentCommands Preserve text ownership and invalidate stale focus.
            [app, figure, panelId] = testCase.fixture();
            cleanup = onCleanup(@() delete(app));
            testCase.select(figure, panelId);
            copy = findall(figure, "Tag", "macd-edit-copy");
            copy.MenuSelectedFcn(copy, []);
            field = uieditfield(figure, "Value", "Local text");
            figure.CurrentObject = field;
            before = app.Document.Components;
            for key = ["c", "x", "v"]
                figure.WindowKeyPressFcn(figure, struct("Key", key, "Modifier", {{'control'}}));
            end
            testCase.verifyEqual(app.Document.Components, before);
            tree = findall(figure, "Type", "uitree");
            figure.CurrentObject = tree;
            figure.WindowKeyPressFcn(figure, struct("Key", "tab", "Modifier", {{}}));
            figure.WindowKeyPressFcn(figure, struct("Key", "v", "Modifier", {{'control'}}));
            testCase.verifyEqual(app.Document.Components, before);
        end

        function documentReplacementClearsClipboard(testCase)
            % documentReplacementClearsClipboard Do not offer prior-document content after successful New.
            [app, figure, panelId] = testCase.fixture();
            cleanup = onCleanup(@() delete(app));
            testCase.select(figure, panelId);
            copy = findall(figure, "Tag", "macd-edit-copy");
            copy.MenuSelectedFcn(copy, []);
            app.Document.markSaved();
            menus = findall(figure, "Type", "uimenu");
            item = menus(erase(string({menus.Text}), "&") == "New");
            item.MenuSelectedFcn(item, []);
            paste = findall(figure, "Tag", "macd-edit-paste");
            testCase.verifyEqual(string(paste.Enable), "off");
            testCase.verifyEqual(numel(app.Document.Components), 1);
            status = findall(figure, "Tag", "macd-status");
            testCase.verifySubstring(string(status.Tooltip), "The document root cannot be copied.");
        end
    end

    methods (Access = private)
        function exerciseRoute(testCase, route)
            % exerciseRoute Verify complete subtree changes through one public UI command route.
            arguments (Input)
                testCase (1, 1) EditorClipboardTest
                route (1, 1) string
            end
            [app, figure, panelId] = testCase.fixture();
            cleanup = onCleanup(@() delete(app));
            rootId = app.Document.RootComponentId;
            testCase.select(figure, panelId);
            if route == "context", testCase.select(figure, rootId); end
            selected = app.SelectedComponentId;
            history = app.Document.HistoryIndex;
            testCase.invoke(figure, "Copy", route, panelId);
            testCase.verifyEqual(app.SelectedComponentId, selected);
            testCase.verifyEqual(app.Document.HistoryIndex, history);
            testCase.select(figure, rootId);
            testCase.invoke(figure, "Paste", route, rootId);
            pastedId = app.SelectedComponentId;
            pasted = app.Document.getComponent(pastedId);
            testCase.verifyNotEqual(pastedId, panelId);
            testCase.verifyEqual(pasted.ParentId, rootId);
            testCase.verifyEqual(numel(pasted.Children), 1);
            testCase.verifyEqual(app.Document.HistoryIndex, history + 1);
            testCase.invoke(figure, "Cut", route, pastedId);
            testCase.verifyEmpty(app.Document.getComponent(pastedId));
            testCase.verifyEqual(app.SelectedComponentId, rootId);
            testCase.verifyEqual(app.Document.HistoryIndex, history + 2);
            menus = findall(figure, "Type", "uimenu");
            undo = menus(erase(string({menus.Text}), "&") == "Undo");
            undo.MenuSelectedFcn(undo, []);
            testCase.verifyNotEmpty(app.Document.getComponent(pastedId));
            undo.MenuSelectedFcn(undo, []);
            testCase.verifyEmpty(app.Document.getComponent(pastedId));
        end

        function invoke(testCase, figure, action, route, id)
            % invoke Dispatch one route using public UI handles and native right-click targeting.
            arguments (Input)
                testCase (1, 1) EditorClipboardTest
                figure (1, 1) matlab.ui.Figure
                action (1, 1) string
                route (1, 1) string
                id (1, 1) string
            end
            if route == "menu"
                item = findall(figure, "Tag", "macd-edit-" + lower(action));
                testCase.assertEqual(string(item.Enable), "on");
                item.MenuSelectedFcn(item, []);
            elseif route == "keyboard"
                tree = findall(figure, "Type", "uitree");
                figure.CurrentObject = tree;
                keys = ["c", "x", "v"];
                actions = ["Copy", "Cut", "Paste"];
                figure.WindowButtonDownFcn(figure, []);
                figure.WindowKeyPressFcn(figure, struct("Key", keys(actions == action), "Modifier", {{'control'}}));
            else
                tree = findall(figure, "Type", "uitree");
                nodes = findall(tree, "Type", "uitreenode");
                node = nodes(arrayfun(@(value) string(value.NodeData) == id, nodes));
                expand(tree.Children(1));
                drawnow;
                item = findall(tree.ContextMenu, "Tag", "macd-context-" + lower(action));
                testCase.chooseContextMenu(node, item);
            end
            drawnow;
        end

        function select(~, figure, id)
            % select Update the real editor through the hierarchy selection callback.
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

        function [app, figure, panelId] = fixture(~)
            % fixture Create a panel with one child using the editor's palette workflow.
            arguments (Input)
                ~
            end
            arguments (Output)
                app (1, 1) yamada
                figure (1, 1) matlab.ui.Figure
                panelId (1, 1) string
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
            panelId = app.SelectedComponentId;
            row = find(string(palette.Data(:, 1)) == "Label", 1);
            palette.DoubleClickedFcn(palette, struct("InteractionInformation", struct("Row", row)));
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
