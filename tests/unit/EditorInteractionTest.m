classdef EditorInteractionTest < matlab.unittest.TestCase
    % EditorInteractionTest Verify the Phase 5 editor interaction surfaces.
    %   These tests construct the real programmatic editor, allow its UI to lay
    %   out, inspect public callback wiring through UI handles, and always delete
    %   the editor fixture. They do not execute any opened application source.

    methods (Test)
        function editorBuildsPhase5Surfaces(testCase)
            % editorBuildsPhase5Surfaces Verify palette, right pane, and toolbar.

            % Construct the editor through its ordinary application entry point.
            app = MatlabAppClassDesigner();
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
            app = MatlabAppClassDesigner();
            cleanup = onCleanup(@() deleteIfValid(app));
            drawnow;
            trees = findall(0, "Type", "uitree");
            testCase.verifyEqual(numel(trees), 1);
            trees.SelectedNodes = trees.Children(1);
            drawnow;

            % The callback must leave the root selected and show its properties.
            testCase.verifyEqual(app.SelectedComponentId, app.Document.RootComponentId);
            tables = findall(0, "Type", "uitable");
            inspector = tables(arrayfun(@(table) any(string(table.ColumnName) == ...
                "Property"), tables));
            testCase.verifyEqual(numel(inspector), 1);
            testCase.verifyGreaterThan(size(inspector.Data, 1), 0);
            clear cleanup
        end

        function editMenuExposesPhase5Commands(testCase)
            % editMenuExposesPhase5Commands Verify Delete, Undo, and Redo menu items.

            % Inspect the actual menu hierarchy after editor construction.
            app = MatlabAppClassDesigner();
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
            app = MatlabAppClassDesigner();
            cleanup = onCleanup(@() deleteIfValid(app));
            drawnow;
            figures = findall(0, "Type", "figure", ...
                "Name", "MATLAB App Class Designer");
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
MatlabAppClassDesigner - Editor interaction tests for the Phase 5 canvas shell.
Copyright (C) 2026 MatlabAppClassDesigner contributors

This file is part of MatlabAppClassDesigner.

MatlabAppClassDesigner is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

MatlabAppClassDesigner is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with MatlabAppClassDesigner. If not, see <https://www.gnu.org/licenses/>.
%}
