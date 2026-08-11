classdef InspectorPropertyRowTest < matlab.unittest.TestCase
    % InspectorPropertyRowTest Verify native property-row draft and error behavior.
    %   These tests use the real controls and prove a rejected edit stays in the
    %   editor while the model callback reports an inline error.

    methods (Test)
        function retainsRejectedTextAndShowsInlineError(testCase)
            % retainsRejectedTextAndShowsInlineError Keep an invalid draft out of the model callback.

            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            grid = uigridlayout(figure, [1 1]);
            definition = macd.model.PropertyDefinition("Position", [], false, true, ...
                struct("editor", "numericVector"));
            row = macd.ui.inspector.InspectorPropertyRow(grid, 1, "component-1", ...
                definition, @(~, ~, ~) "Enter a finite numeric vector."); %#ok<NASGU>
            editor = findall(figure, "Tag", "macd-inspector-property-editor");
            editor.Value = "not a vector";
            editor.ValueChangedFcn(editor, struct());
            drawnow;
            errorLabel = findall(figure, "Tag", "macd-inspector-property-error");
            testCase.verifyEqual(string(editor.Value), "not a vector");
            testCase.verifyEqual(string(errorLabel.Text), "Enter a finite numeric vector.");
            clear cleanup
        end
    end
end

function deleteIfValid(value)
% deleteIfValid Delete one UI fixture when it remains valid.
arguments (Input)
    value
end

if ~isempty(value) && isvalid(value)
    delete(value);
end
end

%{
MatlabAppClassDesigner - Native inspector property row tests.
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
