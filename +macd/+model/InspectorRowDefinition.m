classdef InspectorRowDefinition
    % InspectorRowDefinition Describe one declarative multi-property Inspector row.
    %   This immutable value defines only the presentation overlay for one or more
    %   atomic property definitions. It never changes model validation, source
    %   ownership, or the per-property catalog contract.

    properties (SetAccess = private)
        % Id - Stable catalog identifier for the projected Inspector row.
        Id string = ""
        % DisplayName - Label shown in the Inspector.
        DisplayName string = ""
        % Editor - Allowlisted composite editor identifier.
        Editor string = ""
        % MemberPaths - Ordered member property paths represented by this row.
        MemberPaths string = strings(1, 0)
        % MemberRoles - Stable editor-facing role for each member path.
        MemberRoles string = strings(1, 0)
        % CategoryId - Optional catalog category placement; empty uses the anchor category.
        CategoryId string = ""
        % OrderAnchor - Member path that supplies the projected position.
        OrderAnchor string = ""
        % ComponentIds - Concrete component variants eligible for this row.
        ComponentIds string = strings(1, 0)
        % ParentContextIds - Optional direct-parent factories eligible for this row.
        ParentContextIds string = strings(1, 0)
    end

    methods
        function obj = InspectorRowDefinition(id, displayName, editor, memberPaths, ...
                memberRoles, categoryId, orderAnchor, componentIds, parentContextIds)
            % InspectorRowDefinition Create one validated presentation-only row template.
            arguments (Input)
                id (1, 1) string = ""
                displayName (1, 1) string = ""
                editor (1, 1) string = ""
                memberPaths (1, :) string = strings(1, 0)
                memberRoles (1, :) string = strings(1, 0)
                categoryId (1, 1) string = ""
                orderAnchor (1, 1) string = ""
                componentIds (1, :) string = strings(1, 0)
                parentContextIds (1, :) string = strings(1, 0)
            end
            arguments (Output)
                obj (1, 1) macd.model.InspectorRowDefinition
            end

            obj.Id = id;
            obj.DisplayName = displayName;
            obj.Editor = editor;
            obj.MemberPaths = memberPaths;
            obj.MemberRoles = memberRoles;
            obj.CategoryId = categoryId;
            obj.OrderAnchor = orderAnchor;
            obj.ComponentIds = componentIds(strlength(componentIds) > 0);
            obj.ParentContextIds = parentContextIds(strlength(parentContextIds) > 0);
        end

        function result = matches(obj, componentId, parentFactory, paths)
            % matches Return whether the complete row template applies to one surface.
            arguments (Input)
                obj (1, 1) macd.model.InspectorRowDefinition
                componentId (1, 1) string
                parentFactory (1, 1) string
                paths (1, :) string
            end
            arguments (Output)
                result (1, 1) logical
            end

            result = (isempty(obj.ComponentIds) || any(obj.ComponentIds == componentId)) && ...
                (isempty(obj.ParentContextIds) || any(obj.ParentContextIds == parentFactory)) && ...
                all(ismember(obj.MemberPaths, paths));
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
