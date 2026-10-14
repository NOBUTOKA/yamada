classdef EditorInteractionTest < matlab.unittest.TestCase
    % EditorInteractionTest Verify the editor interaction surfaces.
    %   These tests construct the real programmatic editor, allow its UI to lay
    %   out, inspect public callback wiring through UI handles, and always delete
    %   the editor fixture. They do not execute any opened application source.

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
            testCase.verifyEqual(string(palette.Data{1, 1}), "UI Axes");

            panels = findall(0, "Type", "uipanel");
            titles = string({panels.Title});
            testCase.verifyTrue(any(titles == "Hierarchy"));
            testCase.verifyTrue(any(titles == "Properties"));

            toolbars = findall(0, "Type", "uitoolbar");
            testCase.verifyEqual(numel(toolbars), 1);
            testCase.verifyEqual(numel(toolbars.Children), 3);
            refresh = findall(toolbars, "Tag", "macd-refresh-source");
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
            overlay = findall(figure, "Type", "uihtml", "Tag", "macd-interaction-overlay");
            for phase = ["pointerdown", "pointerup"]
                overlay.HTMLEventReceivedFcn(overlay, struct( ...
                    "HTMLEventName", "Pointer", "HTMLEventData", struct( ...
                    "phase", phase, "x", 25, "y", 25, ...
                    "componentId", buttonId, "handle", "")));
                overlay = findall(figure, "Type", "uihtml", "Tag", "macd-interaction-overlay");
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
            overlay = findall(figure, "Type", "uihtml", "Tag", "macd-interaction-overlay");
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
            figures = findall(0, "Type", "figure", "Tag", "macd-yamada-editor");
            tables = findall(figures, "Type", "uitable");
            palette = tables(arrayfun(@(table) any(string(table.ColumnName) == "Component") && ...
                any(string(table.ColumnName) == "Category"), tables));
            names = string(palette.Data(:, 1));
            testCase.verifyTrue(all(ismember(["State Button", "Numeric Edit Field", ...
                "Linear Gauge", "90-Degree Gauge", "Semicircular Gauge", ...
                "Discrete Knob", "Range Slider", "Rocker Switch", ...
                "Toggle Switch", "Check Box Tree"], names)));
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
            figure = findall(0, "Type", "figure", "Tag", "macd-yamada-editor");
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
        function hierarchySelectionCallbackUpdatesInspector(testCase)
            % hierarchySelectionCallbackUpdatesInspector Verify real tree selection.

            % Select the root node through the live uitree callback path.
            app = yamada();
            cleanup = onCleanup(@() deleteIfValid(app));
            drawnow;
            trees = findall(0, "Type", "uitree");
            testCase.verifyEqual(numel(trees), 1);
            trees.SelectedNodes = trees.Children(1);
            drawnow;

            % The callback must leave the root selected and show its properties.
            testCase.verifyEqual(app.SelectedComponentId, app.Document.RootComponentId);
            editors = findall(0, "Type", "uieditfield", ...
                "Tag", "macd-inspector-property-editor");
            testCase.verifyGreaterThan(numel(editors), 0);
            clear cleanup
        end

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

            menus = findall(figure, "Type", "uimenu");
            deleteMenu = menus(erase(string({menus.Text}), "&") == "Delete");
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

    methods (Test, TestTags = {'gridOverlay', 'ui'})
        function gridOverlayUsesOnlyTheNearestNestedGrid(testCase)
            % gridOverlayUsesOnlyTheNearestNestedGrid Keep nested grid contexts separate on canvas.

            app = yamada();
            cleanup = onCleanup(@() deleteIfValid(app));
            drawnow;
            figure = findall(0, "Type", "figure", "Tag", "macd-yamada-editor");
            tables = findall(figure, "Type", "uitable");
            palette = tables(arrayfun(@(table) any(string(table.ColumnName) == "Component") && ...
                any(string(table.ColumnName) == "Category"), tables));
            gridRow = find(string(palette.Data(:, 1)) == "Grid Layout", 1);
            labelRow = find(string(palette.Data(:, 1)) == "Label", 1);
            palette.DoubleClickedFcn(palette, ...
                struct("InteractionInformation", struct("Row", gridRow)));
            outerGridId = app.SelectedComponentId;
            palette.DoubleClickedFcn(palette, ...
                struct("InteractionInformation", struct("Row", gridRow)));
            innerGridId = app.SelectedComponentId;
            palette.DoubleClickedFcn(palette, ...
                struct("InteractionInformation", struct("Row", labelRow)));
            drawnow;

            overlays = findall(figure, "Type", "uihtml");
            testCase.verifyNotEqual(outerGridId, innerGridId);
            testCase.verifyEqual(app.ActiveGridId, innerGridId);
            testCase.verifyEqual(string(overlays.Data.gridEditor.activeGridId), innerGridId);
            clear cleanup
        end
    end

    methods (Test, TestTags = {'gridOverlay', 'fast', 'ui'})
        function gridOverlayTrackActionCommitsOneValidatedTrackChange(testCase)
            % gridOverlayTrackActionCommitsOneValidatedTrackChange Route a header action through atomic model editing.

            app = yamada();
            cleanup = onCleanup(@() deleteIfValid(app));
            drawnow;
            figure = findall(0, "Type", "figure", "Tag", "macd-yamada-editor");
            tables = findall(figure, "Type", "uitable");
            palette = tables(arrayfun(@(table) any(string(table.ColumnName) == "Component") && ...
                any(string(table.ColumnName) == "Category"), tables));
            gridRow = find(string(palette.Data(:, 1)) == "Grid Layout", 1);
            palette.DoubleClickedFcn(palette, ...
                struct("InteractionInformation", struct("Row", gridRow)));
            drawnow;
            overlays = findall(figure, "Type", "uihtml");
            gridData = overlays.Data.gridEditor;
            historyIndex = app.Document.HistoryIndex;

            % A full-figure grid needs editing space for settings outside every edge.
            surface = overlays.Data.surfaceBounds;
            testCase.verifyLessThanOrEqual(surface(1:2), gridData.outerBounds(1:2) - 14);
            testCase.verifyGreaterThanOrEqual(surface(1:2) + surface(3:4), ...
                gridData.outerBounds(1:2) + gridData.outerBounds(3:4) + 14);
            testCase.verifyEqual([overlays.Data.width overlays.Data.height], [640 480]);

            overlays.HTMLEventReceivedFcn(overlays, struct( ...
                "HTMLEventName", "GridAction", ...
                "HTMLEventData", struct("action", "set-track", ...
                "revision", gridData.revision, "activeGridId", gridData.activeGridId, ...
                "axis", "row", "index", 1, "mode", "fixed", "value", 40)));
            drawnow;

            grid = app.Document.getComponent(app.ActiveGridId);
            rowHeight = grid.getProperty("RowHeight").LiteralValue;
            testCase.verifyEqual(rowHeight{1}, 40);
            testCase.verifyEqual(app.Document.HistoryIndex, historyIndex + 1);
            overlays = findall(figure, "Type", "uihtml");
            refreshed = overlays.Data.gridEditor;
            overlays.HTMLEventReceivedFcn(overlays, struct( ...
                "HTMLEventName", "GridAction", ...
                "HTMLEventData", struct("action", "insert-track", ...
                "revision", refreshed.revision, "activeGridId", refreshed.activeGridId, ...
                "axis", "row", "index", 2, "mode", "fit", "value", 0)));
            drawnow;
            testCase.verifyEqual(numel(grid.getProperty("RowHeight").LiteralValue), 3);
            overlays = findall(figure, "Type", "uihtml");
            refreshed = overlays.Data.gridEditor;
            overlays.HTMLEventReceivedFcn(overlays, struct( ...
                "HTMLEventName", "GridAction", ...
                "HTMLEventData", struct("action", "delete-track", ...
                "revision", refreshed.revision, "activeGridId", refreshed.activeGridId, ...
                "axis", "row", "index", 2, "mode", "fit", "value", 0)));
            drawnow;
            testCase.verifyEqual(numel(grid.getProperty("RowHeight").LiteralValue), 2);
            clear cleanup
        end
    end

    methods (Test, TestTags = {'gridOverlay', 'ui'})
        function staleGridOverlayActionsDoNotMutateTheDocument(testCase)
            % staleGridOverlayActionsDoNotMutateTheDocument Reject canvas events from obsolete preview data.

            app = yamada();
            cleanup = onCleanup(@() deleteIfValid(app));
            drawnow;
            figure = findall(0, "Type", "figure", "Tag", "macd-yamada-editor");
            tables = findall(figure, "Type", "uitable");
            palette = tables(arrayfun(@(table) any(string(table.ColumnName) == "Component") && ...
                any(string(table.ColumnName) == "Category"), tables));
            gridRow = find(string(palette.Data(:, 1)) == "Grid Layout", 1);
            palette.DoubleClickedFcn(palette, ...
                struct("InteractionInformation", struct("Row", gridRow)));
            drawnow;
            overlays = findall(figure, "Type", "uihtml");
            gridData = overlays.Data.gridEditor;
            historyIndex = app.Document.HistoryIndex;

            overlays.HTMLEventReceivedFcn(overlays, struct( ...
                "HTMLEventName", "GridAction", ...
                "HTMLEventData", struct("action", "set-track", ...
                "revision", gridData.revision - 1, "activeGridId", gridData.activeGridId, ...
                "axis", "row", "index", 1, "mode", "fixed", "value", 40)));

            grid = app.Document.getComponent(app.ActiveGridId);
            testCase.verifyEmpty(grid.getProperty("RowHeight"));
            testCase.verifyEqual(app.Document.HistoryIndex, historyIndex);
            clear cleanup
        end

        function gridOverlayChildActionsCommitOnlyForTheSelectedChild(testCase)
            % gridOverlayChildActionsCommitOnlyForTheSelectedChild Commit overlapping gestures for the selected child.

            app = yamada();
            cleanup = onCleanup(@() deleteIfValid(app));
            drawnow;
            figure = findall(0, "Type", "figure", "Tag", "macd-yamada-editor");
            tables = findall(figure, "Type", "uitable");
            palette = tables(arrayfun(@(table) any(string(table.ColumnName) == "Component") && ...
                any(string(table.ColumnName) == "Category"), tables));
            gridRow = find(string(palette.Data(:, 1)) == "Grid Layout", 1);
            labelRow = find(string(palette.Data(:, 1)) == "Label", 1);
            palette.DoubleClickedFcn(palette, ...
                struct("InteractionInformation", struct("Row", gridRow)));
            % Occupy both destinations before rendering the moving child's overlay.
            registry = macd.model.ComponentRegistry.createDefault();
            occupied = app.Document.insertComponent(registry, "uilabel", app.SelectedComponentId);
            app.Document.setProperty(occupied.Id, "Layout.Row", [1 2]);
            app.Document.setProperty(occupied.Id, "Layout.Column", 2);
            palette.DoubleClickedFcn(palette, ...
                struct("InteractionInformation", struct("Row", labelRow)));
            app.Document.setProperty(app.SelectedComponentId, "Layout.Row", 1);
            app.Document.setProperty(app.SelectedComponentId, "Layout.Column", 1);
            drawnow;
            overlays = findall(figure, "Type", "uihtml");
            gridData = overlays.Data.gridEditor;
            historyIndex = app.Document.HistoryIndex;

            overlays.HTMLEventReceivedFcn(overlays, struct( ...
                "HTMLEventName", "GridAction", ...
                "HTMLEventData", struct("action", "move-child", ...
                "revision", gridData.revision, "activeGridId", gridData.activeGridId, ...
                "childId", app.SelectedComponentId, "rowStart", 2, "rowEnd", 2, ...
                "columnStart", 2, "columnEnd", 2)));
            drawnow;

            child = app.Document.getComponent(app.SelectedComponentId);
            testCase.verifyEqual(child.getProperty("Layout.Row").LiteralValue, 2);
            testCase.verifyEqual(child.getProperty("Layout.Column").LiteralValue, 2);
            testCase.verifyEqual(app.Document.HistoryIndex, historyIndex + 1);
            overlays = findall(figure, "Type", "uihtml");
            refreshed = overlays.Data.gridEditor;
            overlays.HTMLEventReceivedFcn(overlays, struct( ...
                "HTMLEventName", "GridAction", ...
                "HTMLEventData", struct("action", "resize-span", ...
                "revision", refreshed.revision, "activeGridId", refreshed.activeGridId, ...
                "childId", app.SelectedComponentId, "rowStart", 1, "rowEnd", 2, ...
                "columnStart", 2, "columnEnd", 2)));
            drawnow;
            testCase.verifyEqual(child.getProperty("Layout.Row").LiteralValue, [1 2]);
            testCase.verifyEqual(app.Document.HistoryIndex, historyIndex + 2);
            overlays = findall(figure, "Type", "uihtml");
            refreshed = overlays.Data.gridEditor;
            overlays.HTMLEventReceivedFcn(overlays, struct( ...
                "HTMLEventName", "GridAction", ...
                "HTMLEventData", struct("action", "move-child", ...
                "revision", refreshed.revision - 1, "activeGridId", refreshed.activeGridId, ...
                "childId", app.SelectedComponentId, "rowStart", 2, "rowEnd", 3, ...
                "columnStart", 1, "columnEnd", 1)));
            testCase.verifyEqual(app.Document.HistoryIndex, historyIndex + 2);
            testCase.verifyEqual(occupied.getProperty("Layout.Row").LiteralValue, [1 2]);
            testCase.verifyEqual(occupied.getProperty("Layout.Column").LiteralValue, 2);
            app.Document.undo();
            testCase.verifyEqual(child.getProperty("Layout.Row").LiteralValue, 2);
            app.Document.undo();
            testCase.verifyEqual(child.getProperty("Layout.Row").LiteralValue, 1);
            testCase.verifyEqual(child.getProperty("Layout.Column").LiteralValue, 1);
            clear cleanup
        end

        function gridOverlaySelectsAnImmediateChildWithoutEditingTheDocument(testCase)
            % gridOverlaySelectsAnImmediateChildWithoutEditingTheDocument Route one canvas selection safely.

            app = yamada();
            cleanup = onCleanup(@() deleteIfValid(app));
            drawnow;
            figure = findall(0, "Type", "figure", "Tag", "macd-yamada-editor");
            tables = findall(figure, "Type", "uitable");
            palette = tables(arrayfun(@(table) any(string(table.ColumnName) == "Component") && ...
                any(string(table.ColumnName) == "Category"), tables));
            gridRow = find(string(palette.Data(:, 1)) == "Grid Layout", 1);
            labelRow = find(string(palette.Data(:, 1)) == "Label", 1);
            palette.DoubleClickedFcn(palette, ...
                struct("InteractionInformation", struct("Row", gridRow)));
            palette.DoubleClickedFcn(palette, ...
                struct("InteractionInformation", struct("Row", labelRow)));
            drawnow;

            % Re-select the grid so its immediate label is an unselected canvas target.
            tree = findall(figure, "Type", "uitree");
            gridNode = tree.Children(1).Children(1);
            tree.SelectedNodes = gridNode;
            drawnow;
            overlays = findall(figure, "Type", "uihtml");
            gridData = overlays.Data.gridEditor;
            childId = string(gridData.children(1).id);
            app.Document.markSaved();
            historyIndex = app.Document.HistoryIndex;

            overlays.HTMLEventReceivedFcn(overlays, struct( ...
                "HTMLEventName", "GridAction", ...
                "HTMLEventData", struct("action", "select-child", ...
                "revision", gridData.revision, "activeGridId", gridData.activeGridId, ...
                "childId", childId)));
            drawnow;

            testCase.verifyEqual(app.SelectedComponentId, childId);
            testCase.verifyEqual(string(tree.SelectedNodes.NodeData), childId);
            testCase.verifyTrue(isvalid(gridNode));
            testCase.verifyEqual(tree.SelectedNodes.Parent, gridNode);
            testCase.verifyEqual(app.Document.HistoryIndex, historyIndex);
            testCase.verifyFalse(app.Document.IsDirty);
            clear cleanup
        end

        function gridOverlaySelectsChildBeforeAnyGridIsActive(testCase)
            % gridOverlaySelectsChildBeforeAnyGridIsActive Expose grid-child selection after returning to the root.

            app = yamada();
            cleanup = onCleanup(@() deleteIfValid(app));
            drawnow;
            figure = findall(0, "Type", "figure", "Tag", "macd-yamada-editor");
            tables = findall(figure, "Type", "uitable");
            palette = tables(arrayfun(@(table) any(string(table.ColumnName) == "Component") && ...
                any(string(table.ColumnName) == "Category"), tables));
            gridRow = find(string(palette.Data(:, 1)) == "Grid Layout", 1);
            labelRow = find(string(palette.Data(:, 1)) == "Label", 1);
            palette.DoubleClickedFcn(palette, ...
                struct("InteractionInformation", struct("Row", gridRow)));
            palette.DoubleClickedFcn(palette, ...
                struct("InteractionInformation", struct("Row", labelRow)));
            drawnow;

            tree = findall(figure, "Type", "uitree");
            rootNode = tree.Children(1);
            tree.SelectedNodes = rootNode;
            tree.SelectionChangedFcn(tree, struct("SelectedNodes", rootNode));
            drawnow;
            overlays = findall(figure, "Type", "uihtml");
            payload = overlays.Data;
            target = payload.gridSelectionTargets(1);
            app.Document.markSaved();
            historyIndex = app.Document.HistoryIndex;

            testCase.verifyEqual(string(payload.gridEditor.activeGridId), "");
            overlays.HTMLEventReceivedFcn(overlays, struct( ...
                "HTMLEventName", "GridAction", ...
                "HTMLEventData", struct("action", "select-child", ...
                "revision", payload.gridEditor.revision, "activeGridId", ...
                string(target.gridId), "childId", string(target.id))));
            drawnow;

            testCase.verifyEqual(app.SelectedComponentId, string(target.id));
            testCase.verifyEqual(app.ActiveGridId, string(target.gridId));
            testCase.verifyEqual(app.Document.HistoryIndex, historyIndex);
            testCase.verifyFalse(app.Document.IsDirty);
            clear cleanup
        end

        function gridOverlayRejectsStaleChildSelection(testCase)
            % gridOverlayRejectsStaleChildSelection Ignore an obsolete child-selection event.

            app = yamada();
            cleanup = onCleanup(@() deleteIfValid(app));
            drawnow;
            figure = findall(0, "Type", "figure", "Tag", "macd-yamada-editor");
            tables = findall(figure, "Type", "uitable");
            palette = tables(arrayfun(@(table) any(string(table.ColumnName) == "Component") && ...
                any(string(table.ColumnName) == "Category"), tables));
            gridRow = find(string(palette.Data(:, 1)) == "Grid Layout", 1);
            labelRow = find(string(palette.Data(:, 1)) == "Label", 1);
            palette.DoubleClickedFcn(palette, ...
                struct("InteractionInformation", struct("Row", gridRow)));
            palette.DoubleClickedFcn(palette, ...
                struct("InteractionInformation", struct("Row", labelRow)));
            drawnow;

            tree = findall(figure, "Type", "uitree");
            gridNode = tree.Children(1).Children(1);
            tree.SelectedNodes = gridNode;
            drawnow;
            overlays = findall(figure, "Type", "uihtml");
            gridData = overlays.Data.gridEditor;
            expectedSelection = app.SelectedComponentId;

            overlays.HTMLEventReceivedFcn(overlays, struct( ...
                "HTMLEventName", "GridAction", ...
                "HTMLEventData", struct("action", "select-child", ...
                "revision", gridData.revision - 1, "activeGridId", gridData.activeGridId, ...
                "childId", string(gridData.children(1).id))));
            testCase.verifyEqual(app.SelectedComponentId, expectedSelection);

            overlays.HTMLEventReceivedFcn(overlays, struct( ...
                "HTMLEventName", "GridAction", ...
                "HTMLEventData", struct("action", "select-child", ...
                "revision", gridData.revision, "activeGridId", gridData.activeGridId, ...
                "childId", app.Document.RootComponentId)));
            testCase.verifyEqual(app.SelectedComponentId, expectedSelection);
            clear cleanup
        end

        function gridOverlaySelectsOpenedFileChildBeforeAnyGridIsActive(testCase)
            % gridOverlaySelectsOpenedFileChildBeforeAnyGridIsActive Select parsed grid content from the root view.

            testPath = mfilename("fullpath");
            projectRoot = fileparts(fileparts(fileparts(testPath)));
            fixture = string(fullfile(projectRoot, "tests", "fixtures", "SimpleCalculatorApp.m"));
            lifecycle = macd.ui.DocumentLifecycleService(struct( ...
                "RequestOpenPathFcn", @() acceptedOpenPath(fixture)));
            app = yamada(lifecycle);
            cleanup = onCleanup(@() deleteIfValid(app));
            figure = findall(0, "Type", "figure", "Tag", "macd-yamada-editor");
            menus = findall(figure, "Type", "uimenu");
            openMenu = menus(erase(string({menus.Text}), "&") == "Open...");
            testCase.verifyEqual(numel(openMenu), 1);
            openMenu.MenuSelectedFcn(openMenu, struct());
            drawnow;

            overlays = findall(figure, "Type", "uihtml");
            payload = overlays.Data;
            target = payload.gridSelectionTargets(1);
            historyIndex = app.Document.HistoryIndex;

            testCase.verifyEqual(string(payload.gridEditor.activeGridId), "");
            overlays.HTMLEventReceivedFcn(overlays, struct( ...
                "HTMLEventName", "GridAction", ...
                "HTMLEventData", struct("action", "select-child", ...
                "revision", payload.gridEditor.revision, "activeGridId", ...
                string(target.gridId), "childId", string(target.id))));
            drawnow;

            testCase.verifyEqual(app.SelectedComponentId, string(target.id));
            testCase.verifyEqual(app.ActiveGridId, string(target.gridId));
            testCase.verifyEqual(app.Document.HistoryIndex, historyIndex);
            clear cleanup
        end

        function gridOverlaySelectsNestedGridBeforeItIsActive(testCase)
            % gridOverlaySelectsNestedGridBeforeItIsActive Edit inner tracks and move in the outer grid.

            app = yamada();
            cleanup = onCleanup(@() deleteIfValid(app));
            drawnow;
            [figure, palette] = editorPalette();
            names = string(palette.Data(:, 1));
            gridRow = find(names == "Grid Layout", 1);
            labelRow = find(names == "Label", 1);
            palette.DoubleClickedFcn(palette, ...
                struct("InteractionInformation", struct("Row", gridRow)));
            outerGridId = app.SelectedComponentId;
            palette.DoubleClickedFcn(palette, ...
                struct("InteractionInformation", struct("Row", gridRow)));
            innerGridId = app.SelectedComponentId;
            palette.DoubleClickedFcn(palette, ...
                struct("InteractionInformation", struct("Row", labelRow)));
            labelId = app.SelectedComponentId;
            drawnow;

            tree = findall(figure, "Type", "uitree");
            rootNode = tree.Children(1);
            tree.SelectedNodes = rootNode;
            tree.SelectionChangedFcn(tree, struct("SelectedNodes", rootNode));
            drawnow;
            overlays = findall(figure, "Type", "uihtml");
            payload = overlays.Data;
            targetIndex = find(string({payload.gridSelectionTargets.id}) == innerGridId, 1);
            target = payload.gridSelectionTargets(targetIndex);
            app.Document.markSaved();
            historyIndex = app.Document.HistoryIndex;

            testCase.verifyNotEmpty(targetIndex);
            overlays.HTMLEventReceivedFcn(overlays, struct( ...
                "HTMLEventName", "GridAction", ...
                "HTMLEventData", struct("action", "select-child", ...
                "revision", payload.gridEditor.revision, "activeGridId", ...
                string(target.gridId), "childId", string(target.id))));
            drawnow;

            refreshed = overlays.Data.gridEditor;
            testCase.verifyEqual(app.SelectedComponentId, innerGridId);
            testCase.verifyEqual(app.ActiveGridId, innerGridId);
            testCase.verifyEqual(string(refreshed.activeGridId), innerGridId);
            testCase.verifyEqual(numel(refreshed.children), 1);
            testCase.verifyEqual(string(refreshed.children(1).id), labelId);
            testCase.verifyNotEqual(outerGridId, innerGridId);
            testCase.verifyEqual(app.Document.HistoryIndex, historyIndex);
            testCase.verifyFalse(app.Document.IsDirty);

            % Parent placement remains editable after entering the inner grid context.
            parentData = overlays.Data.gridPlacement;
            testCase.verifyEqual(string(parentData.activeGridId), outerGridId);
            testCase.assertTrue(parentData.geometryAvailable, parentData.readOnlyReason);
            inner = app.Document.getComponent(innerGridId);
            originalRow = inner.getProperty("Layout.Row").LiteralValue;
            originalColumn = inner.getProperty("Layout.Column").LiteralValue;
            overlays.HTMLEventReceivedFcn(overlays, struct( ...
                "HTMLEventName", "GridAction", ...
                "HTMLEventData", struct("action", "move-child", ...
                "revision", parentData.revision, "activeGridId", outerGridId, ...
                "childId", innerGridId, "rowStart", 2, "rowEnd", 2, ...
                "columnStart", 2, "columnEnd", 2)));
            drawnow;
            testCase.verifyEqual(inner.getProperty("Layout.Row").LiteralValue, 2);
            testCase.verifyEqual(inner.getProperty("Layout.Column").LiteralValue, 2);
            testCase.verifyEqual(app.ActiveGridId, innerGridId);
            testCase.verifyEqual(app.Document.HistoryIndex, historyIndex + 1);

            % Reacquire the disposable overlay before resizing and checking stale events.
            overlays = findall(figure, "Type", "uihtml", "Tag", "macd-interaction-overlay");
            parentData = overlays.Data.gridPlacement;
            action = struct("action", "resize-span", "revision", parentData.revision, ...
                "activeGridId", outerGridId, "childId", innerGridId, ...
                "rowStart", 1, "rowEnd", 2, "columnStart", 2, "columnEnd", 2);
            overlays.HTMLEventReceivedFcn(overlays, struct( ...
                "HTMLEventName", "GridAction", "HTMLEventData", action));
            testCase.verifyEqual(inner.getProperty("Layout.Row").LiteralValue, [1 2]);
            testCase.verifyEqual(app.Document.HistoryIndex, historyIndex + 2);
            overlays = findall(figure, "Type", "uihtml", "Tag", "macd-interaction-overlay");
            overlays.HTMLEventReceivedFcn(overlays, struct( ...
                "HTMLEventName", "GridAction", "HTMLEventData", action));
            testCase.verifyEqual(app.Document.HistoryIndex, historyIndex + 2);
            app.Document.undo();
            app.Document.undo();
            testCase.verifyEqual(inner.getProperty("Layout.Row").LiteralValue, originalRow);
            testCase.verifyEqual(inner.getProperty("Layout.Column").LiteralValue, originalColumn);
            clear cleanup
        end

        function gridOverlaySelectsOpenedControlGalleryNestedGridChild(testCase)
            % gridOverlaySelectsOpenedControlGalleryNestedGridChild Select a parsed nested-grid child from the root view.

            testPath = mfilename("fullpath");
            projectRoot = fileparts(fileparts(fileparts(testPath)));
            fixture = string(fullfile(projectRoot, "tests", "fixtures", "ControlGalleryApp.m"));
            lifecycle = macd.ui.DocumentLifecycleService(struct( ...
                "RequestOpenPathFcn", @() acceptedOpenPath(fixture)));
            app = yamada(lifecycle);
            cleanup = onCleanup(@() deleteIfValid(app));
            figure = findall(0, "Type", "figure", "Tag", "macd-yamada-editor");
            menus = findall(figure, "Type", "uimenu");
            openMenu = menus(erase(string({menus.Text}), "&") == "Open...");
            testCase.verifyEqual(numel(openMenu), 1);
            openMenu.MenuSelectedFcn(openMenu, struct());
            drawnow;

            child = app.Document.getComponentByName("DueDatePicker");
            overlays = findall(figure, "Type", "uihtml");
            payload = overlays.Data;
            targetIndex = find(string({payload.gridSelectionTargets.id}) == child.Id, 1);
            testCase.verifyNotEmpty(targetIndex);
            target = payload.gridSelectionTargets(targetIndex);
            datePicker = findall(figure, "Type", "uidatepicker");
            panels = findall(figure, "Type", "uipanel");
            previewPanel = panels(string({panels.Title}) == "Safe preview: UIFigure");
            testCase.verifyEqual(numel(datePicker), 1);
            testCase.verifyEqual(numel(previewPanel), 1);
            datePosition = double(getpixelposition(datePicker, true));
            canvas = findall(previewPanel, "Type", "uipanel", ...
                "Tag", "macd-preview-canvas");
            testCase.verifyEqual(numel(canvas), 1);
            canvasPosition = double(getpixelposition(canvas, true));
            datePosition(1:2) = datePosition(1:2) - canvasPosition(1:2);
            testCase.verifyEqual([target.x target.y target.width target.height], ...
                datePosition, "AbsTol", 1);
            outerChild = app.Document.getComponentByName("FormPanel");
            outerTargetIndex = find(string({payload.gridSelectionTargets.id}) == outerChild.Id, 1);
            testCase.verifyNotEmpty(outerTargetIndex);
            testCase.verifyGreaterThan(target.depth, ...
                payload.gridSelectionTargets(outerTargetIndex).depth);

            overlays.HTMLEventReceivedFcn(overlays, struct( ...
                "HTMLEventName", "GridAction", ...
                "HTMLEventData", struct("action", "select-child", ...
                "revision", payload.gridEditor.revision, "activeGridId", ...
                string(target.gridId), "childId", string(target.id))));
            drawnow;

            refreshed = overlays.Data.gridEditor;
            testCase.verifyEqual(app.SelectedComponentId, child.Id);
            testCase.verifyEqual(app.ActiveGridId, string(target.gridId));
            testCase.verifyTrue(refreshed.geometryAvailable, refreshed.readOnlyReason);
            testCase.verifyTrue(refreshed.editable, refreshed.readOnlyReason);
            testCase.verifyEqual(string(refreshed.activeGridId), string(target.gridId));
            clear cleanup
        end

        function gridOverlayMovesChildIntoCollapsedFitTrack(testCase)
            % gridOverlayMovesChildIntoCollapsedFitTrack Treat a zero-height fit row as a move destination.

            app = yamada();
            cleanup = onCleanup(@() deleteIfValid(app));
            drawnow;
            [figure, palette] = editorPalette();
            names = string(palette.Data(:, 1));
            gridRow = find(names == "Grid Layout", 1);
            labelRow = find(names == "Label", 1);
            palette.DoubleClickedFcn(palette, ...
                struct("InteractionInformation", struct("Row", gridRow)));
            gridId = app.SelectedComponentId;
            palette.DoubleClickedFcn(palette, ...
                struct("InteractionInformation", struct("Row", labelRow)));
            childId = app.SelectedComponentId;
            drawnow;
            pause(0.25);
            drawnow;

            overlays = findall(figure, "Type", "uihtml");
            gridData = overlays.Data.gridEditor;
            overlays.HTMLEventReceivedFcn(overlays, struct( ...
                "HTMLEventName", "GridAction", ...
                "HTMLEventData", struct("action", "move-child", ...
                "revision", gridData.revision, "activeGridId", gridId, ...
                "childId", childId, "rowStart", 2, "rowEnd", 2, ...
                "columnStart", 2, "columnEnd", 2)));
            drawnow;
            overlays = findall(figure, "Type", "uihtml");
            gridData = overlays.Data.gridEditor;
            overlays.HTMLEventReceivedFcn(overlays, struct( ...
                "HTMLEventName", "GridAction", ...
                "HTMLEventData", struct("action", "set-track", ...
                "revision", gridData.revision, "activeGridId", gridId, ...
                "axis", "row", "index", 1, "mode", "fit", "value", 0)));
            drawnow;
            pause(0.25);
            drawnow;

            overlays = findall(figure, "Type", "uihtml");
            gridData = overlays.Data.gridEditor;
            overlays.HTMLEventReceivedFcn(overlays, struct( ...
                "HTMLEventName", "GridAction", ...
                "HTMLEventData", struct("action", "set-track", ...
                "revision", gridData.revision, "activeGridId", gridId, ...
                "axis", "column", "index", 1, "mode", "fit", "value", 0)));
            drawnow;
            pause(0.25);
            drawnow;

            overlays = findall(figure, "Type", "uihtml");
            collapsed = overlays.Data.gridEditor;
            testCase.verifyTrue(collapsed.geometryAvailable, collapsed.readOnlyReason);
            testCase.verifyTrue(collapsed.editable, collapsed.readOnlyReason);
            testCase.verifyEqual(collapsed.rowTracks(1).bounds(4), 0, "AbsTol", 1);
            testCase.verifyEqual(collapsed.columnTracks(1).bounds(3), 0, "AbsTol", 1);
            testCase.verifyEqual(app.SelectedComponentId, childId);
            testCase.verifyEqual(app.ActiveGridId, gridId);
            testCase.verifyEqual(string(collapsed.children(1).id), childId);
            testCase.verifyEqual(collapsed.children(1).rowStart, 2);
            testCase.verifyEqual(collapsed.children(1).columnStart, 2);
            testCase.verifyTrue(collapsed.children(1).editable);
            overlays.HTMLEventReceivedFcn(overlays, struct( ...
                "HTMLEventName", "GridAction", ...
                "HTMLEventData", struct("action", "move-child", ...
                "revision", collapsed.revision, "activeGridId", gridId, ...
                "childId", childId, "rowStart", 1, "rowEnd", 1, ...
                "columnStart", 1, "columnEnd", 1)));
            drawnow;

            overlays = findall(figure, "Type", "uihtml");
            refreshed = overlays.Data.gridEditor;
            child = app.Document.getComponent(childId);
            testCase.verifyEqual(child.getProperty("Layout.Row").LiteralValue, 1);
            testCase.verifyEqual(child.getProperty("Layout.Column").LiteralValue, 1);
            testCase.verifyGreaterThan(refreshed.rowTracks(1).bounds(4), 0);
            testCase.verifyGreaterThan(refreshed.columnTracks(1).bounds(3), 0);
            clear cleanup
        end
    end

    methods (Test, TestTags = {'fast', 'gridOverlay'})
        function gridOverlayHtmlOmitsTrackReordering(testCase)
            % gridOverlayHtmlOmitsTrackReordering Keep unsupported reordering out of the browser contract.

            projectRoot = fileparts(which("yamada"));
            html = fileread(fullfile(projectRoot, "resources", "EditorInteractionOverlay.html"));
            testCase.verifyFalse(contains(html, "move-track"));
            testCase.verifyFalse(contains(html, "Move Earlier"));
            testCase.verifyFalse(contains(html, "Move Later"));
            testCase.verifyTrue(contains(html, "select-child"));
            testCase.verifyFalse(contains(html, "72 * (Number(track.index) - 1)"));
            testCase.verifyFalse(contains(html, "22 * Number(track.index)"));
            testCase.verifyTrue(contains(html, "grid-separator"));
            testCase.verifyTrue(contains(html, "placeTrackPopover"));
            testCase.verifyTrue(contains(html, "gridSelectionTargets"));
            testCase.verifyTrue(contains(html, ...
                ".grid-selection-target { position: absolute; z-index: 1;"));
            testCase.verifyFalse(contains(html, "hitTarget.style.zIndex"));
            testCase.verifyTrue(contains(html, "track-settings"));
            testCase.verifyTrue(contains(html, "componentArray(targets).sort"));
            testCase.verifyTrue(contains(html, "addTrackDividers"));
            testCase.verifyFalse(contains(html, "data.rowBoundaries"));
            testCase.verifyTrue(contains(html, "rgba(34, 100, 199, 0.20)"));
            testCase.verifyTrue(contains(html, "rowRail"));
            testCase.verifyTrue(contains(html, "columnRail"));
            testCase.verifyTrue(contains(html, "var buttonSize = 12"));
            testCase.verifyTrue(contains(html, "var railGap = 0"));
            testCase.verifyTrue(contains(html, "Insert Row Above"));
            testCase.verifyTrue(contains(html, "Insert Column Left"));
            testCase.verifyFalse(contains(html, "Insert Before"));
            testCase.verifyTrue(contains(html, "grid-drop-band"));
            testCase.verifyTrue(contains(html, "width: min(244px, calc(100% - 8px))"));
            testCase.verifyTrue(contains(html, "grid-template-columns: 1fr"));
            testCase.verifyTrue(contains(html, "white-space: normal"));
            testCase.verifyTrue(contains(html, "aria-label"));
        end
    end

    methods (Test, TestTags = {'inspector', 'ui'})
        function inspectorProbesRuntimeDefaultsWithoutEntries(testCase)
            % inspectorProbesRuntimeDefaults Show runtime defaults without materializing properties.

            app = yamada();
            cleanup = onCleanup(@() deleteIfValid(app));
            drawnow;
            figures = findall(0, "Type", "figure", "Tag", "macd-yamada-editor");
            tables = findall(figures, "Type", "uitable");
            palette = tables(arrayfun(@(table) any(string(table.ColumnName) == "Component") && ...
                any(string(table.ColumnName) == "Category"), tables));
            row = find(string(palette.Data(:, 1)) == "List Box", 1);
            palette.DoubleClickedFcn(palette, struct("InteractionInformation", struct("Row", row)));
            drawnow;
            checks = findall(0, "Type", "uicheckbox", "Tag", "macd-inspector-property-editor");
            testCase.verifyNotEmpty(checks);
            testCase.verifyTrue(any([checks.Value]));
            selected = app.Document.getComponent(app.SelectedComponentId);
            testCase.verifyEmpty(selected.getProperty("Visible"));
            clear cleanup
        end
    end

    methods (Test, TestTags = {'inspector', 'fast', 'ui'})
        function fontStyleButtonCommitsCatalogChoice(testCase)
            % fontStyleButtonCommitsCatalogChoice Commit a typographic style toggle through the live inspector.

            % Insert a button through the palette so its Font Style row is reconstructed.
            app = yamada();
            cleanup = onCleanup(@() deleteIfValid(app));
            drawnow;
            figure = findall(0, "Type", "figure", "Tag", "macd-yamada-editor");
            tables = findall(figure, "Type", "uitable");
            palette = tables(arrayfun(@(table) any(string(table.ColumnName) == "Component") && ...
                any(string(table.ColumnName) == "Category"), tables));
            row = find(string(palette.Data(:, 1)) == "Button", 1);
            palette.DoubleClickedFcn(palette, struct("InteractionInformation", struct("Row", row)));
            drawnow;

            % Toggle the compact bold state button using the real batch callback binding.
            labels = findall(figure, "Type", "uilabel", "Tag", "macd-inspector-property-label");
            label = labels(string({labels.Text}) == "Font Style");
            testCase.verifyEqual(numel(label), 1);
            controls = findall(figure, "Tag", "macd-inspector-font-weight-button");
            control = controls(arrayfun(@(candidate) isa(candidate, ...
                "matlab.ui.control.StateButton") && isvalid(candidate), controls));
            testCase.verifyEqual(numel(control), 1);
            testCase.verifyEqual(string(control.Enable), "on");
            control.Value = true;
            control.ValueChangedFcn(control, struct());
            drawnow;
            component = app.Document.getComponent(app.SelectedComponentId);
            entry = component.getProperty("FontWeight");
            testCase.verifyEqual(string(entry.LiteralValue), "bold");
            clear cleanup
        end
    end

    methods (Test, TestTags = {'inspector', 'ui'})
        function itemSelectionInspectorCommitsAnItemsChoice(testCase)
            % itemSelectionInspectorCommitsAnItemsChoice Route a native selection through the live inspector.

            app = yamada();
            cleanup = onCleanup(@() deleteIfValid(app));
            figure = findall(0, "Type", "figure", "Tag", "macd-yamada-editor");
            figure.Visible = "off";
            tables = findall(figure, "Type", "uitable");
            palette = tables(arrayfun(@(table) any(string(table.ColumnName) == "Component") && ...
                any(string(table.ColumnName) == "Category"), tables));
            row = find(string(palette.Data(:, 1)) == "Drop-down", 1);
            palette.DoubleClickedFcn(palette, struct( ...
                "InteractionInformation", struct("Row", row)));
            drawnow;

            labels = findall(figure, "Type", "uilabel", ...
                "Tag", "macd-inspector-property-label");
            label = labels(string({labels.Text}) == "Value");
            editor = findall(label.Parent, "Tag", "macd-inspector-item-selection-editor");
            testCase.verifyClass(editor, "matlab.ui.control.DropDown");
            testCase.verifyEqual(string(editor.Enable), "on");
            testCase.verifyGreaterThanOrEqual(numel(editor.Items), 2);
            selected = string(editor.Items{2});
            editor.Value = char(selected);
            editor.ValueChangedFcn(editor, struct());
            drawnow;

            component = app.Document.getComponent(app.SelectedComponentId);
            testCase.verifyEqual(string(component.getProperty("Value").LiteralValue), selected);
            clear cleanup
        end

        function itemsDataEditRetainsAndRebindsTheCurrentSelection(testCase)
            % itemsDataEditRetainsAndRebindsTheCurrentSelection Keep Value in ItemsData's domain.

            app = yamada();
            cleanup = onCleanup(@() deleteIfValid(app));
            figure = findall(0, "Type", "figure", "Tag", "macd-yamada-editor");
            figure.Visible = "off";
            tables = findall(figure, "Type", "uitable");
            palette = tables(arrayfun(@(table) any(string(table.ColumnName) == "Component") && ...
                any(string(table.ColumnName) == "Category"), tables));
            row = find(string(palette.Data(:, 1)) == "Drop-down", 1);
            palette.DoubleClickedFcn(palette, struct( ...
                "InteractionInformation", struct("Row", row)));
            drawnow;

            editItems = findall(figure, "Tag", "macd-inspector-items-editor");
            editItems.ButtonPushedFcn(editItems, struct());
            dialog = findall(0, "Type", "figure", "Tag", "macd-items-editor-dialog");
            table = findall(dialog, "Type", "uitable", "Tag", "macd-items-editor-table");
            data = table.Data;
            data(:, 2) = string((10:10:(10 * size(data, 1)))');
            table.Data = data;
            apply = findall(dialog, "Tag", "macd-items-editor-apply");
            apply.ButtonPushedFcn(apply, struct());
            drawnow;

            component = app.Document.getComponent(app.SelectedComponentId);
            testCase.verifyEqual(component.getProperty("Value").LiteralValue, 10);
            labels = findall(figure, "Type", "uilabel", "Tag", "macd-inspector-property-label");
            valueLabel = labels(string({labels.Text}) == "Value");
            editor = findall(valueLabel.Parent, "Tag", "macd-inspector-item-selection-editor");
            editor.Value = char(editor.Items{2});
            editor.ValueChangedFcn(editor, struct());
            drawnow;
            testCase.verifyEqual(component.getProperty("Value").LiteralValue, 20);
            clear cleanup
        end
        function textAreaValueCommitPreservesAllLines(testCase)
            % textAreaValueCommitPreservesAllLines Keep one multiline Value as one transaction change.

            % Insert a Text Area, then invoke its native multiline inspector callback.
            app = yamada();
            cleanup = onCleanup(@() deleteIfValid(app));
            figure = findall(0, "Type", "figure", "Tag", "macd-yamada-editor");
            figure.Visible = "off";
            tables = findall(figure, "Type", "uitable");
            palette = tables(arrayfun(@(table) any(string(table.ColumnName) == "Component") && ...
                any(string(table.ColumnName) == "Category"), tables));
            row = find(string(palette.Data(:, 1)) == "Text Area", 1);
            palette.DoubleClickedFcn(palette, struct( ...
                "InteractionInformation", struct("Row", row)));
            drawnow;

            % Resolve the Value row without confusing it with the Tooltip text area.
            labels = findall(figure, "Type", "uilabel", ...
                "Tag", "macd-inspector-property-label");
            label = labels(string({labels.Text}) == "Value");
            editor = findall(label.Parent, "Type", "uitextarea", ...
                "Tag", "macd-inspector-property-editor");
            lines = {'First'; 'Second'; 'Third'};
            editor.Value = lines;
            editor.ValueChangedFcn(editor, struct());
            drawnow;

            component = app.Document.getComponent(app.SelectedComponentId);
            entry = component.getProperty("Value");
            testCase.verifyEqual(entry.LiteralValue, {'First', 'Second', 'Third'});
            labels = findall(figure, "Type", "uilabel", ...
                "Tag", "macd-inspector-property-label");
            label = labels(string({labels.Text}) == "Value");
            editor = findall(label.Parent, "Type", "uitextarea", ...
                "Tag", "macd-inspector-property-editor");
            testCase.verifyEqual(string(editor.Value), string(lines));
            clear cleanup
        end

        function datePickerValueCommitPreservesTypedDate(testCase)
            % datePickerValueCommitPreservesTypedDate Keep native datetime data out of text parsing.

            % Insert a Date Picker, then invoke the native date editor callback.
            app = yamada();
            cleanup = onCleanup(@() deleteIfValid(app));
            figure = findall(0, "Type", "figure", "Tag", "macd-yamada-editor");
            figure.Visible = "off";
            tables = findall(figure, "Type", "uitable");
            palette = tables(arrayfun(@(table) any(string(table.ColumnName) == "Component") && ...
                any(string(table.ColumnName) == "Category"), tables));
            row = find(string(palette.Data(:, 1)) == "Date Picker", 1);
            palette.DoubleClickedFcn(palette, struct( ...
                "InteractionInformation", struct("Row", row)));
            drawnow;

            labels = findall(figure, "Type", "uilabel", ...
                "Tag", "macd-inspector-property-label");
            label = labels(string({labels.Text}) == "Value");
            editor = findall(label.Parent, "Tag", "macd-inspector-date-picker-editor");
            selected = datetime(2024, 2, 29);
            editor.Value = selected;
            editor.ValueChangedFcn(editor, struct());
            drawnow;

            component = app.Document.getComponent(app.SelectedComponentId);
            entry = component.getProperty("Value");
            testCase.verifyClass(entry.LiteralValue, "datetime");
            testCase.verifyEqual(entry.LiteralValue, selected);
            clear cleanup
        end

        function datePickerLimitsCommitBothBoundsAtomically(testCase)
            % datePickerLimitsCommitBothBoundsAtomically Reject a partial invalid range without mutation.

            app = yamada();
            cleanup = onCleanup(@() deleteIfValid(app));
            figure = findall(0, "Type", "figure", "Tag", "macd-yamada-editor");
            figure.Visible = "off";
            tables = findall(figure, "Type", "uitable");
            palette = tables(arrayfun(@(table) any(string(table.ColumnName) == "Component") && ...
                any(string(table.ColumnName) == "Category"), tables));
            row = find(string(palette.Data(:, 1)) == "Date Picker", 1);
            palette.DoubleClickedFcn(palette, struct( ...
                "InteractionInformation", struct("Row", row)));
            drawnow;

            limitsEditor = findall(figure, "Tag", "macd-inspector-date-limits-editor");
            editorPosition = getpixelposition(limitsEditor, true);
            testCase.verifyGreaterThanOrEqual(editorPosition(4), 56);
            parts = limitsEditor.UserData;
            parts.Start.Value = datetime(2024, 12, 31);
            parts.End.Value = datetime(2024, 1, 1);
            parts.Start.ValueChangedFcn(parts.Start, struct());
            component = app.Document.getComponent(app.SelectedComponentId);
            testCase.verifyEmpty(component.getProperty("Limits"));
            parts.Start.Value = datetime(2024, 1, 1);
            parts.End.Value = datetime(2024, 12, 31);
            parts.End.ValueChangedFcn(parts.End, struct());
            entry = component.getProperty("Limits");
            testCase.verifyEqual(entry.LiteralValue, ...
                [datetime(2024, 1, 1) datetime(2024, 12, 31)]);
            clear cleanup
        end

        function datePickerValueEditorSynchronizesEffectiveRestrictions(testCase)
            % datePickerValueEditorSynchronizesEffectiveRestrictions Refresh the native calendar after a related inspector edit.

            app = yamada();
            cleanup = onCleanup(@() deleteIfValid(app));
            figure = findall(0, "Type", "figure", "Tag", "macd-yamada-editor");
            figure.Visible = "off";
            tables = findall(figure, "Type", "uitable");
            palette = tables(arrayfun(@(table) any(string(table.ColumnName) == "Component") && ...
                any(string(table.ColumnName) == "Category"), tables));
            row = find(string(palette.Data(:, 1)) == "Date Picker", 1);
            palette.DoubleClickedFcn(palette, struct( ...
                "InteractionInformation", struct("Row", row)));
            drawnow;

            limits = [datetime(2024, 1, 1) datetime(2024, 12, 31)];
            limitsEditor = findall(figure, "Tag", "macd-inspector-date-limits-editor");
            parts = limitsEditor.UserData;
            parts.Start.Value = limits(1);
            parts.End.Value = limits(2);
            parts.End.ValueChangedFcn(parts.End, struct());
            drawnow;

            editor = findall(figure, "Tag", "macd-inspector-date-picker-editor");
            testCase.verifyEqual(editor.Limits, limits);
            clear cleanup
        end

        function datePickerInspectorRetainsItsCompleteEditableSurface(testCase)
            % datePickerInspectorRetainsItsCompleteEditableSurface Keep all audited Date Picker rows visible.

            app = yamada();
            cleanup = onCleanup(@() deleteIfValid(app));
            figure = findall(0, "Type", "figure", "Tag", "macd-yamada-editor");
            figure.Visible = "off";
            tables = findall(figure, "Type", "uitable");
            palette = tables(arrayfun(@(table) any(string(table.ColumnName) == "Component") && ...
                any(string(table.ColumnName) == "Category"), tables));
            row = find(string(palette.Data(:, 1)) == "Date Picker", 1);
            palette.DoubleClickedFcn(palette, struct( ...
                "InteractionInformation", struct("Row", row)));
            drawnow;

            labels = findall(figure, "Type", "uilabel", ...
                "Tag", "macd-inspector-property-label");
            actual = string({labels.Text});
            expected = ["Value", "Placeholder", "Limits", "DisplayFormat", ...
                "DisabledDates", "DisabledDaysOfWeek", "FontName", "FontSize", ...
                "Font Style", "FontColor", "BackgroundColor", "Visible", "Editable", ...
                "Enable", "Tooltip", "ContextMenu", "Position", "Interruptible", "BusyAction"];
            testCase.verifyTrue(all(ismember(expected, actual)));
            clear cleanup
        end

        function tableDataDialogCommitsTypedDataFromTheInspector(testCase)
            % tableDataDialogCommitsTypedDataFromTheInspector Apply one typed table draft through the real row binding.

            app = yamada();
            cleanup = onCleanup(@() deleteIfValid(app));
            figure = findall(0, "Type", "figure", "Tag", "macd-yamada-editor");
            figure.Visible = "off";
            tables = findall(figure, "Type", "uitable");
            palette = tables(arrayfun(@(table) any(string(table.ColumnName) == "Component") && ...
                any(string(table.ColumnName) == "Category"), tables));
            row = find(string(palette.Data(:, 1)) == "Table", 1);
            palette.DoubleClickedFcn(palette, struct( ...
                "InteractionInformation", struct("Row", row)));
            drawnow;

            labels = findall(figure, "Type", "uilabel", ...
                "Tag", "macd-inspector-property-label");
            dataLabel = labels(string({labels.Text}) == "Data & Names");
            editor = findall(dataLabel.Parent, "Tag", "macd-inspector-table-data-editor");
            editor.ButtonPushedFcn(editor, struct());
            dialog = findall(0, "Tag", "macd-inspector-table-data-dialog");
            addColumn = findall(dialog, "Tag", "macd-table-data-add-column");
            addColumn.ButtonPushedFcn(addColumn, struct());
            addRow = findall(dialog, "Tag", "macd-table-data-add-row");
            addRow.ButtonPushedFcn(addRow, struct());
            table = findall(dialog, "Tag", "macd-table-data-editor-table");
            bodyRows = size(table.Data, 1) - 1;
            bodyColumns = size(table.Data, 2) - 1;
            expected = reshape(1:bodyRows * bodyColumns, bodyRows, bodyColumns);
            dataType = findall(dialog, "Tag", "macd-table-data-type");
            dataType.Value = "numeric";
            dataType.ValueChangedFcn(dataType, struct());
            table.Data(2:end, 2:end) = string(expected);
            applyButton = findall(dialog, "Tag", "macd-table-data-apply");
            applyButton.ButtonPushedFcn(applyButton, struct());
            drawnow;

            component = app.Document.getComponent(app.SelectedComponentId);
            entry = component.getProperty("Data");
            testCase.verifyEqual(entry.LiteralValue, expected);
            columnEditors = findall(figure, "Tag", "macd-inspector-column-settings-editor");
            columnEditor = columnEditors(arrayfun(@(candidate) isa(candidate, ...
                "matlab.ui.control.Button") && isvalid(candidate), columnEditors));
            testCase.verifyEqual(numel(columnEditor), 1);
            columnEditor.ButtonPushedFcn(columnEditor, struct());
            columnDialog = findall(0, "Tag", "macd-column-settings-dialog");
            columnTable = findall(columnDialog, "Tag", "macd-column-settings-table");
            columnTable.Data{1, 2} = true;
            columnTable.Data{1, 3} = true;
            columnTable.Data{1, 4} = 'fit';
            columnTable.Data{1, 5} = '''bank''';
            columnApply = findall(columnDialog, "Tag", "macd-column-settings-apply");
            columnApply.ButtonPushedFcn(columnApply, struct());
            drawnow;
            component = app.Document.getComponent(app.SelectedComponentId);
            testCase.verifyEqual(component.getProperty("ColumnWidth").LiteralValue, 'fit');
            testCase.verifyTrue(component.getProperty("ColumnEditable").LiteralValue);
            testCase.verifyTrue(component.getProperty("ColumnSortable").LiteralValue);
            testCase.verifyEqual(component.getProperty("ColumnFormat").LiteralValue, {'bank'});
            clear cleanup
        end
    end

    methods (Test, TestTags = {'editorShell', 'ui'})
        function editMenuExposesEditingCommands(testCase)
            % editMenuExposesEditingCommands Verify Delete, Undo, and Redo menu items.

            % Inspect the actual menu hierarchy after editor construction.
            app = yamada();
            cleanup = onCleanup(@() deleteIfValid(app));
            drawnow;
            menus = findall(0, "Type", "uimenu");
            menuText = string({menus.Text});
            testCase.verifyTrue(any(contains(menuText, "Edit")));
            testCase.verifyTrue(any(contains(menuText, "Delete")));
            testCase.verifyTrue(any(contains(menuText, "Undo")));
            testCase.verifyTrue(any(contains(menuText, "Redo")));
            clear cleanup
        end
    end

    methods (Test, TestTags = {'editorShell', 'previewTab', 'ui'})
        function tabSwitchClearsHiddenGridEditor(testCase)
            % tabSwitchClearsHiddenGridEditor Hide grid tools immediately and restore them on return.
            app = yamada();
            cleanup = onCleanup(@() deleteIfValid(app));
            drawnow;
            [figure, palette] = editorPalette();
            for name = ["Tab Group", "Tab", "Tab", "Grid Layout", "Label"]
                row = find(string(palette.Data(:, 1)) == name, 1);
                palette.DoubleClickedFcn(palette, struct( ...
                    "InteractionInformation", struct("Row", row)));
                drawnow;
            end
            overlay = findall(figure, "Type", "uihtml");
            group = findall(figure, "Type", "uitabgroup");
            group.Position = [20 20 400 300];
            drawnow;
            items = overlay.Data.components;
            groupData = items([items.tabGroup]);
            selectedId = app.SelectedComponentId;
            historyIndex = app.Document.HistoryIndex;
            for index = [2 1 2]
                overlay.HTMLEventReceivedFcn(overlay, struct( ...
                    "HTMLEventName", "Pointer", "HTMLEventData", struct( ...
                    "phase", "tabselect", "componentId", groupData.id, ...
                    "tabIndex", index, "x", 0, "y", 0)));
                testCase.verifyEqual(group.SelectedTab, group.Children(index));
                if index == 1
                    testCase.verifyEqual(app.ActiveGridId, "");
                    testCase.verifyEmpty(overlay.Data.gridEditor.children);
                    testCase.verifyEmpty(overlay.Data.gridSelectionTargets);
                else
                    testCase.verifyNotEqual(app.ActiveGridId, "");
                    % Visible-tab geometry is published after the native layout settles.
                    for attempt = 1:40
                        drawnow;
                        pause(0.05);
                        if ~isempty(overlay.Data.gridEditor.children)
                            break
                        end
                    end
                    testCase.verifyNotEmpty(overlay.Data.gridEditor.children, ...
                        string(overlay.Data.gridEditor.readOnlyReason));
                end
                testCase.verifyEqual(app.SelectedComponentId, selectedId);
                testCase.verifyEqual(app.Document.HistoryIndex, historyIndex);
            end
            clear cleanup
        end

        function tabSelectorEventChangesPreviewTab(testCase)
            % tabSelectorEventChangesPreviewTab Verify the overlay tab selector route.

            % Add a tab group and two tabs through the same palette callback path users use.
            app = yamada();
            cleanup = onCleanup(@() deleteIfValid(app));
            drawnow;
            figures = findall(0, "Type", "figure", "Tag", "macd-yamada-editor");
            tables = findall(figures, "Type", "uitable");
            palette = tables(arrayfun(@(table) any(string(table.ColumnName) == ...
                "Component") && any(string(table.ColumnName) == "Category"), tables));
            row = find(string(palette.Data(:, 1)) == "Tab Group", 1);
            palette.DoubleClickedFcn(palette, struct( ...
                "InteractionInformation", struct("Row", row)));
            drawnow;
            row = find(string(palette.Data(:, 1)) == "Tab", 1);
            palette.DoubleClickedFcn(palette, struct( ...
                "InteractionInformation", struct("Row", row)));
            drawnow;
            palette.DoubleClickedFcn(palette, struct( ...
                "InteractionInformation", struct("Row", row)));
            drawnow;
            row = find(string(palette.Data(:, 1)) == "Button", 1);
            palette.DoubleClickedFcn(palette, struct( ...
                "InteractionInformation", struct("Row", row)));
            drawnow;

            % Confirm the overlay exposes both titles and the current selection.
            overlays = findall(figures, "Type", "uihtml");
            components = overlays.Data.components;
            if ~isstruct(components)
                components = struct(components);
            end
            tabGroup = components([components.tabGroup]);
            testCase.verifyEqual(numel(tabGroup.tabTitles), 2);
            testCase.verifyEqual(tabGroup.tabSelected, 1);

            % Exercise the same event payload emitted by the HTML select control.
            overlays.HTMLEventReceivedFcn(overlays, struct( ...
                "HTMLEventName", "Pointer", ...
                "HTMLEventData", struct("phase", "tabselect", ...
                "componentId", tabGroup.id, "tabIndex", 2, ...
                "x", 0, "y", 0)));
            drawnow;
            groups = findall(figures, "Type", "uitabgroup");
            testCase.verifyEqual(groups.SelectedTab, groups.Children(2));

            % Wait for the overlay to publish the selected tab's settled geometry.
            child = struct.empty;
            for attempt = 1:20
                drawnow;
                pause(0.05);
                components = overlays.Data.components;
                if ~isstruct(components)
                    components = struct(components);
                end
                child = components(strcmp(string({components.shape}), "roundedRectangle"));
                if ~isempty(child)
                    break
                end
            end
            testCase.verifyNotEmpty(child);

            % A subsequent component interaction must preserve the chosen tab.
            child = child(1);
            overlays.HTMLEventReceivedFcn(overlays, struct( ...
                "HTMLEventName", "Pointer", ...
                "HTMLEventData", struct("phase", "pointerdown", ...
                "componentId", child.id, "tabIndex", 0, "x", 1, "y", 1, ...
                "handle", "")));
            overlays.HTMLEventReceivedFcn(overlays, struct( ...
                "HTMLEventName", "Pointer", ...
                "HTMLEventData", struct("phase", "pointerup", ...
                "componentId", child.id, "tabIndex", 0, "x", 1, "y", 1, ...
                "handle", "")));
            drawnow;
            groups = findall(figures, "Type", "uitabgroup");
            testCase.verifyEqual(groups.SelectedTab, groups.Children(2));
            clear cleanup
        end
    end

    methods (Test, TestTags = {'catalog', 'fast'})
        function registryCarriesResizePolicies(testCase)
            % registryCarriesResizePolicies Verify constrained controls are explicit.
            registry = macd.model.ComponentRegistry.createDefault();
            testCase.verifyEqual(registry.get("uigauge").ResizeConstraint, ...
                "aspectRatio");
            testCase.verifyEqual(registry.get("uiknob").ResizeConstraint, ...
                "aspectRatio");
            testCase.verifyEqual(registry.get("uiswitch").ResizeConstraint, ...
                "aspectRatio");
            testCase.verifyEqual(registry.get("uilamp").ResizeConstraint, ...
                "aspectRatio");
            testCase.verifyEqual(registry.get("uislider").ResizeConstraint, ...
                "fixedHeight");
            testCase.verifyEqual(registry.get("uiknob").OverlayShape, "circle");
            testCase.verifyEqual(registry.get("uislider").OverlayShape, "slider");
            testCase.verifyEqual(registry.get("uiswitch").OverlayShape, "switch");
            ninetyDegree = registry.getById("uigauge-ninetydegree");
            semicircular = registry.getById("uigauge-semicircular");
            rocker = registry.getById("uiswitch-rocker");
            toggle = registry.getById("uiswitch-toggle");
            testCase.verifyEqual(ninetyDegree.overlayShapeFor(ninetyDegree.CreationArguments), ...
                "quarterCircle");
            testCase.verifyEqual(semicircular.overlayShapeFor(semicircular.CreationArguments), ...
                "semicircle");
            testCase.verifyEqual(rocker.overlayShapeFor(rocker.CreationArguments), ...
                "rockerSwitch");
            testCase.verifyEqual(toggle.overlayShapeFor(toggle.CreationArguments), ...
                "toggleSwitch");
        end
    end

    methods (Test, TestTags = {'editorShell', 'ui'})
        function largeActualSizeFixtureScrollsAndRootResizeIsUndoable(testCase)
            % largeActualSizeFixtureScrollsAndRootResizeIsUndoable Exercise real editor geometry.
            testPath = mfilename("fullpath");
            projectRoot = fileparts(fileparts(fileparts(testPath)));
            fixture = string(fullfile(projectRoot, "tests", "fixtures", ...
                "LargePreviewFixtureApp.m"));
            lifecycle = macd.ui.DocumentLifecycleService(struct( ...
                "RequestOpenPathFcn", @() acceptedOpenPath(fixture)));
            app = yamada(lifecycle);
            cleanup = onCleanup(@() deleteIfValid(app));
            figure = findall(0, "Type", "figure", "Tag", "macd-yamada-editor");
            menus = findall(figure, "Type", "uimenu");
            openMenu = menus(erase(string({menus.Text}), "&") == "Open...");
            openMenu.MenuSelectedFcn(openMenu, struct());
            drawnow;

            % The oversized canvas keeps source pixels and exposes native scrolling.
            previewPanel = findall(figure, "Type", "uipanel", ...
                "Title", "Safe preview: UIFigure");
            scrollPanel = findall(previewPanel, "Type", "uipanel", ...
                "Tag", "macd-preview-scroll-host");
            canvas = findall(previewPanel, "Type", "uipanel", ...
                "Tag", "macd-preview-canvas");
            testCase.assertEqual(numel(canvas), 1);
            testCase.assertEqual(numel(scrollPanel), 1);
            testCase.verifyEqual(canvas.Position, [2 2 1200 900]);
            testCase.verifyEqual(string(scrollPanel.Scrollable), "on");
            content = canvas.Parent.Parent;
            testCase.verifyGreaterThanOrEqual(content.Position(3:4) - ...
                canvas.Parent.Position(3:4), [24 24]);
            testCase.verifyGreaterThan(content.Position(3), ...
                scrollPanel.InnerPosition(3));
            testCase.verifyGreaterThan(content.Position(4), ...
                scrollPanel.InnerPosition(4));
            verticalDivider = findall(previewPanel, "Type", "uipanel", ...
                "Tag", "macd-preview-vertical-scroll-divider");
            horizontalDivider = findall(previewPanel, "Type", "uipanel", ...
                "Tag", "macd-preview-horizontal-scroll-divider");
            testCase.verifyEqual(string(verticalDivider.Visible), "on");
            testCase.verifyEqual(string(horizontalDivider.Visible), "on");
            testCase.verifyEqual(verticalDivider.Position(1), ...
                scrollPanel.Position(3) - 17);
            testCase.verifyEqual(horizontalDivider.Position(2), 17);
            button = findall(canvas, "Type", "uibutton", "Text", "Bottom right");
            testCase.assertEqual(numel(button), 1);
            scroll(scrollPanel, "right");
            scroll(scrollPanel, "bottom");
            drawnow;
            overlay = findall(canvas.Parent.Parent, "Type", "uihtml", ...
                "Tag", "macd-interaction-overlay");
            components = overlay.Data.components;
            buttonId = app.Document.getComponentByName("BottomRightButton").Id;
            target = components(string({components.id}) == buttonId);
            testCase.assertEqual(numel(target), 1);
            buttonPosition = double(getpixelposition(button, true));
            canvasPosition = double(getpixelposition(canvas, true));
            buttonPosition(1:2) = buttonPosition(1:2) - canvasPosition(1:2);
            testCase.verifyEqual([target.x target.y target.width target.height], ...
                buttonPosition, "AbsTol", 1);

            % The root handle changes only width and height through one model edit.
            rootId = app.Document.RootComponentId;
            testCase.verifyTrue(overlay.Data.rootEditable);
            for phase = ["pointerdown", "pointermove", "pointerup"]
                point = [1190 890];
                handle = "root-ne";
                if phase ~= "pointerdown"
                    point = [1230 920];
                    handle = "";
                end
                overlay.HTMLEventReceivedFcn(overlay, struct( ...
                    "HTMLEventName", "Pointer", ...
                    "HTMLEventData", struct("phase", phase, ...
                    "x", point(1), "y", point(2), ...
                    "componentId", rootId, "handle", handle)));
                if phase == "pointermove"
                    guide = findall(content, "Type", "uihtml", ...
                        "Tag", "macd-root-resize-guide");
                    testCase.assertEqual(numel(guide), 1);
                    testCase.verifyEqual(string(guide.Visible), "on");
                    testCase.verifyEqual(guide.Position(3:4), [1240 930]);
                end
            end
            testCase.verifyEmpty(findall(content, "Type", "uihtml", ...
                "Tag", "macd-root-resize-guide"));
            root = app.Document.getComponent(rootId);
            testCase.verifyEqual(root.getProperty("Position").LiteralValue, ...
                [100 100 1240 930]);
            [source, diagnostics] = macd.source.RoundTripGenerator().generate(app.Document);
            testCase.verifyEmpty(diagnostics);
            testCase.verifyTrue(contains(source, ...
                "app.UIFigure.Position = [100 100 1240 930];"));
            reopened = macd.source.AppSourceParser.parseText(source, ...
                macd.model.ComponentRegistry.createDefault(), fixture);
            reopenedRoot = reopened.getComponent(reopened.RootComponentId);
            testCase.verifyEqual(reopenedRoot.getProperty("Position").LiteralValue, ...
                [100 100 1240 930]);

            undoMenu = menus(erase(string({menus.Text}), "&") == "Undo");
            undoMenu.MenuSelectedFcn(undoMenu, struct());
            testCase.verifyEqual(root.getProperty("Position").LiteralValue, ...
                [100 100 1200 900]);
            redoMenu = menus(erase(string({menus.Text}), "&") == "Redo");
            redoMenu.MenuSelectedFcn(redoMenu, struct());
            testCase.verifyEqual(root.getProperty("Position").LiteralValue, ...
                [100 100 1240 930]);
            canvas = findall(figure, "Type", "uipanel", ...
                "Tag", "macd-preview-canvas");
            overlay = findall(canvas.Parent.Parent, "Type", "uihtml", ...
                "Tag", "macd-interaction-overlay");
            for phase = ["pointerdown", "pointermove", "pointerup"]
                point = [7 7];
                handle = "root-sw";
                if phase ~= "pointerdown"
                    point = [-13 -8];
                    handle = "";
                end
                overlay.HTMLEventReceivedFcn(overlay, struct( ...
                    "HTMLEventName", "Pointer", ...
                    "HTMLEventData", struct("phase", phase, ...
                    "x", point(1), "y", point(2), ...
                    "componentId", rootId, "handle", handle)));
                if phase == "pointermove"
                    guide = findall(canvas.Parent.Parent, "Type", "uihtml", ...
                        "Tag", "macd-root-resize-guide");
                    testCase.assertEqual(numel(guide), 1);
                    testCase.verifyEqual(guide.Position(3:4), [1260 945]);
                end
            end
            testCase.verifyEqual(root.getProperty("Position").LiteralValue, ...
                [80 85 1260 945]);
            undoMenu.MenuSelectedFcn(undoMenu, struct());
            testCase.verifyEqual(root.getProperty("Position").LiteralValue, ...
                [100 100 1240 930]);
            canvas = findall(figure, "Type", "uipanel", ...
                "Tag", "macd-preview-canvas");
            figure.Position(3:4) = [1100 700];
            drawnow;
            testCase.verifyEqual(canvas.Position(3:4), [1240 930]);
            clear cleanup
        end
        function shrinkingFigureKeepsStrandedComponentsReachable(testCase)
            % shrinkingFigureKeepsStrandedComponentsReachable Recover components outside the root.
            projectRoot = fileparts(which("yamada"));
            fixture = string(fullfile(projectRoot, "tests", "fixtures", ...
                "LargePreviewFixtureApp.m"));
            lifecycle = macd.ui.DocumentLifecycleService(struct( ...
                "RequestOpenPathFcn", @() acceptedOpenPath(fixture)));
            app = yamada(lifecycle);
            cleanup = onCleanup(@() deleteIfValid(app));
            figure = findall(0, "Type", "figure", "Tag", "macd-yamada-editor");
            menus = findall(figure, "Type", "uimenu");
            openMenu = menus(erase(string({menus.Text}), "&") == "Open...");
            openMenu.MenuSelectedFcn(openMenu, struct());
            drawnow;

            % Shrink the actual figure without moving its existing components.
            overlay = findall(figure, "Type", "uihtml", "Tag", "macd-interaction-overlay");
            sendOverlayGesture(overlay, app.Document.RootComponentId, ...
                "root-ne", [1190 890], [310 230]);
            canvas = findall(figure, "Type", "uipanel", "Tag", "macd-preview-canvas");
            scrollPanel = findall(figure, "Type", "uipanel", "Tag", "macd-preview-scroll-host");
            overlay = findall(figure, "Type", "uihtml", "Tag", "macd-interaction-overlay");
            testCase.verifyEqual(canvas.Position(3:4), [320 240]);
            testCase.verifyEqual([overlay.Data.width overlay.Data.height], [320 240]);
            testCase.verifyGreaterThan(overlay.Data.surfaceBounds(3:4), [1186 886]);
            testCase.verifyEqual(overlay.Parent, canvas.Parent.Parent);
            scroll(scrollPanel, "right");
            scroll(scrollPanel, "bottom");
            drawnow;

            % Retrieve stranded controls through canvas-local gestures after scrolling.
            names = ["BottomRightButton", "CenterPanel", "TopLeftLabel"];
            destinations = [50 60; 0 50; 12 212];
            for index = 1:numel(names)
                overlay = findall(figure, "Type", "uihtml", "Tag", "macd-interaction-overlay");
                component = app.Document.getComponentByName(names(index));
                target = overlay.Data.components(string({overlay.Data.components.id}) == component.Id);
                testCase.assertEqual(numel(target), 1);
                testCase.verifyGreaterThanOrEqual(overlay.Data.surfaceBounds(1:2) + ...
                    overlay.Data.surfaceBounds(3:4), [target.x + target.width target.y + target.height]);
                startPoint = component.getProperty("Position").LiteralValue(1:2) + 4;
                sendOverlayGesture(overlay, component.Id, "", ...
                    startPoint, destinations(index, :) + 4);
                testCase.verifyEqual(component.getProperty("Position").LiteralValue(1:2), ...
                    destinations(index, :));
            end
            canvas = findall(figure, "Type", "uipanel", "Tag", "macd-preview-canvas");
            content = canvas.Parent.Parent;
            testCase.verifyEqual(canvas.Position(3:4), [320 240]);
            testCase.verifyEqual(content.Position(3:4), scrollPanel.InnerPosition(3:4));

            % Undo restores the stranded outline and its range; Redo removes it.
            undoMenu = menus(erase(string({menus.Text}), "&") == "Undo");
            redoMenu = menus(erase(string({menus.Text}), "&") == "Redo");
            undoMenu.MenuSelectedFcn(undoMenu, struct());
            overlay = findall(figure, "Type", "uihtml", "Tag", "macd-interaction-overlay");
            testCase.verifyGreaterThan(overlay.Data.surfaceBounds(4), 886);
            redoMenu.MenuSelectedFcn(redoMenu, struct());
            overlay = findall(figure, "Type", "uihtml", "Tag", "macd-interaction-overlay");
            testCase.verifyLessThanOrEqual(overlay.Data.surfaceBounds(4), 246);
            clear cleanup
        end
    end
end

function [figure, palette] = editorPalette()
% editorPalette Find the live editor figure and its component palette table.

figure = findall(0, "Type", "figure", "Tag", "macd-yamada-editor");
tables = findall(figure, "Type", "uitable");
palette = tables(arrayfun(@(table) any(string(table.ColumnName) == "Component") && ...
    any(string(table.ColumnName) == "Category"), tables));
end

function sendOverlayGesture(overlay, componentId, kind, startPoint, endPoint)
% sendOverlayGesture Dispatch one complete canvas-local editing gesture.
arguments (Input)
    overlay (1, 1) matlab.ui.control.HTML
    componentId (1, 1) string
    kind (1, 1) string
    startPoint (1, 2) double
    endPoint (1, 2) double
end

% Pointer capture keeps the target identity until the model commits on release.
for phase = ["pointerdown", "pointermove", "pointerup"]
    point = startPoint;
    handle = kind;
    if phase ~= "pointerdown"
        point = endPoint;
        handle = "";
    end
    overlay.HTMLEventReceivedFcn(overlay, struct("HTMLEventName", "Pointer", ...
        "HTMLEventData", struct("phase", phase, "x", point(1), "y", point(2), ...
        "componentId", componentId, "handle", handle)));
end
end

function [accepted, filePath] = acceptedOpenPath(filePath)
% acceptedOpenPath Return one accepted source fixture path for lifecycle testing.
arguments (Input)
    filePath (1, 1) string
end
arguments (Output)
    accepted (1, 1) logical
    filePath (1, 1) string
end

accepted = true;
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
