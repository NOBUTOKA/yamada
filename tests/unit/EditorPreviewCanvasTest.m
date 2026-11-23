classdef EditorPreviewCanvasTest < matlab.unittest.TestCase
    % EditorPreviewCanvasTest Verify Preview tab, scroll, and resize interactions.

    methods (Test, TestTags = {'editorShell', 'previewTab', 'ui'})
        % Guarantee: Preview tab changes update the shown tab and hide tools for hidden content.
        % Failure mode: grid tools for a hidden tab stay active and edit invisible components.
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
            figures = findall(0, "Type", "figure", "Tag", "yamada-editor");
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

    methods (Test, TestTags = {'editorShell', 'ui'})
        % Guarantee: Preview scrolls to all content and root resize is undoable.
        % Failure mode: components outside a shrunken root become unreachable, or resize bypasses history.
        function largeActualSizeFixtureScrollsAndRootResizeIsUndoable(testCase)
            % largeActualSizeFixtureScrollsAndRootResizeIsUndoable Exercise real editor geometry.
            testPath = mfilename("fullpath");
            projectRoot = fileparts(fileparts(fileparts(testPath)));
            fixture = string(fullfile(projectRoot, "tests", "fixtures", ...
                "LargePreviewFixtureApp.m"));
            lifecycle = yamada.ui.DocumentLifecycleService(struct( ...
                "RequestOpenPathFcn", @() acceptedOpenPath(fixture)));
            app = yamada(lifecycle);
            cleanup = onCleanup(@() deleteIfValid(app));
            figure = findall(0, "Type", "figure", "Tag", "yamada-editor");
            menus = findall(figure, "Type", "uimenu");
            openMenu = menus(erase(string({menus.Text}), "&") == "Open...");
            openMenu.MenuSelectedFcn(openMenu, struct());
            drawnow;

            % The oversized canvas keeps source pixels and exposes native scrolling.
            previewPanel = findall(figure, "Type", "uipanel", ...
                "Title", "Safe preview: UIFigure");
            scrollPanel = findall(previewPanel, "Type", "uipanel", ...
                "Tag", "yamada-preview-scroll-host");
            canvas = findall(previewPanel, "Type", "uipanel", ...
                "Tag", "yamada-preview-canvas");
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
                "Tag", "yamada-preview-vertical-scroll-divider");
            horizontalDivider = findall(previewPanel, "Type", "uipanel", ...
                "Tag", "yamada-preview-horizontal-scroll-divider");
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
                "Tag", "yamada-interaction-overlay");
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
                        "Tag", "yamada-root-resize-guide");
                    testCase.assertEqual(numel(guide), 1);
                    testCase.verifyEqual(string(guide.Visible), "on");
                    testCase.verifyEqual(guide.Position(3:4), [1240 930]);
                end
            end
            testCase.verifyEmpty(findall(content, "Type", "uihtml", ...
                "Tag", "yamada-root-resize-guide"));
            root = app.Document.getComponent(rootId);
            testCase.verifyEqual(root.getProperty("Position").LiteralValue, ...
                [100 100 1240 930]);
            [source, diagnostics] = yamada.source.RoundTripGenerator().generate(app.Document);
            testCase.verifyEmpty(diagnostics);
            testCase.verifyTrue(contains(source, ...
                "app.UIFigure.Position = [100 100 1240 930];"));
            reopened = yamada.source.AppSourceParser.parseText(source, ...
                yamada.model.ComponentRegistry.createDefault(), fixture);
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
                "Tag", "yamada-preview-canvas");
            overlay = findall(canvas.Parent.Parent, "Type", "uihtml", ...
                "Tag", "yamada-interaction-overlay");
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
                        "Tag", "yamada-root-resize-guide");
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
                "Tag", "yamada-preview-canvas");
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
            lifecycle = yamada.ui.DocumentLifecycleService(struct( ...
                "RequestOpenPathFcn", @() acceptedOpenPath(fixture)));
            app = yamada(lifecycle);
            cleanup = onCleanup(@() deleteIfValid(app));
            figure = findall(0, "Type", "figure", "Tag", "yamada-editor");
            menus = findall(figure, "Type", "uimenu");
            openMenu = menus(erase(string({menus.Text}), "&") == "Open...");
            openMenu.MenuSelectedFcn(openMenu, struct());
            drawnow;

            % Shrink the actual figure without moving its existing components.
            overlay = findall(figure, "Type", "uihtml", "Tag", "yamada-interaction-overlay");
            sendOverlayGesture(overlay, app.Document.RootComponentId, ...
                "root-ne", [1190 890], [310 230]);
            canvas = findall(figure, "Type", "uipanel", "Tag", "yamada-preview-canvas");
            scrollPanel = findall(figure, "Type", "uipanel", "Tag", "yamada-preview-scroll-host");
            overlay = findall(figure, "Type", "uihtml", "Tag", "yamada-interaction-overlay");
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
                overlay = findall(figure, "Type", "uihtml", "Tag", "yamada-interaction-overlay");
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
            canvas = findall(figure, "Type", "uipanel", "Tag", "yamada-preview-canvas");
            content = canvas.Parent.Parent;
            testCase.verifyEqual(canvas.Position(3:4), [320 240]);
            testCase.verifyEqual(content.Position(3:4), scrollPanel.InnerPosition(3:4));

            % Undo restores the stranded outline and its range; Redo removes it.
            undoMenu = menus(erase(string({menus.Text}), "&") == "Undo");
            redoMenu = menus(erase(string({menus.Text}), "&") == "Redo");
            undoMenu.MenuSelectedFcn(undoMenu, struct());
            overlay = findall(figure, "Type", "uihtml", "Tag", "yamada-interaction-overlay");
            testCase.verifyGreaterThan(overlay.Data.surfaceBounds(4), 886);
            redoMenu.MenuSelectedFcn(redoMenu, struct());
            overlay = findall(figure, "Type", "uihtml", "Tag", "yamada-interaction-overlay");
            testCase.verifyLessThanOrEqual(overlay.Data.surfaceBounds(4), 246);
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
