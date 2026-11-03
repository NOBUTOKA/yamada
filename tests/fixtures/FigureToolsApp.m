classdef FigureToolsApp < handle

    properties (Access = public)
        UIFigure matlab.ui.Figure
        ActionContextMenu matlab.ui.container.ContextMenu
        FileMenu matlab.ui.container.Menu
        ExportMenu matlab.ui.container.Menu
        HelpMenu matlab.ui.container.Menu
        Toolbar matlab.ui.container.Toolbar
        RefreshTool matlab.ui.container.toolbar.PushTool
        PinTool matlab.ui.container.toolbar.ToggleTool
        PreviewLabel matlab.ui.control.Label
    end

    methods (Access = private)
        function createComponents(app)
            app.UIFigure = uifigure("Visible", "off");
            app.UIFigure.CloseRequestFcn = @(~, ~) delete(app);
            app.UIFigure.Position = [100 100 420 260];
            app.UIFigure.Name = "Figure Tools";

            app.ActionContextMenu = uicontextmenu(app.UIFigure);
            app.ActionContextMenu.Visible = "on";

            app.FileMenu = uimenu(app.UIFigure);
            app.FileMenu.Text = "File";

            app.ExportMenu = uimenu(app.FileMenu);
            app.ExportMenu.Text = "Export";
            app.ExportMenu.Separator = "on";

            app.HelpMenu = uimenu(app.UIFigure);
            app.HelpMenu.Text = "Help";

            app.Toolbar = uitoolbar(app.UIFigure);
            app.Toolbar.Visible = "on";

            app.RefreshTool = uipushtool(app.Toolbar);
            app.RefreshTool.Tooltip = "Refresh";

            app.PinTool = uitoggletool(app.Toolbar);
            app.PinTool.Tooltip = "Pin";
            app.PinTool.State = "off";

            app.PreviewLabel = uilabel(app.UIFigure);
            app.PreviewLabel.Position = [40 115 340 30];
            app.PreviewLabel.Text = "Figure tools are ignored in Safe Preview.";
            app.PreviewLabel.HorizontalAlignment = "center";

            app.UIFigure.Visible = "on";
        end
    end

    methods (Access = public)
        function app = FigureToolsApp
            createComponents(app);

            addlistener(app.UIFigure, "ObjectBeingDestroyed", @app.figureDeleted);
        end

        function figureDeleted(app, source, event)
            % figureDeleted Release the owner when its figure is destroyed.
            if isvalid(app), delete(app); end
        end

        function delete(app)
            delete(app.UIFigure);
        end
    end
end
