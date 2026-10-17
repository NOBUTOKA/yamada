classdef ReparentOverlayDataBuilder
    % ReparentOverlayDataBuilder Publish canvas-local destination geometry for subtree dragging.
    %   This adapter combines validated destination states with public Safe Preview
    %   geometry. It does not mutate the model or run an opened application.

    methods (Static)
        function [source, targets] = build(document, handles, canvas, id, states, revision, visibleFcn, gridFcn, boundsFcn)
            % build Describe the selected source and visible container destinations.
            arguments (Input)
                document (1, 1) macd.model.DocumentModel
                handles containers.Map
                canvas (1, 1) matlab.ui.container.Panel
                id (1, 1) string
                states struct
                revision (1, 1) double
                visibleFcn (1, 1) function_handle
                gridFcn = []
                boundsFcn = []
            end
            arguments (Output)
                source (1, 1) struct
                targets struct
            end
            source = struct("id", "", "parentId", "", "bounds", zeros(1, 4), ...
                "rowSpan", 1, "columnSpan", 1, "fillsParent", false);
            targets = struct("id", {}, "name", {}, "bounds", {}, "origin", {}, "depth", {}, ...
                "enabled", {}, "reason", {}, "grid", {});
            component = document.getComponent(id);
            if isempty(component) || id == document.RootComponentId || ~isKey(handles, char(id)), return, end
            preview = handles(char(id));
            if ~isvalid(preview) || ~isprop(preview, "Position"), return, end
            if isempty(boundsFcn)
                bounds = macd.ui.ReparentOverlayDataBuilder.bounds(preview, canvas);
            else
                bounds = boundsFcn(id);
            end
            if any(~isfinite(bounds)) || any(bounds(3:4) <= 0), return, end
            snapshot = macd.model.SubtreeSnapshot(document, id);
            subtreeIds = string({snapshot.Records.Id});
            source.id = char(id);
            source.parentId = char(component.ParentId);
            source.bounds = bounds;
            source.fillsParent = component.Factory == "uigridlayout";
            source.rowSpan = macd.ui.ReparentOverlayDataBuilder.spanSize(component, "Layout.Row");
            source.columnSpan = macd.ui.ReparentOverlayDataBuilder.spanSize(component, "Layout.Column");
            builder = macd.ui.GridLayoutOverlayDataBuilder();

            % Parent-local origins use the same public InnerPosition transform as grid geometry.
            for state = states
                parent = document.getComponent(state.Id);
                if isempty(parent) || any(subtreeIds == parent.Id) || ~visibleFcn(parent.Id), continue, end
                if ~any(parent.Factory == ["uifigure", "uipanel", "uibuttongroup", "uitab", "uitabgroup", "uigridlayout"]), continue, end
                if parent.Id == document.RootComponentId
                    rectangle = [0 0 double(canvas.Position(3:4))];
                    origin = [0 0];
                else
                    if ~isKey(handles, char(parent.Id)), continue, end
                    parentPreview = handles(char(parent.Id));
                    if ~isvalid(parentPreview) || ~isprop(parentPreview, "InnerPosition"), continue, end
                    if isempty(boundsFcn)
                        rectangle = macd.ui.ReparentOverlayDataBuilder.bounds(parentPreview, canvas);
                    else
                        rectangle = boundsFcn(parent.Id);
                    end
                    if isprop(parentPreview, "Units") && string(parentPreview.Units) ~= "pixels", continue, end
                    inner = double(parentPreview.InnerPosition);
                    position = double(parentPreview.Position);
                    origin = rectangle(1:2) + inner(1:2) - position(1:2);
                    rectangle = [origin inner(3:4)];
                end
                if any(~isfinite(rectangle)) || any(rectangle(3:4) <= 0), continue, end
                grid = struct();
                enabled = state.Enabled;
                reason = state.Reason;
                if parent.Id == component.ParentId, enabled = component.IsEditable && parent.IsEditable; end
                if parent.Factory == "uigridlayout"
                    if isempty(gridFcn)
                        grid = builder.build(document, handles, canvas, parent.Id, id, revision);
                    else
                        grid = gridFcn(parent.Id);
                    end
                    if ~grid.geometryAvailable
                        enabled = false;
                        reason = grid.readOnlyReason;
                    end
                end
                depth = 0;
                ancestor = parent;
                while strlength(ancestor.ParentId) > 0 && depth <= numel(document.Components)
                    depth = depth + 1;
                    ancestor = document.getComponent(ancestor.ParentId);
                    if isempty(ancestor), break, end
                end
                targets(end + 1) = struct("id", char(parent.Id), "name", char(parent.Name), ...
                    "bounds", rectangle, "origin", origin, "depth", depth, ...
                    "enabled", enabled, "reason", char(reason), "grid", grid); %#ok<AGROW>
            end
        end
    end

    methods (Static, Access = private)
        function rectangle = bounds(preview, canvas)
            % bounds Express public pixel geometry relative to the root preview canvas.
            arguments (Input)
                preview
                canvas (1, 1) matlab.ui.container.Panel
            end
            arguments (Output)
                rectangle (1, 4) double
            end
            rectangle = double(getpixelposition(preview, true));
            canvasRectangle = double(getpixelposition(canvas, true));
            rectangle(1:2) = rectangle(1:2) - canvasRectangle(1:2);
        end

        function count = spanSize(component, path)
            % spanSize Retain explicit grid span extent or a singleton absolute placement.
            arguments (Input)
                component (1, 1) macd.model.ComponentRecord
                path (1, 1) string
            end
            arguments (Output)
                count (1, 1) double
            end
            count = 1;
            entry = component.getProperty(path);
            if ~isempty(entry) && entry.ValueKind == "literal" && isnumeric(entry.LiteralValue) && ...
                    ~isempty(entry.LiteralValue) && numel(entry.LiteralValue) <= 2
                value = entry.LiteralValue;
                count = max(1, double(value(end) - value(1) + 1));
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
