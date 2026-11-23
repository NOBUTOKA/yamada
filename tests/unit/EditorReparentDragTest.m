classdef (TestTags = {'ui', 'editorShell', 'gridOverlay'}) EditorReparentDragTest < matlab.uitest.TestCase
    % EditorReparentDragTest Verify versioned drop commits, layout boundaries and cancellation.
    %   Real preview geometry supplies destination payloads; opened apps never run.

    properties (Access = private)
        EventNames string = strings(1, 0)
    end

    methods (Test)
        % Guarantee: a drop commits the exact requested placement as one undo step.
        % Failure mode: the drop picks another cell, keeps obsolete grid placement, or needs several Undo steps.
        function absoluteToGridAndBetweenGrids(testCase)
            % absoluteToGridAndBetweenGrids Commit exact destination cells with one history step each.
            [app, figure, button, left, grid] = testCase.fixture();
            cleanup = onCleanup(@() delete(app));
            overlay = findall(figure, "Tag", "yamada-interaction-overlay");
            targets = overlay.Data.reparentTargets;
            target = targets(string({targets.id}) == grid.Id);
            testCase.verifyTrue(target.enabled);
            testCase.verifyTrue(target.grid.geometryAvailable);
            history = app.Document.HistoryIndex;
            testCase.drop(figure, button.Id, grid.Id, [2 2], []);
            testCase.verifyEqual(button.ParentId, grid.Id);
            testCase.verifyEqual(button.getProperty("Layout.Row").LiteralValue, 2);
            testCase.verifyEqual(button.getProperty("Layout.Column").LiteralValue, 2);
            testCase.verifyEqual(app.Document.HistoryIndex, history + 1);
            testCase.select(figure, left.Id);
            tables = findall(figure, "Type", "uitable");
            palette = tables(arrayfun(@(table) any(string(table.ColumnName) == "Category"), tables));
            row = find(string(palette.Data(:, 1)) == "Grid Layout", 1);
            palette.DoubleClickedFcn(palette, struct("InteractionInformation", struct("Row", row)));
            secondId = app.SelectedComponentId;
            testCase.select(figure, button.Id);
            history = app.Document.HistoryIndex;
            testCase.drop(figure, button.Id, secondId, [1 2], []);
            testCase.verifyEqual(button.ParentId, secondId);
            testCase.verifyEqual(button.getProperty("Layout.Column").LiteralValue, 2);
            testCase.verifyEqual(app.Document.HistoryIndex, history + 1);
        end

        function gridToAbsoluteUsesRequestedLocalPosition(testCase)
            % gridToAbsoluteUsesRequestedLocalPosition Restore editable pixels and remove obsolete grid placement.
            [app, figure, button, left, grid] = testCase.fixture();
            cleanup = onCleanup(@() delete(app));
            testCase.drop(figure, button.Id, grid.Id, [1 1], []);
            history = app.Document.HistoryIndex;
            testCase.drop(figure, button.Id, left.Id, [], [45 35 90 28]);
            testCase.verifyEqual(button.ParentId, left.Id);
            testCase.verifyEqual(button.getProperty("Position").LiteralValue, [45 35 90 28]);
            testCase.verifyEmpty(button.getProperty("Layout.Row"));
            testCase.verifyEqual(app.Document.HistoryIndex, history + 1);
            menus = findall(figure, "Type", "uimenu");
            undo = menus(erase(string({menus.Text}), "&") == "Undo");
            undo.MenuSelectedFcn(undo, []);
            testCase.verifyEqual(button.ParentId, grid.Id);
            testCase.verifyEmpty(button.getProperty("Position"));
        end

        function embeddedBrowserDragTransfersBetweenGrids(testCase)
            % embeddedBrowserDragTransfersBetweenGrids Exercise actual iframe DOM handlers and the MATLAB event bridge.
            % Guarantee: real overlay DOM drags reach MATLAB as reparent commits.
            % Failure mode: the iframe event bridge changes and drags no longer commit.
            [app, figure, button, left, rightGrid] = testCase.fixture();
            cleanup = onCleanup(@() delete(app));
            testCase.select(figure, left.Id);
            tables = findall(figure, "Type", "uitable");
            palette = tables(arrayfun(@(table) any(string(table.ColumnName) == "Category"), tables));
            row = find(string(palette.Data(:, 1)) == "Grid Layout", 1);
            palette.DoubleClickedFcn(palette, struct("InteractionInformation", struct("Row", row)));
            leftGridId = app.SelectedComponentId;
            testCase.select(figure, button.Id);
            testCase.drop(figure, button.Id, leftGridId, [1 1], []);
            drawnow;
            overlay = findall(figure, "Tag", "yamada-interaction-overlay");
            data = overlay.Data;
            source = data.dragSource.bounds;
            targets = data.reparentTargets;
            target = targets(string({targets.id}) == rightGrid.Id);
            destination = target.grid.rowTracks(1).bounds;
            column = target.grid.columnTracks(2).bounds;
            startPoint = source(1:2) + source(3:4) / 2;
            stopPoint = [column(1) + column(3) / 2, destination(2) + destination(4) / 2];
            history = app.Document.HistoryIndex;
            originalFcn = overlay.HTMLEventReceivedFcn;
            overlay.HTMLEventReceivedFcn = @(src, event) testCase.capture(originalFcn, src, event);
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            html = string(fileread(fullfile(root, "resources", "EditorInteractionOverlay.html")));
            hook = "htmlComponent.addEventListener('HarnessDrag', function(event) {" + ...
                "var p=event.Data; var r=svg.getBoundingClientRect(); var b=currentData.surfaceBounds;" + ...
                "function point(a){return {x:r.left+a[0]-b[0],y:r.top+b[1]+b[3]-a[1]};}" + ...
                "var a=point(p.startPoint), z=point(p.stopPoint);" + ...
                "var target=document.elementFromPoint(a.x,a.y);" + ...
                "target.dispatchEvent(new PointerEvent('pointerdown',{bubbles:true,cancelable:true,clientX:a.x,clientY:a.y,buttons:1,pointerId:7}));" + ...
                "document.dispatchEvent(new PointerEvent('pointermove',{bubbles:true,clientX:z.x,clientY:z.y,buttons:1,pointerId:7}));" + ...
                "document.dispatchEvent(new PointerEvent('pointerup',{bubbles:true,clientX:z.x,clientY:z.y,buttons:0,pointerId:7}));" + ...
                "});";
            html = replace(html, "function setup(htmlComponent) {", "function setup(htmlComponent) {" + hook);
            marker = "  currentData = htmlComponent.Data || currentData;" + string(sprintf("\r\n")) + "  render();";
            html = replace(html, marker, marker + " htmlComponent.sendEventToMATLAB('HarnessReady',{});");
            filePath = string(tempname) + ".html";
            fileCleanup = onCleanup(@() EditorReparentDragTest.removeFile(filePath));
            file = fopen(filePath, "w", "n", "UTF-8");
            fwrite(file, unicode2native(char(html), "UTF-8"), "uint8");
            fclose(file);
            overlay.HTMLSource = filePath;
            timer = tic;
            while ~any(testCase.EventNames == "HarnessReady") && toc(timer) < 10
                drawnow;
                pause(0.05);
            end
            testCase.assertTrue(any(testCase.EventNames == "HarnessReady"), "The embedded HTML test fixture did not initialize.");
            sendEventToHTMLSource(overlay, "HarnessDrag", struct("startPoint", startPoint, "stopPoint", stopPoint));
            timer = tic;
            while ~any(testCase.EventNames == "Reparent") && toc(timer) < 10
                drawnow;
                pause(0.05);
            end
            testCase.verifyTrue(any(testCase.EventNames == "Reparent"), "The iframe DOM did not emit a reparent command.");
            testCase.verifyEqual(button.ParentId, rightGrid.Id);
            testCase.verifyEqual(button.getProperty("Layout.Row").LiteralValue, 1);
            testCase.verifyEqual(button.getProperty("Layout.Column").LiteralValue, 2);
            testCase.verifyEqual(app.Document.HistoryIndex, history + 1);
        end

        % Guarantee: rejected, cancelled, or stale drops leave the model and history unchanged.
        % Failure mode: a stale drop applies to a rebuilt Preview, or hover planning mutates the document.
        function displayDoesNotPlanDestinationsAndRejectsAtDrop(testCase)
            % displayDoesNotPlanDestinationsAndRejectsAtDrop Defer destination checks without changing rejected edits.
            [app, figure, button, left, grid] = testCase.fixture();
            cleanup = onCleanup(@() delete(app));
            testCase.select(figure, left.Id);
            testCase.select(figure, button.Id);
            drawnow;
            overlay = findall(figure, "Tag", "yamada-interaction-overlay");
            targets = overlay.Data.reparentTargets;
            testCase.verifyFalse(any(string({targets.id}) == button.Id));
            testCase.verifyTrue(targets(string({targets.id}) == grid.Id).enabled);
            grid.IsEditable = false;
            history = app.Document.HistoryIndex;
            testCase.drop(figure, button.Id, grid.Id, [1 1], []);
            testCase.verifyEqual(button.ParentId, left.Id);
            testCase.verifyEqual(app.Document.HistoryIndex, history);
        end

        function occupiedGridDropsClipSpansAndRemainUndoable(testCase)
            % occupiedGridDropsClipSpansAndRemainUndoable Permit overlap and fit a larger span at the chosen cell.
            % Guarantee and failure mode: shared with absoluteToGridAndBetweenGrids.
            [app, figure, button, left, grid] = testCase.fixture();
            cleanup = onCleanup(@() delete(app));
            testCase.select(figure, grid.Id);
            testCase.addFromPalette(figure, "Label");
            occupied = app.Document.getComponent(app.SelectedComponentId);
            testCase.select(figure, left.Id);
            testCase.select(figure, button.Id);
            testCase.drop(figure, button.Id, grid.Id, [1 1], []);
            testCase.verifyEqual(button.ParentId, grid.Id);
            testCase.verifyEqual(occupied.getProperty("Layout.Row").LiteralValue, 1);
            testCase.gridAction(figure, struct("action", "resize-span", "childId", button.Id, ...
                "rowStart", 1, "rowEnd", 2, "columnStart", 1, "columnEnd", 2));
            testCase.select(figure, left.Id);
            testCase.addFromPalette(figure, "Grid Layout");
            source = app.Document.getComponent(app.SelectedComponentId);
            for axis = ["row", "column"]
                testCase.gridAction(figure, struct("action", "delete-track", "axis", axis, ...
                    "index", 2, "mode", "fit", "value", 0));
            end
            testCase.select(figure, left.Id);
            testCase.select(figure, button.Id);
            history = app.Document.HistoryIndex;
            testCase.drop(figure, button.Id, source.Id, [1 1], []);
            testCase.verifyEqual(button.ParentId, source.Id);
            testCase.verifyEqual(button.getProperty("Layout.Row").LiteralValue, 1);
            testCase.verifyEqual(button.getProperty("Layout.Column").LiteralValue, 1);
            testCase.verifyEqual(app.Document.HistoryIndex, history + 1);
            undo = findall(figure, "Tag", "yamada-edit-undo");
            undo.MenuSelectedFcn(undo, []);
            testCase.verifyEqual(button.ParentId, grid.Id);
            testCase.verifyEqual(button.getProperty("Layout.Row").LiteralValue, [1 2]);
            redo = findall(figure, "Tag", "yamada-edit-redo");
            redo.MenuSelectedFcn(redo, []);
            testCase.verifyEqual(button.ParentId, source.Id);
            testCase.verifyEqual(button.getProperty("Layout.Row").LiteralValue, 1);
        end

        function cancelInvalidAndStaleDropsDoNotEdit(testCase)
            % cancelInvalidAndStaleDropsDoNotEdit Keep model and history intact across rejected gestures.
            % Guarantee and failure mode: shared with displayDoesNotPlanDestinationsAndRejectsAtDrop.
            [app, figure, button, left, grid] = testCase.fixture();
            cleanup = onCleanup(@() delete(app));
            overlay = findall(figure, "Tag", "yamada-interaction-overlay");
            position = button.getProperty("Position").LiteralValue;
            history = app.Document.HistoryIndex;
            for phase = ["pointerdown", "pointermove", "pointercancel"]
                point = [5 5];
                if phase ~= "pointerdown", point = [65 65]; end
                overlay.HTMLEventReceivedFcn(overlay, struct("HTMLEventName", "Pointer", ...
                    "HTMLEventData", struct("phase", phase, "componentId", button.Id, "handle", "", "x", point(1), "y", point(2))));
            end
            testCase.verifyEqual(button.getProperty("Position").LiteralValue, position);
            testCase.verifyEqual(app.Document.HistoryIndex, history);
            testCase.drop(figure, button.Id, "", [], []);
            testCase.verifyEqual(button.ParentId, left.Id);
            testCase.verifyEqual(app.Document.HistoryIndex, history);
            oldRevision = overlay.Data.reparentRevision;
            testCase.editPosition(figure, position + [1 0 0 0]);
            menus = findall(figure, "Type", "uimenu");
            undo = menus(erase(string({menus.Text}), "&") == "Undo");
            undo.MenuSelectedFcn(undo, []);
            overlay = findall(figure, "Tag", "yamada-interaction-overlay");
            history = app.Document.HistoryIndex;
            overlay.HTMLEventReceivedFcn(overlay, struct("HTMLEventName", "Reparent", ...
                "HTMLEventData", struct("componentId", button.Id, "parentId", grid.Id, ...
                "modelRevision", oldRevision, "targetCell", [1 1], "targetPosition", [])));
            testCase.verifyEqual(button.ParentId, left.Id);
            testCase.verifyEqual(app.Document.HistoryIndex, history);
        end
    end

    methods (Static, Access = private)
        function removeFile(path)
            % removeFile Delete only the temporary HTML test harness created by this fixture.
            arguments (Input)
                path (1, 1) string
            end
            if isfile(path), delete(path); end
        end
    end

    methods (Access = private)
        function capture(testCase, callback, src, event)
            % capture Record native HTML event delivery while forwarding the real callback.
            arguments (Input)
                testCase (1, 1) EditorReparentDragTest
                callback (1, 1) function_handle
                src
                event
            end
            name = string(event.HTMLEventName);
            if name == "Pointer", name = name + ":" + string(event.HTMLEventData.phase); end
            testCase.EventNames(end + 1) = name;
            callback(src, event);
        end

        function drop(~, figure, id, parentId, cell, position)
            % drop Dispatch the semantic event emitted after a browser drag is completed.
            arguments (Input)
                ~
                figure (1, 1) matlab.ui.Figure
                id (1, 1) string
                parentId (1, 1) string
                cell double
                position double
            end
            overlay = findall(figure, "Tag", "yamada-interaction-overlay");
            overlay.HTMLEventReceivedFcn(overlay, struct("HTMLEventName", "Reparent", ...
                "HTMLEventData", struct("componentId", id, "parentId", parentId, ...
                "modelRevision", overlay.Data.reparentRevision, "targetCell", cell, "targetPosition", position)));
        end

        function select(~, figure, id)
            % select Dispatch a hierarchy selection and refresh its preview editing context.
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

        function editPosition(testCase, figure, position)
            % editPosition Set the selected component rectangle through its Inspector fields.
            arguments (Input)
                testCase (1, 1) EditorReparentDragTest %#ok<INUSA>
                figure (1, 1) matlab.ui.Figure
                position (1, 4) double
            end
            for index = 1:4
                editor = findall(figure, "Tag", "yamada-inspector-position-editor");
                field = editor.UserData.Fields(index);
                if field.Value == position(index), continue, end
                field.Value = position(index);
                field.ValueChangedFcn(field, struct());
            end
        end

        function addFromPalette(testCase, figure, name)
            % addFromPalette Dispatch the normal palette insertion command.
            arguments (Input)
                testCase (1, 1) EditorReparentDragTest %#ok<INUSA>
                figure (1, 1) matlab.ui.Figure
                name (1, 1) string
            end
            tables = findall(figure, "Type", "uitable");
            palette = tables(arrayfun(@(table) any(string(table.ColumnName) == "Category"), tables));
            row = find(string(palette.Data(:, 1)) == name, 1);
            palette.DoubleClickedFcn(palette, struct("InteractionInformation", struct("Row", row)));
        end

        function gridAction(testCase, figure, data)
            % gridAction Apply one grid edit through the current Overlay revision.
            arguments (Input)
                testCase (1, 1) EditorReparentDragTest %#ok<INUSA>
                figure (1, 1) matlab.ui.Figure
                data (1, 1) struct
            end
            overlay = findall(figure, "Tag", "yamada-interaction-overlay");
            data.revision = overlay.Data.gridEditor.revision;
            data.activeGridId = overlay.Data.gridEditor.activeGridId;
            overlay.HTMLEventReceivedFcn(overlay, struct("HTMLEventName", "GridAction", "HTMLEventData", data));
        end

        function [app, figure, button, left, grid] = fixture(testCase)
            % fixture Arrange two separated absolute containers with a grid destination.
            arguments (Input)
                testCase (1, 1) EditorReparentDragTest
            end
            arguments (Output)
                app (1, 1) yamada
                figure (1, 1) matlab.ui.Figure
                button (1, 1) yamada.model.ComponentRecord
                left (1, 1) yamada.model.ComponentRecord
                grid (1, 1) yamada.model.ComponentRecord
            end
            app = yamada();
            figure = findall(0, "Type", "figure", "Tag", "yamada-editor");
            tables = findall(figure, "Type", "uitable");
            palette = tables(arrayfun(@(table) any(string(table.ColumnName) == "Category"), tables));
            panelRow = find(string(palette.Data(:, 1)) == "Panel", 1);
            palette.DoubleClickedFcn(palette, struct("InteractionInformation", struct("Row", panelRow)));
            left = app.Document.getComponent(app.SelectedComponentId);
            testCase.editPosition(figure, [10 10 240 200]);
            row = find(string(palette.Data(:, 1)) == "Button", 1);
            palette.DoubleClickedFcn(palette, struct("InteractionInformation", struct("Row", row)));
            button = app.Document.getComponent(app.SelectedComponentId);
            testCase.select(figure, app.Document.RootComponentId);
            palette.DoubleClickedFcn(palette, struct("InteractionInformation", struct("Row", panelRow)));
            right = app.Document.getComponent(app.SelectedComponentId);
            testCase.editPosition(figure, [300 10 240 200]);
            row = find(string(palette.Data(:, 1)) == "Grid Layout", 1);
            palette.DoubleClickedFcn(palette, struct("InteractionInformation", struct("Row", row)));
            grid = app.Document.getComponent(app.SelectedComponentId);
            drawnow;
            testCase.select(figure, button.Id);
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
