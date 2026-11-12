classdef CustomColormapDialog
    % CustomColormapDialog Stage edits to a literal RGB colormap.
    %   Changes stay in the modal dialog until Apply publishes one document edit.

    methods (Static)
        function open(owner, map, commitFcn)
            % open Show the gradient and controls for its editable color stops.
            arguments (Input)
                owner (1,1) matlab.ui.Figure
                map (:,3) double
                commitFcn (1,1) function_handle
            end
            count = size(map,1);
            assert(count > 0);
            originalSamples = linspace(0,100,max(2,count)).';
            positions = linspace(0,100,max(2,count)).';
            colors = map;
            if count == 1, colors = [map; map]; end
            added = false(size(positions));
            dirty = false;
            selected = 1;

            sizePixels = [420 330];
            origin = owner.Position;
            dialog = uifigure("Name","Edit Colormap","WindowStyle","modal","Visible","off", ...
                "Position",[origin(1:2)+(origin(3:4)-sizePixels)/2 sizePixels], ...
                "Tag","yamada-custom-colormap-dialog");
            listener = addlistener(owner,"ObjectBeingDestroyed",@(~,~) delete(dialog));
            dialog.DeleteFcn = @(~,~) delete(listener);
            layout = uigridlayout(dialog,[5 1],"RowHeight",{32,"1x",28,28,28});
            gradient = uiimage(layout,"ScaleMethod","stretch","Tag","yamada-custom-colormap-preview");
            stops = uilistbox(layout,"Tag","yamada-colormap-stops", ...
                "ValueChangedFcn",@(source,~) select(source.Value));
            fields = uigridlayout(layout,[1 4],"Padding",[0 0 0 0], ...
                "ColumnWidth",{"fit","1x","fit",50});
            uilabel(fields,"Text","Position (%)");
            position = uieditfield(fields,"numeric","Limits",[0 100], ...
                "Tag","yamada-colormap-stop-position","ValueChangedFcn",@(source,~) move(source.Value));
            uilabel(fields,"Text","Color");
            color = uicolorpicker(fields,"Tag","yamada-colormap-stop-color", ...
                "ValueChangedFcn",@(source,~) changeColor(source.Value));
            actions = uigridlayout(layout,[1 5],"Padding",[0 0 0 0], ...
                "ColumnWidth",{"fit","fit","1x","fit","fit"});
            uibutton(actions,"Text","Add Stop","Tag","yamada-colormap-add-stop", ...
                "ButtonPushedFcn",@(~,~) add());
            removeButton = uibutton(actions,"Text","Remove Stop","Tag","yamada-colormap-remove-stop", ...
                "ButtonPushedFcn",@(~,~) remove());
            cancel = uibutton(actions,"Text","Cancel","ButtonPushedFcn",@(~,~) delete(dialog));
            cancel.Layout.Column = 4;
            uibutton(actions,"Text","Apply","Tag","yamada-colormap-apply", ...
                "ButtonPushedFcn",@(~,~) apply());
            status = uilabel(layout,"WordWrap","on");
            refresh();
            dialog.Visible = "on";

            function result = interpolate()
                % interpolate Retain original samples and include newly added stops.
                samples = union(originalSamples,positions(added));
                result = interp1(positions,colors,samples,"linear");
            end

            function refresh()
                % refresh Show the current stop selection and staged gradient.
                stops.Items = cellstr(compose("%d  |  %.2f%%", (1:numel(positions)).',positions));
                stops.ItemsData = 1:numel(positions);
                stops.Value = selected;
                position.Value = positions(selected);
                color.Value = colors(selected,:);
                endpoint = selected == 1 || selected == numel(positions);
                position.Editable = ~endpoint;
                removeButton.Enable = ~endpoint;
                gradient.ImageSource = yamada.ui.inspector.ColormapEditor.gradient(interpolate());
            end

            function select(index)
                % select Switch the active stop without changing the gradient.
                selected = index;
                refresh();
            end

            function move(value)
                % move Relocate an interior stop within its neighboring interval.
                if selected > 1 && selected < numel(positions) && ...
                        value > positions(selected-1) && value < positions(selected+1)
                    dirty = dirty || positions(selected) ~= value;
                    positions(selected) = value;
                    status.Text = "";
                else
                    status.Text = "Place the stop between its neighbors.";
                end
                refresh();
            end

            function changeColor(value)
                % changeColor Set the active stop's staged RGB triplet.
                dirty = dirty || ~isequal(colors(selected,:),value);
                colors(selected,:) = value;
                status.Text = "";
                refresh();
            end

            function add()
                % add Insert an interpolated stop next to the current selection.
                left = min(selected,numel(positions)-1);
                middle = mean(positions(left:left+1));
                if middle <= positions(left) || middle >= positions(left+1), return, end
                added = [added(1:left); true; added(left+1:end)];
                positions = [positions(1:left); middle; positions(left+1:end)];
                colors = [colors(1:left,:); mean(colors(left:left+1,:),1); colors(left+1:end,:)];
                dirty = true;
                selected = left+1;
                status.Text = "";
                refresh();
            end

            function remove()
                % remove Delete an interior stop while retaining both endpoints.
                if selected == 1 || selected == numel(positions), return, end
                added(selected) = [];
                positions(selected) = [];
                colors(selected,:) = [];
                dirty = true;
                status.Text = "";
                refresh();
            end

            function apply()
                % apply Publish the staged RGB matrix once and close on success.
                if ~dirty, delete(dialog); return, end
                result = interpolate();
                if isequal(result,map), delete(dialog); return, end
                message = commitFcn(result);
                if ~isvalid(dialog), return, end
                if message == "", delete(dialog); else, status.Text = message; end
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
