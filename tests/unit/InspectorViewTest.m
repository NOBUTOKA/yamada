classdef InspectorViewTest < matlab.unittest.TestCase
    % InspectorViewTest Verify native inspector scroll-container lifecycle.
    %   These tests construct the real R2024a UI controls and delete every
    %   fixture, without requiring a document model or editor application.

    methods (Test)
        function createsScrollableNativeGrid(testCase)
            % createsScrollableNativeGrid Construct a view with public scrolling enabled.

            % Use a hidden ordinary figure to exercise the programmatic UI path.
            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            view = macd.ui.inspector.InspectorView(figure);
            drawnow;

            grid = view.contentGrid();
            testCase.verifyTrue(isvalid(grid));
            testCase.verifyTrue(view.isScrollable());
            view.setContentHeight(800);
            drawnow;
            testCase.verifyGreaterThan(view.contentPixelHeight(), 100);
            clear cleanup
        end

        function clearDeletesOnlyOwnedChildren(testCase)
            % clearDeletesOnlyOwnedChildren Remove view children without deleting the host.

            % Add one owned control, then verify clearing preserves the outer figure.
            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            view = macd.ui.inspector.InspectorView(figure);
            label = uilabel(view.contentGrid(), "Text", "Owned");
            drawnow;
            view.clear();

            testCase.verifyFalse(isvalid(label));
            testCase.verifyTrue(isvalid(figure));
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
MatlabAppClassDesigner - Inspector view unit tests.
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
