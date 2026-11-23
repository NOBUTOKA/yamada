classdef (TestTags = {'inspector', 'ui'}) InspectorViewTest < matlab.unittest.TestCase
    % InspectorViewTest Verify native inspector scroll-container lifecycle.
    %   These tests construct the real R2024a UI controls and delete every
    %   fixture, without requiring a document model or editor application.

    methods (Test, TestTags = {'fast'})
        function createsScrollableNativeGrid(testCase)
            % createsScrollableNativeGrid Construct a view whose native host scrolls tall content.
            % Guarantee: the inspector content can scroll when it exceeds the viewport.
            % Failure mode: the native grid loses Scrollable or sizes content to the viewport, hiding rows.

            % Use a hidden ordinary figure to exercise the programmatic UI path.
            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            view = yamada.ui.inspector.InspectorView(figure);
            drawnow;

            grid = view.contentGrid();
            testCase.verifyTrue(isvalid(grid));
            % Read the native scroll host and content panel that own the grid.
            content = grid.Parent;
            host = content.Parent;
            testCase.verifyEqual(string(host.Scrollable), "on");
            view.setContentHeight(800);
            drawnow;
            testCase.verifyGreaterThan(content.Position(4), 100);
            viewport = getpixelposition(host, true);
            testCase.verifyLessThan(content.Position(3), viewport(3));
            clear cleanup
        end
    end

    methods (Test)
        function unreachableViewReleasesOwnedControls(testCase)
            % unreachableViewReleasesOwnedControls Exercise implicit destructor dispatch.
            % Guarantee: dropping the view deletes its own controls but not the host figure.
            % Failure mode: the destructor is not dispatched or deletes the shared figure, leaking or destroying UI.
            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(figure));
            view = yamada.ui.inspector.InspectorView(figure);
            grid = view.contentGrid();

            % Remove the callback's reference so clearing the owner triggers destruction.
            panel = grid.Parent.Parent;
            panel.SizeChangedFcn = [];
            clear view
            testCase.verifyFalse(isvalid(grid));
            testCase.verifyFalse(isvalid(panel));
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
