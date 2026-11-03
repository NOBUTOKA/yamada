classdef (TestTags = {'preview', 'inspector', 'ui'}) PerformanceViewTest < matlab.unittest.TestCase
    % PerformanceViewTest Verify view reuse without stale bindings or skipped model changes.
    %   Tests assert behavior and handle identity instead of machine-dependent timings.
    methods (Test)
        function multilineTextCommitsPlainScalarAndMultipleLines(testCase)
            % multilineTextCommitsPlainScalarAndMultipleLines Preserve char/string text through real Inspector commits.
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            fixture = string(fullfile(folder.Folder, "TextInputFixture.m"));
            forms = ["'Initial'", macd.source.LiteralEncoder.encode("Initial")];
            registry = macd.model.ComponentRegistry.createDefault();
            for index = 1:numel(forms)
                source = strjoin(["classdef TextInputFixture < handle", "properties", ...
                    "UIFigure matlab.ui.Figure", "Label matlab.ui.control.Label", "end", "methods", ...
                    "function app = TextInputFixture", "createComponents(app);", "end", ...
                    "function createComponents(app)", "app.UIFigure = uifigure(Visible='off');", ...
                    "app.Label = uilabel(app.UIFigure);", "app.Label.Text = " + forms(index) + ";", ...
                    "end", "end", "end"], sprintf('\r\n'));
                macd.source.SourceWriter.write(fixture, source, "CRLF");
                lifecycle = macd.ui.DocumentLifecycleService(struct("RequestOpenPathFcn", @() deal(true, fixture)));
                app = yamada(lifecycle);
                cleanup = onCleanup(@() delete(app));
                figure = findall(0, "Tag", "macd-yamada-editor");
                menus = findall(figure, "Type", "uimenu");
                open = menus(erase(string({menus.Text}), "&") == "Open...");
                open.MenuSelectedFcn(open, struct());
                label = app.Document.getComponentByName("Label");
                trees = findall(figure, "Type", "uitree");
                tree = trees(arrayfun(@(item) ~isempty(item.SelectionChangedFcn), trees));
                nodes = findall(tree, "Type", "uitreenode");
                node = nodes(arrayfun(@(item) string(item.NodeData) == label.Id, nodes));
                tree.SelectedNodes = node;
                tree.SelectionChangedFcn(tree, struct("SelectedNodes", node));

                % Plain text, including quote characters, is data rather than source syntax.
                labels = findall(figure, "Tag", "macd-inspector-property-label");
                row = labels(string({labels.Text}) == "Text");
                editor = findall(row.Parent, "Tag", "macd-inspector-property-editor");
                draft = "literal(1) + 'quoted'";
                editor.Value = {char(draft)};
                editor.ValueChangedFcn(editor, struct());
                expected = draft;
                if index == 1, expected = char(draft); end
                testCase.assertEqual(label.getProperty("Text").LiteralValue, expected);
                testCase.verifyEqual(app.Document.HistoryIndex, 1);
                emitted = macd.source.RoundTripGenerator(registry).generate(app.Document);
                parsed = macd.source.AppSourceParser.parseText(emitted, registry);
                testCase.verifyEqual(parsed.getComponentByName("Label").getProperty("Text").LiteralValue, expected);
                app.Document.undo();
                testCase.verifyEqual(string(label.getProperty("Text").LiteralValue), "Initial");
                app.Document.redo();
                testCase.verifyEqual(label.getProperty("Text").LiteralValue, expected);

                % Existing multiline cell values remain supported after a scalar edit.
                labels = findall(figure, "Tag", "macd-inspector-property-label");
                row = labels(string({labels.Text}) == "Text");
                editor = findall(row.Parent, "Tag", "macd-inspector-property-editor");
                lines = cellstr(["First line"; "Second line"]);
                editor.Value = lines;
                editor.ValueChangedFcn(editor, struct());
                testCase.verifyEqual(label.getProperty("Text").LiteralValue, reshape(lines, 1, []));
                testCase.verifyEqual(app.Document.HistoryIndex, 2);
                clear cleanup
            end
        end

        function gridCommandPublishesOneSettledSnapshotWithoutPolling(testCase)
            % gridCommandPublishesOneSettledSnapshotWithoutPolling Share native geometry and publish one atomic result.
            app = yamada();
            cleanup = onCleanup(@() delete(app));
            figure = findall(0, "Tag", "macd-yamada-editor");
            palette = findall(figure, "Type", "uitable");
            palette = palette(arrayfun(@(item) ~isempty(item.DoubleClickedFcn), palette));
            row = find(string(palette.Data(:, 1)) == "Grid Layout", 1);
            palette.DoubleClickedFcn(palette, struct("InteractionInformation", struct("Row", row)));
            gridId = app.SelectedComponentId;
            overlay = findall(figure, "Tag", "macd-interaction-overlay");
            data = overlay.Data.gridEditor;
            overlay.HTMLEventReceivedFcn(overlay, struct("HTMLEventName", "GridAction", ...
                "HTMLEventData", struct("action", "set-track", "revision", data.revision, ...
                "activeGridId", gridId, "axis", "row", "index", 1, "mode", "fixed", "value", 40)));
            testCase.verifyTrue(overlay.Data.gridEditor.geometryAvailable);
            testCase.verifyEqual(app.Document.getComponent(gridId).getProperty("RowHeight").LiteralValue{1}, 40);
        end

        function obsoletePointerCannotSelectFromReplacedGeometry(testCase)
            % obsoletePointerCannotSelectFromReplacedGeometry Reject delayed coordinates after native reconstruction.
            app = yamada();
            cleanup = onCleanup(@() delete(app));
            figure = findall(0, "Tag", "macd-yamada-editor");
            overlay = findall(figure, "Tag", "macd-interaction-overlay");
            old = overlay.Data.nativeGeometryRevision;
            palette = findall(figure, "Type", "uitable");
            palette = palette(arrayfun(@(item) ~isempty(item.DoubleClickedFcn), palette));
            row = find(string(palette.Data(:, 1)) == "Grid Layout", 1);
            palette.DoubleClickedFcn(palette, struct("InteractionInformation", struct("Row", row)));
            selected = app.SelectedComponentId;
            overlay = findall(figure, "Tag", "macd-interaction-overlay");
            data = struct("phase", "pointerdown", "x", 1, "y", 1, ...
                "componentId", app.Document.RootComponentId, "handle", "root-e", ...
                "nativeGeometryRevision", old);
            overlay.HTMLEventReceivedFcn(overlay, struct("HTMLEventName", "Pointer", "HTMLEventData", data));
            testCase.verifyEqual(app.SelectedComponentId, selected);
            data.nativeGeometryRevision = overlay.Data.nativeGeometryRevision;
            overlay.HTMLEventReceivedFcn(overlay, struct("HTMLEventName", "Pointer", "HTMLEventData", data));
            testCase.verifyEqual(app.SelectedComponentId, app.Document.RootComponentId);
        end

        function preservedNavigationHandlesNonvisualTreeNodes(testCase)
            % preservedNavigationHandlesNonvisualTreeNodes Exclude records without pixel bounds from geometry.
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            fixture = string(fullfile(root, "tests", "fixtures", "NavigationDataApp.m"));
            lifecycle = macd.ui.DocumentLifecycleService(struct("RequestOpenPathFcn", @() deal(true, fixture)));
            app = yamada(lifecycle);
            cleanup = onCleanup(@() delete(app));
            figure = findall(0, "Tag", "macd-yamada-editor");
            menus = findall(figure, "Type", "uimenu");
            open = menus(erase(string({menus.Text}), "&") == "Open...");
            open.MenuSelectedFcn(open, struct());
            testCase.verifyEqual(app.Document.ClassName, "NavigationDataApp");
            nodes = app.Document.Components([app.Document.Components.Factory] == "uitreenode");
            testCase.assertNotEmpty(nodes);
            trees = findall(figure, "Type", "uitree");
            tree = trees(arrayfun(@(item) ~isempty(item.SelectionChangedFcn), trees));
            testCase.assertEqual(numel(tree), 1);
            nativeNodes = findall(tree, "Type", "uitreenode");
            selected = nativeNodes(arrayfun(@(item) string(item.NodeData) == nodes(1).Id, nativeNodes));
            tree.SelectedNodes = selected;
            tree.SelectionChangedFcn(tree, struct("SelectedNodes", selected));
            overlay = findall(figure, "Tag", "macd-interaction-overlay");
            testCase.verifyTrue(isvalid(overlay));
            testCase.verifyEqual(app.SelectedComponentId, nodes(1).Id);
        end

        function fitGridGrowthMatchesIndependentFullRender(testCase)
            % fitGridGrowthMatchesIndependentFullRender Let native fit tracks settle after an incremental setter.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("FitFixture", registry);
            grid = document.insertComponent(registry, "uigridlayout", document.RootComponentId);
            grid.setProperty("RowHeight", {"fit", "1x"});
            grid.setProperty("ColumnWidth", {"1x"});
            label = document.insertComponent(registry, "uilabel", grid.Id);
            label.setProperty("Text", "Fit growth");
            label.setProperty("Layout.Row", 1);
            label.setProperty("Layout.Column", 1);
            figure = uifigure("Visible", "on", "Position", [100 100 900 500]);
            cleanup = onCleanup(@() delete(figure));
            first = uipanel(figure, "Position", [1 1 440 480]);
            second = uipanel(figure, "Position", [450 1 440 480]);
            renderer = macd.ui.PreviewRenderer(registry);
            handles = renderer.render(document, first);
            waitForFitLayout(handles(char(label.Id)));
            previous = handles(char(label.Id)).Position;
            label.setProperty("FontSize", 32);
            [applied, diagnostics, geometry] = renderer.synchronize(document, handles, ...
                macd.ui.RefreshRequest("properties", label.Id, "FontSize"));
            testCase.verifyTrue(applied);
            testCase.verifyTrue(geometry);
            testCase.verifyEmpty(diagnostics);
            reference = macd.ui.PreviewRenderer(registry).render(document, second);
            waitForFitLayout(handles(char(label.Id)));
            waitForFitLayout(reference(char(label.Id)));
            testCase.verifyGreaterThan(handles(char(label.Id)).Position(4), previous(4));
            testCase.verifyEqual(handles(char(label.Id)).Position, reference(char(label.Id)).Position, "AbsTol", 1);
        end

        function auditedLabelChangeRetainsPreviewAndMatchesRebuild(testCase)
            % auditedLabelChangeRetainsPreviewAndMatchesRebuild Compare incremental and full rendering.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("IncrementalFixture", registry);
            label = document.insertComponent(registry, "uilabel", document.RootComponentId);
            label.setProperty("FontSize", 13);
            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() delete(figure));
            first = uipanel(figure, "Position", [1 1 300 300]);
            second = uipanel(figure, "Position", [301 1 300 300]);
            renderer = macd.ui.PreviewRenderer(registry);
            [handles, diagnostics] = renderer.render(document, first);
            testCase.verifyEmpty(diagnostics);
            document.setPropertyBatch(label.Id, macd.model.PropertyTransaction.singleChange("FontSize", 21), registry);
            [applied, diagnostics, geometry] = renderer.synchronize(document, handles, ...
                macd.ui.RefreshRequest("properties", label.Id, "FontSize"));
            testCase.verifyTrue(applied);
            testCase.verifyEmpty(diagnostics);
            testCase.verifyFalse(geometry);
            [reference, diagnostics] = macd.ui.PreviewRenderer(registry).render(document, second);
            testCase.verifyEmpty(diagnostics);
            testCase.verifyEqual(handles(char(label.Id)).FontSize, reference(char(label.Id)).FontSize);
        end

        function unrelatedDirectChangeForcesConservativeRebuild(testCase)
            % unrelatedDirectChangeForcesConservativeRebuild Do not miss mutations outside the request.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("IncrementalFixture", registry);
            label = document.insertComponent(registry, "uilabel", document.RootComponentId);
            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() delete(figure));
            renderer = macd.ui.PreviewRenderer(registry);
            handles = renderer.render(document, figure);
            document.getComponent(document.RootComponentId).setProperty("Color", [0.2 0.3 0.4]);
            label.setProperty("FontSize", 21);
            applied = renderer.synchronize(document, handles, macd.ui.RefreshRequest("properties", label.Id, "FontSize"));
            testCase.verifyFalse(applied);
            testCase.verifyEqual(renderer.statistics().fallbackReason, "unrelated-inputs");
        end

        function rebindRetainsEditorAndRejectsQueuedEvent(testCase)
            % rebindRetainsEditorAndRejectsQueuedEvent Keep the old callback tied to its old target.
            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() delete(figure));
            setappdata(figure, "commits", strings(1, 0));
            definition = macd.model.PropertyDefinition("FontSize", 13, true, true, struct("editor", "number"));
            grid = uigridlayout(figure, [1 1]);
            row = macd.ui.inspector.InspectorPropertyRow(grid, 1, "first", definition, ...
                @(id, path, value) recordCommit(figure, id, path, value));
            editor = findall(figure, "Tag", "macd-inspector-property-editor");
            old = editor.ValueChangedFcn;
            row.rebind("second");
            editor.Value = 19;
            old(editor, struct());
            testCase.verifyEmpty(getappdata(figure, "commits"));
            editor.ValueChangedFcn(editor, struct());
            testCase.verifyEqual(getappdata(figure, "commits"), "second:FontSize:19");
            testCase.verifyTrue(isvalid(editor));
        end
    end
end

function waitForFitLayout(label)
% waitForFitLayout Wait for realized public geometry instead of the initial factory rectangle.
arguments (Input)
    label (1, 1) matlab.ui.control.Label
end
previous = zeros(1, 4);
stable = 0;
for index = 1:60
    drawnow;
    pause(0.05);
    current = double(label.Position);
    if current(3) > 200 && isequal(current, previous)
        stable = stable + 1;
    else
        stable = 0;
    end
    if stable >= 4, return, end
    previous = current;
end
error("macd:PerformanceViewTest:UnstableLayout", "Fit geometry did not settle.");
end

function message = recordCommit(figure, id, path, value)
% recordCommit Retain callback ownership for the row-binding regression.
arguments (Input)
    figure (1, 1) matlab.ui.Figure
    id (1, 1) string
    path (1, 1) string
    value (1, 1) double
end
arguments (Output)
    message (1, 1) string
end
setappdata(figure, "commits", [getappdata(figure, "commits"), id + ":" + path + ":" + value]);
message = "";
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
