classdef ParentSelectionDialog < handle
    % ParentSelectionDialog Select an explicit destination for one complete subtree.
    %   The adapter owns transient controls and injected state/action callbacks.
    %   Model validation and history remain outside this dialog.

    properties (Access = private)
        Figure matlab.ui.Figure
        Table matlab.ui.control.Table
        MoveButton matlab.ui.control.Button
        Message matlab.ui.control.Label
        StateFcn function_handle
        ActionFcn function_handle
        ValidFcn function_handle
        States struct = struct([])
        SelectedId string = ""
    end

    methods
        function obj = ParentSelectionDialog(name, stateFcn, actionFcn, validFcn, visible)
            % ParentSelectionDialog Show destinations and reasons without editing the document.
            arguments (Input)
                name (1, 1) string
                stateFcn (1, 1) function_handle
                actionFcn (1, 1) function_handle
                validFcn (1, 1) function_handle
                visible (1, 1) logical = true
            end
            arguments (Output)
                obj (1, 1) macd.ui.ParentSelectionDialog
            end
            obj.StateFcn = stateFcn;
            obj.ActionFcn = actionFcn;
            obj.ValidFcn = validFcn;
            obj.Figure = uifigure("Name", "Move: " + name, "Visible", "off", ...
                "WindowStyle", "modal", "Position", [300 300 600 360], "Tag", "macd-parent-selection", ...
                "CloseRequestFcn", @(~, ~) delete(obj));
            grid = uigridlayout(obj.Figure, [3 2], "RowHeight", {"1x", 54, 30}, "ColumnWidth", {"1x", "1x"});
            obj.Table = uitable(grid, "ColumnName", {"Destination", "Available", "Reason"}, ...
                "ColumnEditable", [false false false], "ColumnWidth", {140, 70, "auto"}, ...
                "Tag", "macd-parent-destinations", "CellSelectionCallback", @(~, event) obj.selected(event));
            obj.Table.Layout.Column = [1 2];
            obj.Message = uilabel(grid, "Text", "Select a destination.", "WordWrap", "on", "Tag", "macd-parent-message");
            obj.Message.Layout.Row = 2;
            obj.Message.Layout.Column = [1 2];
            obj.MoveButton = uibutton(grid, "Text", "Move", "Enable", "off", "Tag", "macd-parent-move", ...
                "ButtonPushedFcn", @(~, ~) obj.move());
            obj.MoveButton.Layout.Row = 3;
            uibutton(grid, "Text", "Cancel", "Tag", "macd-parent-cancel", "ButtonPushedFcn", @(~, ~) delete(obj));
            try
                obj.refresh();
            catch exception
                delete(obj);
                rethrow(exception)
            end
            if visible && obj.isOpen(), obj.Figure.Visible = "on"; end
        end

        function result = isOpen(obj)
            % isOpen Report whether the native dialog figure still exists.
            arguments (Input)
                obj (1, 1) macd.ui.ParentSelectionDialog
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = ~isempty(obj.Figure) && isvalid(obj.Figure);
        end

        function focus(obj)
            % focus Raise an existing popup for the same document and target.
            arguments (Input)
                obj (1, 1) macd.ui.ParentSelectionDialog
            end
            if obj.isOpen(), figure(obj.Figure); end
        end

        function refresh(obj)
            % refresh Reload destination availability or close an expired target.
            arguments (Input)
                obj (1, 1) macd.ui.ParentSelectionDialog
            end
            if ~obj.isOpen(), return, end
            if ~obj.ValidFcn(), delete(obj); return, end
            obj.States = obj.StateFcn();
            data = cell(numel(obj.States), 3);
            for index = 1:numel(obj.States)
                state = obj.States(index);
                % The mixed-cell uitable Data schema requires character vectors for text.
                data(index, :) = {char(state.Name), state.Enabled, char(state.Reason)};
            end
            obj.Table.Data = data;
            obj.MoveButton.Enable = "off";
            if ~isempty(obj.States)
                state = obj.States(string({obj.States.Id}) == obj.SelectedId);
                if isscalar(state)
                    obj.MoveButton.Enable = state.Enabled;
                    if ~state.Enabled, obj.Message.Text = state.Reason; end
                end
            end
        end

        function delete(obj)
            % delete Release the dialog figure and transient selection state.
            arguments (Input)
                obj (1, 1) macd.ui.ParentSelectionDialog
            end
            if obj.isOpen(), delete(obj.Figure); end
        end
    end

    methods (Access = private)
        function selected(obj, event)
            % selected Resolve a table row to its stable destination identity.
            arguments (Input)
                obj (1, 1) macd.ui.ParentSelectionDialog
                event
            end
            obj.SelectedId = "";
            obj.MoveButton.Enable = "off";
            if isempty(event.Indices), return, end
            row = event.Indices(1, 1);
            if row < 1 || row > numel(obj.States), return, end
            state = obj.States(row);
            obj.SelectedId = state.Id;
            obj.MoveButton.Enable = state.Enabled;
            obj.Message.Text = state.Reason;
            if state.Enabled, obj.Message.Text = "Move the complete subtree to " + state.Name + "."; end
        end

        function move(obj)
            % move Revalidate the selected destination and close only after success.
            arguments (Input)
                obj (1, 1) macd.ui.ParentSelectionDialog
            end
            obj.refresh();
            if ~isvalid(obj) || ~obj.isOpen() || strlength(obj.SelectedId) == 0, return, end
            state = obj.States(string({obj.States.Id}) == obj.SelectedId);
            if ~isscalar(state) || ~state.Enabled, return, end
            message = obj.ActionFcn(obj.SelectedId);
            if strlength(message) == 0, delete(obj); else, obj.Message.Text = message; end
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
