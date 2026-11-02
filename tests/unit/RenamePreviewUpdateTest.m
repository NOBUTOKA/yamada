classdef (TestTags = {'ui', 'preview', 'rename'}) RenamePreviewUpdateTest < matlab.unittest.TestCase
    % RenamePreviewUpdateTest Preserve native geometry across component member renaming.
    %   Real hierarchy edits and history refresh source and names while retaining
    %   controls, measured rectangles, hit regions, and native callback isolation.
    properties (TestParameter)
        % Layout - Absolute, fixed-grid, and fit-grid arrangements under test.
        Layout = {"absolute", "flat", "nested", "flatfit", "nestedfit"}
    end
    methods (Test)
        function hierarchyAndHistoryRetainGeometry(testCase, Layout)
            % hierarchyAndHistoryRetainGeometry Exercise child and container renames through the real editor.
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            path = fullfile(folder.Folder, "RenamePreviewFixture.m");
            source = renameFixture(Layout);
            macd.source.SourceWriter.write(path, source, "CRLF");
            service = macd.ui.DocumentLifecycleService(struct("RequestOpenPathFcn", @() deal(true, path)));
            app = yamada(service); cleanup = onCleanup(@() delete(app));
            figure = findall(0, "Tag", "macd-yamada-editor");
            setappdata(figure, "macdPerformanceMeasurement", true);
            menus = findall(figure, "Type", "uimenu");
            open = menus(erase(string({menus.Text}), "&") == "Open...");
            open.MenuSelectedFcn(open, struct());
            subject = app.Document.getComponentByName("Subject");
            tree = findall(figure, "Type", "uitree");
            selectComponent(tree, subject.Id); settleRenamePreview(figure);
            canvas = findall(figure, "Tag", "macd-preview-canvas");
            native = findall(canvas, "Type", "uibutton");
            rectangle = native.Position;
            renameThroughEditor(testCase, figure, "RenamedSubject");
            testCase.verifyEqual(subject.Name, "RenamedSubject");
            testCase.verifySubstring(app.Document.GeneratedText, "RenamedSubjectButtonPushed");
            for action = ["Undo", "Redo"]
                menus = findall(figure, "Type", "uimenu");
                menu = menus(erase(string({menus.Text}), "&") == action);
                menu.MenuSelectedFcn(menu, struct());
                settleRenamePreview(figure);
                if action == "Undo", expected = "Subject"; else, expected = "RenamedSubject"; end
                testCase.verifyEqual(subject.Name, expected);
                testCase.verifySubstring(app.Document.GeneratedText, "app." + expected);
                canvas = findall(figure, "Tag", "macd-preview-canvas");
                native = findall(canvas, "Type", "uibutton");
                testCase.assertNumElements(native, 1);
                testCase.verifyEqual(native.Position, rectangle);
                testCase.verifyEmpty(native.ButtonPushedFcn);
            end
            % Container names also appear in drop-target labels and the root panel title.
            parent = app.Document.getComponent(subject.ParentId);
            selectComponent(tree, parent.Id); settleRenamePreview(figure);
            renameThroughEditor(testCase, figure, "RenamedContainer");
            overlay = findall(figure, "Tag", "macd-interaction-overlay");
            targets = overlay.Data.reparentTargets;
            match = string({targets.id}) == parent.Id;
            if any(match), testCase.verifyEqual(string(targets(match).name), "RenamedContainer"); end
            if parent.Id == app.Document.RootComponentId
                preview = findall(figure, "Type", "uipanel");
                testCase.verifyTrue(any(string({preview.Title}) == "Safe preview: RenamedContainer"));
            end
            testCase.verifyEqual(app.Document.OriginalText, source);
            canvas = findall(figure, "Tag", "macd-preview-canvas");
            native = findall(canvas, "Type", "uibutton");
            testCase.assertNumElements(native, 1);
            testCase.verifyEqual(native.Position, rectangle);
            % A following visual property edit must still update the current preview.
            selectComponent(tree, subject.Id); settleRenamePreview(figure);
            labels = findall(figure, "Tag", "macd-inspector-property-label");
            label = labels(string({labels.Text}) == "Text");
            editor = findall(label.Parent, "Tag", "macd-inspector-property-editor");
            editor.Value = "After rename";
            editor.ValueChangedFcn(editor, struct());
            settleRenamePreview(figure);
            canvas = findall(figure, "Tag", "macd-preview-canvas");
            native = findall(canvas, "Type", "uibutton");
            testCase.assertNumElements(native, 1);
            testCase.verifyEqual(string(native.Text), "After rename");
            clear cleanup
        end

        function acknowledgementRejectsUnrelatedInputs(testCase)
            % acknowledgementRejectsUnrelatedInputs Refuse visual, structural, source, and catalog changes.
            for change = ["property", "structure", "source", "catalog"]
                registry = macd.model.ComponentRegistry.createDefault();
                document = macd.source.AppSourceParser.parseText(renameFixture("absolute"), registry);
                figure = uifigure(Visible="off"); cleanup = onCleanup(@() delete(figure));
                renderer = macd.ui.PreviewRenderer(registry); renderer.render(document, figure);
                subject = document.getComponentByName("Subject");
                document.renameComponent(subject.Id, "RenamedSubject", registry);
                switch change
                    case "property"
                        subject.setProperty("Text", "Unrelated visual change");
                    case "structure"
                        document.insertComponent(registry, "uilabel", document.RootComponentId);
                    case "source"
                        document.OriginalText = document.OriginalText + newline + "% Changed input";
                    case "catalog"
                        registry.register(registry.getById("uibutton-push"));
                end
                testCase.verifyFalse(renderer.acknowledgeRenameChanges(document), change);
                clear cleanup
            end
        end
    end
