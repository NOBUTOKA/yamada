classdef AxesExplorerApp < matlab.apps.AppBase

    properties (Access = public)
        UIFigure matlab.ui.Figure
        UIAxes matlab.ui.control.UIAxes
        StandardAxes matlab.graphics.axis.Axes
        PolarAxes matlab.graphics.axis.PolarAxes
        GeographicAxes matlab.graphics.axis.GeographicAxes
    end

    methods (Access = private)
        function createComponents(app)
            app.UIFigure = uifigure("Visible", "off");
            app.UIFigure.Position = [100 100 760 440];
            app.UIFigure.Name = "Axes Explorer";

            app.UIAxes = uiaxes(app.UIFigure);
            app.UIAxes.Position = [20 230 340 180];
            app.UIAxes.XLim = [0 10];
            app.UIAxes.YLim = [0 100];

            app.StandardAxes = axes(app.UIFigure);
            app.StandardAxes.Position = [0.55 0.55 0.35 0.35];
            app.StandardAxes.XLim = [0 1];
            app.StandardAxes.YLim = [0 1];

            app.PolarAxes = polaraxes(app.UIFigure);
            app.PolarAxes.Position = [20 20 340 180];
            app.PolarAxes.ThetaLim = [0 180];
            app.PolarAxes.RLim = [0 5];

            app.GeographicAxes = geoaxes(app.UIFigure);
            app.GeographicAxes.Position = [400 20 340 180];
            geolimits(app.GeographicAxes, [30 40], [130 140]);

            app.UIFigure.Visible = "on";
        end
    end

    methods (Access = public)
        function app = AxesExplorerApp
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
