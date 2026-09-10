classdef ActiveGridResolver
    % ActiveGridResolver Find the nearest model-owned Grid Layout for a selection.
    %   This utility separates editor canvas context from the component selection
    %   that drives the hierarchy and Property Inspector. It only walks document
    %   parent links and never inspects preview controls.
    %
    %   Example:
    %       gridId = macd.model.ActiveGridResolver.resolve(document, selectedId);

    methods (Static)
        function gridId = resolve(document, selectedComponentId)
            % resolve Return the selected component's nearest Grid Layout ancestor.
            arguments (Input)
                document (1, 1) macd.model.DocumentModel
                selectedComponentId (1, 1) string
            end
            arguments (Output)
                gridId (1, 1) string
            end

            gridId = "";
            component = document.getComponent(selectedComponentId);
            remaining = numel(document.Components);
            while ~isempty(component) && remaining > 0
                if component.Factory == "uigridlayout"
                    gridId = component.Id;
                    return
                end
                if strlength(component.ParentId) == 0
                    return
                end
                component = document.getComponent(component.ParentId);
                remaining = remaining - 1;
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
