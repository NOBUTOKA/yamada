classdef EditorGridSelectionTest < matlab.unittest.TestCase
    % EditorGridSelectionTest Verify selection across nested Grid Layout overlays.

    methods (Test, TestTags = {'gridOverlay', 'ui'})
        function gridOverlaySelectsAnImmediateChildWithoutEditingTheDocument(testCase)
            % gridOverlaySelectsAnImmediateChildWithoutEditingTheDocument Route one canvas selection safely.

            app = yamada();
            cleanup = onCleanup(@() deleteIfValid(app));
            drawnow;
            figure = findall(0, "Type", "figure", "Tag", "yamada-editor");
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
            figure = findall(0, "Type", "figure", "Tag", "yamada-editor");
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
            figure = findall(0, "Type", "figure", "Tag", "yamada-editor");
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
            lifecycle = yamada.ui.DocumentLifecycleService(struct( ...
                "RequestOpenPathFcn", @() acceptedOpenPath(fixture)));
            app = yamada(lifecycle);
            cleanup = onCleanup(@() deleteIfValid(app));
            figure = findall(0, "Type", "figure", "Tag", "yamada-editor");
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
            overlays = findall(figure, "Type", "uihtml", "Tag", "yamada-interaction-overlay");
            parentData = overlays.Data.gridPlacement;
            action = struct("action", "resize-span", "revision", parentData.revision, ...
                "activeGridId", outerGridId, "childId", innerGridId, ...
                "rowStart", 1, "rowEnd", 2, "columnStart", 2, "columnEnd", 2);
            overlays.HTMLEventReceivedFcn(overlays, struct( ...
                "HTMLEventName", "GridAction", "HTMLEventData", action));
            testCase.verifyEqual(inner.getProperty("Layout.Row").LiteralValue, [1 2]);
            testCase.verifyEqual(app.Document.HistoryIndex, historyIndex + 2);
            overlays = findall(figure, "Type", "uihtml", "Tag", "yamada-interaction-overlay");
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

            fixture = yamadaFixturePath("ControlGalleryApp.m");
            lifecycle = yamada.ui.DocumentLifecycleService(struct( ...
                "RequestOpenPathFcn", @() acceptedOpenPath(fixture)));
            app = yamada(lifecycle);
            cleanup = onCleanup(@() deleteIfValid(app));
            figure = findall(0, "Type", "figure", "Tag", "yamada-editor");
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
                "Tag", "yamada-preview-canvas");
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
            % Incremental placement may return before native fit tracks have expanded.
            started = tic;
            refreshed = overlays.Data.gridEditor;
            while toc(started) < 3 && (~refreshed.geometryAvailable || ...
                    refreshed.rowTracks(1).bounds(4) <= 0 || refreshed.columnTracks(1).bounds(3) <= 0)
                pause(0.01); drawnow;
                refreshed = overlays.Data.gridEditor;
            end
            fprintf("COLLAPSED_MOVE_SETTLE Seconds=%.3f Available=%d\n", toc(started), refreshed.geometryAvailable);
            child = app.Document.getComponent(childId);
            testCase.verifyEqual(child.getProperty("Layout.Row").LiteralValue, 1);
            testCase.verifyEqual(child.getProperty("Layout.Column").LiteralValue, 1);
            testCase.verifyGreaterThan(refreshed.rowTracks(1).bounds(4), 0);
            testCase.verifyGreaterThan(refreshed.columnTracks(1).bounds(3), 0);
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
