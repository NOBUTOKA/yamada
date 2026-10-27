classdef (TestTags = {'ui', 'preview', 'callback'}) CallbackPreviewUpdateTest < matlab.unittest.TestCase
    % CallbackPreviewUpdateTest Keep callback source transactions outside native geometry updates.
    %   Real Manage Callbacks actions preserve handles, bounds, source safety,
    %   and history across free, fixed-grid, and nested-grid fixtures.
    methods (Test)
        function managerActionsAndHistoryRetainAllPreviewGeometry(testCase)
            % managerActionsAndHistoryRetainAllPreviewGeometry Profile real Add/Delete and callback Undo/Redo.
            for layout = ["absolute", "flat", "nested"]
                folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
                path = fullfile(folder.Folder, "CallbackPreviewFixture.m");
                source = callbackFixture(layout);
                macd.source.SourceWriter.write(path, source, "CRLF");
                service = macd.ui.DocumentLifecycleService(struct("RequestOpenPathFcn", @() deal(true, path)));
                app = yamada(service); cleanup = onCleanup(@() delete(app));
                figure = findall(0, "Tag", "macd-yamada-editor");
                menus = findall(figure, "Type", "uimenu");
                open = menus(erase(string({menus.Text}), "&") == "Open...");
                open.MenuSelectedFcn(open, struct());
                subject = app.Document.getComponentByName("Subject");
                tree = findall(figure, "Type", "uitree");
                nodes = findall(tree, "Type", "uitreenode");
                node = nodes(arrayfun(@(item) isequal(string(item.NodeData), subject.Id), nodes));
                tree.SelectedNodes = node;
                tree.SelectionChangedFcn(tree, struct("SelectedNodes", node));
                % Finish unrelated initial layout before profiling a nonvisual source operation.
                drawnow; pause(0.5); drawnow;
                overlay = findall(figure, "Tag", "macd-interaction-overlay");
                canvas = findall(figure, "Tag", "macd-preview-canvas");
                native = findall(canvas, "Type", "uibutton");
                original = native; rectangle = native.Position; geometry = overlay.Data.geometryRevision;
                context = findall(figure, "Tag", "macd-hierarchy-context");
                context.ContextMenuOpeningFcn(context, struct("InteractionInformation", struct("Node", node)));
                manage = findall(context, "Tag", "macd-manage-callbacks");
                manage.MenuSelectedFcn(manage, struct());
                dialog = findall(0, "Tag", "macd-callback-manager");
                for action = ["add", "delete"]
                    button = findall(dialog, "Tag", "macd-callback-" + action, "UserData", "ButtonPushedFcn");
                    testCase.assertEqual(numel(button), 1);
                    testCase.assertEqual(string(button.Enable), "on");
                    profile clear; profile on; stop = onCleanup(@() profile("off"));
                    button.ButtonPushedFcn(button, struct());
                    drawnow; profile off; info = profile("info"); clear stop
                    verifyNoGeometry(testCase, info, layout + "." + action);
                    testCase.verifyTrue(isvalid(original));
                    testCase.verifyEqual(native.Position, rectangle);
                    testCase.verifyEqual(overlay.Data.geometryRevision, geometry);
                    testCase.verifyEmpty(native.ButtonPushedFcn);
                    if action == "add"
                        testCase.verifySubstring(app.Document.GeneratedText, "SubjectButtonPushed");
                    end
                end
                for action = ["Undo", "Redo"]
                    menus = findall(figure, "Type", "uimenu");
                    menu = menus(erase(string({menus.Text}), "&") == action);
                    profile clear; profile on; stop = onCleanup(@() profile("off"));
                    menu.MenuSelectedFcn(menu, struct());
                    drawnow; profile off; info = profile("info"); clear stop
                    verifyNoGeometry(testCase, info, layout + "." + action);
                    testCase.verifyEqual(overlay.Data.geometryRevision, geometry);
                    testCase.verifyTrue(isvalid(original));
                    if action == "Undo"
                        testCase.verifySubstring(app.Document.GeneratedText, "SubjectButtonPushed");
                    else
                        testCase.verifyFalse(contains(app.Document.GeneratedText, "SubjectButtonPushed"));
                    end
                end
                testCase.verifyEqual(app.Document.OriginalText, source);
                testCase.verifyEqual(app.Document.HistoryIndex, 2);
                clear cleanup
            end
        end

        function callbackAcknowledgementCannotMaskVisualChanges(testCase)
            % callbackAcknowledgementCannotMaskVisualChanges Carry callback input versions without hiding property edits.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.source.AppSourceParser.parseText(callbackFixture("absolute"), registry);
            figure = uifigure(Visible="off"); cleanup = onCleanup(@() delete(figure));
            renderer = macd.ui.PreviewRenderer(registry); handles = renderer.render(document, figure);
            subject = document.getComponentByName("Subject");
            document.applyCallbackAction(subject.Id, "ButtonPushedFcn", "Add", registry);
            testCase.verifyTrue(renderer.acknowledgeCallbackChanges(document));
            subject.setProperty("Text", "After callback");
            testCase.verifyFalse(renderer.acknowledgeCallbackChanges(document));
            testCase.verifyTrue(renderer.synchronize(document, handles, macd.ui.RefreshRequest("properties", subject.Id, "Text")));
            testCase.verifyEqual(string(handles(char(subject.Id)).Text), "After callback");
            clear cleanup
        end
    end
