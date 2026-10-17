classdef RefreshRequest
    % RefreshRequest Describe the authoritative edit that invalidated editor views.
    %   Requests distinguish selection, values, geometry, and hierarchy changes.
    %   An absent or unsupported incremental request uses the full rebuild path.
    properties (SetAccess = private)
        % Kind - Selection, properties, layout, or structure update category.
        Kind string
        % ComponentIds - Stable identities directly affected by the command.
        ComponentIds string
        % Paths - Properties explicitly accepted in the atomic command.
        Paths string
    end
    methods
        function obj = RefreshRequest(kind, componentIds, paths)
            % RefreshRequest Retain one accepted change without inspecting native UI state.
            arguments (Input)
                kind (1, 1) string {mustBeMember(kind, ["selection", "properties", "layout", "structure"])}
                componentIds string = strings(1, 0)
                paths string = strings(1, 0)
            end
            obj.Kind = kind;
            obj.ComponentIds = reshape(componentIds, 1, []);
            obj.Paths = unique(reshape(paths, 1, []), "stable");
        end

        function result = affectsGeometry(obj)
            % affectsGeometry Include native fit sizing even for independently stored font values.
            arguments (Input)
                obj (1, 1) macd.ui.RefreshRequest
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = any(obj.Kind == ["layout", "structure"]) || ...
                any(startsWith(obj.Paths, "Layout.")) || any(ismember(obj.Paths, ...
                ["Position", "InnerPosition", "OuterPosition", "Units", "Text", "FontSize", ...
                "FontName", "FontWeight", "FontAngle", "WordWrap", "Visible", "Padding", ...
                "RowSpacing", "ColumnSpacing", "RowHeight", "ColumnWidth"]));
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
