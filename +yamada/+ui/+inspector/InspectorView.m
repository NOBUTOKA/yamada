classdef InspectorView < handle
    % InspectorView Host a native scrollable container for inspector sections.
    %   This view owns only transient UI layout and scroll state. Property values,
    %   validation, and history remain owned by the document model.
    %
    %   Example:
    %       view = yamada.ui.inspector.InspectorView(parent);

    properties (Access = private)
        Panel matlab.ui.container.Panel
        ContentPanel matlab.ui.container.Panel
        Grid matlab.ui.container.GridLayout
        ContentHeight double = 1
        Anchor matlab.ui.control.Label
    end

    methods
        function obj = InspectorView(parent)
            % InspectorView Create an initially empty native scrollable inspector.
            arguments (Input)
                parent
            end
            arguments (Output)
                obj (1, 1) yamada.ui.inspector.InspectorView
            end

            % The nested content panel preserves the outer panel as the native scroll host.
            obj.Panel = uipanel(parent, "BorderType", "none");
            obj.Panel.Scrollable = "on";
            obj.Panel.AutoResizeChildren = "off";
            obj.Panel.SizeChangedFcn = @(~, ~) obj.layoutContent();
            obj.ContentPanel = uipanel(obj.Panel, "BorderType", "none");
            % An empty direct child of the scroll host gives reveal a renderable scroll target.
            obj.Anchor = uilabel(obj.Panel, "Text", "", "Position", [1 1 1 1], ...
                "Tag", "yamada-inspector-reveal-anchor");
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
                obj (1, 1) yamada.ui.inspector.InspectorView
            end

            % Delete only children owned by this disposable inspector view.
            delete(obj.Grid.Children);
            obj.Grid.RowHeight = {"1x"};
            obj.ContentHeight = 1;
            obj.layoutContent();
        end

        function reveal(obj, row)
            % reveal Bring the settled editor row into the scrollable Inspector viewport.
            arguments (Input)
                obj (1, 1) yamada.ui.inspector.InspectorView
                row (1, 1) matlab.ui.container.GridLayout
            end

            % Measure the row in scroll-content coordinates, padded to center it in the viewport.
            bounds = getpixelposition(row, true);
            content = getpixelposition(obj.ContentPanel, true);
            viewport = getpixelposition(obj.Panel);
            padding = max(0, (viewport(4) - bounds(4))/2);
            bottom = bounds(2) - content(2) + obj.ContentPanel.Position(2) - padding;
            bottom = max(1, round(bottom));
            top = min(obj.ContentPanel.Position(2) + obj.ContentPanel.Position(4) - 1, ...
                round(bounds(2) - content(2) + obj.ContentPanel.Position(2) + bounds(4) + padding));

            % Scroll to a direct-child anchor: numeric scroll never reaches the view on
            % R2024a and R2024b, and component targets must be direct children of the host.
            obj.Anchor.Position = [1 bottom 1 max(1, top - bottom)];
            scroll(obj.Panel, obj.Anchor);
        end

        function grid = contentGrid(obj)
            % contentGrid Return the inspector-owned grid for section construction.
            arguments (Input)
                obj (1, 1) yamada.ui.inspector.InspectorView
            end
            arguments (Output)
                grid (1, 1) matlab.ui.container.GridLayout
            end

            grid = obj.Grid;
        end

        function setContentHeight(obj, value)
            % setContentHeight Set the pixel extent that activates native vertical scrolling.
            arguments (Input)
                obj (1, 1) yamada.ui.inspector.InspectorView
                value (1, 1) double {mustBeFinite, mustBePositive}
            end

            obj.ContentHeight = value;
            obj.layoutContent();
        end

        function delete(obj)
            % delete Release the inspector grid when its editor host is disposed.
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

            % Keep a stale reveal target from extending the scroll extent after content shrinks.
            if ~isempty(obj.Anchor) && isvalid(obj.Anchor) && ...
                    sum(obj.Anchor.Position([2 4])) > contentHeight + 1
                obj.Anchor.Position = [1 1 1 1];
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
