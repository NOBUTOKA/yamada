classdef PreviewRendererTest < matlab.unittest.TestCase
    % PreviewRendererTest Compare safe preview layout with a trusted fixture app.
    %   This test parses the preserved SimpleCalculator fixture, renders the model
    %   without executing it, and compares key visual properties against a separate
    %   runtime instance of that known fixture. It does not permit the editor to run
    %   arbitrary opened source.

    methods (Test)
        function safePreviewMatchesTrustedCalculatorLayout(testCase)
            % safePreviewMatchesTrustedCalculatorLayout Compare grid placement and text.

            % Render parsed data into an editor-owned hidden preview surface.
            registry = macd.model.ComponentRegistry.createDefault();
            fixturePath = PreviewRendererTest.fixturePath();
            document = macd.source.AppSourceParser.parseFile(fixturePath, registry);
            previewFigure = uifigure("Visible", "off");
            previewPanel = uipanel(previewFigure);
            renderer = macd.ui.PreviewRenderer(registry);
            [handles, diagnostics] = renderer.render(document, previewPanel);
            previewCleanup = onCleanup(@() deleteIfValid(previewFigure));
            testCase.verifyEmpty(diagnostics);

            % Execute only the maintained trusted fixture as the visual oracle.
            fixtureFolder = fileparts(fixturePath);
            addpath(fixtureFolder);
            pathCleanup = onCleanup(@() rmpath(fixtureFolder));
            actual = SimpleCalculatorApp();
            actual.UIFigure.Visible = "off";
            actualCleanup = onCleanup(@() deleteIfValid(actual));

            % Compare the rows, columns, spans, and user-facing text at risk here.
            testCase.verifyEqual(handles("parsed-CalculateButton").Layout.Row, ...
                actual.CalculateButton.Layout.Row);
            testCase.verifyEqual(handles("parsed-CalculateButton").Layout.Column, ...
                actual.CalculateButton.Layout.Column);
            testCase.verifyEqual(handles("parsed-ResultLabel").Layout.Row, ...
                actual.ResultLabel.Layout.Row);
            testCase.verifyEqual(handles("parsed-ResultLabel").Layout.Column, ...
                actual.ResultLabel.Layout.Column);
            testCase.verifyEqual(handles("parsed-ResultValueLabel").Layout.Row, ...
                actual.ResultValueLabel.Layout.Row);
            testCase.verifyEqual(handles("parsed-ResultValueLabel").Layout.Column, ...
                actual.ResultValueLabel.Layout.Column);
            testCase.verifyEqual(handles("parsed-OperatorDropDown").Value, ...
                actual.OperatorDropDown.Value);
            testCase.verifyEqual(handles("parsed-ResultValueLabel").Text, ...
                actual.ResultValueLabel.Text);
            clear actualCleanup pathCleanup previewCleanup
        end
    end

    methods (Static, Access = private)
        function result = fixturePath()
            % fixturePath Resolve the preserved trusted visual fixture path.
            arguments (Output)
                result (1, 1) string
            end

            % Resolve relative to this class so test execution remains location-independent.
            testPath = mfilename("fullpath");
            projectRoot = fileparts(fileparts(fileparts(testPath)));
            result = string(fullfile(projectRoot, "tests", "fixtures", ...
                "SimpleCalculatorApp.m"));
        end
    end
end

function deleteIfValid(value)
% deleteIfValid Delete one graphics or AppBase handle when it remains valid.
arguments (Input)
    value
end

% Keep cleanup idempotent after assertion failures and partial construction.
if isvalid(value)
    delete(value);
end
end

%{
MatlabAppClassDesigner - Tests for the safe registry-only preview renderer.
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
