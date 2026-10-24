classdef (TestTags = {'ui', 'editorShell'}) EditorClipboardTest < matlab.uitest.TestCase
    % EditorClipboardTest Verify the three shared clipboard command entry points.
    %   Real editor fixtures exercise menus, keyboard focus and native context targets.

    properties (Access = private)
        HtmlEvents string = strings(1, 0)
    end

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

        function menusShowShortcutsAndReparentHasNoMenu(testCase)
            % menusShowShortcutsAndReparentHasNoMenu Keep parent changes exclusive to Preview drag.
            [app, figure] = testCase.fixture();
            cleanup = onCleanup(@() delete(app));
            actions = ["Copy", "Cut", "Paste"];
            keys = ["C", "X", "V"];
            for index = 1:numel(actions)
                item = findall(figure, "Tag", "macd-edit-" + lower(actions(index)));
                testCase.verifyEqual(string(item.Text), actions(index));
                testCase.verifyEqual(string(item.Accelerator), keys(index));
            end
            rename = findall(figure, "Tag", "macd-rename-component");
            testCase.verifyEmpty(rename);
            items = findall(figure, "Type", "uimenu");
            labels = string({items.Text});
            for label = ["&Delete" + string(sprintf("\t\t\t")) + "(Del)", "&Undo", "&Redo", "Reload Source" + string(char(9)) + "(F5)"]
                testCase.verifyTrue(any(labels == label));
            end
            undo = findall(figure, "Tag", "macd-edit-undo");
            redo = findall(figure, "Tag", "macd-edit-redo");
            testCase.verifyEqual(string(undo.Accelerator), "Z");
            testCase.verifyEqual(string(redo.Accelerator), "R");
            for key = ["N", "O", "S"]
                testCase.verifyNumElements(findall(figure, "Type", "uimenu", "Accelerator", key), 1);
            end
            testCase.verifyEmpty(findall(figure, "Type", "uimenu", "Accelerator", "A"));
            testCase.verifyEmpty(findall(figure, "Tag", "macd-edit-reparent"));
            testCase.verifyEmpty(findall(figure, "Tag", "macd-context-reparent"));
        end

        function previewContextTargetsAndShortcutsShareCommands(testCase)
            % previewContextTargetsAndShortcutsShareCommands Keep right-click identity and reject stale keys.
            [app, figure, panelId] = testCase.fixture();
            cleanup = onCleanup(@() delete(app));
            selected = app.SelectedComponentId;
            overlay = findall(figure, "Tag", "macd-interaction-overlay");
            request = struct("componentId", panelId, "revision", overlay.Data.gridEditor.revision, "x", 30, "y", 40);
            overlay.HTMLEventReceivedFcn(overlay, struct("HTMLEventName", "ContextMenu", "HTMLEventData", request));
            testCase.verifyEqual(app.SelectedComponentId, selected);
            tree = findall(figure, "Type", "uitree");
            copy = findall(tree.ContextMenu, "Tag", "macd-context-copy");
            testCase.verifyEqual(string(copy.Enable), "on");
            copy.MenuSelectedFcn(copy, []);
            testCase.select(figure, app.Document.RootComponentId);
            paste = findall(figure, "Tag", "macd-edit-paste");
            paste.MenuSelectedFcn(paste, []);
            testCase.verifyEqual(numel(app.Document.getComponent(app.SelectedComponentId).Children), 1);
            history = app.Document.HistoryIndex;
            overlay = findall(figure, "Tag", "macd-interaction-overlay");
            request = struct("componentId", app.SelectedComponentId, "revision", overlay.Data.gridEditor.revision - 1, "action", "Undo");
            overlay.HTMLEventReceivedFcn(overlay, struct("HTMLEventName", "Shortcut", "HTMLEventData", request));
            testCase.verifyEqual(app.Document.HistoryIndex, history);
            request.revision = overlay.Data.gridEditor.revision;
            overlay.HTMLEventReceivedFcn(overlay, struct("HTMLEventName", "Shortcut", "HTMLEventData", request));
            testCase.verifyEqual(app.Document.HistoryIndex, history - 1);
            overlay = findall(figure, "Tag", "macd-interaction-overlay");
            request.componentId = app.SelectedComponentId;
            request.revision = overlay.Data.gridEditor.revision;
            request.action = "Redo";
            overlay.HTMLEventReceivedFcn(overlay, struct("HTMLEventName", "Shortcut", "HTMLEventData", request));
            testCase.verifyEqual(app.Document.HistoryIndex, history);
        end

        function nativeDeleteAfterAddAndPreviewClickDoesNotNeedCurrentObject(testCase)
            % nativeDeleteAfterAddAndPreviewClickDoesNotNeedCurrentObject Match actual palette and empty uihtml hit state.
            [app, figure, panelId] = testCase.fixture();
            cleanup = onCleanup(@() delete(app));
            selected = app.SelectedComponentId;
            tables = findall(figure, "Type", "uitable");
            palette = tables(arrayfun(@(table) any(string(table.ColumnName) == "Category"), tables));
            figure.CurrentObject = palette;
            figure.WindowKeyPressFcn(figure, struct("Key", "delete", "Modifier", {{}}));
            testCase.verifyEmpty(app.Document.getComponent(selected));
            testCase.verifyNotEmpty(app.Document.getComponent(panelId));
            overlay = findall(figure, "Tag", "macd-interaction-overlay");
            figure.CurrentObject = [];
            figure.WindowButtonDownFcn(figure, []);
            request = struct("phase", "pointerdown", "componentId", panelId, "handle", "", "x", 30, "y", 40);
            overlay.HTMLEventReceivedFcn(overlay, struct("HTMLEventName", "Pointer", "HTMLEventData", request));
            request.phase = "pointermove";
            request.x = 70;
            request.y = 80;
            overlay.HTMLEventReceivedFcn(overlay, struct("HTMLEventName", "Pointer", "HTMLEventData", request));
            request.phase = "pointerup";
            overlay.HTMLEventReceivedFcn(overlay, struct("HTMLEventName", "Pointer", "HTMLEventData", request));
            figure.WindowKeyPressFcn(figure, struct("Key", "delete", "Modifier", {{}}));
            testCase.verifyEmpty(app.Document.getComponent(panelId));
        end

        function contextDeleteUsesExplicitTargetAndNativeKeysDoNotDuplicate(testCase)
            % contextDeleteUsesExplicitTargetAndNativeKeysDoNotDuplicate Delete the hit subtree once through shared actions.
            [app, figure, panelId] = testCase.fixture();
            cleanup = onCleanup(@() delete(app));
            testCase.select(figure, app.Document.RootComponentId);
            history = app.Document.HistoryIndex;
            figure.CurrentObject = findall(figure, "Type", "uitree");
            for key = ["c", "x", "v", "z", "r", "n", "o", "s", "a"]
                figure.WindowKeyPressFcn(figure, struct("Key", key, "Modifier", {{'control'}}));
            end
            testCase.verifyEqual(app.Document.HistoryIndex, history);
            overlay = findall(figure, "Tag", "macd-interaction-overlay");
            request = struct("componentId", panelId, "revision", overlay.Data.gridEditor.revision, "x", 30, "y", 40);
            overlay.HTMLEventReceivedFcn(overlay, struct("HTMLEventName", "ContextMenu", "HTMLEventData", request));
            tree = findall(figure, "Type", "uitree");
            item = findall(tree.ContextMenu, "Tag", "macd-context-delete");
            testCase.verifyEqual(string(item.Enable), "on");
            item.MenuSelectedFcn(item, []);
            testCase.verifyEmpty(app.Document.getComponent(panelId));
            testCase.verifyEqual(app.SelectedComponentId, app.Document.RootComponentId);
            testCase.verifyEqual(app.Document.HistoryIndex, history + 1);
            item.MenuSelectedFcn(item, []);
            testCase.verifyEqual(app.Document.HistoryIndex, history + 1);
        end

        function embeddedPreviewCtrlVPastesSubtree(testCase)
            % embeddedPreviewCtrlVPastesSubtree Exercise actual iframe key handlers and the MATLAB bridge.
            [app, figure, panelId] = testCase.fixture();
            cleanup = onCleanup(@() delete(app));
            testCase.select(figure, panelId);
            overlay = findall(figure, "Tag", "macd-interaction-overlay");
            originalFcn = overlay.HTMLEventReceivedFcn;
            overlay.HTMLEventReceivedFcn = @(src, event) testCase.captureHtml(originalFcn, src, event);
            html = string(fileread(overlay.HTMLSource));
            hook = "htmlComponent.addEventListener('HarnessKey', function(event) {" + ...
                "var target=document; if(event.Data.editing){target=document.createElement('input');document.body.appendChild(target);}" + ...
                "target.dispatchEvent(new KeyboardEvent('keydown',{key:event.Data.key,ctrlKey:!event.Data.unmodified,bubbles:true,cancelable:true}));" + ...
                "if(event.Data.editing)target.remove(); htmlComponent.sendEventToMATLAB('HarnessDone',{});});";
            html = replace(html, "function setup(htmlComponent) {", "function setup(htmlComponent) {" + hook);
            marker = "  currentData = htmlComponent.Data || currentData;" + string(sprintf("\r\n")) + "  render();";
            html = replace(html, marker, marker + " htmlComponent.sendEventToMATLAB('HarnessReady', {});");
            filePath = string(tempname) + ".html";
            fileCleanup = onCleanup(@() EditorClipboardTest.removeHarness(filePath));
            file = fopen(filePath, "w", "n", "UTF-8");
            fwrite(file, unicode2native(char(html), "UTF-8"), "uint8");
            fclose(file);
            overlay.HTMLSource = filePath;
            testCase.waitForHtml("HarnessReady");
            sendEventToHTMLSource(overlay, "HarnessKey", struct("key", "c", "editing", false, "unmodified", false));
            testCase.waitForHtml("HarnessDone");
            testCase.verifyEqual(sum(testCase.HtmlEvents == "Clipboard"), 1);
            testCase.select(figure, app.Document.RootComponentId);
            drawnow;
            pause(0.1);
            history = app.Document.HistoryIndex;
            testCase.HtmlEvents = strings(1, 0);
            sendEventToHTMLSource(overlay, "HarnessKey", struct("key", "v", "editing", true, "unmodified", false));
            testCase.waitForHtml("HarnessDone");
            testCase.verifyEqual(app.Document.HistoryIndex, history);
            testCase.HtmlEvents = strings(1, 0);
            sendEventToHTMLSource(overlay, "HarnessKey", struct("key", "v", "editing", false, "unmodified", false));
            testCase.waitForHtml("HarnessDone");
            testCase.verifyEqual(sum(testCase.HtmlEvents == "Clipboard"), 1);
            testCase.verifyEqual(app.Document.HistoryIndex, history + 1);
            pasted = app.Document.getComponent(app.SelectedComponentId);
            testCase.verifyEqual(pasted.ParentId, app.Document.RootComponentId);
            testCase.verifyEqual(numel(pasted.Children), 1);
            pastedId = pasted.Id;
            overlay = findall(figure, "Tag", "macd-interaction-overlay");
            originalFcn = overlay.HTMLEventReceivedFcn;
            overlay.HTMLEventReceivedFcn = @(src, event) testCase.captureHtml(originalFcn, src, event);
            testCase.HtmlEvents = strings(1, 0);
            overlay.HTMLSource = filePath;
            testCase.waitForHtml("HarnessReady");
            sendEventToHTMLSource(overlay, "HarnessKey", struct("key", "Delete", "editing", false, "unmodified", true));
            testCase.waitForHtml("HarnessDone");
            testCase.verifyEqual(sum(testCase.HtmlEvents == "DeleteSelection"), 1);
            testCase.verifyEmpty(app.Document.getComponent(pastedId));
            testCase.verifyEqual(app.Document.HistoryIndex, history + 2);
        end

        function previewClipboardEventChecksSelectionAndRevision(testCase)
            % previewClipboardEventChecksSelectionAndRevision Reject stale Preview commands and paste once.
            [app, figure, panelId] = testCase.fixture();
            cleanup = onCleanup(@() delete(app));
            testCase.select(figure, panelId);
            overlay = findall(figure, "Tag", "macd-interaction-overlay");
            data = struct("action", "Copy", "componentId", panelId, "revision", overlay.Data.gridEditor.revision);
            overlay.HTMLEventReceivedFcn(overlay, struct("HTMLEventName", "Clipboard", "HTMLEventData", data));
            testCase.select(figure, app.Document.RootComponentId);
            overlay = findall(figure, "Tag", "macd-interaction-overlay");
            history = app.Document.HistoryIndex;
            data.action = "Paste";
            overlay.HTMLEventReceivedFcn(overlay, struct("HTMLEventName", "Clipboard", "HTMLEventData", data));
            testCase.verifyEqual(app.Document.HistoryIndex, history);
            data.componentId = app.SelectedComponentId;
            data.revision = overlay.Data.gridEditor.revision;
            overlay.HTMLEventReceivedFcn(overlay, struct("HTMLEventName", "Clipboard", "HTMLEventData", data));
            testCase.verifyEqual(app.Document.HistoryIndex, history + 1);
            testCase.verifyEqual(numel(app.Document.getComponent(app.SelectedComponentId).Children), 1);
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

    methods (Static, Access = private)
        function removeHarness(path)
            % removeHarness Remove only the temporary iframe test source.
            arguments (Input)
                path (1, 1) string
            end
            if isfile(path), delete(path); end
        end
    end

    methods (Access = private)
        function captureHtml(testCase, callback, src, event)
            % captureHtml Record bridge messages and forward the real editor handler.
            arguments (Input)
                testCase (1, 1) EditorClipboardTest
                callback (1, 1) function_handle
                src
                event
            end
            testCase.HtmlEvents(end + 1) = string(event.HTMLEventName);
            callback(src, event);
        end

        function waitForHtml(testCase, name)
            % waitForHtml Allow the asynchronous iframe bridge to deliver a bounded event.
            arguments (Input)
                testCase (1, 1) EditorClipboardTest
                name (1, 1) string
            end
            timer = tic;
            while ~any(testCase.HtmlEvents == name) && toc(timer) < 10
                drawnow;
                pause(0.05);
            end
            testCase.assertTrue(any(testCase.HtmlEvents == name), "Missing iframe event: " + name);
        end

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
            undo = menus(string({menus.Tag}) == "macd-edit-undo");
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
                item = findall(figure, "Type", "uimenu", "Accelerator", upper(keys(actions == action)));
                testCase.assertEqual(string(item.Enable), "on");
                item.MenuSelectedFcn(item, []);
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
