classdef LargePreviewFixtureApp < matlab.apps.AppBase
    % LargePreviewFixtureApp Exercise a client area larger than Safe Preview.
    %   Edge controls and a center grid expose both scrolling directions.

    properties (Access = public)
        % UIFigure - Root figure with a 1200-by-900 client area.
        UIFigure matlab.ui.Figure
        % TopLeftLabel - Control near the upper-left figure edge.
        TopLeftLabel matlab.ui.control.Label
        % BottomRightButton - Control near the lower-right figure edge.
        BottomRightButton matlab.ui.control.Button
        % CenterPanel - Container positioned in the figure center.
        CenterPanel matlab.ui.container.Panel
        % CenterGrid - Layout-managed region inside the center panel.
        CenterGrid matlab.ui.container.GridLayout
        % CenterLabel - Label managed by the center grid.
        CenterLabel matlab.ui.control.Label
    end

    methods (Access = private)
        function createComponents(app)
            % createComponents Build the oversized visual test application.
            app.UIFigure = uifigure("Visible", "off");
            app.UIFigure.Position = [100 100 1200 900];
            app.UIFigure.Name = "Large Safe Preview Fixture";

            app.TopLeftLabel = uilabel(app.UIFigure);
            app.TopLeftLabel.Position = [12 864 110 22];
            app.TopLeftLabel.Text = "Top left";

            app.BottomRightButton = uibutton(app.UIFigure, "push");
            app.BottomRightButton.Position = [1070 12 116 28];
            app.BottomRightButton.Text = "Bottom right";

            app.CenterPanel = uipanel(app.UIFigure);
            app.CenterPanel.Position = [440 330 320 180];
            app.CenterGrid = uigridlayout(app.CenterPanel, [1 1]);
            app.CenterGrid.RowHeight = {"1x"};
            app.CenterGrid.ColumnWidth = {"1x"};

            app.CenterLabel = uilabel(app.CenterGrid);
            app.CenterLabel.Text = "Grid center";
            app.CenterLabel.Layout.Row = 1;
            app.CenterLabel.Layout.Column = 1;

            app.UIFigure.Visible = "on";
        end
    end

    methods (Access = public)
        function app = LargePreviewFixtureApp
            % LargePreviewFixtureApp Construct and register the test application.
            createComponents(app);
            registerApp(app, app.UIFigure);
            if nargout == 0
                clear app
            end
        end

        function delete(app)
            % delete Close the fixture figure.
            delete(app.UIFigure);
        end
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
