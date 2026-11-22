classdef EditorAxesInteractionTest < matlab.uitest.TestCase
    % EditorAxesInteractionTest Verify axes settings through the Inspector and native controls.

    methods (Test, TestTags = {'inspector', 'editorShell', 'ui'})
        function editsGeographicLimitsTogetherThroughInspector(testCase)
            % editsGeographicLimitsTogetherThroughInspector Save one paired edit and refresh the map preview.
            path = string(tempname()) + ".m";
            testCase.addTeardown(@() delete(path));
            [~,name] = fileparts(path);
            source = strjoin(["classdef " + name + " < handle", "properties", ...
                "UIFigure matlab.ui.Figure", "Map matlab.graphics.axis.GeographicAxes", ...
                "end", "methods", "function app = " + name, ...
                "app.UIFigure = uifigure(Visible='off');", ...
                "app.Map = geoaxes(app.UIFigure, Basemap='none', Position=[20 20 400 300]);", ...
                "end", "end", "end"],newline);
            yamada.source.SourceWriter.write(path,source);
            lifecycle = yamada.ui.DocumentLifecycleService(struct("RequestOpenPathFcn",@() deal(true,path)));
            app = yamada(lifecycle,Visible="off");
            cleanup = onCleanup(@() deleteIfValid(app));
            figure = findall(0,"Type","figure","Tag","yamada-editor");
            menus = findall(figure,"Type","uimenu");
            command = menus(erase(string({menus.Text}),"&") == "Open...");
            command.MenuSelectedFcn(command,struct());
            component = app.Document.getComponentByName("Map");
            tree = findall(figure,"Type","uitree");
            node = tree.Children(1).Children(string({tree.Children(1).Children.NodeData}) == component.Id);
            tree.SelectedNodes = node;
            tree.SelectionChangedFcn(tree,struct("SelectedNodes",node));
            button = findall(figure,"Tag","yamada-edit-geographic-limits");
            testCase.assertNumElements(button,1);
            testCase.verifyEqual(string(button.Enable),"on");
            button.ButtonPushedFcn(button,struct());
            dialog = findall(0,"Tag","yamada-geographic-limits-dialog");
            testCase.addTeardown(@() deleteIfValid(dialog));
            latitude = findall(dialog,"Tag","yamada-geographic-latitude");
            longitude = findall(dialog,"Tag","yamada-geographic-longitude");
            latitude.Value = "[-15 15]";
            longitude.Value = "[170 190]";
            apply = findall(dialog,"Tag","yamada-geographic-limits-apply");
            apply.ButtonPushedFcn(apply,struct());
            testCase.verifyFalse(isvalid(dialog));
            testCase.verifySubstring(app.Document.CurrentText,"geolimits(app.Map, [-15 15], [170 190]);");
            [~,shown] = geolimits(findall(figure,"-isa","matlab.graphics.axis.GeographicAxes"));
            testCase.verifyLessThanOrEqual(shown(1),170.001);
            testCase.verifyGreaterThanOrEqual(shown(2),189.999);
        end

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
            testCase.verifyEqual(component.getSettings("Title.FontSize").LiteralValue,19);
            testCase.verifySubstring(app.Document.CurrentText,"""FontSize"", 19)");
            handles = findall(figure,"-isa","matlab.ui.control.UIAxes");
            testCase.verifyEqual(handles.Title.FontSize,19);
        end

        function editsNonPixelAxesGeometryInTheirOwnUnits(testCase)
            % editsNonPixelAxesGeometryInTheirOwnUnits Convert overlay gestures and keep Units before Position.
            fixture = string(fullfile(fileparts(fileparts(mfilename("fullpath"))), ...
                "fixtures","AxesExplorerApp.m"));
            lifecycle = yamada.ui.DocumentLifecycleService(struct( ...
                "RequestOpenPathFcn",@() acceptedOpenPath(fixture)));
            app = yamada(lifecycle);
            cleanup = onCleanup(@() deleteIfValid(app));
            figure = editorPalette();
            open = findall(figure,"Type","uimenu","Text","&Open...");
            open.MenuSelectedFcn(open,[]);
            drawnow;
            overlay = findall(figure,"Type","uihtml","Tag","yamada-interaction-overlay");
            axesId = app.Document.getComponentByName("StandardAxes").Id;

            % A 760-by-440 parent maps 38 and 22 pixels to 0.05 normalized units.
            gesture(overlay,axesId,"",[500 300],[538 322]);
            position = app.Document.getComponent(axesId).getProperty("Position").LiteralValue;
            testCase.verifyEqual(position,[0.6 0.6 0.35 0.35],"AbsTol",1e-4);
            gesture(overlay,axesId,"e",[0 0],[76 0]);
            position = app.Document.getComponent(axesId).getProperty("Position").LiteralValue;
            testCase.verifyEqual(position,[0.6 0.6 0.45 0.35],"AbsTol",1e-4);

            % Units is editable and lands before the existing Position setter.
            geographic = app.Document.getComponentByName("GeographicAxes");
            tree = findall(figure,"Type","uitree");
            nodes = findall(tree,"Type","uitreenode");
            node = nodes(string({nodes.NodeData}) == geographic.Id);
            tree.SelectedNodes = node;
            tree.SelectionChangedFcn(tree,struct("SelectedNodes",node));
            labels = findall(figure,"Tag","yamada-inspector-property-label");
            row = labels(string({labels.Text}) == "Units");
            testCase.assertNumElements(row,1);
            editor = findall(row.Parent,"Tag","yamada-inspector-property-editor");
            handle = findall(figure,"-isa","matlab.graphics.axis.GeographicAxes");
            before = getpixelposition(handle);
            editor.Value = "pixels";
            editor.ValueChangedFcn(editor,struct());
            source = app.Document.CurrentText;
            testCase.verifyLessThan(strfind(source,"app.GeographicAxes.Units ="), ...
                strfind(source,"app.GeographicAxes.Position = "));
            testCase.verifyEmpty(strfind(source,"app.GeographicAxes.Position = [400 20 340 180];"));
            % The stored Position is converted so the rectangle keeps its extent.
            handle = findall(figure,"-isa","matlab.graphics.axis.GeographicAxes");
            testCase.verifyEqual(string(handle.Units),"pixels");
            testCase.verifyEqual(getpixelposition(handle),before,"AbsTol",1);
            clear cleanup
        end

        function togglesAutoModeBesideTheStoredValue(testCase)
            % togglesAutoModeBesideTheStoredValue Keep the stored value while Auto owns the effective limits.
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            path = string(fullfile(folder, "ModeApp.m"));
            writeModeApp(path, ["app.First.XLim = [0 10];", "app.Second.XLimMode = 'auto';", ...
                "app.Second.XLim = [0 5];"]);
            lifecycle = yamada.ui.DocumentLifecycleService(struct( ...
                "RequestOpenPathFcn",@() acceptedOpenPath(path)));
            app = yamada(lifecycle);
            cleanup = onCleanup(@() deleteIfValid(app));
            figure = editorPalette();
            open = findall(figure,"Type","uimenu","Text","&Open...");
            open.MenuSelectedFcn(open,[]);
            drawnow;

            % Auto locks the field without discarding the stored limits.
            parts = modeEditor(app,figure,"First","XLim");
            testCase.verifyEqual(string(parts.Value.Value),"[0 10]");
            testCase.verifyFalse(parts.Auto.Value);
            parts.Auto.Value = true;
            parts.Auto.ValueChangedFcn(parts.Auto,struct());
            parts = modeEditor(app,figure,"First","XLim");
            testCase.verifyTrue(parts.Auto.Value);
            testCase.verifyFalse(logical(parts.Value.Editable));
            testCase.verifyEqual(string(parts.Value.Value),"[0 10]");
            source = app.Document.CurrentText;
            testCase.verifyLessThan(strfind(source,"app.First.XLim = [0 10];"), ...
                regexp(source,"xlim\(app\.First, [""']auto[""']\);"));
            parts.Auto.Value = false;
            parts.Auto.ValueChangedFcn(parts.Auto,struct());
            testCase.verifyMatches(app.Document.CurrentText,"xlim\(app\.First, [""']manual[""']\);");
            handle = findall(figure,"-isa","matlab.ui.control.UIAxes","Tag","");
            limits = arrayfun(@(item) mat2str(item.XLim), handle, "UniformOutput", false);
            testCase.verifyTrue(any(string(limits) == "[0 10]"));

            % A Mode setting before the value cannot be made effective in place.
            parts = modeEditor(app,figure,"Second","XLim");
            testCase.verifyFalse(parts.Auto.Value);
            testCase.verifyEqual(string(parts.Auto.Enable),"off");
            testCase.verifySubstring(string(parts.Auto.Tooltip),"XLimMode is set before XLim");
            clear cleanup
        end

        function leavingAutoWithoutStoredValueFreezesTheEffectiveValue(testCase)
            % leavingAutoWithoutStoredValueFreezesTheEffectiveValue Write the effective value with the manual Mode.
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            path = string(fullfile(folder, "ModeApp.m"));
            writeModeApp(path, "app.First.YLim = [0 4];");
            lifecycle = yamada.ui.DocumentLifecycleService(struct( ...
                "RequestOpenPathFcn",@() acceptedOpenPath(path)));
            app = yamada(lifecycle);
            cleanup = onCleanup(@() deleteIfValid(app));
            figure = editorPalette();
            open = findall(figure,"Type","uimenu","Text","&Open...");
            open.MenuSelectedFcn(open,[]);
            drawnow;

            % Leaving Auto stores the limits MATLAB derives from the explicit settings.
            parts = modeEditor(app,figure,"First","XLim");
            testCase.verifyTrue(parts.Auto.Value);
            handles = findall(figure,"-isa","matlab.ui.control.UIAxes");
            limits = arrayfun(@(item) string(mat2str(item.XLim)), handles);
            shown = limits(1);
            testCase.assertTrue(all(limits == shown));
            parts.Auto.Value = false;
            parts.Auto.ValueChangedFcn(parts.Auto,struct());
            source = app.Document.CurrentText;
            % The reviewed call already implies the manual Mode.
            testCase.verifySubstring(source,"xlim(app.First, " + shown + ");");
            testCase.verifyFalse(contains(source,"XLimMode"));
            clear cleanup
        end

    end
end

function writeModeApp(path, settings)
% writeModeApp Write one owned two-axes source fixture with the given settings.
arguments (Input)
    path (1,1) string
    settings (1,:) string
end

lines = ["classdef ModeApp < handle", "properties (Access = public)", ...
    "UIFigure matlab.ui.Figure", "First matlab.ui.control.UIAxes", ...
    "Second matlab.ui.control.UIAxes", "end", "methods (Access = private)", ...
    "function createComponents(app)", "app.UIFigure = uifigure(""Visible"", ""off"");", ...
    "app.First = uiaxes(app.UIFigure);", "app.Second = uiaxes(app.UIFigure);", settings, ...
    "end", "end", "methods (Access = public)", "function app = ModeApp", ...
    "createComponents(app);", "end", "end", "end"];
yamada.source.SourceWriter.write(path, strjoin(lines, sprintf("\r\n")) + sprintf("\r\n"), "CRLF");
end

function parts = modeEditor(app, figure, name, label)
% modeEditor Select one component and return the parts of its value-and-Auto row.
arguments (Input)
    app (1,1) yamada
    figure (1,1) matlab.ui.Figure
    name (1,1) string
    label (1,1) string
end
arguments (Output)
    parts (1,1) struct
end

tree = findall(figure,"Type","uitree");
nodes = findall(tree,"Type","uitreenode");
node = nodes(string({nodes.NodeData}) == app.Document.getComponentByName(name).Id);
tree.SelectedNodes = node;
tree.SelectionChangedFcn(tree,struct("SelectedNodes",node));
drawnow;
labels = findall(figure,"Tag","yamada-inspector-property-label");
row = labels(string({labels.Text}) == label);
editor = findall(row(1).Parent,"Tag","yamada-inspector-value-mode-editor");
parts = editor.UserData;
end

function gesture(overlay, componentId, handle, startPoint, endPoint)
% gesture Send one complete overlay pointer gesture.
arguments (Input)
    overlay (1,1) matlab.ui.control.HTML
    componentId (1,1) string
    handle (1,1) string
    startPoint (1,2) double
    endPoint (1,2) double
end

% Pointer phases share the gesture handle, matching the overlay page.
phases = ["pointerdown","pointermove","pointerup"];
points = [startPoint; endPoint; endPoint];
for index = 1:numel(phases)
    overlay.HTMLEventReceivedFcn(overlay,struct("HTMLEventName","Pointer", ...
        "HTMLEventData",struct("phase",phases(index),"componentId",componentId, ...
        "handle",handle,"x",points(index,1),"y",points(index,2))));
end
drawnow;
end

function [accepted, filePath] = acceptedOpenPath(filePath)
% acceptedOpenPath Return one accepted source fixture path for lifecycle testing.
arguments (Input)
    filePath (1,1) string
end
arguments (Output)
    accepted (1,1) logical
    filePath (1,1) string
end

accepted = true;
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
