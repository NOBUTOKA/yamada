classdef WelcomeApp < handle
    % WelcomeApp Provide a small, project-owned application for the yamada tutorial.
    %   Open this file in yamada to edit its label, button, and window without
    %   running callbacks. Run WelcomeApp in MATLAB to try the finished app.
    %
    %   Example:
    %       WelcomeApp

    properties (Access = private)
        UIFigure matlab.ui.Figure
        GreetingLabel matlab.ui.control.Label
        GreetButton matlab.ui.control.Button
    end

    methods (Access = private)
        function createComponents(app)
            % createComponents Build a simple fixed-position greeting interface.
            arguments (Input)
                app (1, 1) WelcomeApp
            end
            app.UIFigure = uifigure("Visible", "off");
            app.UIFigure.Position = [100 100 420 240];
            app.UIFigure.Name = "Welcome to yamada";
            app.UIFigure.CloseRequestFcn = @(~, ~) delete(app);

            app.GreetingLabel = uilabel(app.UIFigure);
            app.GreetingLabel.Position = [40 130 340 40];
            app.GreetingLabel.Text = "Hello from MATLAB!";
            app.GreetingLabel.FontSize = 22;

            app.GreetButton = uibutton(app.UIFigure, "push");
            app.GreetButton.Position = [40 60 160 36];
            app.GreetButton.Text = "Say hello";
            app.GreetButton.ButtonPushedFcn = @(source, event) app.greet(source, event);
            app.UIFigure.Visible = "on";
        end

        function greet(app, source, event)
            % greet Update the greeting when the running application's button is pressed.
            arguments (Input)
                app (1, 1) WelcomeApp
                source (1, 1) matlab.ui.control.Button
                event
            end
            app.GreetingLabel.Text = "Hello from your app!";
        end
    end

    methods
        function app = WelcomeApp()
            % WelcomeApp Construct and retain the example through figure callbacks.
            arguments (Output)
                app (1, 1) WelcomeApp
            end
            app.createComponents();
        end

        function delete(app)
            % delete Close the example's window when its owner is released.
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                delete(app.UIFigure);
            end
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
