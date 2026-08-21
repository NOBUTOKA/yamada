classdef InspectorSurfaceBuilder
    % InspectorSurfaceBuilder Project atomic property states into Inspector rows.
    %   This presentation-only builder groups complete declarative templates and
    %   leaves every unmatched property as its existing one-member Inspector row.

    methods (Static)
        function rows = build(componentId, parentFactory, states, templates)
            % build Return deterministic composite and singleton Inspector row states.
            arguments (Input)
                componentId (1, 1) string
                parentFactory (1, 1) string
                states
                templates macd.model.InspectorRowDefinition = ...
                    macd.model.InspectorRowDefinition.empty
            end
            arguments (Output)
                rows (1, :) struct
            end

            paths = arrayfun(@(state) state.Definition.Path, states);
            claimed = false(1, numel(states));
            rows = repmat(macd.ui.inspector.InspectorSurfaceBuilder.emptyRow(), 1, 0);
            for templateIndex = 1:numel(templates)
                template = templates(templateIndex);
                if ~template.matches(componentId, parentFactory, paths)
                    continue
                end
                indices = zeros(1, numel(template.MemberPaths));
                for memberIndex = 1:numel(template.MemberPaths)
                    indices(memberIndex) = find(paths == template.MemberPaths(memberIndex), 1);
                end
                if any(claimed(indices))
                    error("macd:InspectorSurfaceBuilder:OverlappingRows", ...
                        "Composite Inspector row templates overlap on one effective property.");
                end
                anchorIndex = find(template.MemberPaths == template.OrderAnchor, 1);
                anchor = states(indices(anchorIndex)).Definition;
                category = anchor.Category;
                if strlength(template.CategoryId) > 0
                    anchorCategoryId = "";
                    if isfield(anchor.Metadata, "categoryId")
                        anchorCategoryId = string(anchor.Metadata.categoryId);
                    end
                    if anchorCategoryId ~= template.CategoryId
                        error("macd:InspectorSurfaceBuilder:InvalidPlacement", ...
                            "The composite row anchor does not belong to its declared category.");
                    end
                end
                row = macd.ui.inspector.InspectorSurfaceBuilder.emptyRow();
                row.Id = template.Id;
                row.DisplayName = template.DisplayName;
                row.Editor = template.Editor;
                row.Category = category;
                row.Order = anchor.Order;
                row.MemberIndices = indices;
                row.MemberPaths = template.MemberPaths;
                row.MemberRoles = template.MemberRoles;
                row.IsComposite = true;
                rows(end + 1) = row; %#ok<AGROW>
                claimed(indices) = true;
            end
            for index = 1:numel(states)
                if claimed(index)
                    continue
                end
                definition = states(index).Definition;
                row = macd.ui.inspector.InspectorSurfaceBuilder.emptyRow();
                row.Id = "property:" + definition.Path;
                row.DisplayName = definition.DisplayName;
                row.Editor = definition.Editor;
                row.Category = definition.Category;
                row.Order = definition.Order;
                row.MemberIndices = index;
                row.MemberPaths = definition.Path;
                row.MemberRoles = "value";
                row.IsComposite = false;
                rows(end + 1) = row; %#ok<AGROW>
            end
            categoryOrder = unique(arrayfun(@(state) state.Definition.Category, states), "stable");
            rows = macd.ui.inspector.InspectorSurfaceBuilder.sortRows(rows, categoryOrder);
        end
    end

    methods (Static, Access = private)
        function row = emptyRow()
            % emptyRow Return a fixed-shape projected row record.
            row = struct("Id", "", "DisplayName", "", "Editor", "", ...
                "Category", "", "Order", 0, "MemberIndices", zeros(1, 0), ...
                "MemberPaths", strings(1, 0), "MemberRoles", strings(1, 0), ...
                "IsComposite", false);
        end

        function rows = sortRows(rows, categoryOrder)
            % sortRows Preserve catalog category order while ordering each anchor numerically.
            arguments (Input)
                rows (1, :) struct
                categoryOrder (1, :) string
            end
            arguments (Output)
                rows (1, :) struct
            end

            ordered = rows([]);
            for category = categoryOrder
                members = rows(string({rows.Category}) == category);
                [~, order] = sort([members.Order]);
                ordered = [ordered, members(order)]; %#ok<AGROW>
            end
            rows = ordered;
        end
    end
end

%{
Copyright (C) 2026 Nobuto Kaitoh

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
