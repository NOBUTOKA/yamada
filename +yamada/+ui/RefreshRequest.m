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
        % Changes - Optional exact component/path pairs for heterogeneous atomic updates.
        Changes struct = struct("ComponentId", {}, "Path", {})
    end
    methods
        function obj = RefreshRequest(kind, componentIds, paths, changes)
            % RefreshRequest Retain one accepted change without inspecting native UI state.
            arguments (Input)
                kind (1, 1) string {mustBeMember(kind, ["selection", "properties", "layout", "structure"])}
                componentIds string = strings(1, 0)
                paths string = strings(1, 0)
                changes struct = struct("ComponentId", {}, "Path", {})
            end
            obj.Kind = kind;
            obj.ComponentIds = reshape(componentIds, 1, []);
            obj.Paths = unique(reshape(paths, 1, []), "stable");
            obj.Changes = changes;
        end

        function paths = pathsFor(obj, id)
            % pathsFor Return the exact property subset owned by one atomic update member.
            arguments (Input)
                obj (1, 1) yamada.ui.RefreshRequest
                id (1, 1) string
            end
            arguments (Output)
                paths (1, :) string
            end
            paths = obj.Paths;
            if ~isempty(obj.Changes)
                selected = obj.Changes(string({obj.Changes.ComponentId}) == id);
                paths = reshape(string({selected.Path}), 1, []);
            end
        end

        function result = affectsGeometry(obj, document, registry, handles)
            % affectsGeometry Resolve catalog impacts against actual placement and native fit dependencies.
            arguments (Input)
                obj (1, 1) yamada.ui.RefreshRequest
                document (1, 1) yamada.model.DocumentModel
                registry (1, 1) yamada.model.ComponentRegistry
                handles containers.Map
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = obj.Kind ~= "selection";
            if obj.Kind ~= "properties" || isempty(obj.Paths) || isempty(obj.ComponentIds), return, end
            for id = obj.ComponentIds
                component = document.getComponent(id);
                if isempty(component), return, end
                parent = document.getComponent(component.ParentId);
                parentFactory = "";
                if ~isempty(parent), parentFactory = parent.Factory; end
                definitions = registry.getEffectiveProperties(component.Factory, parentFactory, component.CreationArguments);
                [found, indices] = ismember(obj.pathsFor(id), string({definitions.Path}));
                if ~all(found), return, end
                for index = indices
                    definition = definitions(index);
                    if parentFactory ~= "uigridlayout"
                        if definition.AbsoluteGeometryImpact, return, end
                    elseif ~any(definition.GridGeometryImpact == ["none", "fit"]) || ...
                            (definition.GridGeometryImpact == "fit" && ...
                            yamada.ui.RefreshRequest.hasFitDependency(document, handles, parent))
                        return
                    end
                end
            end
            result = false;
        end

    end
    methods (Static)
        function request = forChanges(changes)
            % forChanges Retain exact component/path membership without storing mutable values.
            arguments (Input)
                changes (1, :) struct
            end
            arguments (Output)
                request (1, 1) yamada.ui.RefreshRequest
            end
            pairs = struct("ComponentId", {}, "Path", {});
            for change = changes
                pairs(end + 1) = struct("ComponentId", string(change.ComponentId), "Path", string(change.Path)); %#ok<AGROW>
            end
            request = yamada.ui.RefreshRequest("properties", unique(string({pairs.ComponentId}), "stable"), ...
                unique(string({pairs.Path}), "stable"), pairs);
        end
    end
    methods (Static, Access = private)
        function result = hasFitDependency(document, handles, component)
            % hasFitDependency Retain refresh for fit ancestors and unavailable native layout inputs.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                handles containers.Map
                component (1, 1) yamada.model.ComponentRecord
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = true;
            for depth = 1:numel(document.Components)
                if component.Factory == "uigridlayout"
                    if ~isKey(handles, char(component.Id)), return, end
                    preview = handles(char(component.Id));
                    if ~isvalid(preview) || ~isa(preview, "matlab.ui.container.GridLayout"), return, end
                    for path = ["RowHeight", "ColumnWidth"]
                        tracks = preview.(path);
                        if isnumeric(tracks), continue, end
                        if ~iscell(tracks), tracks = cellstr(string(tracks)); end
                        for index = 1:numel(tracks)
                            track = tracks{index};
                            if (ischar(track) || isstring(track)) && isequal(string(track), "fit"), return, end
                        end
                    end
                end
                if strlength(component.ParentId) == 0
                    result = false;
                    return
                end
                component = document.getComponent(component.ParentId);
                if isempty(component), return, end
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
