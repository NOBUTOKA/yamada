classdef (TestTags = {'ui', 'editorShell'}) HierarchyContextMenuTest < matlab.uitest.TestCase
    % HierarchyContextMenuTest Verify native context routing without changing selection.
    %   Tests use the shared tree menu and native right-click gesture, including
    %   invalidation across document replacement and empty tree space.

    properties (Access = private)
        Document yamada.model.DocumentModel
        ReceivedId string = ""
    end

    methods (Test)
        function nativeRightClickRoutesUnselectedNode(testCase)
            % nativeRightClickRoutesUnselectedNode Exercise native hit data and unchanged selection.
            [figure, tree, menu, root, button] = testCase.fixture();
            cleanup = onCleanup(@() delete(figure));
            tree.SelectedNodes = root;
            expand(root);
            drawnow;
            item = findall(menu, "Tag", "yamada-manage-callbacks");
            testCase.chooseContextMenu(button, item);
            testCase.verifyEqual(testCase.ReceivedId, "button");
            testCase.verifyEqual(tree.SelectedNodes, root);
            testCase.verifyFalse(testCase.Document.IsDirty);
            testCase.verifyEmpty(testCase.Document.History);
            tree.SelectedNodes = button;
            testCase.chooseContextMenu(root, item);
            testCase.verifyEqual(testCase.ReceivedId, "root");
            testCase.verifyEqual(tree.SelectedNodes, button);
        end

        function previewUsesSameMenuWithoutChangingTreeSelection(testCase)
            % previewUsesSameMenuWithoutChangingTreeSelection Dispatch explicit Preview targets through the shared menu.
            [figure, tree, menu, root, ~] = testCase.fixture();
            cleanup = onCleanup(@() delete(figure));
            tree.SelectedNodes = root;
            adapter = figure.UserData;
            adapter.openForComponent("button", [30 40]);
            item = findall(menu, "Tag", "yamada-manage-callbacks");
            item.MenuSelectedFcn(item, []);
            testCase.verifyEqual(testCase.ReceivedId, "button");
            testCase.verifyEqual(tree.SelectedNodes, root);
            adapter.openForComponent("missing", [30 40]);
            testCase.verifyEqual(string(item.Enable), "off");
        end

        function emptySpaceAndReplacementCannotReuseTarget(testCase)
            % emptySpaceAndReplacementCannotReuseTarget Reject stale targets after native menu preparation.
            [figure, tree, menu, ~, button] = testCase.fixture();
            cleanup = onCleanup(@() delete(figure));
            item = findall(menu, "Tag", "yamada-manage-callbacks");
            menu.ContextMenuOpeningFcn(menu, struct("InteractionInformation", struct("Node", button)));
            testCase.verifyEqual(item.Enable, matlab.lang.OnOffSwitchState.on);
            menu.ContextMenuOpeningFcn(menu, struct("InteractionInformation", struct("Node", [])));
            testCase.verifyEqual(item.Enable, matlab.lang.OnOffSwitchState.off);
            item.MenuSelectedFcn(item, []);
            testCase.verifyEqual(testCase.ReceivedId, "");
            menu.ContextMenuOpeningFcn(menu, struct("InteractionInformation", struct("Node", button)));
            testCase.Document = yamada.model.DocumentModel("Replacement");
            item.MenuSelectedFcn(item, []);
            testCase.verifyEqual(testCase.ReceivedId, "");
            testCase.verifyEqual(item.Enable, matlab.lang.OnOffSwitchState.off);
            testCase.verifyTrue(isvalid(tree));
        end

        function resetDeletionAndCallbackFreeTargetsDisableCommand(testCase)
            % resetDeletionAndCallbackFreeTargetsDisableCommand Verify explicit invalidation and empty capability surfaces.
            [figure, tree, menu, ~, button] = testCase.fixture();
            cleanup = onCleanup(@() delete(figure));
            item = findall(menu, "Tag", "yamada-manage-callbacks");
            menu.ContextMenuOpeningFcn(menu, struct("InteractionInformation", struct("Node", button)));
            figure.UserData.reset();
            item.MenuSelectedFcn(item, []);
            testCase.verifyEqual(testCase.ReceivedId, "");
            menu.ContextMenuOpeningFcn(menu, struct("InteractionInformation", struct("Node", button)));
            testCase.Document.removeComponent("button");
            item.MenuSelectedFcn(item, []);
            testCase.verifyEqual(testCase.ReceivedId, "");
            testCase.verifyEqual(item.Enable, matlab.lang.OnOffSwitchState.off);

            % Use an extension catalog with no callbacks to exercise availability independently.
            delete(figure.UserData);
            registry = yamada.model.ComponentRegistry();
            registry.register(yamada.model.ComponentDefinition("uifigure", "matlab.ui.Figure"));
            figure.UserData = yamada.ui.HierarchyContextMenu(figure, tree, registry, ...
                @() testCase.Document, @(id) testCase.receive(id));
            menu = tree.ContextMenu;
            menu.ContextMenuOpeningFcn(menu, struct("InteractionInformation", struct("Node", tree.Children(1))));
            item = findall(menu, "Tag", "yamada-manage-callbacks");
            testCase.verifyEqual(item.Enable, matlab.lang.OnOffSwitchState.off);
        end

        function editorMenuSurvivesRebuildWithoutChangingInspector(testCase)
            % editorMenuSurvivesRebuildWithoutChangingInspector Exercise real editor command wiring and rebuilds.
            app = yamada();
            cleanup = onCleanup(@() delete(app));
            figure = findall(0, "Type", "figure", "Tag", "yamada-editor");
            palette = findall(figure, "Type", "uitable");
            palette = palette(arrayfun(@(table) any(string(table.ColumnName) == "Component") && ...
                any(string(table.ColumnName) == "Category"), palette));
            row = find(string(palette.Data(:, 1)) == "Button", 1);
            palette.DoubleClickedFcn(palette, struct("InteractionInformation", struct("Row", row)));
            selected = app.SelectedComponentId;
            historyIndex = app.Document.HistoryIndex;
            tree = findall(figure, "Type", "uitree");
            root = tree.Children(1);
            menu = tree.ContextMenu;
            item = findall(menu, "Tag", "yamada-manage-callbacks");
            inspector = findall(figure, "Tag", "yamada-inspector-property-editor");
            menu.ContextMenuOpeningFcn(menu, struct("InteractionInformation", struct("Node", root)));
            item.MenuSelectedFcn(item, []);
            popup = findall(0, "Tag", "yamada-callback-manager");
            testCase.verifyEqual(numel(popup), 1);
            item.MenuSelectedFcn(item, []);
            testCase.verifyEqual(findall(0, "Tag", "yamada-callback-manager"), popup);
            testCase.verifyEqual(app.SelectedComponentId, selected);
            testCase.verifyEqual(app.Document.HistoryIndex, historyIndex);
            testCase.verifyEqual(findall(figure, "Tag", "yamada-inspector-property-editor"), inspector);
            close(popup);
            palette.DoubleClickedFcn(palette, struct("InteractionInformation", struct("Row", row)));
            testCase.verifyTrue(isvalid(menu));
            testCase.verifyEqual(item.Enable, matlab.lang.OnOffSwitchState.off);
            testCase.verifyFalse(isvalid(root));
        end

        function popupActionsCommitAndUndoCompleteCallbacks(testCase)
            % popupActionsCommitAndUndoCompleteCallbacks Exercise binding-only dropdown edits and editor history callbacks.
            app = yamada();
            cleanup = onCleanup(@() delete(app));
            registry = yamada.model.ComponentRegistry.createDefault();
            app.Document.applyCallbackAction(app.Document.RootComponentId, "SizeChangedFcn", "New", registry, "RootSized");
            app.Document.applyCallbackAction(app.Document.RootComponentId, "SizeChangedFcn", "Disconnect", registry);
            figure = findall(0, "Type", "figure", "Tag", "yamada-editor");
            tree = findall(figure, "Type", "uitree");
            menu = tree.ContextMenu;
            item = findall(menu, "Tag", "yamada-manage-callbacks");
            menu.ContextMenuOpeningFcn(menu, struct("InteractionInformation", struct("Node", tree.Children(1))));
            item.MenuSelectedFcn(item, []);
            popup = findall(0, "Tag", "yamada-callback-manager");
            control = findall(popup, "Tag", "yamada-callback-target", "UserData", "SizeChangedFcn");
            control.Value = "RootSized";
            control.ValueChangedFcn(control, []);
            testCase.verifyEqual(app.Document.HistoryIndex, 3);
            testCase.verifySubstring(app.Document.GeneratedText, "SizeChangedFcn = @app.");
            control = findall(popup, "Tag", "yamada-callback-target", "UserData", "SizeChangedFcn");
            testCase.verifyEqual(string(control.Enable), "on");
            control.Value = "<Disconnect>";
            control.ValueChangedFcn(control, []);
            testCase.verifyEqual(app.Document.HistoryIndex, 4);
            testCase.verifyFalse(contains(app.Document.GeneratedText, "SizeChangedFcn = @app."));
            testCase.verifySubstring(app.Document.CurrentText, "function RootSized(app, source, event)");
            undo = findall(figure, "Type", "uimenu", "Tag", "yamada-edit-undo");
            undo.MenuSelectedFcn(undo, []);
            testCase.verifySubstring(app.Document.GeneratedText, "SizeChangedFcn = @app.");
            control = findall(popup, "Tag", "yamada-callback-target", "UserData", "SizeChangedFcn");
            testCase.verifyEqual(string(control.Value), "RootSized");
        end
    end

    methods (Access = private)
        function [figure, tree, menu, root, button] = fixture(testCase)
            % fixture Create a visible native tree with injected document and command callbacks.
            arguments (Input)
                testCase (1, 1) HierarchyContextMenuTest
            end
            arguments (Output)
                figure (1, 1) matlab.ui.Figure
                tree (1, 1) matlab.ui.container.Tree
                menu (1, 1) matlab.ui.container.ContextMenu
                root (1, 1) matlab.ui.container.TreeNode
                button (1, 1) matlab.ui.container.TreeNode
            end
            testCase.ReceivedId = "";
            testCase.Document = yamada.model.DocumentModel("ContextFixture");
            testCase.Document.addComponent(yamada.model.ComponentRecord("root", "UIFigure", "uifigure", "matlab.ui.Figure"));
            testCase.Document.addComponent(yamada.model.ComponentRecord("button", "Button", "uibutton", "matlab.ui.control.Button"), "root");
            testCase.Document.markSaved();
            figure = uifigure("Position", [300 300 350 300]);
            tree = uitree(figure, "Position", [10 10 320 270]);
            root = uitreenode(tree, "Text", "UIFigure", "NodeData", "root");
            button = uitreenode(root, "Text", "Button", "NodeData", "button");
            adapter = yamada.ui.HierarchyContextMenu(figure, tree, ...
                yamada.model.ComponentRegistry.createDefault(), @() testCase.Document, ...
                @(id) testCase.receive(id));
            figure.UserData = adapter;
            menu = tree.ContextMenu;
        end

        function receive(testCase, componentId)
            % receive Capture the explicit command target independently of tree selection.
            arguments (Input)
                testCase (1, 1) HierarchyContextMenuTest
                componentId (1, 1) string
            end
            testCase.ReceivedId = componentId;
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
