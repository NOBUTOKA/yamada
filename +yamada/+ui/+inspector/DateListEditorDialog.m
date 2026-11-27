classdef DateListEditorDialog < yamada.ui.inspector.PropertyEditDialog
    % DateListEditorDialog Edit a draft list of disabled calendar dates.
    %   This editor keeps a column datetime vector local until Apply. It uses
    %   native date controls, so no locale-formatted date text is parsed.
    %   PropertyEditDialog owns Apply, Cancel, and the commit.
    %
    %   Example:
    %       editor = yamada.ui.inspector.DateListEditorDialog(dates, "DisabledDates");
    %       dialog = yamada.ui.inspector.PropertyEditDialog.show(editor, commitFcn);

    properties (Access = private)
        % Path - Property path that receives the date list.
        Path string = ""
        % Dates - Normalized draft date column.
        Dates datetime = datetime.empty(0, 1)
        % ListPanel - Scrollable panel that holds the date rows.
        ListPanel matlab.ui.container.Panel = matlab.ui.container.Panel.empty
    end

    methods
        function obj = DateListEditorDialog(initialValue, path)
            % DateListEditorDialog Prepare a date-list draft for one property path.
            arguments (Input)
                initialValue datetime
                path (1, 1) string
            end
            arguments (Output)
                obj (1, 1) yamada.ui.inspector.DateListEditorDialog
            end

            dates = yamada.ui.inspector.DateListEditorDialog.normalize(initialValue);
            spec = struct("Name", "Edit disabled dates", ...
                "Tag", "yamada-inspector-date-list-dialog", "Position", [300 300 360 330], ...
                "ContentHeight", "1x", "AlertTitle", "Invalid dates", ...
                "ApplyTag", "yamada-inspector-date-list-apply", ...
                "CancelTag", "yamada-inspector-date-list-cancel");
            obj@yamada.ui.inspector.PropertyEditDialog(spec, ...
                yamada.model.PropertyTransaction(path, {dates}));
            obj.Path = path;
            obj.Dates = dates;
        end
    end

    methods (Access = protected)
        function buildContent(obj, content)
            % buildContent Create the scrollable panel of date rows.
            arguments (Input)
                obj (1, 1) yamada.ui.inspector.DateListEditorDialog
                content (1, 1) matlab.ui.container.GridLayout
            end

            obj.ListPanel = uipanel(content, "BorderType", "line", ...
                "Tag", "yamada-inspector-date-list-values");
            obj.ListPanel.Scrollable = "on";
            obj.ListPanel.AutoResizeChildren = "off";
            obj.ListPanel.SizeChangedFcn = @(~, ~) obj.refreshRows();
            obj.refreshRows();
        end

        function actions = editorActions(obj)
            % editorActions Offer Clear beside the shared Cancel and Apply.
            arguments (Input)
                obj (1, 1) yamada.ui.inspector.DateListEditorDialog
            end
            arguments (Output)
                actions struct
            end

            actions = struct("Text", "Clear", "Tag", "yamada-inspector-date-list-clear", ...
                "Callback", @(~, ~) obj.clearDates());
        end

        function [transaction, message] = read(obj, transaction)
            % read Stage the complete date draft for the single commit.
            arguments (Input)
                obj (1, 1) yamada.ui.inspector.DateListEditorDialog
                transaction (1, 1) yamada.model.PropertyTransaction
            end
            arguments (Output)
                transaction (1, 1) yamada.model.PropertyTransaction
                message (1, 1) string
            end

            transaction.stage(obj.Path, obj.Dates);
            message = "";
        end
    end

    methods (Access = private)
        function addDate(obj)
            % addDate Insert one editable, nonduplicate calendar date into the local draft.
            arguments (Input)
                obj (1, 1) yamada.ui.inspector.DateListEditorDialog
            end

            candidate = yamada.ui.inspector.DateListEditorDialog.nextSuggestedDate(obj.Dates);
            obj.Dates = yamada.ui.inspector.DateListEditorDialog.normalize([obj.Dates; candidate]);
            obj.refreshRows();
        end

        function deleteDate(obj, source)
            % deleteDate Remove one draft row without changing the document.
            arguments (Input)
                obj (1, 1) yamada.ui.inspector.DateListEditorDialog
                source (1, 1) matlab.ui.control.Button
            end

            obj.Dates(source.UserData) = [];
            obj.Dates = reshape(obj.Dates, [], 1);
            obj.refreshRows();
        end

        function changeDate(obj, source)
            % changeDate Replace one draft date and retain the documented normalized order.
            arguments (Input)
                obj (1, 1) yamada.ui.inspector.DateListEditorDialog
                source (1, 1) matlab.ui.control.DatePicker
            end

            index = source.UserData;
            candidate = source.Value;
            if isnat(candidate)
                source.Value = obj.Dates(index);
                return
            end
            obj.Dates(index) = candidate;
            obj.Dates = yamada.ui.inspector.DateListEditorDialog.normalize(obj.Dates);
            obj.refreshRows();
        end

        function clearDates(obj)
            % clearDates Stage the documented empty column vector until Apply.
            arguments (Input)
                obj (1, 1) yamada.ui.inspector.DateListEditorDialog
            end

            obj.Dates = datetime.empty(0, 1);
            obj.refreshRows();
        end

        function refreshRows(obj)
            % refreshRows Rebuild native date rows from the dialog-owned draft only.
            arguments (Input)
                obj (1, 1) yamada.ui.inspector.DateListEditorDialog
            end

            % Size the row content to the panel so it scrolls once rows exceed the viewport.
            delete(obj.ListPanel.Children);
            panelPosition = getpixelposition(obj.ListPanel, true);
            rowCount = numel(obj.Dates) + 1;
            contentHeight = max(6 + 33 * rowCount, panelPosition(4) + 1);
            contentWidth = max(panelPosition(3) - 18, 1);
            content = uipanel(obj.ListPanel, "BorderType", "none", ...
                "Position", [1 1 contentWidth contentHeight]);
            rows = uigridlayout(content, [rowCount 2], "Padding", [3 3 3 3], ...
                "RowSpacing", 3, "ColumnSpacing", 6, ...
                "ColumnWidth", {"1x", 30}, ...
                "RowHeight", repmat({30}, 1, rowCount));

            % Add one picker and delete button per date, then the add button.
            for index = 1:numel(obj.Dates)
                picker = uidatepicker(rows, "Value", obj.Dates(index), ...
                    "Tag", "yamada-inspector-date-list-row-picker", ...
                    "ValueChangedFcn", @(source, ~) obj.changeDate(source));
                picker.UserData = index;
                picker.Layout.Row = index;
                remove = uibutton(rows, "Text", "−", "FontColor", [0.8 0 0], ...
                    "FontSize", 18, "FontWeight", "bold", ...
                    "Tag", "yamada-inspector-date-list-delete", ...
                    "ButtonPushedFcn", @(source, ~) obj.deleteDate(source));
                remove.UserData = index;
                remove.Layout.Row = index;
                remove.Layout.Column = 2;
            end
            add = uibutton(rows, "Text", "+", "FontColor", [0 0.55 0], ...
                "FontSize", 18, "FontWeight", "bold", ...
                "Tag", "yamada-inspector-date-list-add", ...
                "ButtonPushedFcn", @(~, ~) obj.addDate());
            add.Layout.Row = rowCount;
        end
    end

    methods (Static, Access = private)
        function value = normalize(value)
            % normalize Canonicalize a nonmissing date list as one sorted unique column vector.
            arguments (Input)
                value datetime
            end
            arguments (Output)
                value datetime
            end

            value = reshape(value, [], 1);
            value = value(~isnat(value));
            if isempty(value)
                value = datetime.empty(0, 1);
                return
            end
            value.TimeZone = "";
            value = dateshift(value, "start", "day");
            value = unique(value, "sorted");
        end

        function result = labels(value)
            % labels Render lossless date-only list labels for selection and deletion.
            arguments (Input)
                value datetime
            end
            arguments (Output)
                result string
            end

            result = string(value, "yyyy-MM-dd");
        end

        function result = nextSuggestedDate(value)
            % nextSuggestedDate Choose a visible new date without duplicating the current draft.
            arguments (Input)
                value datetime
            end
            arguments (Output)
                result (1, 1) datetime
            end

            result = dateshift(datetime("today"), "start", "day");
            if ~isempty(value) && result <= value(end)
                result = value(end) + caldays(1);
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
