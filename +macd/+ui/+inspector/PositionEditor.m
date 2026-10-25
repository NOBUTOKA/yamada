classdef PositionEditor
    % PositionEditor Present one inline Position row with four numeric fields.
    %   Linked sizes share the model constraint and commit one complete vector.
    %   The adapter retains rejected drafts and never mutates document state.

    methods (Static)
        function control = create(parent, definition, commitFcn)
            % create Allocate four ordered fields and two aspect-link indicators.
            arguments (Input)
                parent
                definition (1, 1) macd.model.PropertyDefinition
                commitFcn (1, 1) function_handle
            end
            arguments (Output)
                control (1, 1) matlab.ui.container.Panel
            end
            control = uipanel(parent, "BorderType", "none", "Tag", "macd-inspector-position-editor");
            grid = uigridlayout(control, [4 3], "Padding", [0 0 0 0], ...
                "ColumnWidth", {16, "1x", 20}, "RowHeight", {24, 24, 24, 24}, ...
                "ColumnSpacing", 4, "RowSpacing", 2);
            fields = matlab.ui.control.NumericEditField.empty;
            names = ["X", "Y", "Width", "Height"];
            headings = ["X", "Y", "W", "H"];
            fieldLabels = matlab.ui.control.Label.empty;
            for index = 1:4
                label = uilabel(grid, "Text", headings(index), "Tooltip", names(index), ...
                    "Tag", "macd-inspector-position-label", "HorizontalAlignment", "center");
                label.Layout.Row = index;
                label.Layout.Column = 1;
                fieldLabels(end + 1) = label; %#ok<AGROW>
                field = uieditfield(grid, "numeric", "Tooltip", names(index), ...
                    "Tag", "macd-inspector-position-field", "ValueDisplayFormat", "%.6g");
                field.Layout.Row = index;
                field.Layout.Column = 2;
                field.Limits = [-realmax realmax];
                if index > 2, field.Limits = [0 realmax]; end
                fields(end + 1) = field; %#ok<AGROW>
            end
            % Keep both corner glyphs inside the fixed-height rows without clipping.
            links = matlab.ui.control.Label.empty;
            for index = 1:2
                label = uilabel(grid, "Text", "", "Tooltip", "Width and height are linked", ...
                    "Tag", "macd-inspector-position-link", "HorizontalAlignment", "center", "FontSize", 14);
                label.Layout.Row = index + 2;
                label.Layout.Column = 3;
                links(end + 1) = label; %#ok<AGROW>
            end
            control.UserData = struct("Fields", fields, "FieldLabels", fieldLabels, "Links", links, ...
                "Policy", definition.Application.EffectPolicy, "Value", zeros(1, 4), ...
                "Constraint", macd.model.PositionGeometry.constraint("none"), "Editable", false);
            macd.ui.inspector.PositionEditor.bind(control, commitFcn);
        end

        function bind(control, commitFcn)
            % bind Replace field callbacks when the owning Inspector row is rebound.
            arguments (Input)
                control (1, 1) matlab.ui.container.Panel
                commitFcn (1, 1) function_handle
            end
            state = control.UserData;
            for index = 1:4
                state.Fields(index).ValueChangedFcn = @(source, ~) ...
                    macd.ui.inspector.PositionEditor.commit(control, index, source.Value, commitFcn);
            end
        end

        function synchronize(control, value, editable, related)
            % synchronize Display one effective rectangle and its current orientation constraints.
            arguments (Input)
                control (1, 1) matlab.ui.container.Panel
                value
                editable (1, 1) logical
                related (1, 1) struct = struct()
            end
            orientation = "";
            known = false;
            if all(isfield(related, ["Paths", "Values", "KnownValues"]))
                index = find(string(related.Paths) == "Orientation", 1);
                if ~isempty(index) && related.KnownValues(index)
                    orientation = string(related.Values{index});
                    known = isscalar(orientation);
                end
            end
            state = control.UserData;
            state.Constraint = macd.model.PositionGeometry.constraint(state.Policy, orientation, known);
            valid = macd.model.PositionGeometry.valid(value);
            state.Editable = editable && valid && state.Constraint.Known;
            if valid, state.Value = reshape(double(value), 1, 4); end
            names = ["X", "Y", "Width", "Height"];
            for index = 1:4
                field = state.Fields(index);
                field.Value = state.Value(index);
                field.Editable = matlab.lang.OnOffSwitchState(state.Editable && index ~= state.Constraint.FixedIndex);
                field.Tooltip = names(index);
                if index == state.Constraint.FixedIndex, field.Tooltip = names(index) + " (fixed)"; end
            end
            linked = state.Constraint.Known && ~isnan(state.Constraint.Ratio);
            glyphs = ["┓", "┛"];
            for index = 1:2
                state.Links(index).Text = "";
                state.Links(index).Visible = matlab.lang.OnOffSwitchState(linked);
                if linked, state.Links(index).Text = glyphs(index); end
            end
            control.UserData = state;
        end

        function value = value(control)
            % value Read all four native field values for draft preservation.
            arguments (Input)
                control (1, 1) matlab.ui.container.Panel
            end
            arguments (Output)
                value (1, 4) double
            end
            fields = control.UserData.Fields;
            value = [fields.Value];
        end

        function restore(control, value)
            % restore Restore an uncommitted rectangle without firing native callbacks.
            arguments (Input)
                control (1, 1) matlab.ui.container.Panel
                value (1, 4) double {mustBeFinite}
            end
            state = control.UserData;
            state.Value = value;
            for index = 1:4, state.Fields(index).Value = value(index); end
            control.UserData = state;
        end
    end

    methods (Static, Access = private)
        function commit(control, index, number, commitFcn)
            % commit Update linked fields locally and send one atomic Position request.
            arguments (Input)
                control (1, 1) matlab.ui.container.Panel
                index (1, 1) double
                number (1, 1) double
                commitFcn (1, 1) function_handle
            end
            state = control.UserData;
            if ~state.Editable || index == state.Constraint.FixedIndex, return, end
            value = macd.model.PositionGeometry.edit(state.Value, index, number, state.Constraint);
            macd.ui.inspector.PositionEditor.restore(control, value);
            commitFcn(value);
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
