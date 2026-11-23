classdef GeographicLimitsEditor
    % GeographicLimitsEditor Edit requested geographic limits inline beside their displayed extent.
    %   The adapter shows one requested latitude and longitude pair, each with
    %   the extent MATLAB currently draws in Preview. An edit to either field
    %   commits both intervals together, because geolimits takes them as one
    %   call. A field without a requested value starts from the displayed
    %   extent. The adapter never mutates document state.

    methods (Static)
        function control = create(parent, commitFcn)
            % create Allocate the two requested fields and their displayed-extent labels.
            arguments (Input)
                parent
                commitFcn (1, 1) function_handle
            end
            arguments (Output)
                control (1, 1) matlab.ui.container.Panel
            end

            % Lay out each requested field above its displayed extent.
            control = uipanel(parent, "BorderType", "none", "Tag", "yamada-geographic-limits-editor");
            grid = uigridlayout(control, [4 2], "Padding", [0 0 0 0], ...
                "ColumnWidth", {105, "1x"}, "RowHeight", {24, 18, 24, 18}, ...
                "ColumnSpacing", 4, "RowSpacing", 2);
            names = ["Latitude", "Longitude"];
            % Present each interval as its own Inspector-style row aligned with row labels.
            fields = gobjects(1, 2);
            displayed = gobjects(1, 2);
            for index = 1:2
                label = uilabel(grid, "Text", names(index) + " Limits");
                label.Layout.Row = 2*index - 1;
                label.Layout.Column = 1;
                fields(index) = uieditfield(grid, "text", ...
                    "Tag", "yamada-geographic-" + lower(names(index)));
                fields(index).Layout.Row = 2*index - 1;
                fields(index).Layout.Column = 2;
                displayed(index) = uilabel(grid, "Text", "", "FontWeight", "bold", ...
                    "Tag", "yamada-geographic-" + lower(names(index)) + "-displayed");
                displayed(index).Layout.Row = 2*index;
                displayed(index).Layout.Column = 2;
            end
            control.UserData = struct("Fields", fields, "Displayed", displayed, ...
                "NormalColor", fields(1).BackgroundColor);
            yamada.ui.inspector.GeographicLimitsEditor.bind(control, commitFcn);
        end

        function bind(control, commitFcn)
            % bind Route either field edit to one paired commit.
            arguments (Input)
                control (1, 1) matlab.ui.container.Panel
                commitFcn (1, 1) function_handle
            end

            parts = control.UserData;
            for index = 1:2
                parts.Fields(index).ValueChangedFcn = @(~, ~) ...
                    yamada.ui.inspector.GeographicLimitsEditor.commit(control, commitFcn);
            end
        end

        function synchronize(control, state, isEditable)
            % synchronize Load requested limits, falling back to the displayed extent.
            arguments (Input)
                control (1, 1) matlab.ui.container.Panel
                state
                isEditable (1, 1) logical
            end

            % Accept only the state shape the Inspector publishes for geographic axes.
            requested = [];
            displayed = [];
            if isstruct(state) && isscalar(state) && all(isfield(state, ["Requested", "Displayed"]))
                requested = state.Requested;
                displayed = state.Displayed;
            end
            parts = control.UserData;
            for index = 1:2
                field = parts.Fields(index);
                if isequal(size(requested), [2 2])
                    field.Value = yamada.source.LiteralEncoder.encode(requested(index, :));
                elseif isequal(size(displayed), [2 2])
                    field.Value = yamada.ui.inspector.GeographicLimitsEditor.format(displayed(index, :));
                else
                    field.Value = "";
                end
                field.Editable = isEditable;
                field.BackgroundColor = parts.NormalColor;
                field.Tooltip = "";
                parts.Displayed(index).Text = "";
                if isequal(size(displayed), [2 2])
                    parts.Displayed(index).Text = compose("Displayed: [%.4g %.4g]", displayed(index, 1), displayed(index, 2));
                end
            end
        end

        function value = value(control)
            % value Return both field drafts without parsing them.
            arguments (Input)
                control (1, 1) matlab.ui.container.Panel
            end
            arguments (Output)
                value (1, 2) string
            end

            parts = control.UserData;
            value = [string(parts.Fields(1).Value), string(parts.Fields(2).Value)];
        end

        function restore(control, value)
            % restore Reload both field drafts without invoking their callbacks.
            arguments (Input)
                control (1, 1) matlab.ui.container.Panel
                value
            end

            if isstring(value) && numel(value) == 2
                parts = control.UserData;
                parts.Fields(1).Value = value(1);
                parts.Fields(2).Value = value(2);
            end
        end
    end

    methods (Static, Access = private)
        function commit(control, commitFcn)
            % commit Parse both inert vectors and publish them as one requested pair.
            arguments (Input)
                control (1, 1) matlab.ui.container.Panel
                commitFcn (1, 1) function_handle
            end

            % Reject a malformed field locally; range checks belong to the source edit.
            parts = control.UserData;
            limits = zeros(2, 2);
            valid = true;
            for index = 1:2
                field = parts.Fields(index);
                [interval, safe] = yamada.source.MatlabLiteralParser.parse(string(field.Value));
                if safe && isnumeric(interval) && isreal(interval) && numel(interval) == 2 && ...
                        all(isfinite(interval))
                    limits(index, :) = reshape(double(interval), 1, 2);
                    field.BackgroundColor = parts.NormalColor;
                    field.Tooltip = "";
                else
                    valid = false;
                    field.BackgroundColor = [1 0.9 0.9];
                    field.Tooltip = "Enter two numbers, such as [10 20].";
                end
            end
            if valid
                commitFcn(limits);
            end
        end

        function text = format(interval)
            % format Render one displayed interval at default display precision.
            arguments (Input)
                interval (1, 2) double
            end
            arguments (Output)
                text (1, 1) string
            end

            text = compose("[%g %g]", interval(1), interval(2));
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
