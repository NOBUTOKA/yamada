classdef InspectorView < handle
    % InspectorView Host a native scrollable container for inspector sections.
    %   This view owns only transient UI layout and scroll state. Property values,
    %   validation, and history remain owned by the document model.
    %
    %   Example:
    %       view = macd.ui.inspector.InspectorView(parent);

    properties (Access = private)
        Panel matlab.ui.container.Panel
        ContentPanel matlab.ui.container.Panel
        Grid matlab.ui.container.GridLayout
        ContentHeight double = 1
    end

    methods
        function obj = InspectorView(parent)
            % InspectorView Create an initially empty native scrollable inspector.
            arguments (Input)
                parent
            end
            arguments (Output)
                obj (1, 1) macd.ui.inspector.InspectorView
            end

            % Panel provides native scrolling; R2024a exposes no scroll-position API here.
            obj.Panel = uipanel(parent, "BorderType", "none");
            obj.Panel.Scrollable = "on";
            obj.Panel.AutoResizeChildren = "off";
            obj.Panel.SizeChangedFcn = @(~, ~) obj.layoutContent();
            obj.ContentPanel = uipanel(obj.Panel, "BorderType", "none");
            obj.Grid = uigridlayout(obj.ContentPanel, [1 1]);
            obj.Grid.Padding = [0 0 0 0];
            obj.Grid.RowSpacing = 0;
            obj.Grid.ColumnSpacing = 0;
            obj.Grid.RowHeight = {"1x"};
            obj.Grid.ColumnWidth = {"1x"};
            obj.layoutContent();
        end

        function clear(obj)
            % clear Delete all inspector-owned section controls and reset scrolling.
            arguments (Input)
                obj (1, 1) macd.ui.inspector.InspectorView
            end

            % Delete only children owned by this disposable inspector view.
            delete(obj.Grid.Children);
            obj.Grid.RowHeight = {"1x"};
            obj.ContentHeight = 1;
            obj.layoutContent();
        end

        function result = isScrollable(obj)
            % isScrollable Return whether the native panel enables scrolling.
            arguments (Input)
                obj (1, 1) macd.ui.inspector.InspectorView
            end
            arguments (Output)
                result (1, 1) logical
            end

            result = obj.Panel.Scrollable == "on";
        end

        function grid = contentGrid(obj)
            % contentGrid Return the inspector-owned grid for section construction.
            arguments (Input)
                obj (1, 1) macd.ui.inspector.InspectorView
            end
            arguments (Output)
                grid (1, 1) matlab.ui.container.GridLayout
            end

            grid = obj.Grid;
        end

        function setContentHeight(obj, value)
            % setContentHeight Set the pixel extent that activates native vertical scrolling.
            arguments (Input)
                obj (1, 1) macd.ui.inspector.InspectorView
                value (1, 1) double {mustBeFinite, mustBePositive}
            end

            obj.ContentHeight = value;
            obj.layoutContent();
        end

        function value = contentPixelHeight(obj)
            % contentPixelHeight Return the current native scroll-content height.
            arguments (Input)
                obj (1, 1) macd.ui.inspector.InspectorView
            end
            arguments (Output)
                value (1, 1) double
            end

            value = obj.ContentPanel.Position(4);
        end

        function value = contentPixelWidth(obj)
            % contentPixelWidth Return the current width reserved for inspector content.
            arguments (Input)
                obj (1, 1) macd.ui.inspector.InspectorView
            end
            arguments (Output)
                value (1, 1) double
            end

            value = obj.ContentPanel.Position(3);
        end

        function value = viewportPixelWidth(obj)
            % viewportPixelWidth Return the scroll host width in its local coordinate system.
            arguments (Input)
                obj (1, 1) macd.ui.inspector.InspectorView
            end
            arguments (Output)
                value (1, 1) double
            end

            position = getpixelposition(obj.Panel, true);
            value = position(3);
        end

        function delete(obj)
            % delete Release the inspector grid when its editor host is disposed.
            arguments (Input)
                obj (1, 1) macd.ui.inspector.InspectorView
            end

            if ~isempty(obj.Panel) && isvalid(obj.Panel)
                delete(obj.Panel);
            end
        end
    end

    methods (Access = private)
        function layoutContent(obj)
            % layoutContent Reserve scrollbar width and force a visible vertical scroll track.
            if isempty(obj.Panel) || ~isvalid(obj.Panel) || ...
                    isempty(obj.ContentPanel) || ~isvalid(obj.ContentPanel)
                return
            end
            position = getpixelposition(obj.Panel, true);
            scrollbarWidth = 18;
            contentWidth = max(position(3) - scrollbarWidth, 1);
            contentHeight = max(obj.ContentHeight, position(4) + 1);
            obj.ContentPanel.Position = [1 1 contentWidth contentHeight];
        end
    end
end

%{
MatlabAppClassDesigner - Native scrollable inspector view container.
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
