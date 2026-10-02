classdef CallbackManagerDialog < handle
    % CallbackManagerDialog Present callback availability and immediate action requests.
    %   The dialog owns transient controls only. Injected state and action functions
    %   keep model transactions and source rewriting outside this UI adapter.

    properties (Access = private)
        Figure matlab.ui.Figure
        Rows matlab.ui.container.GridLayout
        Message matlab.ui.control.Label
        StateFcn function_handle
        ActionFcn function_handle
        ValidFcn function_handle
    end

    methods
        function obj = CallbackManagerDialog(targetName, stateFcn, actionFcn, validFcn, visible, reloadFcn)
            % CallbackManagerDialog Create a modal callback list with a fixed command layout.
            arguments (Input)
                targetName (1, 1) string
                stateFcn (1, 1) function_handle
                actionFcn (1, 1) function_handle
                validFcn (1, 1) function_handle
                visible (1, 1) logical = true
                reloadFcn (1, 1) function_handle = @() []
            end
            arguments (Output)
                obj (1, 1) macd.ui.CallbackManagerDialog
            end

            % Bind narrow state seams before constructing disposable native controls.
            obj.StateFcn = stateFcn;
            obj.ActionFcn = actionFcn;
            obj.ValidFcn = validFcn;
            obj.Figure = uifigure("Name", "Callbacks: " + targetName, "Visible", "off", ...
                "WindowStyle", "modal", "Position", [300 300 520 420], ...
                "Tag", "macd-callback-manager", "CloseRequestFcn", @(~, ~) delete(obj));
            obj.Figure.WindowKeyPressFcn = @(~, event) obj.keyPressed(event, reloadFcn);
            grid = uigridlayout(obj.Figure, [3 1], "RowHeight", {"1x", 52, 30});
            obj.Rows = uigridlayout(grid, [1 3], "ColumnWidth", {"1x", 64, 64}, ...
                "Scrollable", "on", "Padding", [0 0 0 0]);
            obj.Message = uilabel(grid, "WordWrap", "on", "Text", "", ...
                "Tag", "macd-callback-message");
            uibutton(grid, "Text", "Close", "ButtonPushedFcn", @(~, ~) delete(obj));
            obj.refresh();
            if visible && obj.isOpen(), obj.Figure.Visible = "on"; end
        end

        function result = isOpen(obj)
            % isOpen Report whether the dialog still owns a valid figure.
            arguments (Input)
                obj (1, 1) macd.ui.CallbackManagerDialog
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = ~isempty(obj.Figure) && isvalid(obj.Figure);
        end

        function focus(obj)
            % focus Raise the existing popup without creating a second copy.
            arguments (Input)
                obj (1, 1) macd.ui.CallbackManagerDialog
            end
            if obj.isOpen(), figure(obj.Figure); end
        end

        function refresh(obj)
            % refresh Rebuild rows from authoritative state or close an expired target.
            arguments (Input)
                obj (1, 1) macd.ui.CallbackManagerDialog
            end
            if ~obj.isOpen(), return, end
            if ~obj.ValidFcn(), delete(obj); return, end
            states = obj.StateFcn();
            delete(obj.Rows.Children);
            obj.Rows.RowHeight = repmat({32}, 1, max(numel(states), 1));

            % Preserve catalog ordering and make blocked reasons available on all row controls.
            for index = 1:numel(states)
                state = states(index);
                label = uilabel(obj.Rows, "Text", state.Name, "Tooltip", state.Reason);
                label.Layout.Row = index;
                label.Layout.Column = 1;
                for action = ["Add", "Delete"]
                    enabled = (action == "Add" && state.State == "absent") || ...
                        (action == "Delete" && state.State == "editable");
                    button = uibutton(obj.Rows, "Text", action, "Enable", enabled, ...
                        "Tooltip", state.Reason, "Tag", "macd-callback-" + lower(action), ...
                        "UserData", state.Name, "ButtonPushedFcn", ...
                        @(~, ~) obj.invoke(state.Name, action));
                    button.Layout.Row = index;
                    button.Layout.Column = 2 + double(action == "Delete");
                end
            end
        end

        function delete(obj)
            % delete Close the popup without altering any committed document edits.
            arguments (Input)
                obj (1, 1) macd.ui.CallbackManagerDialog
            end
            if obj.isOpen(), delete(obj.Figure); end
        end
    end

    methods (Access = private)
        function keyPressed(~, event, reloadFcn)
            % keyPressed Forward an unmodified F5 to the shared saved-source reload command.
            arguments (Input)
                ~
                event
                reloadFcn (1, 1) function_handle
            end
            if strcmpi(event.Key, "f5") && isempty(event.Modifier)
                reloadFcn();
            end
        end

        function invoke(obj, name, action)
            % invoke Revalidate availability and dispatch one atomic action request.
            arguments (Input)
                obj (1, 1) macd.ui.CallbackManagerDialog
                name (1, 1) string
                action (1, 1) string
            end
            if ~obj.ValidFcn(), delete(obj); return, end
            states = obj.StateFcn();
            state = states(string({states.Name}) == name);
            if numel(state) ~= 1 || ...
                    ~(action == "Add" && state.State == "absent" || action == "Delete" && state.State == "editable")
                obj.refresh();
                return
            end

            % A failed command reports an error without optimistically changing button states.
            try
                message = obj.ActionFcn(name, action);
            catch exception
                message = string(exception.message);
            end
            if isvalid(obj) && obj.isOpen()
                obj.Message.Text = message;
                obj.refresh();
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
