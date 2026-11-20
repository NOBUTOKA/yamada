classdef EditorShellInteractionTest < matlab.unittest.TestCase
    % EditorShellInteractionTest Verify hierarchy, palette, and shell editing callbacks.

    methods (Test, TestTags = {'editorShell', 'fast', 'ui'})
        function editorBuildsEditingSurfaces(testCase)
            % editorBuildsEditingSurfaces Verify palette, right pane, and toolbar.

            % Construct the editor through its ordinary application entry point.
            app = yamada();
            cleanup = onCleanup(@() deleteIfValid(app));
            drawnow;

            % Locate the editor-owned controls through their public UI metadata.
            tables = findall(0, "Type", "uitable");
            palette = tables(arrayfun(@(table) numel(table.ColumnName) >= 2 && ...
                string(table.ColumnName(2)) == "Category", tables));
            testCase.verifyEqual(numel(palette), 1);
            testCase.verifyNotEmpty(palette.DoubleClickedFcn);
            testCase.verifyNotEmpty(palette.CellSelectionCallback);

            toolbars = findall(0, "Type", "uitoolbar");
            testCase.verifyEqual(numel(toolbars), 1);
            refresh = findall(toolbars, "Tag", "yamada-refresh-source");
            testCase.verifyEqual(numel(refresh), 1);
            testCase.verifyEqual(string(refresh.Enable), "off");
            testCase.verifyTrue(all(arrayfun(@(tool) ...
                ~isempty(tool.ClickedCallback), toolbars.Children)));
            overlays = findall(0, "Type", "uihtml");
            testCase.verifyEqual(numel(overlays), 1);
            testCase.verifyNotEmpty(overlays.HTMLEventReceivedFcn);
            testCase.verifyTrue(isstruct(overlays.Data));
            testCase.verifyEqual(string(overlays.Data.rootId), ...
                app.Document.RootComponentId);
            testCase.verifyTrue(overlays.Data.rootEditable);
            rootId = app.Document.RootComponentId;
            for phase = ["pointerdown", "pointermove", "pointerup"]
                point = [320 7];
                handle = "root-s";
                if phase ~= "pointerdown"
                    point = [320 -13];
                    handle = "";
                end
                overlays.HTMLEventReceivedFcn(overlays, struct( ...
                    "HTMLEventName", "Pointer", ...
                    "HTMLEventData", struct("phase", phase, ...
                    "x", point(1), "y", point(2), ...
                    "componentId", rootId, "handle", handle)));
            end
            root = app.Document.getComponent(rootId);
            testCase.verifyEqual(root.getProperty("Position").LiteralValue, ...
                [100 80 640 500]);
            clear cleanup
        end
    end

    methods (Test, TestTags = {'editorShell', 'ui'})
        function hierarchyRenameOwnsTextKeysAndPreservesNodes(testCase)
            % hierarchyRenameOwnsTextKeysAndPreservesNodes Commit and cancel inline names with atomic history.
            app = yamada();
            cleanup = onCleanup(@() deleteIfValid(app));
            drawnow;
            [figure, palette] = editorPalette();
            row = find(string(palette.Data(:, 1)) == "Button", 1);
            palette.DoubleClickedFcn(palette, struct("InteractionInformation", struct("Row", row)));
            tree = findall(figure, "Type", "uitree");
            node = tree.SelectedNodes;
            rootNode = tree.Children(1);
            expand(rootNode);
            id = app.SelectedComponentId;
            component = app.Document.getComponent(id);
            before = app.Document.HistoryIndex;
            tree.SelectionChangedFcn(tree, struct("SelectedNodes", node));
            figure.CurrentObject = node;
            figure.WindowKeyPressFcn(figure, struct("Key", "f2", "Modifier", {{}}));
            field = findall(figure, "Tag", "yamada-hierarchy-rename");
            testCase.assertEqual(numel(field), 1);
            testCase.verifyEqual(string(field.Value), component.Name);
            figure.WindowKeyPressFcn(figure, struct("Key", "delete", "Modifier", {{}}));
            testCase.verifyEqual(app.Document.getComponent(id), component);
            field.ValueChangingFcn(field, struct("Value", "RunButton"));
            figure.WindowKeyPressFcn(figure, struct("Key", "escape", "Modifier", {{}}));
            testCase.verifyEmpty(findall(figure, "Tag", "yamada-hierarchy-rename"));
            testCase.verifyEqual(component.Name, "Button");
            testCase.verifyEqual(app.Document.HistoryIndex, before);
            information = struct("Node", node, "Location", [60 50]);
            tree.ClickedFcn(tree, struct("InteractionInformation", information));
            tree.ClickedFcn(tree, struct("InteractionInformation", information));
            field = findall(figure, "Tag", "yamada-hierarchy-rename");
            testCase.assertEqual(numel(field), 1);
            field.ValueChangingFcn(field, struct("Value", "RunButton"));
            figure.WindowKeyPressFcn(figure, struct("Key", "return", "Modifier", {{}}));
            testCase.verifyEqual(component.Name, "RunButton");
            testCase.verifyEqual(app.Document.HistoryIndex, before + 1);
            testCase.verifyTrue(isvalid(node));
            testCase.verifyEqual(tree.SelectedNodes, node);
            testCase.verifySubstring(string(node.Text), "RunButton");
            menu = findall(figure, "Tag", "yamada-edit-undo");
            menu.MenuSelectedFcn(menu, []);
            testCase.verifyEqual(component.Name, "Button");
            testCase.verifyTrue(isvalid(rootNode));
            testCase.verifyEqual(tree.SelectedNodes, node);
            menu = findall(figure, "Tag", "yamada-edit-redo");
            menu.MenuSelectedFcn(menu, []);
            testCase.verifyEqual(component.Name, "RunButton");
            testCase.verifyTrue(isvalid(node));
            clear cleanup
        end

        function hierarchyRenameRetainsRejectedTextAndF2UsesSelection(testCase)
            % hierarchyRenameRetainsRejectedTextAndF2UsesSelection Correct invalid names without document mutation.
            app = yamada();
            cleanup = onCleanup(@() deleteIfValid(app));
            drawnow;
            [figure, ~] = editorPalette();
            tree = findall(figure, "Type", "uitree");
            node = tree.SelectedNodes;
            testCase.verifyEmpty(findall(figure, "Tag", "yamada-rename-component"));
            figure.CurrentObject = node;
            figure.WindowKeyPressFcn(figure, struct("Key", "f2", "Modifier", {{}}));
            field = findall(figure, "Tag", "yamada-hierarchy-rename");
            field.Value = "bad name";
            field.ValueChangedFcn(field, struct("Value", "bad name"));
            testCase.verifyEqual(app.Document.getComponent(app.SelectedComponentId).Name, "UIFigure");
            testCase.verifyEqual(string(field.Value), "bad name");
            testCase.verifyNotEmpty(field.Tooltip);
            field.Value = "MainWindow";
            field.ValueChangedFcn(field, struct("Value", "MainWindow"));
            testCase.verifyEmpty(findall(figure, "Tag", "yamada-hierarchy-rename"));
            testCase.verifyEqual(app.Document.getComponent(app.SelectedComponentId).Name, "MainWindow");
            testCase.verifyEqual(tree.SelectedNodes, node);
            clear cleanup
        end

        function previewSelectionSynchronizesHierarchyWithoutRebuildingBranches(testCase)
            % previewSelectionSynchronizesHierarchyWithoutRebuildingBranches Reveal nested Preview selections.

            app = yamada();
            cleanup = onCleanup(@() deleteIfValid(app));
            drawnow;
            [figure, palette] = editorPalette();
            names = string(palette.Data(:, 1));
            for name = ["Button Group", "Button"]
                row = find(names == name, 1);
                testCase.assertNotEmpty(row, name);
                palette.DoubleClickedFcn(palette, ...
                    struct("InteractionInformation", struct("Row", row)));
            end
            buttonId = app.SelectedComponentId;
            tree = findall(figure, "Type", "uitree");
            rootNode = tree.Children(1);
            groupNode = rootNode.Children(1);
            buttonNode = groupNode.Children(1);
            tree.SelectedNodes = rootNode;
            tree.SelectionChangedFcn(tree, struct("SelectedNodes", rootNode));
            collapse(groupNode);
            collapse(rootNode);
            app.Document.markSaved();
            historyIndex = app.Document.HistoryIndex;

            % A completed SVG click selects the existing leaf without creating history.
            overlay = findall(figure, "Type", "uihtml", "Tag", "yamada-interaction-overlay");
            for phase = ["pointerdown", "pointerup"]
                overlay.HTMLEventReceivedFcn(overlay, struct( ...
                    "HTMLEventName", "Pointer", "HTMLEventData", struct( ...
                    "phase", phase, "x", 25, "y", 25, ...
                    "componentId", buttonId, "handle", "")));
                overlay = findall(figure, "Type", "uihtml", "Tag", "yamada-interaction-overlay");
                testCase.verifyEqual(tree.SelectedNodes, buttonNode);
            end
            testCase.verifyEqual(app.SelectedComponentId, buttonId);
            testCase.verifyEqual(tree.SelectedNodes, buttonNode);
            testCase.verifyTrue(isvalid(rootNode) && isvalid(groupNode));
            testCase.verifyEqual(app.Document.HistoryIndex, historyIndex);
            testCase.verifyFalse(app.Document.IsDirty);
            clear cleanup
        end

        function deleteShortcutIgnoresInspectorEditingAndKeyboardNavigation(testCase)
            % deleteShortcutIgnoresInspectorEditingAndKeyboardNavigation Delete only from owned selection contexts.

            app = yamada();
            cleanup = onCleanup(@() deleteIfValid(app));
            drawnow;
            [figure, palette] = editorPalette();
            buttonRow = find(string(palette.Data(:, 1)) == "Button", 1);
            palette.DoubleClickedFcn(palette, ...
                struct("InteractionInformation", struct("Row", buttonRow)));
            selectedId = app.SelectedComponentId;
            historyIndex = app.Document.HistoryIndex;
            key = struct("Key", "delete", "Modifier", {{}});
            fields = findall(figure, "Type", "uieditfield");
            testCase.assertNotEmpty(fields);

            % Input controls own Delete, including when a component remains selected.
            for field = fields(:)'
                figure.CurrentObject = field;
                figure.WindowKeyPressFcn(figure, key);
                testCase.verifyNotEmpty(app.Document.getComponent(selectedId));
            end
            testCase.verifyEqual(app.Document.HistoryIndex, historyIndex);
            tree = findall(figure, "Type", "uitree");
            figure.CurrentObject = tree;
            figure.WindowButtonDownFcn(figure, struct());
            figure.WindowKeyPressFcn(figure, struct("Key", "tab", "Modifier", {{}}));
            figure.WindowKeyPressFcn(figure, key);
            testCase.verifyNotEmpty(app.Document.getComponent(selectedId));

            % Preview requests carry selection identity and revision, excluding stale input.
            overlay = findall(figure, "Type", "uihtml", "Tag", "yamada-interaction-overlay");
            revision = overlay.Data.gridEditor.revision;
            request = struct("componentId", selectedId, "revision", revision - 1);
            overlay.HTMLEventReceivedFcn(overlay, struct( ...
                "HTMLEventName", "DeleteSelection", "HTMLEventData", request));
            testCase.verifyNotEmpty(app.Document.getComponent(selectedId));
            request.revision = revision;
            overlay.HTMLEventReceivedFcn(overlay, struct( ...
                "HTMLEventName", "DeleteSelection", "HTMLEventData", request));
            testCase.verifyEmpty(app.Document.getComponent(selectedId));
            testCase.verifyEqual(app.Document.HistoryIndex, historyIndex + 1);

            % A fresh hierarchy click continues to enable its Delete shortcut.
            palette.DoubleClickedFcn(palette, ...
                struct("InteractionInformation", struct("Row", buttonRow)));
            selectedId = app.SelectedComponentId;
            figure.CurrentObject = tree;
            figure.WindowButtonDownFcn(figure, struct());
            figure.WindowKeyPressFcn(figure, struct("Key", "tab", "Modifier", {{}}));
            tree.SelectionChangedFcn(tree, struct("SelectedNodes", tree.SelectedNodes));
            figure.WindowKeyPressFcn(figure, key);
            testCase.verifyEmpty(app.Document.getComponent(selectedId));
            clear cleanup
        end

        function paletteListsConcreteStyleVariants(testCase)
            % paletteListsConcreteStyleVariants Expose every catalog-defined style.

            % Inspect the live palette to ensure variants are not collapsed by factory.
            app = yamada();
            cleanup = onCleanup(@() deleteIfValid(app));
            drawnow;
            figures = findall(0, "Type", "figure", "Tag", "yamada-editor");
            tables = findall(figures, "Type", "uitable");
            palette = tables(arrayfun(@(table) any(string(table.ColumnName) == "Component") && ...
                any(string(table.ColumnName) == "Category"), tables));
            names = string(palette.Data(:, 1));
            % Every style variant in the running release's catalog appears under its own name.
            styles = ["uibutton-state", "State Button"; "uieditfield-numeric", "Numeric Edit Field"; ...
                "uigauge-linear", "Linear Gauge"; "uigauge-ninetydegree", "90-Degree Gauge"; ...
                "uigauge-semicircular", "Semicircular Gauge"; "uiknob-discrete", "Discrete Knob"; ...
                "uislider-range", "Range Slider"; "uiswitch-rocker", "Rocker Switch"; ...
                "uiswitch-toggle", "Toggle Switch"; "uitree-checkbox", "Check Box Tree"];
            available = ismember(styles(:, 1), yamada.model.ComponentRegistry.createDefault().listVariantIds());
            testCase.verifyTrue(all(ismember(styles(available, 2), names)));
            testCase.verifyFalse(any(ismember(styles(~available, 2), names)));
            row = find(names == "State Button", 1);
            palette.DoubleClickedFcn(palette, ...
                struct("InteractionInformation", struct("Row", row)));
            component = app.Document.getComponent(app.SelectedComponentId);
            testCase.verifyEqual(component.DeclaredType, "matlab.ui.control.StateButton");
            testCase.verifyEqual(component.CreationArguments, {'state'});
            clear cleanup
        end

        function buttonInsideButtonGroupCanBeSelectedMovedAndResized(testCase)
            % buttonInsideButtonGroupCanBeSelectedMovedAndResized Keep nested controls above their parent on the canvas.
            app = yamada();
            cleanup = onCleanup(@() deleteIfValid(app));
            drawnow;
            figure = findall(0, "Type", "figure", "Tag", "yamada-editor");
            tables = findall(figure, "Type", "uitable");
            palette = tables(arrayfun(@(table) any(string(table.ColumnName) == "Component") && ...
                any(string(table.ColumnName) == "Category"), tables));
            names = string(palette.Data(:, 1));
            groupRow = find(names == "Button Group", 1);
            buttonRow = find(names == "Button", 1);
            palette.DoubleClickedFcn(palette, ...
                struct("InteractionInformation", struct("Row", groupRow)));
            groupId = app.SelectedComponentId;
            palette.DoubleClickedFcn(palette, ...
                struct("InteractionInformation", struct("Row", buttonRow)));
            buttonId = app.SelectedComponentId;
            drawnow;

            % The child outline must be painted after its containing group.
            button = app.Document.getComponent(buttonId);
            testCase.verifyEqual(button.ParentId, groupId);
            overlay = findall(figure, "Type", "uihtml");
            components = overlay.Data.components;
            testCase.verifyFalse(overlay.Data.rootSelected);
            testCase.verifyTrue(overlay.Data.rootEditable);
            groupIndex = find(string({components.id}) == groupId, 1);
            buttonIndex = find(string({components.id}) == buttonId, 1);
            testCase.assertNotEmpty(groupIndex);
            testCase.assertNotEmpty(buttonIndex);
            testCase.verifyLessThan(groupIndex, buttonIndex);

            % Exercise the same pointer events used by selection, move, and resize.
            startPosition = button.getProperty("Position").LiteralValue;
            point = [components(buttonIndex).x + 5, components(buttonIndex).y + 5];
            overlay.HTMLEventReceivedFcn(overlay, struct("HTMLEventName", "Pointer", ...
                "HTMLEventData", struct("phase", "pointerdown", "x", point(1), ...
                "y", point(2), "componentId", buttonId, "handle", "")));
            overlay.HTMLEventReceivedFcn(overlay, struct("HTMLEventName", "Pointer", ...
                "HTMLEventData", struct("phase", "pointermove", "x", point(1) + 12, ...
                "y", point(2) + 12, "componentId", "", "handle", "")));
            overlay.HTMLEventReceivedFcn(overlay, struct("HTMLEventName", "Pointer", ...
                "HTMLEventData", struct("phase", "pointerup", "x", point(1) + 12, ...
                "y", point(2) + 12, "componentId", "", "handle", "")));
            movedPosition = button.getProperty("Position").LiteralValue;
            testCase.verifyEqual(app.SelectedComponentId, buttonId);
            testCase.verifyNotEqual(movedPosition(1:2), startPosition(1:2));

            overlay = findall(figure, "Type", "uihtml");
            overlay.HTMLEventReceivedFcn(overlay, struct("HTMLEventName", "Pointer", ...
                "HTMLEventData", struct("phase", "pointerdown", "x", point(1), ...
                "y", point(2), "componentId", buttonId, "handle", "ne")));
            overlay.HTMLEventReceivedFcn(overlay, struct("HTMLEventName", "Pointer", ...
                "HTMLEventData", struct("phase", "pointermove", "x", point(1) + 12, ...
                "y", point(2) + 12, "componentId", "", "handle", "")));
            overlay.HTMLEventReceivedFcn(overlay, struct("HTMLEventName", "Pointer", ...
                "HTMLEventData", struct("phase", "pointerup", "x", point(1) + 12, ...
                "y", point(2) + 12, "componentId", "", "handle", "")));
            resizedPosition = button.getProperty("Position").LiteralValue;
            testCase.verifyGreaterThan(resizedPosition(3), movedPosition(3));
            testCase.verifyGreaterThan(resizedPosition(4), movedPosition(4));
            clear cleanup
        end

        function buttonInsideGridButtonGroupHasEditableOverlayTarget(testCase)
            % buttonInsideGridButtonGroupHasEditableOverlayTarget Expose nested absolute controls above grid gestures.
            app = yamada();
            cleanup = onCleanup(@() deleteIfValid(app));
            drawnow;
            [figure, palette] = editorPalette();
            names = string(palette.Data(:, 1));
            for name = ["Grid Layout", "Button Group", "Button"]
                row = find(names == name, 1);
                palette.DoubleClickedFcn(palette, ...
                    struct("InteractionInformation", struct("Row", row)));
            end
            buttonId = app.SelectedComponentId;
            button = app.Document.getComponent(buttonId);
            group = app.Document.getComponent(button.ParentId);
            testCase.verifyEqual(group.Factory, "uibuttongroup");
            testCase.verifyEqual(app.Document.getComponent(group.ParentId).Factory, "uigridlayout");
            drawnow;

            overlay = findall(figure, "Type", "uihtml");
            components = overlay.Data.components;
            buttonIndex = find(string({components.id}) == buttonId, 1);
            testCase.assertNotEmpty(buttonIndex);
            testCase.verifyTrue(components(buttonIndex).inGrid);
            testCase.verifyEqual(string(overlay.Data.gridEditor.activeGridId), group.ParentId);

            % Move and resize the nested button through the ordinary Pointer route.
            point = [components(buttonIndex).x + 5, components(buttonIndex).y + 5];
            startPosition = button.getProperty("Position").LiteralValue;
            overlay.HTMLEventReceivedFcn(overlay, struct("HTMLEventName", "Pointer", ...
                "HTMLEventData", struct("phase", "pointerdown", "x", point(1), ...
                "y", point(2), "componentId", buttonId, "handle", "")));
            overlay.HTMLEventReceivedFcn(overlay, struct("HTMLEventName", "Pointer", ...
                "HTMLEventData", struct("phase", "pointermove", "x", point(1) + 12, ...
                "y", point(2) + 12, "componentId", "", "handle", "")));
            overlay.HTMLEventReceivedFcn(overlay, struct("HTMLEventName", "Pointer", ...
                "HTMLEventData", struct("phase", "pointerup", "x", point(1) + 12, ...
                "y", point(2) + 12, "componentId", "", "handle", "")));
            movedPosition = button.getProperty("Position").LiteralValue;
            testCase.verifyNotEqual(movedPosition(1:2), startPosition(1:2));

            overlay = findall(figure, "Type", "uihtml");
            overlay.HTMLEventReceivedFcn(overlay, struct("HTMLEventName", "Pointer", ...
                "HTMLEventData", struct("phase", "pointerdown", "x", point(1), ...
                "y", point(2), "componentId", buttonId, "handle", "ne")));
            overlay.HTMLEventReceivedFcn(overlay, struct("HTMLEventName", "Pointer", ...
                "HTMLEventData", struct("phase", "pointermove", "x", point(1) + 12, ...
                "y", point(2) + 12, "componentId", "", "handle", "")));
            overlay.HTMLEventReceivedFcn(overlay, struct("HTMLEventName", "Pointer", ...
                "HTMLEventData", struct("phase", "pointerup", "x", point(1) + 12, ...
                "y", point(2) + 12, "componentId", "", "handle", "")));
            resizedPosition = button.getProperty("Position").LiteralValue;
            testCase.verifyGreaterThan(resizedPosition(3), movedPosition(3));
            testCase.verifyGreaterThan(resizedPosition(4), movedPosition(4));
            clear cleanup
        end
    end

    methods (Test, TestTags = {'editorShell', 'fast', 'ui'})

        function deletingTreeLeafSelectsParentWithoutRebuildingBranches(testCase)
            % deletingTreeLeafSelectsParentWithoutRebuildingBranches Preserve the open hierarchy after deletion.
            app = yamada();
            cleanup = onCleanup(@() deleteIfValid(app));
            drawnow;
            [figure, palette] = editorPalette();
            names = string(palette.Data(:, 1));
            groupRow = find(names == "Button Group", 1);
            buttonRow = find(names == "Button", 1);
            labelRow = find(names == "Label", 1);
            palette.DoubleClickedFcn(palette, ...
                struct("InteractionInformation", struct("Row", groupRow)));
            groupId = app.SelectedComponentId;
            palette.DoubleClickedFcn(palette, ...
                struct("InteractionInformation", struct("Row", buttonRow)));
            buttonId = app.SelectedComponentId;
            tree = findall(figure, "Type", "uitree");
            tree.SelectedNodes = tree.Children(1);
            tree.SelectionChangedFcn(tree, struct("SelectedNodes", tree.Children(1)));
            palette.DoubleClickedFcn(palette, ...
                struct("InteractionInformation", struct("Row", labelRow)));
            labelId = app.SelectedComponentId;
            drawnow;

            rootNode = tree.Children(1);
            groupNode = rootNode.Children(string({rootNode.Children.NodeData}) == groupId);
            siblingNode = rootNode.Children(string({rootNode.Children.NodeData}) == labelId);
            buttonNode = groupNode.Children(1);
            expand(rootNode);
            expand(groupNode);
            tree.SelectedNodes = buttonNode;
            tree.SelectionChangedFcn(tree, struct("SelectedNodes", buttonNode));
            testCase.verifyEqual(app.SelectedComponentId, buttonId);

            deleteMenu = findall(figure, "Tag", "yamada-edit-delete");
            deleteMenu.MenuSelectedFcn(deleteMenu, struct());
            drawnow;

            testCase.verifyEqual(app.SelectedComponentId, groupId);
            testCase.verifyEqual(tree.SelectedNodes, groupNode);
            testCase.verifyEqual(tree.Children(1), rootNode);
            testCase.verifyTrue(isvalid(groupNode));
            testCase.verifyTrue(isvalid(siblingNode));
            testCase.verifyEmpty(groupNode.Children);
            testCase.verifyFalse(isvalid(buttonNode));
            clear cleanup
        end
    end
end

function [figure, palette] = editorPalette()
% editorPalette Find the live editor figure and its component palette table.
arguments (Output)
    figure matlab.ui.Figure
    palette matlab.ui.control.Table
end

figure = findall(0, "Type", "figure", "Tag", "yamada-editor");
tables = findall(figure, "Type", "uitable");
palette = tables(arrayfun(@(table) any(string(table.ColumnName) == "Component") && ...
    any(string(table.ColumnName) == "Category"), tables));
end

function deleteIfValid(value)
% deleteIfValid Delete an editor fixture when it remains valid.
arguments (Input)
    value
end

% Keep cleanup safe if an assertion or UI construction fails midway.
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