end

function verifyNoGeometry(testCase, info, context)
% verifyNoGeometry Reject reconstruction, rectangle capture, boundary solving, and region rendering.
arguments (Input)
    testCase (1, 1) matlab.unittest.TestCase
    info (1, 1) struct
    context (1, 1) string
end
functions = info.FunctionTable;
names = string({functions.FunctionName});
measured = contains(names, ["PreviewRenderer.render", "PreviewRenderer.rebuildScope", ...
    "PreviewUpdatePlanner.plan", "GridLayoutOverlayDataBuilder.build", ...
    "GridLayoutOverlayDataBuilder.nativeInputs", "GridLayoutOverlayDataBuilder.trackBounds", ...
    "yamada.capturePreviewGeometry", "yamada.updateInteractionOverlay"]);
testCase.verifyEqual(sum([functions(measured).NumCalls]), 0, context);
end

function source = callbackFixture(layout)
% callbackFixture Build inert button fixtures without executing an application class.
arguments (Input)
    layout (1, 1) string
end
arguments (Output)
    source (1, 1) string
end
properties = ["UIFigure matlab.ui.Figure", "Subject matlab.ui.control.Button"];
body = ["app.UIFigure = uifigure(Visible='off');", "app.UIFigure.Position = [100 100 800 650];"];
parent = "UIFigure";
if layout ~= "absolute"
    depth = 1;
    if layout == "nested", depth = 4; end
    for index = 1:depth
        name = "Grid" + index;
        properties(end + 1) = name + " matlab.ui.container.GridLayout"; %#ok<AGROW>
        body = [body, "app." + name + " = uigridlayout(app." + parent + ",[1 1]);", ...
            "app." + name + ".RowHeight = {'1x'};", "app." + name + ".ColumnWidth = {'1x'};"]; %#ok<AGROW>
        parent = name;
    end
end
body = [body, "app.Subject = uibutton(app." + parent + ");", "app.Subject.Text = 'Callback subject';"];
if layout == "absolute", body(end + 1) = "app.Subject.Position = [20 20 180 30];"; end
source = strjoin(["classdef CallbackPreviewFixture < handle", "properties", properties, "end", ...
    "methods", "function app = CallbackPreviewFixture", "createComponents(app);", "end", ...
    "function createComponents(app)", body, "end", "end", "end"], sprintf("\r\n"));
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
