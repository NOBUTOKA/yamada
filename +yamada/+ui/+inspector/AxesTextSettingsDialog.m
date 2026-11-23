classdef AxesTextSettingsDialog
    % AxesTextSettingsDialog Present one axes text object's editable details.
    %   The dialog owns native controls and delegates all edits to the document.
    %   Color uses the Inspector's picker button, and FontWeight and FontAngle
    %   share one Font Style row of bold and italic toggles, as in the Inspector.

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
            members = extractAfter(string({rows.Path}),".");
            layout = yamada.ui.inspector.AxesTextSettingsDialog.layout(members);
            display = replace(group,["XLabel","YLabel","ZLabel"],["X Label","Y Label","Z Label"]);
            position = owner.Position;
            dialog = uifigure("Name",display + " Settings","WindowStyle","modal","Visible","off", ...
                "Position",[position(1:2)+(position(3:4)-[370 220])/2 370 220], ...
                "Tag","yamada-axes-text-dialog");
            listener = addlistener(owner,"ObjectBeingDestroyed",@(~,~) delete(dialog));
            dialog.DeleteFcn = @(~,~) delete(listener);
            grid = uigridlayout(dialog,[numel(layout)+1 3]);
            grid.RowHeight = [repmat({26},1,numel(layout)),{"1x"}];
            grid.ColumnWidth = {92,"1x",32};
            fields = gobjects(1,numel(rows));
            links = gobjects(1,numel(rows));
            subtitle = group == "Subtitle";

            % Build each presentation row; a Font Style row holds two members.
            for line = 1:numel(layout)
                label = uilabel(grid,"Text",layout(line).Label);
                label.Layout.Row = line; label.Layout.Column = 1;
                indices = layout(line).Indices;
                if isscalar(indices)
                    index = indices;
                    field = yamada.ui.inspector.AxesTextSettingsDialog.createField(grid,members(index));
                    field.Layout.Row = line; field.Layout.Column = 2;
                    yamada.ui.inspector.AxesTextSettingsDialog.bindField(field,members(index),@(value) change(index,value,"set"),owner);
                    fields(index) = field;
                    if subtitle
                        links(index) = linkButton(grid,index);
                        links(index).Layout.Row = line; links(index).Layout.Column = 3;
                    end
                else
                    % Adjacent bold and italic toggles, as in the Inspector's Font Style row.
                    style = uigridlayout(grid,[1 numel(indices)+1],"Padding",[0 0 0 0],"ColumnSpacing",3, ...
                        "ColumnWidth",[repmat({34},1,numel(indices)) {"1x"}]);
                    style.Layout.Row = line; style.Layout.Column = 2;
                    for item = 1:numel(indices)
                        index = indices(item);
                        field = yamada.ui.inspector.AxesTextSettingsDialog.createField(style,members(index));
                        yamada.ui.inspector.AxesTextSettingsDialog.bindField(field,members(index),@(value) change(index,value,"set"),owner);
                        fields(index) = field;
                    end
                    % One Subtitle link shares or overrides both style values together.
                    if subtitle
                        link = uibutton(grid,"state","Text","🔗","Tag","yamada-subtitle-link");
                        link.ValueChangedFcn = @(source,~) toggleGroup(indices,source.Value);
                        link.Layout.Row = line; link.Layout.Column = 3;
                        links(indices) = link;
                    end
                end
            end
            status = uilabel(grid,"Text","","WordWrap","on");
            status.Layout.Row = numel(layout)+1; status.Layout.Column = [1 3];
            refresh();
            dialog.Visible = "on";

            function link = linkButton(parent,index)
                % linkButton Create the Subtitle control that shares or overrides one Title value.
                % A pressed chain state means this field overrides the shared value.
                link = uibutton(parent,"state","Text","🔗","Tag","yamada-subtitle-link");
                link.ValueChangedFcn = @(source,~) toggle(index,source.Value);
            end

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

            function toggleGroup(indices,override)
                % toggleGroup Share or override every member of a combined row that supports it.
                current = snapshotFcn();
                if isempty(current), return, end
                action = "share";
                if override, action = "override"; end
                for index = indices
                    item = current(index);
                    if item.CanShare && item.Shared == override
                        commitFcn(rows(index).Path,[],action);
                    end
                end
                if isvalid(dialog), refresh(); end
            end

            function refresh()
                % refresh Synchronize controls from the current authoritative selection.
                current = snapshotFcn();
                if isempty(current), delete(dialog); return, end
                for row = 1:numel(current)
                    item = current(row);
                    yamada.ui.inspector.AxesTextSettingsDialog.synchronize(fields(row), ...
                        extractAfter(item.Path,"."),item.Value,item.Editable);
                end
                % A link appears only for values that Subtitle can share with a title call;
                % a combined row is overridden while any of its shareable members is.
                for row = 1:numel(current)
                    if ~isgraphics(links(row)), continue, end
                    link = links(row);
                    members = find(arrayfun(@(other) isgraphics(links(other)) && links(other) == link, 1:numel(current)));
                    if row ~= members(1), continue, end
                    shareable = current(members([current(members).CanShare]));
                    link.Visible = "off";
                    if ~isempty(shareable), link.Visible = "on"; end
                    link.Value = any(~[shareable.Shared]);
                    if link.Value
                        link.Tooltip = "Subtitle override. Click to share with Title.";
                    else
                        link.Tooltip = "Shared with Title. Click to override.";
                    end
                end
            end
        end
    end

    methods (Static, Access = private)
        function result = layout(members)
            % layout Group text members into the dialog's labeled presentation rows.
            arguments (Input)
                members (1,:) string
            end
            arguments (Output)
                result (1,:) struct
            end

            result = struct("Label",{},"Indices",{});
            labels = dictionary(["Color","FontName","FontSize","Interpreter"], ...
                ["Color","Font Name","Font Size","Interpreter"]);
            style = find(ismember(members,["FontWeight","FontAngle"]));
            for index = 1:numel(members)
                if any(style == index)
                    if index == style(1), result(end+1) = struct("Label","Font Style","Indices",style); end %#ok<AGROW>
                    continue
                end
                result(end+1) = struct("Label",labels(members(index)),"Indices",index); %#ok<AGROW>
            end
        end

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
                case "Color"
                    field = uibutton(parent,"Text","");
                case "FontSize"
                    field = uieditfield(parent,"numeric","Limits",[0 Inf],"LowerLimitInclusive","off","Value",12);
                case "FontWeight"
                    field = uibutton(parent,"state","Text","B","FontName","Times","FontWeight","bold","FontSize",16);
                case "FontAngle"
                    field = uibutton(parent,"state","Text","I","FontName","Times","FontAngle","italic","FontSize",16);
                case "Interpreter"
                    field = uidropdown(parent,"Items",["tex","latex","none"]);
                otherwise
                    field = uieditfield(parent,"text");
            end
            field.Tag = "yamada-axes-detail-" + member;
        end

        function bindField(field,member,submit,owner)
            % bindField Route one control's edit to the document as a typed value.
            arguments (Input)
                field
                member (1,1) string
                submit (1,1) function_handle
                owner (1,1) matlab.ui.Figure
            end

            switch member
                case "Color"
                    field.ButtonPushedFcn = @(source,~) pick(source);
                case "FontWeight"
                    field.ValueChangedFcn = @(source,~) submit(choice(source.Value,'bold'));
                case "FontAngle"
                    field.ValueChangedFcn = @(source,~) submit(choice(source.Value,'italic'));
                otherwise
                    field.ValueChangedFcn = @(source,~) submit(source.Value);
            end

            function value = choice(pressed,enabled)
                % choice Map a toggle state to its text value.
                value = 'normal';
                if pressed, value = enabled; end
            end

            function pick(source)
                % pick Open the native color picker from the current color.
                current = source.UserData;
                if ~isnumeric(current) || ~isequal(size(current),[1 3]), current = [0 0 0]; end
                selected = uisetcolor(current);
                if isnumeric(selected) && isequal(size(selected),[1 3]) && ...
                        all(isfinite(selected)) && all(selected >= 0) && all(selected <= 1)
                    submit(selected);
                end
                % The native picker returns focus to MATLAB; give it back to yamada and the dialog.
                yamada.ui.DialogFocus.restore(owner,ancestor(source,"figure"));
            end
        end

        function synchronize(field,member,value,editable)
            % synchronize Show one current value and its editability in its control.
            arguments (Input)
                field
                member (1,1) string
                value
                editable (1,1) logical
            end

            switch member
                case "Color"
                    % Named, hexadecimal, and RGB colors all display as a swatch.
                    rgb = [];
                    if ~isempty(value)
                        try
                            rgb = validatecolor(value);
                        catch
                            % An unsupported color stays unpainted.
                        end
                    end
                    field.UserData = rgb;
                    field.BackgroundColor = [0.94 0.94 0.94];
                    if ~isempty(rgb), field.BackgroundColor = rgb; end
                case {"FontWeight","FontAngle"}
                    enabled = "bold";
                    if member == "FontAngle", enabled = "italic"; end
                    field.Value = (ischar(value) || (isstring(value) && isscalar(value))) && ...
                        lower(string(value)) == enabled;
                case "Interpreter"
                    if ~isempty(value) && any(string(field.Items) == string(value))
                        field.Value = string(value);
                    end
                case "FontSize"
                    if isnumeric(value) && isscalar(value), field.Value = value; end
                otherwise
                    if isempty(value), value = ""; end
                    field.Value = string(value);
                    field.Editable = editable;
            end
            field.Enable = "off";
            if editable, field.Enable = "on"; end
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
