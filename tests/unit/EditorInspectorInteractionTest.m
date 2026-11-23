classdef EditorInspectorInteractionTest < matlab.unittest.TestCase
    % EditorInspectorInteractionTest Verify Inspector defaults and incremental edits.

    methods (Test, TestTags = {'inspector', 'ui'})
        % Guarantee: the Inspector shows effective values and defaults without writing source.
        % Failure mode: showing a clamped value or runtime default adds or rewrites a source setting.
        function inspectorShowsEffectiveValueWithoutOverwritingSource(testCase)
            % inspectorShowsEffectiveValueWithoutOverwritingSource Keep clamped display and fixed-slot edits consistent.
            source = strjoin(["classdef StateUIApp < handle", "properties", ...
                "UIFigure matlab.ui.Figure", "Slider matlab.ui.control.Slider", "end", "methods", ...
                "function app = StateUIApp", "createComponents(app);", "end", ...
                "function createComponents(app)", "app.UIFigure = uifigure(Visible='off');", ...
                "app.Slider = uislider(app.UIFigure);", "app.Slider.Value = 20;", ...
                "app.Slider.Limits = [50 100];", "end", "end", "end"], sprintf("\r\n"));
            fixture = string(tempname()) + ".m";
            yamada.source.SourceWriter.write(fixture, source);
            testCase.addTeardown(@() delete(fixture));
            lifecycle = yamada.ui.DocumentLifecycleService(struct( ...
                "RequestOpenPathFcn", @() acceptedOpenPath(fixture)));
            app = yamada(lifecycle, Visible="off");
            cleanup = onCleanup(@() deleteIfValid(app));
            figure = findall(0, "Type", "figure", "Tag", "yamada-editor");
            menus = findall(figure, "Type", "uimenu");
            openMenu = menus(erase(string({menus.Text}), "&") == "Open...");
            openMenu.MenuSelectedFcn(openMenu, struct());
            testCase.verifyEqual(string(figure.Visible), "off");
            document = app.Document;
            component = document.getComponentByName("Slider");
            tree = findall(figure, "Type", "uitree");
            node = tree.Children(1).Children(string({tree.Children(1).Children.NodeData}) == component.Id);
            tree.SelectedNodes = node;
            tree.SelectionChangedFcn(tree, struct("SelectedNodes", node));
            drawnow;
            labels = findall(figure, "Type", "uilabel", "Tag", "yamada-inspector-property-label");
            label = labels(string({labels.Text}) == "Value");
            editor = findall(label.Parent, "Tag", "yamada-inspector-property-editor");
            testCase.assertEqual(numel(editor), 1);
            testCase.verifyEqual(editor.Value, 50);
            testCase.verifyEqual(component.getProperty("Value").LiteralValue, 20);
            testCase.verifyFalse(document.IsDirty);
            editor.Value = 30;
            editor.ValueChangedFcn(editor, struct());
            testCase.verifyEqual(document.HistoryIndex, 0);
            testCase.verifyEqual(component.getProperty("Value").LiteralValue, 20);
            testCase.verifySubstring(editor.Tooltip, "Initialization changes requested Value");
            editor.Value = 75;
            editor.ValueChangedFcn(editor, struct());
            testCase.verifyEqual(document.HistoryIndex, 1);
            testCase.verifyEqual(component.getSettings("Value").LiteralValue, 75);
            testCase.verifyEqual(component.getProperty("Value").LiteralValue, 75);
            menus = findall(figure, "Type", "uimenu");
            undo = menus(erase(string({menus.Text}), "&") == "Undo");
            undo.MenuSelectedFcn(undo, struct());
            labels = findall(figure, "Type", "uilabel", "Tag", "yamada-inspector-property-label");
            label = labels(string({labels.Text}) == "Value");
            editor = findall(label.Parent, "Tag", "yamada-inspector-property-editor");
            testCase.verifyEqual(editor.Value, 50);
            testCase.verifyFalse(document.IsDirty);
            clear cleanup
        end

        function inspectorProbesRuntimeDefaultsWithoutEntries(testCase)
            % inspectorProbesRuntimeDefaultsWithoutEntries Show runtime defaults without materializing properties.

            app = yamada();
            cleanup = onCleanup(@() deleteIfValid(app));
            drawnow;
            figures = findall(0, "Type", "figure", "Tag", "yamada-editor");
            tables = findall(figures, "Type", "uitable");
            palette = tables(arrayfun(@(table) any(string(table.ColumnName) == "Component") && ...
                any(string(table.ColumnName) == "Category"), tables));
            row = find(string(palette.Data(:, 1)) == "List Box", 1);
            palette.DoubleClickedFcn(palette, struct("InteractionInformation", struct("Row", row)));
            drawnow;
            checks = findall(0, "Type", "uicheckbox", "Tag", "yamada-inspector-property-editor");
            testCase.verifyNotEmpty(checks);
            testCase.verifyTrue(any([checks.Value]));
            selected = app.Document.getComponent(app.SelectedComponentId);
            testCase.verifyEmpty(selected.getProperty("Visible"));
            clear cleanup
        end
    end

    methods (Test, TestTags = {'inspector', 'ui'})
        % Guarantee: repeated numeric edits through real callbacks reuse Preview correctly and record history.
        % Failure mode: reuse keeps stale grid measurements, or repeated edits skip history steps.
        function numericGridEditsReuseMeasuredTracksWithoutChangingGeometry(testCase)
            % numericGridEditsReuseMeasuredTracksWithoutChangingGeometry Reuse grid payloads only with matching native inputs.
            source = strjoin(["classdef GridCacheUI < handle", "properties", ...
                "UIFigure matlab.ui.Figure", "Grid matlab.ui.container.GridLayout", ...
                "Field matlab.ui.control.NumericEditField", "end", "methods", ...
                "function app = GridCacheUI", "createComponents(app);", "end", ...
                "function createComponents(app)", "app.UIFigure = uifigure(Visible='off');", ...
                "app.Grid = uigridlayout(app.UIFigure,[2 1]);", ...
                "app.Grid.RowHeight = {'fit','1x'};", "app.Grid.ColumnWidth = {'1x'};", ...
                "app.Field = uieditfield(app.Grid,'numeric');", "app.Field.Value = 1;", ...
                "app.Field.Layout.Row = 1;", "app.Field.Layout.Column = 1;", ...
                "end", "end", "end"], sprintf("\r\n"));
            fixture = string(tempname()) + ".m";
            yamada.source.SourceWriter.write(fixture, source);
            testCase.addTeardown(@() delete(fixture));
            lifecycle = yamada.ui.DocumentLifecycleService(struct("RequestOpenPathFcn", @() acceptedOpenPath(fixture)));
            app = yamada(lifecycle);
            cleanup = onCleanup(@() deleteIfValid(app));
            figure = findall(0, "Tag", "yamada-editor");
            menus = findall(figure, "Type", "uimenu");
            open = menus(erase(string({menus.Text}), "&") == "Open...");
            open.MenuSelectedFcn(open, struct());
            field = app.Document.getComponentByName("Field");
            grid = app.Document.getComponentByName("Grid");
            tree = findall(figure, "Type", "uitree");
            nodes = findall(tree, "Type", "uitreenode");
            node = nodes(arrayfun(@(item) string(item.NodeData) == field.Id, nodes));
            tree.SelectedNodes = node;
            tree.SelectionChangedFcn(tree, struct("SelectedNodes", node));
            drawnow;
            for value = [2 3]
                labels = findall(figure, "Tag", "yamada-inspector-property-label");
                label = labels(string({labels.Text}) == "Value");
                editor = findall(label.Parent, "Tag", "yamada-inspector-property-editor");
                testCase.assertEqual(numel(editor), 1);
                editor.Value = value;
                editor.ValueChangedFcn(editor, struct());
                drawnow;
                canvas = findall(figure, "Tag", "yamada-preview-canvas");
                yamada.ui.waitForPreviewLayout(figure, canvas);
                drawnow;
            end

            % The retained payload must equal an independent measurement of the current native controls.
            canvas = findall(figure, "Tag", "yamada-preview-canvas");
            controls = findall(canvas);
            nativeGrid = controls(arrayfun(@(item) isa(item, "matlab.ui.container.GridLayout"), controls));
            nativeField = controls(arrayfun(@(item) isa(item, "matlab.ui.control.NumericEditField"), controls));
            handles = dictionary(string([]), gobjects(0));
            handles(grid.Id) = nativeGrid;
            handles(field.Id) = nativeField;
            overlay = findall(figure, "Tag", "yamada-interaction-overlay");
            actual = overlay.Data.gridEditor;
            expected = yamada.ui.GridLayoutOverlayDataBuilder().build(app.Document, handles, canvas, ...
                grid.Id, field.Id, actual.revision, yamada.model.ComponentRegistry.createDefault());
            testCase.verifyTrue(actual.geometryAvailable);
            testCase.verifyEqual(actual, expected);
            testCase.verifyEqual(nativeField.Value, 3);
            testCase.verifyEqual(app.Document.HistoryIndex, 2);
            testCase.verifyEqual(app.Document.OriginalText, source);
            clear cleanup
        end

        function repeatedNumericInspectorEditsRetainPreviewAndHistory(testCase)
            % repeatedNumericInspectorEditsRetainPreviewAndHistory Reuse validation through real numeric callbacks.
            source = strjoin(["classdef LocalValidationUI < handle", "properties", ...
                "UIFigure matlab.ui.Figure", "StatusLabel matlab.ui.control.Label", "end", "methods", ...
                "function app = LocalValidationUI", "createComponents(app);", "end", ...
                "function createComponents(app)", "app.UIFigure = uifigure(Visible='off');", ...
                "app.StatusLabel = uilabel(app.UIFigure, Text=""Local validation label"");", ...
                "end", "end", "end"], sprintf("\r\n"));
            fixture = string(tempname()) + ".m";
            yamada.source.SourceWriter.write(fixture, source);
            testCase.addTeardown(@() delete(fixture));
            lifecycle = yamada.ui.DocumentLifecycleService(struct( ...
                "RequestOpenPathFcn", @() acceptedOpenPath(fixture)));
            app = yamada(lifecycle, Visible="off");
            cleanup = onCleanup(@() deleteIfValid(app));
            figure = findall(0, "Type", "figure", "Tag", "yamada-editor");
            menus = findall(figure, "Type", "uimenu");
            open = menus(erase(string({menus.Text}), "&") == "Open...");
            open.MenuSelectedFcn(open, struct());
            component = app.Document.getComponentByName("StatusLabel");
            tree = findall(figure, "Type", "uitree");
            node = tree.Children(1).Children(string({tree.Children(1).Children.NodeData}) == component.Id);
            tree.SelectedNodes = node;
            tree.SelectionChangedFcn(tree, struct("SelectedNodes", node));
            drawnow;

            % The first edit establishes source placement; the second retains real Preview behavior.
            for value = [23 31]
                labels = findall(figure, "Tag", "yamada-inspector-property-label");
                label = labels(string({labels.Text}) == "FontSize");
                editor = findall(label.Parent, "Tag", "yamada-inspector-property-editor");
                testCase.assertEqual(numel(editor), 1);
                if isa(editor, "matlab.ui.control.EditField")
                    editor.Value = char(string(value));
                else
                    editor.Value = value;
                end
                editor.ValueChangedFcn(editor, struct());
                drawnow;
                native = findall(figure, "Type", "uilabel", "Text", "Local validation label");
                testCase.assertEqual(numel(native), 1);
                testCase.verifyEqual(native.FontSize, value);
                testCase.verifyEqual(component.getProperty("FontSize").LiteralValue, value);
            end
            testCase.verifyEqual(app.Document.OriginalText, source);
            testCase.verifyEqual(app.Document.HistoryIndex, 2);

            % History callbacks must invalidate the proof and restore native values atomically.
            menus = findall(figure, "Type", "uimenu");
            for action = ["Undo", "Redo"]
                item = menus(erase(string({menus.Text}), "&") == action);
                item.MenuSelectedFcn(item, struct());
                drawnow;
                expected = 23;
                if action == "Redo", expected = 31; end
                native = findall(figure, "Type", "uilabel", "Text", "Local validation label");
                testCase.assertEqual(numel(native), 1);
                testCase.verifyEqual(native.FontSize, expected);
                testCase.verifyEqual(component.getProperty("FontSize").LiteralValue, expected);
            end
            clear cleanup
        end

    end

    methods (Test, TestTags = {'inspector', 'fast', 'ui'})
        % Guarantee: each live Inspector editor commits the value its native control represents.
        % Failure mode: a native control's event is mapped to the wrong value, such as a label instead of ItemsData or one line of a text area.
        function fontStyleButtonCommitsCatalogChoice(testCase)
            % fontStyleButtonCommitsCatalogChoice Commit a typographic style toggle through the live inspector.

            % Insert a button through the palette so its Font Style row is reconstructed.
            app = yamada();
            cleanup = onCleanup(@() deleteIfValid(app));
            drawnow;
            figure = findall(0, "Type", "figure", "Tag", "yamada-editor");
            tables = findall(figure, "Type", "uitable");
            palette = tables(arrayfun(@(table) any(string(table.ColumnName) == "Component") && ...
                any(string(table.ColumnName) == "Category"), tables));
            row = find(string(palette.Data(:, 1)) == "Button", 1);
            palette.DoubleClickedFcn(palette, struct("InteractionInformation", struct("Row", row)));
            drawnow;

            % Toggle the compact bold state button using the real batch callback binding.
            labels = findall(figure, "Type", "uilabel", "Tag", "yamada-inspector-property-label");
            label = labels(string({labels.Text}) == "Font Style");
            testCase.verifyEqual(numel(label), 1);
            controls = findall(figure, "Tag", "yamada-inspector-font-weight-button");
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

            app = yamada(Visible="off");
            cleanup = onCleanup(@() deleteIfValid(app));
            figure = findall(0, "Type", "figure", "Tag", "yamada-editor");
            tables = findall(figure, "Type", "uitable");
            palette = tables(arrayfun(@(table) any(string(table.ColumnName) == "Component") && ...
                any(string(table.ColumnName) == "Category"), tables));
            row = find(string(palette.Data(:, 1)) == "Drop-down", 1);
            palette.DoubleClickedFcn(palette, struct( ...
                "InteractionInformation", struct("Row", row)));
            drawnow;

            labels = findall(figure, "Type", "uilabel", ...
                "Tag", "yamada-inspector-property-label");
            label = labels(string({labels.Text}) == "Value");
            editor = findall(label.Parent, "Tag", "yamada-inspector-item-selection-editor");
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

            app = yamada(Visible="off");
            cleanup = onCleanup(@() deleteIfValid(app));
            figure = findall(0, "Type", "figure", "Tag", "yamada-editor");
            tables = findall(figure, "Type", "uitable");
            palette = tables(arrayfun(@(table) any(string(table.ColumnName) == "Component") && ...
                any(string(table.ColumnName) == "Category"), tables));
            row = find(string(palette.Data(:, 1)) == "Drop-down", 1);
            palette.DoubleClickedFcn(palette, struct( ...
                "InteractionInformation", struct("Row", row)));
            drawnow;

            editItems = findall(figure, "Tag", "yamada-inspector-items-editor");
            editItems.ButtonPushedFcn(editItems, struct());
            dialog = findall(0, "Type", "figure", "Tag", "yamada-items-editor-dialog");
            table = findall(dialog, "Type", "uitable", "Tag", "yamada-items-editor-table");
            data = table.Data;
            data(:, 2) = string((10:10:(10 * size(data, 1)))');
            table.Data = data;
            apply = findall(dialog, "Tag", "yamada-items-editor-apply");
            apply.ButtonPushedFcn(apply, struct());
            drawnow;

            component = app.Document.getComponent(app.SelectedComponentId);
            testCase.verifyEqual(component.getProperty("Value").LiteralValue, 10);
            labels = findall(figure, "Type", "uilabel", "Tag", "yamada-inspector-property-label");
            valueLabel = labels(string({labels.Text}) == "Value");
            editor = findall(valueLabel.Parent, "Tag", "yamada-inspector-item-selection-editor");
            editor.Value = char(editor.Items{2});
            editor.ValueChangedFcn(editor, struct());
            drawnow;
            testCase.verifyEqual(component.getProperty("Value").LiteralValue, 20);
            clear cleanup
        end
        function textAreaValueCommitPreservesAllLines(testCase)
            % textAreaValueCommitPreservesAllLines Keep one multiline Value as one transaction change.

            % Insert a Text Area, then invoke its native multiline inspector callback.
            app = yamada(Visible="off");
            cleanup = onCleanup(@() deleteIfValid(app));
            figure = findall(0, "Type", "figure", "Tag", "yamada-editor");
            tables = findall(figure, "Type", "uitable");
            palette = tables(arrayfun(@(table) any(string(table.ColumnName) == "Component") && ...
                any(string(table.ColumnName) == "Category"), tables));
            row = find(string(palette.Data(:, 1)) == "Text Area", 1);
            palette.DoubleClickedFcn(palette, struct( ...
                "InteractionInformation", struct("Row", row)));
            drawnow;

            % Resolve the Value row without confusing it with the Tooltip text area.
            labels = findall(figure, "Type", "uilabel", ...
                "Tag", "yamada-inspector-property-label");
            label = labels(string({labels.Text}) == "Value");
            editor = findall(label.Parent, "Type", "uitextarea", ...
                "Tag", "yamada-inspector-property-editor");
            lines = {'First'; 'Second'; 'Third'};
            editor.Value = lines;
            editor.ValueChangedFcn(editor, struct());
            drawnow;

            component = app.Document.getComponent(app.SelectedComponentId);
            entry = component.getProperty("Value");
            testCase.verifyEqual(entry.LiteralValue, {'First', 'Second', 'Third'});
            labels = findall(figure, "Type", "uilabel", ...
                "Tag", "yamada-inspector-property-label");
            label = labels(string({labels.Text}) == "Value");
            editor = findall(label.Parent, "Type", "uitextarea", ...
                "Tag", "yamada-inspector-property-editor");
            testCase.verifyEqual(string(editor.Value), string(lines));
            clear cleanup
        end
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