end

function selectComponent(tree, id)
% selectComponent Select an existing hierarchy node through its normal callback.
arguments (Input)
    tree (1, 1) matlab.ui.container.Tree
    id (1, 1) string
end
nodes = findall(tree, "Type", "uitreenode");
node = nodes(arrayfun(@(item) isequal(string(item.NodeData), id), nodes));
tree.SelectedNodes = node;
tree.SelectionChangedFcn(tree, struct("SelectedNodes", node));
end

function renameThroughEditor(testCase, figure, name)
% renameThroughEditor Commit an F2 rename through the hierarchy editor.
arguments (Input)
    testCase (1, 1) matlab.unittest.TestCase
    figure (1, 1) matlab.ui.Figure
    name (1, 1) string
end
tree = findall(figure, "Type", "uitree");
figure.CurrentObject = tree.SelectedNodes;
figure.WindowKeyPressFcn(figure, struct("Key", "f2", "Modifier", {{}}));
field = findall(figure, "Tag", "macd-hierarchy-rename");
testCase.assertNumElements(field, 1);
field.Value = name;
field.ValueChangedFcn(field, struct("Value", name));
settleRenamePreview(figure);
end

function settleRenamePreview(figure)
% settleRenamePreview Await native layout and the HTML acknowledgement outside user timing.
arguments (Input)
    figure (1, 1) matlab.ui.Figure
end
started = tic;
while true
    drawnow;
    timers = timerfindall;
    active = any(arrayfun(@(item) isvalid(item) && string(item.Running) == "on", timers));
    overlay = findall(figure, "Tag", "macd-interaction-overlay");
    ready = isappdata(figure, "macdRenderedRevision") && ...
        isequal(getappdata(figure, "macdRenderedRevision"), overlay.Data.gridEditor.revision);
    if ~active && ready, return, end
    assert(toc(started) < 60, "Rename test preview did not settle.");
    pause(0.01);
end
end

function source = renameFixture(layout)
% renameFixture Build inert callback-bearing button source in absolute and grid arrangements.
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
    if startsWith(layout, "nested"), depth = 4; end
    for index = 1:depth
        name = "Grid" + index;
        properties(end + 1) = name + " matlab.ui.container.GridLayout"; %#ok<AGROW>
        track = "'1x'";
        if endsWith(layout, "fit"), track = "'fit'"; end
        body = [body, "app." + name + " = uigridlayout(app." + parent + ",[1 1]);", ...
            "app." + name + ".RowHeight = {" + track + "};", ...
            "app." + name + ".ColumnWidth = {" + track + "};"]; %#ok<AGROW>
        parent = name;
    end
end
body = [body, "app.Subject = uibutton(app." + parent + ");", ...
    "app.Subject.Text = 'Rename subject';", "app.Subject.ButtonPushedFcn = @app.SubjectButtonPushed;"];
if layout == "absolute", body(end + 1) = "app.Subject.Position = [20 20 180 30];"; end
source = strjoin(["classdef RenamePreviewFixture < handle", "properties", properties, "end", ...
    "methods", "function app = RenamePreviewFixture", "createComponents(app);", "end", ...
    "function createComponents(app)", body, "end", ...
    "function SubjectButtonPushed(app,src,event)", "end", "end", "end"], sprintf("\r\n"));
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
