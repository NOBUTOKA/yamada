classdef AxesTextSettingsDialog
    % AxesTextSettingsDialog Present one axes text object's editable details.
    %   The dialog owns native controls and delegates all edits to the document.

    methods (Static)
        function open(owner,group,snapshotFcn,commitFcn)
            % open Show a compact modal popup for the selected text object.
            arguments (Input)
                owner (1,1) matlab.ui.Figure
                group (1,1) string
                snapshotFcn (1,1) function_handle
                commitFcn (1,1) function_handle
            end

            rows = snapshotFcn();
            if isempty(rows), return, end
            display = replace(group,["XLabel","YLabel","ZLabel"],["X Label","Y Label","Z Label"]);
            position = owner.Position;
            dialog = uifigure("Name",display + " Settings","WindowStyle","modal","Visible","off", ...
                "Position",[position(1:2)+(position(3:4)-[370 250])/2 370 250], ...
                "Tag","yamada-axes-text-dialog");
            listener = addlistener(owner,"ObjectBeingDestroyed",@(~,~) delete(dialog));
            dialog.DeleteFcn = @(~,~) delete(listener);
            grid = uigridlayout(dialog,[numel(rows)+1 3]);
            grid.RowHeight = [repmat({26},1,numel(rows)),{"1x"}];
            grid.ColumnWidth = {92,"1x",32};
            labels = ["Color","Font Name","Font Size","Font Weight","Font Angle","Interpreter"];
            fields = gobjects(1,numel(rows));
            links = gobjects(1,numel(rows));
            for index = 1:numel(rows)
                label = uilabel(grid,"Text",labels(index));
                label.Layout.Row = index; label.Layout.Column = 1;
                field = yamada.ui.inspector.AxesTextSettingsDialog.createField(grid,extractAfter(rows(index).Path,"."));
                field.Layout.Row = index; field.Layout.Column = 2;
                field.Tag = "yamada-axes-detail-" + extractAfter(rows(index).Path,".");
                field.ValueChangedFcn = @(source,~) change(index,source.Value,"set");
                fields(index) = field;
                if group == "Subtitle"
                    % A pressed chain state means this field overrides the shared value.
                    link = uibutton(grid,"state","Text","🔗","Tag","yamada-subtitle-link");
                    link.Layout.Row = index; link.Layout.Column = 3;
                    link.ValueChangedFcn = @(source,~) toggle(index,source.Value);
                    links(index) = link;
                end
            end
            status = uilabel(grid,"Text","","WordWrap","on");
            status.Layout.Row = numel(rows)+1; status.Layout.Column = [1 3];
            refresh();
            dialog.Visible = "on";

            function change(index,value,action)
                % change Submit one reversible property or link change.
                message = commitFcn(rows(index).Path,value,action);
                if isvalid(dialog)
                    refresh();
                    status.Text = message;
                end
            end

            function toggle(index,override)
                % toggle Switch between shared and independently editable values.
                action = "share";
                if override, action = "override"; end
                change(index,[],action);
            end

            function refresh()
                % refresh Synchronize controls from the current authoritative selection.
                current = snapshotFcn();
                if isempty(current), delete(dialog); return, end
                for row = 1:numel(current)
                    item = current(row);
                    field = fields(row);
                    value = item.Value;
                    if isa(field,"matlab.ui.control.DropDown")
                        if ~isempty(value) && any(string(field.Items) == string(value))
                            field.Value = string(value);
                        end
                    elseif isa(field,"matlab.ui.control.NumericEditField")
                        if isnumeric(value) && isscalar(value), field.Value = value; end
                    else
                        if extractAfter(item.Path,".") == "Color" && isnumeric(value) && numel(value) == 3
                            value = "#" + string(reshape(dec2hex(round(value(:)*255),2).',1,[]));
                        end
                        if isempty(value), value = ""; end
                        field.Value = string(value);
                    end
                    if ~isa(field,"matlab.ui.control.DropDown"), field.Editable = item.Editable; end
                    field.Enable = "off";
                    if item.Editable, field.Enable = "on"; end
                    if isgraphics(links(row))
                        link = links(row);
                        link.Visible = "off";
                        if item.CanShare, link.Visible = "on"; end
                        link.Value = ~item.Shared;
                        if item.Shared
                            link.Tooltip = "Shared with Title. Click to override.";
                        else
                            link.Tooltip = "Subtitle override. Click to share with Title.";
                        end
                    end
                end
            end
        end
    end

    methods (Static, Access = private)
        function field = createField(parent,member)
            % createField Build the native input for one verified text property.
            arguments (Input)
                parent
                member (1,1) string
            end
            arguments (Output)
                field
            end
            switch member
                case "FontSize"
                    field = uieditfield(parent,"numeric","Limits",[0 Inf],"LowerLimitInclusive","off","Value",12);
                case "FontWeight"
                    field = uidropdown(parent,"Items",["normal","bold"]);
                case "FontAngle"
                    field = uidropdown(parent,"Items",["normal","italic"]);
                case "Interpreter"
                    field = uidropdown(parent,"Items",["tex","latex","none"]);
                otherwise
                    field = uieditfield(parent,"text");
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
