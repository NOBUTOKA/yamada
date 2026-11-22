classdef EditorGridActionTest < matlab.unittest.TestCase
    % EditorGridActionTest Verify Grid Layout overlay edits and action validation.

    methods (Test, TestTags = {'gridOverlay', 'ui'})
        % Guarantee: overlay actions edit only the intended grid or selected child, as one validated change.
        % Failure mode: a nested grid action edits the outer grid, or an overlapping gesture moves an unselected child.
        function gridOverlayUsesOnlyTheNearestNestedGrid(testCase)
            % gridOverlayUsesOnlyTheNearestNestedGrid Keep nested grid contexts separate on canvas.

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
            figure = findall(0, "Type", "figure", "Tag", "yamada-editor");
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
            testCase.verifyTrue(refreshed.geometryAvailable);
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
            % Guarantee: overlay events from obsolete Preview data are rejected.
            % Failure mode: a delayed browser event applies to a rebuilt grid with different tracks.

            app = yamada();
            cleanup = onCleanup(@() deleteIfValid(app));
            drawnow;
            figure = findall(0, "Type", "figure", "Tag", "yamada-editor");
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
            % Guarantee and failure mode: shared with gridOverlayUsesOnlyTheNearestNestedGrid.

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
            % Occupy both destinations before rendering the moving child's overlay.
            registry = yamada.model.ComponentRegistry.createDefault();
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
    end
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
