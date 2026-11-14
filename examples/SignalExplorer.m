classdef SignalExplorer < handle
    % SignalExplorer Provide a grid-based waveform plotter for the yamada showcase.
    %   Open this file in yamada to edit its nested Grid Layouts, settings
    %   controls, and axes without running callbacks. Run SignalExplorer in
    %   MATLAB, choose a waveform, frequency, and amplitude, and press Plot.
    %
    %   Example:
    %       SignalExplorer

    properties (Access = private)
        UIFigure matlab.ui.Figure
        MainGrid matlab.ui.container.GridLayout
        SettingsPanel matlab.ui.container.Panel
        SettingsGrid matlab.ui.container.GridLayout
        WaveformLabel matlab.ui.control.Label
        WaveformDropDown matlab.ui.control.DropDown
        FrequencyLabel matlab.ui.control.Label
        FrequencyField matlab.ui.control.NumericEditField
        AmplitudeLabel matlab.ui.control.Label
        AmplitudeSlider matlab.ui.control.Slider
        GridCheckBox matlab.ui.control.CheckBox
        PlotButton matlab.ui.control.Button
        SignalAxes matlab.ui.control.UIAxes
    end

    methods (Access = private)
        function createComponents(app)
            % createComponents Build the settings panel and the plot area.
            arguments (Input)
                app (1, 1) SignalExplorer
            end

            % Create the window and its two-column main grid.
            app.UIFigure = uifigure("Visible", "off");
            app.UIFigure.Position = [100 100 620 400];
            app.UIFigure.Name = "Signal Explorer";
            app.UIFigure.CloseRequestFcn = @(~, ~) delete(app);

            app.MainGrid = uigridlayout(app.UIFigure);
            app.MainGrid.ColumnWidth = {240, "1x"};
            app.MainGrid.RowHeight = {"1x"};

            % Create the settings panel with a nested label-and-control grid.
            app.SettingsPanel = uipanel(app.MainGrid);
            app.SettingsPanel.Title = "Settings";
            app.SettingsPanel.Layout.Row = 1;
            app.SettingsPanel.Layout.Column = 1;

            app.SettingsGrid = uigridlayout(app.SettingsPanel);
            app.SettingsGrid.ColumnWidth = {80, "1x"};
            app.SettingsGrid.RowHeight = {22, 22, 22, 22, "1x", 30};

            app.WaveformLabel = uilabel(app.SettingsGrid);
            app.WaveformLabel.Text = "Waveform";
            app.WaveformLabel.Layout.Row = 1;
            app.WaveformLabel.Layout.Column = 1;

            app.WaveformDropDown = uidropdown(app.SettingsGrid);
            app.WaveformDropDown.Items = ["Sine" "Square" "Sawtooth"];
            app.WaveformDropDown.Value = "Sine";
            app.WaveformDropDown.Layout.Row = 1;
            app.WaveformDropDown.Layout.Column = 2;

            app.FrequencyLabel = uilabel(app.SettingsGrid);
            app.FrequencyLabel.Text = "Frequency";
            app.FrequencyLabel.Layout.Row = 2;
            app.FrequencyLabel.Layout.Column = 1;

            app.FrequencyField = uieditfield(app.SettingsGrid, "numeric");
            app.FrequencyField.Value = 5;
            app.FrequencyField.Layout.Row = 2;
            app.FrequencyField.Layout.Column = 2;

            app.AmplitudeLabel = uilabel(app.SettingsGrid);
            app.AmplitudeLabel.Text = "Amplitude";
            app.AmplitudeLabel.Layout.Row = 3;
            app.AmplitudeLabel.Layout.Column = 1;

            app.AmplitudeSlider = uislider(app.SettingsGrid);
            app.AmplitudeSlider.Limits = [0 2];
            app.AmplitudeSlider.Value = 1;
            app.AmplitudeSlider.Layout.Row = 3;
            app.AmplitudeSlider.Layout.Column = 2;

            app.GridCheckBox = uicheckbox(app.SettingsGrid);
            app.GridCheckBox.Text = "Show grid";
            app.GridCheckBox.Value = true;
            app.GridCheckBox.Layout.Row = 4;
            app.GridCheckBox.Layout.Column = [1 2];

            app.PlotButton = uibutton(app.SettingsGrid, "push");
            app.PlotButton.Text = "Plot";
            app.PlotButton.Layout.Row = 6;
            app.PlotButton.Layout.Column = [1 2];
            app.PlotButton.ButtonPushedFcn = @(source, event) app.plotSignal(source, event);

            % Create the plot area beside the settings panel.
            app.SignalAxes = uiaxes(app.MainGrid);
            app.SignalAxes.Layout.Row = 1;
            app.SignalAxes.Layout.Column = 2;
            app.SignalAxes.XGrid = "on";
            app.SignalAxes.YGrid = "on";

            app.UIFigure.Visible = "on";
        end

        function plotSignal(app, source, event)
            % plotSignal Draw the selected waveform when the running application's button is pressed.
            arguments (Input)
                app (1, 1) SignalExplorer
                source (1, 1) matlab.ui.control.Button
                event
            end

            % Sample one second of the selected waveform.
            t = linspace(0, 1, 1000);
            phase = 2 * pi * app.FrequencyField.Value * t;
            switch app.WaveformDropDown.Value
                case "Square"
                    y = sign(sin(phase));
                case "Sawtooth"
                    y = 2 * mod(phase / (2 * pi), 1) - 1;
                otherwise
                    y = sin(phase);
            end

            % Plot the scaled waveform and apply the grid setting.
            plot(app.SignalAxes, t, app.AmplitudeSlider.Value * y);
            app.SignalAxes.XGrid = app.GridCheckBox.Value;
            app.SignalAxes.YGrid = app.GridCheckBox.Value;
        end
    end

    methods
        function app = SignalExplorer()
            % SignalExplorer Construct and retain the example through figure callbacks.
            arguments (Output)
                app (1, 1) SignalExplorer
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
