classdef ColormapEditor
    % ColormapEditor Display an RGB map and choose a built-in MATLAB preset.
    %   Presets are converted to literal RGB data before document editing.

    methods (Static)
        function control = create(parent, editable, commitFcn)
            % create Make a native gradient row with optional preset selection.
            arguments (Input)
                parent
                editable (1,1) logical
                commitFcn (1,1) function_handle
            end
            arguments (Output)
                control (1,1) matlab.ui.container.GridLayout
            end
            control = uigridlayout(parent,[1 1],"Padding",[0 0 0 0],"ColumnSpacing",4, ...
                "RowHeight",{"1x"},"Tag","yamada-colormap-editor");
            picker = matlab.ui.control.DropDown.empty;
            if editable
                control.RowHeight = {24, "1x"};
                control.RowSpacing = 4;
                control.ColumnWidth = {"1x"};
                picker = uidropdown(control,"Items",cellstr(yamada.ui.inspector.ColormapEditor.presets()), ...
                    "Tag","yamada-colormap-preset");
                picker.Layout.Row = 1;
            end
            strip = uiimage(control,"ScaleMethod","stretch","Tag","yamada-colormap-preview");
            if editable, strip.Layout.Row = 2; end
            control.UserData = struct("Picker",picker,"Strip",strip,"Length",256);
            yamada.ui.inspector.ColormapEditor.bind(control,commitFcn);
        end

        function bind(control, commitFcn)
            % bind Replace the row's preset commit callback.
            arguments (Input)
                control (1,1) matlab.ui.container.GridLayout
                commitFcn (1,1) function_handle
            end
            picker = control.UserData.Picker;
            if isempty(picker), return, end
            picker.ValueChangedFcn = @(source,event) ...
                yamada.ui.inspector.ColormapEditor.commit(control,source,event,commitFcn);
        end

        function synchronize(control, map, editable)
            % synchronize Show the current gradient and classify literal custom maps.
            arguments (Input)
                control (1,1) matlab.ui.container.GridLayout
                map
                editable (1,1) logical
            end
            parts = control.UserData;
            label = "Unresolved";
            if isnumeric(map) && ismatrix(map) && size(map,2) == 3 && ~isempty(map) && ...
                    isreal(map) && all(isfinite(map(:))) && all(map(:)>=0 & map(:)<=1)
                parts.Length = size(map,1);
                indices = round(linspace(1,parts.Length,128));
                pixels = uint8(round(255*map(indices,:)));
                parts.Strip.ImageSource = repmat(reshape(pixels,1,128,3),8,1,1);
                label = "Custom";
                if ~isempty(parts.Picker)
                    for preset = yamada.ui.inspector.ColormapEditor.presets()
                        expected = feval(char(lower(preset)),parts.Length);
                        if max(abs(double(map(:))-expected(:))) <= 1e-12
                            label = preset;
                            break
                        end
                    end
                end
            else
                parts.Strip.ImageSource = "";
            end
            if ~isempty(parts.Picker)
                choices = yamada.ui.inspector.ColormapEditor.presets();
                if ~any(choices == label), choices = [label choices]; end
                parts.Picker.Items = cellstr(choices);
                parts.Picker.Value = label;
                parts.Picker.Enable = editable;
            end
            control.UserData = parts;
        end
    end

    methods (Static, Access = private)
        function names = presets()
            % presets List the built-in maps offered by the editor.
            arguments (Output)
                names (1,:) string
            end
            names = ["Parula","Turbo","Gray","Hot","Cool","Bone","Copper","Pink", ...
                "Spring","Summer","Autumn","Winter","Jet","HSV","Lines","Colorcube","Prism","Flag","White"];
        end

        function commit(control, source, event, commitFcn)
            % commit Stage only an allowlisted preset and restore the picker on rejection.
            arguments (Input)
                control (1,1) matlab.ui.container.GridLayout
                source (1,1) matlab.ui.control.DropDown
                event
                commitFcn (1,1) function_handle
            end
            choice = string(source.Value);
            if ~any(yamada.ui.inspector.ColormapEditor.presets() == choice)
                source.Value = event.PreviousValue;
                return
            end
            map = feval(char(lower(choice)),control.UserData.Length);
            % The document refresh sets the accepted picker value.
            source.Value = event.PreviousValue;
            commitFcn(map);
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
