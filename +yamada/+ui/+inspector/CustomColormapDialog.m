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
            assert(~isempty(map));
            samples = linspace(0,100,size(map,1)).';
            draft = map;
            positions = [];
            colors = [];
            selected = 1;
            acknowledgedMove = 0;

            sizePixels = [600 260];
            origin = owner.Position;
            dialog = uifigure("Name","Customize Colormap","WindowStyle","modal","Visible","off", ...
                "Position",[origin(1:2)+(origin(3:4)-sizePixels)/2 sizePixels], ...
                "Tag","yamada-custom-colormap-dialog");
            listener = addlistener(owner,"ObjectBeingDestroyed",@(~,~) delete(dialog));
            dialog.DeleteFcn = @(~,~) delete(listener);
            layout = uigridlayout(dialog,[5 1],"RowHeight",{28,"1x",28,28,26});
            names = yamada.ui.inspector.ColormapEditor.presets();
            presets = uidropdown(layout,"Items",cellstr(["Reset" names]), ...
                "Tag","yamada-colormap-dialog-preset", ...
                "ValueChangedFcn",@(source,event) resetPreset(source.Value,event.PreviousValue));
            root = fileparts(fileparts(fileparts(fileparts(mfilename("fullpath")))));
            markers = uihtml(layout,"HTMLSource",fullfile(root,"resources","ColormapMarkers.html"), ...
                "Tag","yamada-colormap-markers","HTMLEventReceivedFcn",@(~,event) handleMarker(event));
            fields = uigridlayout(layout,[1 5],"Padding",[0 0 0 0], ...
                "ColumnWidth",{"fit",80,"fit",50,"1x"});
            uilabel(fields,"Text","Position (%)");
            position = uieditfield(fields,"numeric","Limits",[0 100], ...
                "Tag","yamada-colormap-stop-position","ValueChangedFcn",@positionChanged);
            uilabel(fields,"Text","Color");
            color = uicolorpicker(fields,"Tag","yamada-colormap-stop-color", ...
                "ValueChangedFcn",@colorChanged);
            actions = uigridlayout(layout,[1 3],"Padding",[0 0 0 0], ...
                "ColumnWidth",{"1x","fit","fit"});
            cancel = uibutton(actions,"Text","Cancel","ButtonPushedFcn",@(~,~) delete(dialog));
            cancel.Layout.Column = 2;
            uibutton(actions,"Text","Apply","Tag","yamada-colormap-apply", ...
                "ButtonPushedFcn",@(~,~) apply());
            status = uilabel(layout,"WordWrap","on");
            loadMap(map);
            dialog.Visible = "on";

            function loadMap(value)
                % loadMap Reset the draft and recover the RGB slope changes of the selected map.
                draft = value;
                turns = find(any(abs(diff(value,2,1)) > eps(1),2)) + 1;
                indices = unique([1; turns; size(value,1)]);
                positions = samples(indices);
                colors = value(indices,:);
                if isscalar(positions)
                    positions = [0; 100];
                    colors = [value; value];
                end
                selected = 1;
                status.Text = "";
                refresh();
            end

            function resetPreset(choice,previous)
                % resetPreset Replace the staged RGB values and markers without editing the document.
                choice = string(choice);
                if choice == "Reset"
                    loadMap(map);
                elseif any(names == choice)
                    loadMap(feval(char(lower(choice)),size(map,1)));
                else
                    presets.Value = previous;
                end
            end

            function positionChanged(source,~)
                % positionChanged Move the marker selected at the time of entry.
                move(selected,source.Value);
            end

            function colorChanged(source,~)
                % colorChanged Recolor the marker selected at the time of entry.
                changeColor(selected,source.Value);
            end

            function refresh()
                % refresh Publish the editable marker positions and the actual staged RGB samples.
                markers.Data = struct("positions",positions.',"colors",colors,"map",draft,"selected",selected, ...
                    "acknowledgedMove",acknowledgedMove);
                position.Value = positions(selected);
                position.Editable = selected > 1 && selected < numel(positions);
                color.Value = colors(selected,:);
            end

            function handleMarker(event)
                % handleMarker Dispatch validated gestures from the HTML marker strip.
                name = string(event.HTMLEventName);
                data = event.HTMLEventData;
                if ~isstruct(data) || ~isscalar(data), return, end
                if name == "add"
                    if isfield(data,"position") && validNumber(data.position), add(data.position); end
                    return
                end
                if ~isfield(data,"index") || ~validNumber(data.index) || ...
                        data.index ~= fix(data.index) || data.index < 1 || data.index > numel(positions)
                    return
                end
                index = data.index;
                switch name
                    case "select"
                        selected = index;
                        refresh();
                    case "move"
                        if isfield(data,"sequence") && validNumber(data.sequence)
                            acknowledgedMove = data.sequence;
                        end
                        if isfield(data,"position") && validNumber(data.position), move(index,data.position); end
                    case "remove"
                        remove(index);
                    case "pickColor"
                        selected = index;
                        refresh();
                        value = pickColor(colors(index,:));
                        if isvalid(dialog) && numel(value) == 3, changeColor(index,value); end
                end
            end

            function value = pickColor(initialColor)
                % pickColor Give the desktop picker a hidden classic Figure that it can own.
                previousFigure = get(groot,"CurrentFigure");
                target = figure("Visible","off","Color",initialColor,"IntegerHandle","off");
                cleanup = onCleanup(@() restoreFigure(target,previousFigure));
                set(groot,"CurrentFigure",target);
                value = uisetcolor(target);
                clear cleanup
                % The desktop picker can activate MATLAB instead of its caller on dismissal.
                if isvalid(dialog) && dialog.Visible == "on"
                    if isvalid(owner) && owner.Visible == "on", focus(owner); end
                    focus(dialog);
                end
            end

            function restoreFigure(target,previousFigure)
                % restoreFigure Release the picker target and restore the caller's figure context.
                if isgraphics(target,"figure"), delete(target); end
                if isempty(previousFigure) || isgraphics(previousFigure,"figure")
                    set(groot,"CurrentFigure",previousFigure);
                end
            end

            function valid = validNumber(value)
                % validNumber Accept a finite real numeric scalar from a UI event.
                valid = isnumeric(value) && isscalar(value) && isreal(value) && isfinite(value);
            end

            function markCustom()
                % markCustom Allow reselecting the same preset after any staged edit.
                presets.Items = cellstr(["Custom" "Reset" names]);
                presets.Value = "Custom";
                status.Text = "";
            end

            function updateInterval(first,last)
                % updateInterval Recompute only samples between the two unchanged boundary stops.
                inside = samples >= positions(first) & samples <= positions(last);
                draft(inside,:) = interp1(positions(first:last),colors(first:last,:),samples(inside),"linear");
            end

            function move(index,value)
                % move Move an interior stop without crossing its neighbors.
                if index <= 1 || index >= numel(positions) || ...
                        value <= positions(index-1) || value >= positions(index+1)
                    status.Text = "Place the stop between its neighbors.";
                elseif value ~= positions(index)
                    markCustom();
                    selected = index;
                    positions(index) = value;
                    updateInterval(index-1,index+1);
                end
                refresh();
            end

            function changeColor(index,value)
                % changeColor Update the selected stop and its adjacent intervals.
                if ~isequal(colors(index,:),value)
                    markCustom();
                    if size(map,1) == 1
                        colors = repmat(value,numel(positions),1);
                        draft = value;
                    else
                        colors(index,:) = value;
                        updateInterval(max(1,index-1),min(numel(positions),index+1));
                    end
                end
                selected = index;
                refresh();
            end

            function add(value)
                % add Insert a stop on the current segment without changing the sampled colors.
                left = find(positions < value,1,"last");
                if isempty(left) || left == numel(positions) || positions(left+1) == value, return, end
                markCustom();
                rgb = interp1(positions(left:left+1),colors(left:left+1,:),value,"linear");
                positions = [positions(1:left); value; positions(left+1:end)];
                colors = [colors(1:left,:); rgb; colors(left+1:end,:)];
                selected = left+1;
                refresh();
            end

            function remove(index)
                % remove Delete an interior stop and reconnect its neighboring stops.
                if index == 1 || index == numel(positions), return, end
                markCustom();
                positions(index) = [];
                colors(index,:) = [];
                selected = index-1;
                updateInterval(index-1,index);
                refresh();
            end

            function apply()
                % apply Publish the staged RGB matrix once and close on success.
                if isequal(draft,map), delete(dialog); return, end
                message = commitFcn(draft);
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
