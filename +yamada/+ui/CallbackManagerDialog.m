classdef CallbackManagerDialog < handle
    % CallbackManagerDialog Present callback availability and immediate action requests.
    %   The dialog owns transient controls only. Injected state and action functions
    %   keep model transactions and source rewriting outside this UI adapter.

    properties (Access = private)
        Figure matlab.ui.Figure
        MainGrid matlab.ui.container.GridLayout
        Rows matlab.ui.container.GridLayout
        Message matlab.ui.control.Label
        StateFcn function_handle
        ActionFcn function_handle
        ValidFcn function_handle
        TargetsFcn function_handle
        DefaultNameFcn function_handle
        PromptFcn function_handle
    end

    methods
        function obj = CallbackManagerDialog(targetName, stateFcn, actionFcn, validFcn, visible, reloadFcn, targetsFcn, defaultNameFcn, promptFcn)
            % CallbackManagerDialog Create a modal callback list with a fixed command layout.
            arguments (Input)
                targetName (1, 1) string
                stateFcn (1, 1) function_handle
                actionFcn (1, 1) function_handle
                validFcn (1, 1) function_handle
                visible (1, 1) logical = true
                reloadFcn (1, 1) function_handle = @() []
                targetsFcn (1, 1) function_handle = @(~) struct("Name", {}, "Label", {})
                defaultNameFcn (1, 1) function_handle = @(name) name
                promptFcn (1, 1) function_handle = @yamada.ui.CallbackManagerDialog.promptName
            end
            arguments (Output)
                obj (1, 1) yamada.ui.CallbackManagerDialog
            end

            % Bind narrow state seams before constructing disposable native controls.
            obj.StateFcn = stateFcn;
            obj.ActionFcn = actionFcn;
            obj.ValidFcn = validFcn;
            obj.TargetsFcn = targetsFcn;
            obj.DefaultNameFcn = defaultNameFcn;
            obj.PromptFcn = promptFcn;
            obj.Figure = uifigure("Name", "Callbacks: " + targetName, "Visible", "off", ...
                "WindowStyle", "modal", "Resize", "on", "Position", [300 300 380 170], ...
                "Tag", "yamada-callback-manager", "CloseRequestFcn", @(~, ~) delete(obj));
            obj.Figure.WindowKeyPressFcn = @(~, event) obj.keyPressed(event, reloadFcn);
            grid = uigridlayout(obj.Figure, [3 1], "RowHeight", {"1x", 0, 30}, "RowSpacing", 6);
            obj.MainGrid = grid;
            obj.Rows = uigridlayout(grid, [1 2], "ColumnWidth", {"fit", "1x"}, ...
                "Scrollable", "on", "RowSpacing", 6, "Padding", [0 0 0 0]);
            obj.Message = uilabel(grid, "WordWrap", "on", "Text", "", ...
                "Tag", "yamada-callback-message");
            uibutton(grid, "Text", "Close", "ButtonPushedFcn", @(~, ~) delete(obj));
            obj.refresh();
            if obj.isOpen()
                % Fit short callback lists initially and scroll longer lists without resetting user resizing.
                count = min(numel(obj.Rows.RowHeight), 8);
                obj.Figure.Position(4) = count * 32 + max(count - 1, 0) * 6 + 62;
            end
            if visible && obj.isOpen(), obj.Figure.Visible = "on"; end
        end

        function result = isOpen(obj)
            % isOpen Report whether the dialog still owns a valid figure.
            arguments (Input)
                obj (1, 1) yamada.ui.CallbackManagerDialog
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = ~isempty(obj.Figure) && isvalid(obj.Figure);
        end

        function focus(obj)
            % focus Raise the existing popup without creating a second copy.
            arguments (Input)
                obj (1, 1) yamada.ui.CallbackManagerDialog
            end
            if obj.isOpen(), figure(obj.Figure); end
        end

        function refresh(obj)
            % refresh Rebuild rows from authoritative state or close an expired target.
            arguments (Input)
                obj (1, 1) yamada.ui.CallbackManagerDialog
            end
            if ~obj.isOpen(), return, end
            if ~obj.ValidFcn(), delete(obj); return, end
            states = obj.StateFcn();
            % Reserve message space only while an action has something to report.
            messageHeight = 52 * double(strlength(obj.Message.Text) > 0);
            previousHeight = obj.MainGrid.RowHeight{2};
            obj.MainGrid.RowHeight = {"1x", messageHeight, 30};
            obj.Message.Visible = messageHeight > 0;
            if messageHeight ~= previousHeight
                obj.Figure.Position(4) = obj.Figure.Position(4) + messageHeight - previousHeight;
            end
            delete(obj.Rows.Children);
            obj.Rows.RowHeight = repmat({32}, 1, max(numel(states), 1));

            % Preserve catalog ordering and make blocked reasons available on all row controls.
            for index = 1:numel(states)
                state = states(index);
                label = uilabel(obj.Rows, "Text", state.Name, "Tooltip", state.Reason);
                label.Layout.Row = index;
                label.Layout.Column = 1;
                targets = obj.TargetsFcn(state.Name);
                items = ["<New...>", "<Disconnect>", string({targets.Label})];
                values = ["<New...>", "<Disconnect>", string({targets.Name})];
                selected = "<Disconnect>";
                if state.State ~= "absent" && state.HandlerName ~= ""
                    selected = state.HandlerName;
                    if ~any(values == selected)
                        items(end + 1) = selected + " [current; unavailable]";
                        values(end + 1) = selected;
                    end
                end
                control = uidropdown(obj.Rows, "Items", items, "ItemsData", values, ...
                    "Value", selected, "Enable", state.State ~= "unsupported", ...
                    "Tooltip", state.Reason, "Tag", "yamada-callback-target", "UserData", state.Name, ...
                    "ValueChangedFcn", @(control, ~) obj.invoke(state.Name, string(control.Value)));
                control.Layout.Row = index;
                control.Layout.Column = 2;
            end
        end

        function delete(obj)
            % delete Close the popup without altering any committed document edits.
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

        function invoke(obj, name, selection)
            % invoke Revalidate availability and dispatch one atomic action request.
            arguments (Input)
                obj (1, 1) yamada.ui.CallbackManagerDialog
                name (1, 1) string
                selection (1, 1) string
            end
            if ~obj.ValidFcn(), delete(obj); return, end
            states = obj.StateFcn();
            state = states(string({states.Name}) == name);
            if numel(state) ~= 1 || state.State == "unsupported"
                obj.refresh();
                return
            end

            % A failed command reports an error without optimistically changing button states.
            try
                handler = "";
                if selection == "<New...>"
                    handler = string(obj.PromptFcn(obj.DefaultNameFcn(name)));
                    if handler == "", obj.refresh(); return, end
                    action = "New";
                elseif selection == "<Disconnect>"
                    action = "Disconnect";
                else
                    action = "Connect";
                    handler = selection;
                end
                if ~obj.ValidFcn(), delete(obj); return, end
                message = obj.ActionFcn(name, action, handler);
            catch exception
                message = string(exception.message);
            end
            if isvalid(obj) && obj.isOpen()
                obj.Message.Text = message;
                obj.refresh();
            end
        end
    end

    methods (Static, Access = private)
        function name = promptName(defaultName)
            % promptName Ask for a method name while preserving cancellation as a no-op.
            arguments (Input)
                defaultName (1, 1) string
            end
            arguments (Output)
                name (1, 1) string
            end
            answer = inputdlg('Callback method name:', 'New callback', [1 55], {char(defaultName)});
            name = "";
            if ~isempty(answer), name = strtrim(string(answer{1})); end
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
