classdef EditorAxesInteractionTest < matlab.uitest.TestCase
    % EditorAxesInteractionTest Verify axes settings through the Inspector and native controls.

    methods (Test, TestTags = {'inspector', 'editorShell', 'ui'})
        function editsNumericRulerTickFormatThroughInspector(testCase)
            % editsNumericRulerTickFormatThroughInspector Apply a format without executing app source.
            app = yamada(Visible="off");
            cleanup = onCleanup(@() deleteIfValid(app));
            [figure,palette] = editorPalette();
            row = find(string(palette.Data(:,1)) == "UI Axes", 1);
            palette.DoubleClickedFcn(palette,struct("InteractionInformation",struct("Row",row)));
            component = app.Document.getComponent(app.SelectedComponentId);
            labels = findall(figure,"Tag","yamada-inspector-property-label");
            label = labels(string({labels.Text}) == "X Tick Label Format");
            testCase.assertNumElements(label,1);
            editor = findall(label.Parent,"Tag","yamada-inspector-property-editor");
            editor.Value = "%.2f";
            editor.ValueChangedFcn(editor,struct());
            testCase.verifyEqual(string(component.getSettings("XAxis.TickLabelFormat").LiteralValue),"%.2f");
            native = findall(figure,"-isa","matlab.ui.control.UIAxes");
            testCase.assertNumElements(native,1);
            testCase.verifyEqual(string(native.XAxis.TickLabelFormat),"%.2f");

            labels = findall(figure,"Tag","yamada-inspector-property-label");
            label = labels(string({labels.Text}) == "X Secondary Label");
            testCase.assertNumElements(label,1);
            editor = findall(label.Parent,"Tag","yamada-inspector-property-editor");
            editor.Value = "Units";
            editor.ValueChangedFcn(editor,struct());
            native = findall(figure,"-isa","matlab.ui.control.UIAxes");
            testCase.verifyEqual(string(native.XAxis.SecondaryLabel.String),"Units");
        end

        function editsColorbarAndAxesColormap(testCase)
            % editsColorbarAndAxesColormap Add and edit a ColorBar through its normal Inspector routes.
            app = yamada();
            cleanup = onCleanup(@() deleteIfValid(app));
            [figure,palette] = editorPalette();
            names = string(palette.Data(:,1));
            testCase.verifyFalse(any(names == "ColorBar"));
            palette.DoubleClickedFcn(palette,struct("InteractionInformation", ...
                struct("Row",find(names == "UI Axes",1))));
            axesRecord = app.Document.getComponent(app.SelectedComponentId);
            tree = findall(figure,"Type","uitree");
            node = tree.SelectedNodes;
            if isMATLABReleaseOlderThan("R2023b")
                overlay = findall(figure,"Tag","yamada-interaction-overlay");
                menu = findall(figure,"Tag","yamada-hierarchy-context");
                overlay.HTMLEventReceivedFcn(overlay,struct("HTMLEventName","ContextMenu", ...
                    "HTMLEventData",struct("componentId",axesRecord.Id, ...
                    "revision",overlay.Data.gridEditor.revision,"x",20,"y",20)));
            else
                menu = tree.ContextMenu;
                menu.ContextMenuOpeningFcn(menu,struct("InteractionInformation",struct("Node",node)));
            end
            add = findall(menu,"Tag","yamada-context-add-colorbar");
            testCase.assertEqual(string(add.Enable),"on");
            add.MenuSelectedFcn(add,struct());
            bar = app.Document.getComponent(app.SelectedComponentId);
            testCase.verifyEqual(bar.ParentId,axesRecord.Id);
            testCase.verifyEqual(string(tree.SelectedNodes.Parent.NodeData),axesRecord.Id);
            cb = findall(figure,"-isa","matlab.graphics.illustration.ColorBar");
            testCase.assertNumElements(cb,1);
            testCase.verifyTrue(cb.Parent == cb.Axes.Parent);

            labels = findall(figure,"Tag","yamada-inspector-property-label");
            row = labels(string({labels.Text}) == "Location");
            location = findall(row.Parent,"Tag","yamada-inspector-property-editor");
            location.Value = "southoutside";
            location.ValueChangedFcn(location,struct());
            cb = findall(figure,"-isa","matlab.graphics.illustration.ColorBar");
            testCase.verifyEqual(string(cb.Location),"southoutside");
            label = labels(string({labels.Text}) == "Label");
            editor = findall(label.Parent,"Tag","yamada-inspector-property-editor");
            editor.Value = {'Temperature'};
            editor.ValueChangedFcn(editor,struct());
            cb = findall(figure,"-isa","matlab.graphics.illustration.ColorBar");
            testCase.verifyEqual(string(cb.Label.String),"Temperature");
            % Use a short viewport so the deep Colormap row requires scrolling.
            window = figure.Position;
            figure.Position = [window(1:3) 420];
            % Establish that Colormap starts below the viewport before exercising the link.
            barNode = tree.SelectedNodes;
            axesNode = barNode.Parent;
            tree.SelectedNodes = axesNode;
            tree.SelectionChangedFcn(tree,struct("SelectedNodes",axesNode));
            picker = findall(figure,"Tag","yamada-colormap-preset");
            host = picker.Parent;
            while ~isa(host,"matlab.ui.container.Panel") || host.Scrollable ~= "on"
                host = host.Parent;
            end
            scroll(host,"top");
            yamada.ui.waitForPreviewLayout(figure, picker);
            viewport = getpixelposition(host,true);
            pickerBounds = getpixelposition(picker,true);
            testCase.assertLessThan(pickerBounds(2),viewport(2), ...
                "Colormap should start outside the viewport.");

            tree.SelectedNodes = barNode;
            tree.SelectionChangedFcn(tree,struct("SelectedNodes",barNode));
            link = findall(figure,"Tag","yamada-edit-axes-colormap");
            testCase.verifyEqual(string(link.Text),"Edit...");
            scroll(host,"bottom");
            drawnow;
            testCase.press(link);
            testCase.verifyEqual(app.SelectedComponentId,axesRecord.Id);
            picker = findall(figure,"Tag","yamada-colormap-preset");
            strip = findall(picker.Parent,"Tag","yamada-colormap-preview");
            testCase.verifyEqual(picker.Layout.Row,1);
            testCase.verifyEqual(strip.Layout.Row,2);
            started = tic;
            while ~(colormapInViewport(host,picker) && colormapInViewport(host,strip)) && toc(started) < 3
                pause(0.05);
            end
            testCase.verifyTrue(colormapInViewport(host,picker));
            testCase.verifyTrue(colormapInViewport(host,strip));
            testCase.choose(picker,"Turbo");
            testCase.assertNotEmpty(axesRecord.getSettings("Colormap"),string(picker.Parent.Tooltip));
            ax = findall(figure,"-isa","matlab.ui.control.UIAxes");
            testCase.assertNumElements(ax,1);
            expectedMap = turbo(size(ax.Colormap,1));
            testCase.verifyLessThanOrEqual(max(abs(ax.Colormap(:)-expectedMap(:))),1e-12, ...
                strjoin(string({app.Document.Diagnostics.Message}),newline));
            text = app.Document.CurrentText;
            registry = yamada.model.ComponentRegistry.createDefault();
            reopened = yamada.source.AppSourceParser.parseText(text,registry);
            restoredBar = reopened.getComponentByName(bar.Name);
            testCase.assertNotEmpty(restoredBar);
            testCase.verifyEqual(reopened.getComponent(restoredBar.ParentId).Name,axesRecord.Name);
            testCase.verifyEqual(string(restoredBar.getProperty("Location").LiteralValue),"southoutside");
            restoredMap = reopened.getComponentByName(axesRecord.Name).getProperty("Colormap").LiteralValue;
            testCase.verifyLessThanOrEqual(max(abs(restoredMap(:)-expectedMap(:))),1e-12);
            app.Document.undo();
            testCase.verifyEmpty(axesRecord.getSettings("Colormap"));
            app.Document.redo();
            testCase.verifyEqual(app.Document.CurrentText,text);
            edit = findall(figure,"Tag","yamada-customize-colormap");
            edit.ButtonPushedFcn(edit,struct());
            dialog = findall(0,"Tag","yamada-custom-colormap-dialog");
            testCase.assertNumElements(dialog,1);
            strip = findall(dialog,"Tag","yamada-colormap-markers");
            testCase.assertEqual(numel(strip.Data.positions),256);
            callback = strip.HTMLEventReceivedFcn;
            callback(strip,struct("HTMLEventName","remove","HTMLEventData",struct("index",2)));
            testCase.verifyNumElements(strip.Data.positions,255);
            preset = findall(dialog,"Tag","yamada-colormap-dialog-preset");
            preset.Value = "Autumn";
            preset.ValueChangedFcn(preset,struct("PreviousValue","Custom"));
            testCase.verifyEqual(strip.Data.positions,[0 100]);
            callback(strip,struct("HTMLEventName","add","HTMLEventData",struct("position",40)));
            callback(strip,struct("HTMLEventName","select","HTMLEventData",struct("index",2)));
            position = findall(dialog,"Tag","yamada-colormap-stop-position");
            testCase.assertEqual(position.Value,40);
            testCase.verifyEqual(strip.Data.map,autumn(256));
            testCase.type(position,50);
            testCase.verifyEqual(strip.Data.positions,[0 50 100]);
            movedMap = interp1([0 50 100],[1 0 0; 1 0.4 0; 1 1 0],linspace(0,100,256).');
            testCase.verifyEqual(strip.Data.map,movedMap,"AbsTol",eps(1));
            preset.Value = "Reset";
            preset.ValueChangedFcn(preset,struct("PreviousValue","Custom"));
            testCase.verifyEqual(strip.Data.map,expectedMap);
            callback(strip,struct("HTMLEventName","move","HTMLEventData", ...
                struct("index",2,"position",strip.Data.positions(2)*0.98,"sequence",1)));
            testCase.verifyEqual(strip.Data.acknowledgedMove,1);
            color = findall(dialog,"Tag","yamada-colormap-stop-color");
            if isa(color,"matlab.ui.control.Button")
                testCase.verifyEqual(color.BackgroundColor,strip.Data.colors(strip.Data.selected,:));
            else
                color.Value = [1 1 1];
                color.ValueChangedFcn(color,struct());
            end
            expectedCustom = strip.Data.map;
            testCase.verifyEqual(app.Document.CurrentText,text);
            apply = findall(dialog,"Tag","yamada-colormap-apply");
            apply.ButtonPushedFcn(apply,struct());
            testCase.verifyFalse(isvalid(dialog));
            custom = axesRecord.getSettings("Colormap").LiteralValue;
            testCase.verifySize(custom,size(expectedMap));
            testCase.verifyEqual(custom,expectedCustom);
            ax = findall(figure,"-isa","matlab.ui.control.UIAxes");
            testCase.verifyEqual(ax.Colormap,custom);
            app.Document.undo();
            testCase.verifyEqual(app.Document.CurrentText,text);
            app.Document.removeSubtree(bar.Id,registry);
            testCase.verifyEmpty(app.Document.getComponent(bar.Id));
            app.Document.undo();
            testCase.verifyEqual(app.Document.getComponent(bar.Id).ParentId,axesRecord.Id);
        end

        function reopensCustomColormapWithOriginalStops(testCase)
            % reopensCustomColormapWithOriginalStops Preserve off-grid corners through source literal round-trip.
            owner = uifigure("Visible","off");
            cleanup = onCleanup(@() deleteIfValid(owner));
            yamada.ui.inspector.CustomColormapDialog.open(owner,autumn(256),@(~) "");
            dialog = findall(0,"Tag","yamada-custom-colormap-dialog");
            strip = findall(dialog,"Tag","yamada-colormap-markers");
            color = findall(dialog,"Tag","yamada-colormap-stop-color");
            callback = strip.HTMLEventReceivedFcn;
            for stop = [40.17 60.13]
                callback(strip,struct("HTMLEventName","add","HTMLEventData",struct("position",stop)));
                if isa(color,"matlab.ui.control.Button")
                    callback(strip,struct("HTMLEventName","move","HTMLEventData", ...
                        struct("index",strip.Data.selected,"position",stop + 3)));
                else
                    color.Value = [0.2 stop/100 0.8];
                    color.ValueChangedFcn(color,struct());
                end
            end
            before = strip.Data;
            [map,safe] = yamada.source.MatlabLiteralParser.parse(yamada.source.LiteralEncoder.encode(before.map));
            testCase.assertTrue(safe);
            delete(dialog);
            yamada.ui.inspector.CustomColormapDialog.open(owner,map,@(~) "");
            dialog = findall(0,"Tag","yamada-custom-colormap-dialog");
            strip = findall(dialog,"Tag","yamada-colormap-markers");
            testCase.verifyEqual(strip.Data.positions,before.positions,"AbsTol",1e-9);
            testCase.verifyEqual(strip.Data.colors,before.colors,"AbsTol",1e-11);
            testCase.verifyEqual(strip.Data.map,map);
        end

        function editsAxesTitleThroughItsInspector(testCase)
            % editsAxesTitleThroughItsInspector Commit body and popup values through native callbacks.
            app = yamada();
            cleanup = onCleanup(@() deleteIfValid(app));
            [figure,palette] = editorPalette();
            index = find(string(palette.Data(:,1)) == "UI Axes",1);
            palette.DoubleClickedFcn(palette,struct("InteractionInformation",struct("Row",index)));
            component = app.Document.getComponent(app.SelectedComponentId);
            labels = findall(figure,"Tag","yamada-inspector-property-label");
            titleLabel = labels(string({labels.Text}) == "Title");
            testCase.assertNumElements(titleLabel,1);
            editor = findall(titleLabel.Parent,"Tag","yamada-inspector-property-editor");
            editor.Value = {'First line';'Second line'};
            editor.ValueChangedFcn(editor,struct());
            testCase.verifyEqual(string(component.getSettings("Title.String").LiteralValue),["First line","Second line"]);
            testCase.verifySubstring(app.Document.CurrentText,"title(app."+component.Name+",");
            handles = findall(figure,"-isa","matlab.ui.control.UIAxes");
            testCase.assertNumElements(handles,1);
            testCase.verifyEqual(reshape(string(handles.Title.String),1,[]),["First line","Second line"]);
            labels = findall(figure,"Tag","yamada-inspector-property-label");
            titleLabel = labels(string({labels.Text}) == "Title");
            settings = findall(titleLabel.Parent,"Tag","yamada-axes-text-settings");
            settings.ButtonPushedFcn(settings,struct());
            dialog = findall(0,"Tag","yamada-axes-text-dialog");
            testCase.assertNumElements(dialog,1);
            field = findall(dialog,"Tag","yamada-axes-detail-FontSize");
            field.Value = 19;
            field.ValueChangedFcn(field,struct());
            testCase.verifyEqual(component.getProperty("Title.FontSize").LiteralValue,19);
            handles = findall(figure,"-isa","matlab.ui.control.UIAxes");
            testCase.verifyEqual(handles.Title.FontSize,19);
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

function visible = colormapInViewport(host, control)
% colormapInViewport Ask the scrollable container whether its descendant is visible.
arguments (Input)
    host (1,1) matlab.ui.container.Panel
    control
end
arguments (Output)
    visible (1,1) logical
end
visible = isInScrollView(host,control);
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
