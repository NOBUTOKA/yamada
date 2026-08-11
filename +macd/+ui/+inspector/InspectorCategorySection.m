classdef InspectorCategorySection < handle
    % InspectorCategorySection Group native property rows beneath one category label.
    %   The section owns transient controls for one inspector rebuild and does not
    %   retain document or component model objects.

    properties (Access = private)
        Panel matlab.ui.container.Panel
        Grid matlab.ui.container.GridLayout
    end

    methods
        function obj = InspectorCategorySection(parent, title, rowCount)
            % InspectorCategorySection Create one category panel with fixed row slots.
            arguments (Input)
                parent
                title (1, 1) string
                rowCount (1, 1) double {mustBeInteger, mustBeNonnegative}
            end
            arguments (Output)
                obj (1, 1) macd.ui.inspector.InspectorCategorySection
            end

            % Give each section deterministic compact row geometry.
            obj.Panel = uipanel(parent, "Title", title, "Tag", "macd-inspector-category");
            obj.Grid = uigridlayout(obj.Panel, [max(rowCount, 1) 1]);
            obj.Grid.Padding = [6 3 6 3];
            obj.Grid.RowSpacing = 3;
            obj.Grid.ColumnWidth = {"1x"};
            obj.Grid.RowHeight = repmat({28}, 1, max(rowCount, 1));
        end

        function grid = contentGrid(obj)
            % contentGrid Return the grid used by property rows in this section.
            arguments (Input)
                obj (1, 1) macd.ui.inspector.InspectorCategorySection
            end
            arguments (Output)
                grid (1, 1) matlab.ui.container.GridLayout
            end
            grid = obj.Grid;
        end

        function setLayoutRow(obj, row)
            % setLayoutRow Assign this section to one parent-grid row.
            arguments (Input)
                obj (1, 1) macd.ui.inspector.InspectorCategorySection
                row (1, 1) double {mustBeInteger, mustBePositive}
            end
            obj.Panel.Layout.Row = row;
        end
    end
end

%{
MatlabAppClassDesigner - Native categorized section for the property inspector.
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
