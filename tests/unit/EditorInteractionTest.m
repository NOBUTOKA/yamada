classdef EditorInteractionTest < matlab.unittest.TestCase
    % EditorInteractionTest Verify the editor interaction surfaces.
    %   These tests construct the real programmatic editor, allow its UI to lay
    %   out, inspect public callback wiring through UI handles, and always delete
    %   the editor fixture. They do not execute any opened application source.

    methods (Test)
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
            testCase.verifyEqual(numel(toolbars.Children), 2);
            testCase.verifyTrue(all(arrayfun(@(tool) ...
                ~isempty(tool.ClickedCallback), toolbars.Children)));
            overlays = findall(0, "Type", "uihtml");
            testCase.verifyEqual(numel(overlays), 1);
            testCase.verifyNotEmpty(overlays.HTMLEventReceivedFcn);
            clear cleanup
        end

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

        function inspectorProbesRuntimeDefaultsWithoutEntries(testCase)
            % inspectorProbesRuntimeDefaults Show runtime defaults without materializing properties.

            app = yamada();
            cleanup = onCleanup(@() deleteIfValid(app));
            drawnow;
            figures = findall(0, "Type", "figure", "Name", "Yet Another MATLAB App Designer Alternative");
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

        function fontStyleButtonCommitsCatalogChoice(testCase)
            % fontStyleButtonCommitsCatalogChoice Commit a typographic style toggle through the live inspector.

            % Insert a button through the palette so its Font Style row is reconstructed.
            app = yamada();
            cleanup = onCleanup(@() deleteIfValid(app));
            drawnow;
            figure = findall(0, "Type", "figure", "Name", "Yet Another MATLAB App Designer Alternative");
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

        function itemSelectionInspectorCommitsAnItemsChoice(testCase)
            % itemSelectionInspectorCommitsAnItemsChoice Route a native selection through the live inspector.

            app = yamada();
            cleanup = onCleanup(@() deleteIfValid(app));
            figure = findall(0, "Type", "figure", "Name", "Yet Another MATLAB App Designer Alternative");
            figure.Visible = "off";
            tables = findall(figure, "Type", "uitable");
            palette = tables(arrayfun(@(table) any(string(table.ColumnName) == "Component") && ...
                any(string(table.ColumnName) == "Category"), tables));
            row = find(string(palette.Data(:, 1)) == "Drop Down", 1);
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
            figure = findall(0, "Type", "figure", "Name", "Yet Another MATLAB App Designer Alternative");
            figure.Visible = "off";
            tables = findall(figure, "Type", "uitable");
            palette = tables(arrayfun(@(table) any(string(table.ColumnName) == "Component") && ...
                any(string(table.ColumnName) == "Category"), tables));
            row = find(string(palette.Data(:, 1)) == "Drop Down", 1);
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
            figure = findall(0, "Type", "figure", "Name", "Yet Another MATLAB App Designer Alternative");
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
            testCase.verifyEqual(string(editor.Value), string(lines));
            clear cleanup
        end

        function datePickerValueCommitPreservesTypedDate(testCase)
            % datePickerValueCommitPreservesTypedDate Keep native datetime data out of text parsing.

            % Insert a Date Picker, then invoke the native date editor callback.
            app = yamada();
            cleanup = onCleanup(@() deleteIfValid(app));
            figure = findall(0, "Type", "figure", "Name", "Yet Another MATLAB App Designer Alternative");
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
            figure = findall(0, "Type", "figure", "Name", "Yet Another MATLAB App Designer Alternative");
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
            figure = findall(0, "Type", "figure", "Name", "Yet Another MATLAB App Designer Alternative");
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
            figure = findall(0, "Type", "figure", "Name", "Yet Another MATLAB App Designer Alternative");
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
            figure = findall(0, "Type", "figure", "Name", "Yet Another MATLAB App Designer Alternative");
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
            columnTable.Data{1, 2} = 'fit';
            columnTable.Data{1, 3} = true;
            columnTable.Data{1, 4} = true;
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

        function tabSelectorEventChangesPreviewTab(testCase)
            % tabSelectorEventChangesPreviewTab Verify the overlay tab selector route.

            % Add a tab group and two tabs through the same palette callback path users use.
            app = yamada();
            cleanup = onCleanup(@() deleteIfValid(app));
            drawnow;
            figures = findall(0, "Type", "figure", ...
                "Name", "Yet Another MATLAB App Designer Alternative");
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
