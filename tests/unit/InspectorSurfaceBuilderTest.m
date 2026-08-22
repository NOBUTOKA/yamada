classdef InspectorSurfaceBuilderTest < matlab.unittest.TestCase
    % InspectorSurfaceBuilderTest Verify declarative composite row projection.

    methods (Test)
        function projectsCompleteCompositeAndSingletonFallback(testCase)
            % projectsCompleteCompositeAndSingletonFallback Replace only complete member sets.

            states = makeStates(["Data", "ColumnName", "RowName", "Visible"], ...
                ["Table", "Table", "Table", "Interactivity"]);
            template = macd.model.InspectorRowDefinition("dataAndNames", ...
                "Data & Names", "tableData", ["Data", "ColumnName", "RowName"], ...
                ["data", "columnNames", "rowNames"], "table", "Data", "uitable", "");
            rows = macd.ui.inspector.InspectorSurfaceBuilder.build( ...
                "uitable", "uifigure", states, template);

            testCase.verifyEqual(string({rows.Id}), ["dataAndNames", "property:Visible"]);
            testCase.verifyTrue(rows(1).IsComposite);
            testCase.verifyEqual(rows(1).MemberPaths, ["Data", "ColumnName", "RowName"]);
            testCase.verifyFalse(rows(2).IsComposite);
        end

        function rejectsOverlappingTemplates(testCase)
            % rejectsOverlappingTemplates Fail before returning an ambiguous projected surface.

            states = makeStates(["Data", "ColumnName", "RowName"], ...
                ["Table", "Table", "Table"]);
            first = macd.model.InspectorRowDefinition("first", "First", "tableData", ...
                ["Data", "ColumnName"], ["data", "names"], "table", "Data", "uitable", "");
            second = macd.model.InspectorRowDefinition("second", "Second", "tableData", ...
                ["ColumnName", "RowName"], ["names", "rows"], "table", "ColumnName", "uitable", "");

            testCase.verifyError(@() macd.ui.inspector.InspectorSurfaceBuilder.build( ...
                "uitable", "uifigure", states, [first, second]), ...
                "macd:InspectorSurfaceBuilder:OverlappingRows");
        end

        function preservesCatalogCategoryOrderWhenTemplateComesFirst(testCase)
            % preservesCatalogCategoryOrderWhenTemplateComesFirst Keep core categories ahead of font templates.

            states = makeStates(["Value", "FontWeight", "FontAngle"], ...
                ["Gauge", "Font and Color", "Font and Color"]);
            template = macd.model.InspectorRowDefinition("fontStyle", ...
                "Font Style", "fontStyle", ["FontWeight", "FontAngle"], ...
                ["weight", "angle"], "", "FontWeight", "", "");
            rows = macd.ui.inspector.InspectorSurfaceBuilder.build( ...
                "uigauge-circular", "uifigure", states, template);

            testCase.verifyEqual(string({rows.Category}), ["Gauge", "Font and Color"]);
            testCase.verifyEqual(string({rows.Id}), ["property:Value", "fontStyle"]);
        end
    end
end

function states = makeStates(paths, categories)
% makeStates Construct minimal effective states for Inspector projection tests.
arguments (Input)
    paths (1, :) string
    categories (1, :) string
end
arguments (Output)
    states (1, :) struct
end

states = repmat(struct("Definition", macd.model.PropertyDefinition(), ...
    "Entry", macd.model.PropertyEntry.empty, "IsExplicit", false), 1, numel(paths));
for index = 1:numel(paths)
    metadata = struct("displayName", paths(index), "category", categories(index), ...
        "categoryId", lower(erase(categories(index), " ")), "order", index);
    states(index).Definition = macd.model.PropertyDefinition(paths(index), [], false, true, metadata);
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
