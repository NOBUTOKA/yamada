% SimpleCalculatorApp - A small calculator fixture for parser tests.
% Copyright (C) 2026 yamada contributors
%
% This file is part of yamada.
%
% yamada is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
%
% yamada is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
% GNU General Public License for more details.
%
% You should have received a copy of the GNU General Public License
% along with yamada. If not, see <https://www.gnu.org/licenses/>.

classdef SimpleCalculatorApp < matlab.apps.AppBase

    properties (Access = public)
        UIFigure        matlab.ui.Figure
        GridLayout      matlab.ui.container.GridLayout
        LeftValueLabel  matlab.ui.control.Label
        LeftValueField  matlab.ui.control.NumericEditField
        OperatorLabel   matlab.ui.control.Label
        OperatorDropDown matlab.ui.control.DropDown
        RightValueLabel matlab.ui.control.Label
        RightValueField matlab.ui.control.NumericEditField
        CalculateButton matlab.ui.control.Button
        ResultLabel     matlab.ui.control.Label
        ResultValueLabel matlab.ui.control.Label
    end

    methods (Access = private)

        function CalculateButtonPushed(app, ~)
            leftValue = app.LeftValueField.Value;
            rightValue = app.RightValueField.Value;

            switch app.OperatorDropDown.Value
                case 'Add'
                    result = leftValue + rightValue;
                    resultText = string(result);
                case 'Subtract'
                    result = leftValue - rightValue;
                    resultText = string(result);
                case 'Multiply'
                    result = leftValue * rightValue;
                    resultText = string(result);
                case 'Divide'
                    if rightValue == 0
                        resultText = "Undefined (division by zero)";
                    else
                        result = leftValue / rightValue;
                        resultText = string(result);
                    end
            end

            app.ResultValueLabel.Text = resultText;
        end

        function createComponents(app)
            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Position = [100 100 360 250];
            app.UIFigure.Name = 'Simple Calculator';

            app.GridLayout = uigridlayout(app.UIFigure);
            app.GridLayout.ColumnWidth = {'1x', '1x'};
            app.GridLayout.RowHeight = {'fit', 'fit', 'fit', 'fit', 'fit'};

            app.LeftValueLabel = uilabel(app.GridLayout);
            app.LeftValueLabel.Text = 'Left value';
            app.LeftValueLabel.Layout.Row = 1;
            app.LeftValueLabel.Layout.Column = 1;

            app.LeftValueField = uieditfield(app.GridLayout, 'numeric');
            app.LeftValueField.Value = 0;
            app.LeftValueField.Layout.Row = 1;
            app.LeftValueField.Layout.Column = 2;

            app.OperatorLabel = uilabel(app.GridLayout);
            app.OperatorLabel.Text = 'Operation';
            app.OperatorLabel.Layout.Row = 2;
            app.OperatorLabel.Layout.Column = 1;

            app.OperatorDropDown = uidropdown(app.GridLayout);
            app.OperatorDropDown.Items = {'Add', 'Subtract', 'Multiply', 'Divide'};
            app.OperatorDropDown.Value = 'Add';
            app.OperatorDropDown.Layout.Row = 2;
            app.OperatorDropDown.Layout.Column = 2;

            app.RightValueLabel = uilabel(app.GridLayout);
            app.RightValueLabel.Text = 'Right value';
            app.RightValueLabel.Layout.Row = 3;
            app.RightValueLabel.Layout.Column = 1;

            app.RightValueField = uieditfield(app.GridLayout, 'numeric');
            app.RightValueField.Value = 0;
            app.RightValueField.Layout.Row = 3;
            app.RightValueField.Layout.Column = 2;

            app.CalculateButton = uibutton(app.GridLayout, 'push');
            app.CalculateButton.Text = 'Calculate';
            app.CalculateButton.Layout.Row = 4;
            app.CalculateButton.Layout.Column = [1 2];
            app.CalculateButton.ButtonPushedFcn = createCallbackFcn( ...
                app, @CalculateButtonPushed, true);

            app.ResultLabel = uilabel(app.GridLayout);
            app.ResultLabel.Text = 'Result';
            app.ResultLabel.Layout.Row = 5;
            app.ResultLabel.Layout.Column = 1;

            app.ResultValueLabel = uilabel(app.GridLayout);
            app.ResultValueLabel.Text = '0';
            app.ResultValueLabel.Layout.Row = 5;
            app.ResultValueLabel.Layout.Column = 2;

            app.UIFigure.Visible = 'on';
        end
    end

    methods (Access = public)

        function app = SimpleCalculatorApp
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
