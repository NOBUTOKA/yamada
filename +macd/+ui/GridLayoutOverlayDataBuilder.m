classdef GridLayoutOverlayDataBuilder
    % GridLayoutOverlayDataBuilder Build safe, geometry-backed grid overlay payloads.
    %   This utility combines model-owned IDs and literal placement data with
    %   public pixel geometry from editor-owned preview controls. It does not
    %   mutate a document, execute source code, or rely on MATLAB internals.
    %
    %   Example:
    %       data = builder.build(document, handles, panel, gridId, selectedId, 1);

    methods
        function data = build(~, document, previewHandles, previewPanel, ...
                activeGridId, selectedComponentId, revision)
            % build Return one versioned overlay payload for the active Grid Layout.
            arguments (Input)
                ~
                document (1, 1) macd.model.DocumentModel
                previewHandles containers.Map
                previewPanel
                activeGridId (1, 1) string
                selectedComponentId (1, 1) string
                revision (1, 1) double
            end
            arguments (Output)
                data (1, 1) struct
            end

            data = macd.ui.GridLayoutOverlayDataBuilder.emptyData(revision, activeGridId);
            grid = document.getComponent(activeGridId);
            if isempty(grid) || grid.Factory ~= "uigridlayout" || ...
                    ~isKey(previewHandles, char(activeGridId))
                data.readOnlyReason = "The selected Grid Layout is not available in Safe Preview.";
                return
            end
            preview = previewHandles(char(activeGridId));
            if ~isvalid(preview) || ~isa(preview, "matlab.ui.container.GridLayout")
                data.readOnlyReason = "The selected Grid Layout preview is unavailable.";
                return
            end

            [outerBounds, innerBounds, geometryMessage] = ...
                macd.ui.GridLayoutOverlayDataBuilder.gridBounds(preview, previewPanel);
            if strlength(geometryMessage) > 0
                data.readOnlyReason = geometryMessage;
                return
            end
            data.outerBounds = outerBounds;
            data.innerBounds = innerBounds;

            [rowValue, rowEditable, rowReason] = ...
                macd.ui.GridLayoutOverlayDataBuilder.trackValue(grid, preview, "RowHeight");
            [columnValue, columnEditable, columnReason] = ...
                macd.ui.GridLayoutOverlayDataBuilder.trackValue(grid, preview, "ColumnWidth");
            if strlength(rowReason) > 0 || strlength(columnReason) > 0
                data.readOnlyReason = macd.ui.GridLayoutOverlayDataBuilder.joinMessages( ...
                    [rowReason columnReason]);
                return
            end
            rowTracks = macd.model.GridTrackList.describe(rowValue);
            columnTracks = macd.model.GridTrackList.describe(columnValue);
            data.rowTracks = macd.ui.GridLayoutOverlayDataBuilder.decorateTracks( ...
                rowTracks, rowEditable);
            data.columnTracks = macd.ui.GridLayoutOverlayDataBuilder.decorateTracks( ...
                columnTracks, columnEditable);

            [rowBounds, rowMessage] = macd.ui.GridLayoutOverlayDataBuilder.trackBounds( ...
                rowTracks, innerBounds, double(preview.RowSpacing), true);
            [columnBounds, columnMessage] = macd.ui.GridLayoutOverlayDataBuilder.trackBounds( ...
                columnTracks, innerBounds, double(preview.ColumnSpacing), false);
            if strlength(rowMessage) > 0 || strlength(columnMessage) > 0
                data.readOnlyReason = macd.ui.GridLayoutOverlayDataBuilder.joinMessages( ...
                    [rowMessage columnMessage]);
                return
            end
            data.rowBoundaries = rowBounds;
            data.columnBoundaries = columnBounds;
            for index = 1:size(rowBounds, 1)
                data.rowTracks(index).bounds = rowBounds(index, :);
            end
            for index = 1:size(columnBounds, 1)
                data.columnTracks(index).bounds = columnBounds(index, :);
            end
            data.editable = grid.IsEditable && rowEditable && columnEditable;
            data.children = macd.ui.GridLayoutOverlayDataBuilder.children( ...
                document, previewHandles, previewPanel, grid, selectedComponentId);
        end
    end

    methods (Static, Access = private)
        function data = emptyData(revision, activeGridId)
            % emptyData Create a JSON-safe payload when no editable geometry is available.
            data = struct("revision", revision, "activeGridId", char(activeGridId), ...
                "editable", false, "readOnlyReason", "", ...
                "outerBounds", zeros(1, 4), "innerBounds", zeros(1, 4), ...
                "rowBoundaries", zeros(0, 4), "columnBoundaries", zeros(0, 4), ...
                "rowTracks", macd.ui.GridLayoutOverlayDataBuilder.emptyTracks(), ...
                "columnTracks", macd.ui.GridLayoutOverlayDataBuilder.emptyTracks(), ...
                "children", macd.ui.GridLayoutOverlayDataBuilder.emptyChildren());
        end

        function tracks = emptyTracks()
            % emptyTracks Return a consistently shaped empty track collection.
            tracks = struct("index", {}, "kind", {}, "value", {}, "label", {}, ...
                "editable", {}, "bounds", {});
        end

        function children = emptyChildren()
            % emptyChildren Return a consistently shaped empty immediate-child collection.
            children = struct("id", {}, "rowStart", {}, "rowEnd", {}, ...
                "columnStart", {}, "columnEnd", {}, "bounds", {}, ...
                "placementMode", {}, "selected", {}, "editable", {});
        end

        function message = joinMessages(messages)
            % joinMessages Join only populated validation messages.
            arguments (Input)
                messages string
            end
            arguments (Output)
                message (1, 1) string
            end

            message = strjoin(messages(strlength(messages) > 0), " ");
        end

        function [outerBounds, innerBounds, message] = gridBounds(preview, previewPanel)
            % gridBounds Convert public GridLayout bounds into preview-panel pixels.
            outerBounds = zeros(1, 4);
            innerBounds = zeros(1, 4);
            message = "";
            try
                outerPosition = double(getpixelposition(preview, true));
                panelPosition = double(getpixelposition(previewPanel, true));
                innerPosition = double(preview.InnerPosition);
            catch
                message = "Grid geometry is not available yet.";
                return
            end
            outerBounds = outerPosition;
            outerBounds(1:2) = outerBounds(1:2) - panelPosition(1:2);
            if any(~isfinite([outerBounds innerPosition])) || any(outerBounds(3:4) <= 0) || ...
                    any(innerPosition(3:4) <= 0)
                message = "Grid geometry is not available yet.";
                return
            end
            innerBounds = [outerBounds(1:2) + innerPosition(1:2) - 1, innerPosition(3:4)];
        end

        function [value, editable, reason] = trackValue(grid, preview, path)
            % trackValue Select a literal model value or the Safe Preview default.
            value = [];
            editable = grid.IsEditable;
            reason = "";
            entry = grid.getProperty(path);
            if ~isempty(entry)
                if entry.ValueKind ~= "literal" || ~entry.IsEditable
                    editable = false;
                    reason = path + " is source-backed and cannot be edited safely.";
                    return
                end
                value = entry.LiteralValue;
            else
                value = preview.(char(path));
            end
            message = macd.model.GridTrackList.validate(value);
            if strlength(message) > 0
                editable = false;
                reason = path + " is not a supported literal: " + message;
            end
        end

        function tracks = decorateTracks(descriptions, editable)
            % decorateTracks Add stable indices and canvas-editability to normalized tokens.
            tracks = macd.ui.GridLayoutOverlayDataBuilder.emptyTracks();
            for index = 1:numel(descriptions)
                tracks(end + 1) = struct("index", index, ...
                    "kind", char(descriptions(index).kind), ...
                    "value", descriptions(index).value, ...
                    "label", char(descriptions(index).label), ...
                    "editable", editable, "bounds", zeros(1, 4)); %#ok<AGROW>
            end
        end

        function [bounds, message] = trackBounds(tracks, innerBounds, spacing, rows)
            % trackBounds Reconstruct fixed and weighted track rectangles from public geometry.
            bounds = zeros(0, 4);
            message = "";
            if ~isfinite(spacing) || spacing < 0
                message = "Grid spacing is not available for boundary reconstruction.";
                return
            end
            if any(string({tracks.kind}) == "fit")
                message = "Fit track boundaries are locked until their realized geometry is unambiguous.";
                return
            end
            if rows
                available = innerBounds(4);
            else
                available = innerBounds(3);
            end
            sizes = zeros(1, numel(tracks));
            fixed = 0;
            weights = 0;
            for index = 1:numel(tracks)
                if tracks(index).kind == "fixed"
                    fixed = fixed + tracks(index).value;
                    sizes(index) = tracks(index).value;
                else
                    weights = weights + tracks(index).value;
                end
            end
            remaining = available - fixed - spacing * max(numel(tracks) - 1, 0);
            if remaining < -eps(max(available, 1))
                message = "Track sizes exceed the realized grid interior.";
                return
            end
            if weights > 0
                for index = 1:numel(tracks)
                    if tracks(index).kind == "flexible"
                        sizes(index) = max(remaining, 0) * tracks(index).value / weights;
                    end
                end
            elseif any(string({tracks.kind}) == "flexible")
                message = "Flexible track boundaries are ambiguous because their total weight is zero.";
                return
            end

            bounds = zeros(numel(tracks), 4);
            if rows
                top = innerBounds(2) + innerBounds(4);
                for index = 1:numel(tracks)
                    top = top - sizes(index);
                    bounds(index, :) = [innerBounds(1), top, innerBounds(3), sizes(index)];
                    top = top - spacing;
                end
            else
                left = innerBounds(1);
                for index = 1:numel(tracks)
                    bounds(index, :) = [left, innerBounds(2), sizes(index), innerBounds(4)];
                    left = left + sizes(index) + spacing;
                end
            end
        end

        function children = children(document, previewHandles, previewPanel, grid, selectedComponentId)
            % children Publish realized bounds and literal placement of immediate grid children.
            children = macd.ui.GridLayoutOverlayDataBuilder.emptyChildren();
            for index = 1:numel(grid.Children)
                child = document.getComponent(grid.Children(index));
                if isempty(child) || ~isKey(previewHandles, char(child.Id))
                    continue
                end
                preview = previewHandles(char(child.Id));
                if ~isvalid(preview)
                    continue
                end
                [bounds, message] = macd.ui.GridLayoutOverlayDataBuilder.childBounds( ...
                    preview, previewPanel);
                if strlength(message) > 0
                    continue
                end
                [rowStart, rowEnd, rowMode, rowEditable] = ...
                    macd.ui.GridLayoutOverlayDataBuilder.coordinate(child, "Layout.Row");
                [columnStart, columnEnd, columnMode, columnEditable] = ...
                    macd.ui.GridLayoutOverlayDataBuilder.coordinate(child, "Layout.Column");
                mode = rowMode;
                if rowMode ~= columnMode
                    mode = "mixed";
                end
                children(end + 1) = struct("id", char(child.Id), ...
                    "rowStart", rowStart, "rowEnd", rowEnd, ...
                    "columnStart", columnStart, "columnEnd", columnEnd, ...
                    "bounds", bounds, "placementMode", char(mode), ...
                    "selected", child.Id == selectedComponentId, ...
                    "editable", child.IsEditable && rowEditable && columnEditable); %#ok<AGROW>
            end
        end

        function [bounds, message] = childBounds(preview, previewPanel)
            % childBounds Convert one realized child rectangle into preview-panel pixels.
            bounds = zeros(1, 4);
            message = "";
            try
                bounds = double(getpixelposition(preview, true));
                panelPosition = double(getpixelposition(previewPanel, true));
                bounds(1:2) = bounds(1:2) - panelPosition(1:2);
            catch
                message = "Child geometry is not available yet.";
                return
            end
            if any(~isfinite(bounds)) || any(bounds(3:4) <= 0)
                message = "Child geometry is not available yet.";
            end
        end

        function [start, finish, mode, editable] = coordinate(component, path)
            % coordinate Extract one explicit scalar or span without materializing implicit placement.
            start = 0;
            finish = 0;
            mode = "implicit";
            editable = false;
            entry = component.getProperty(path);
            if isempty(entry)
                return
            end
            if entry.ValueKind ~= "literal" || ~entry.IsEditable || ...
                    ~isnumeric(entry.LiteralValue) || ~isvector(entry.LiteralValue) || ...
                    isempty(entry.LiteralValue) || numel(entry.LiteralValue) > 2 || ...
                    any(~isfinite(entry.LiteralValue)) || any(entry.LiteralValue < 1) || ...
                    any(entry.LiteralValue ~= floor(entry.LiteralValue))
                mode = "locked";
                return
            end
            values = double(entry.LiteralValue);
            start = values(1);
            finish = values(end);
            mode = "explicit";
            editable = true;
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
