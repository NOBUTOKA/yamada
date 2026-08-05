classdef FigureToolsApp < matlab.apps.AppBase

    properties (Access = public)
        UIFigure matlab.ui.Figure
        ActionContextMenu matlab.ui.container.ContextMenu
        FileMenu matlab.ui.container.Menu
        ExportMenu matlab.ui.container.Menu
        HelpMenu matlab.ui.container.Menu
        Toolbar matlab.ui.container.Toolbar
        RefreshTool matlab.ui.container.toolbar.PushTool
        PinTool matlab.ui.container.toolbar.ToggleTool
    end

    methods (Access = private)
        function createComponents(app)
            app.UIFigure = uifigure("Visible", "off");
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

            app.UIFigure.Visible = "on";
        end
    end

    methods (Access = public)
        function app = FigureToolsApp
            createComponents(app);
            registerApp(app, app.UIFigure);

            if nargout == 0
                clear app
            end
        end

        function delete(app)
            delete(app.UIFigure);
        end
    end
end
