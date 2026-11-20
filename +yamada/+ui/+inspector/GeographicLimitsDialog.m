classdef GeographicLimitsDialog
    % GeographicLimitsDialog Edit two requested intervals in one commit.

    methods (Static)
        function open(owner,inputs,displayed,commit)
            % open Show requested limits and a snapshot of the current rendered extent.
            arguments (Input)
                owner (1,1) matlab.ui.Figure
                inputs (1,2) string
                displayed double
                commit (1,1) function_handle
            end

            % Set up the two inputs and a read-only view of MATLAB's current extent.
            position = owner.Position;
            sizePixels = [440 194];
            dialog = uifigure(Name="Geographic Limits",WindowStyle="modal", ...
                Position=[position(1:2)+(position(3:4)-sizePixels)/2 sizePixels], ...
                Tag="yamada-geographic-limits-dialog");
            grid = uigridlayout(dialog,[5 2],RowHeight={24,24,48,22,24},ColumnWidth={"1x","2x"});
            uilabel(grid,Text="Requested Latitude");
            latitude = uieditfield(grid,"text",Value=inputs(1),Tag="yamada-geographic-latitude");
            uilabel(grid,Text="Requested Longitude");
            longitude = uieditfield(grid,"text",Value=inputs(2),Tag="yamada-geographic-longitude");
            reference = "Displayed limits unavailable";
            if isequal(size(displayed),[2 2])
                reference = compose("Displayed latitude [%g %g]\nDisplayed longitude [%g %g]", ...
                    displayed(1,1),displayed(1,2),displayed(2,1),displayed(2,2));
            end
            description = uilabel(grid,Text=reference,WordWrap="on");
            description.Layout.Column = [1 2];
            status = uilabel(grid,Text="");
            status.Layout.Column = [1 2];
            uibutton(grid,Text="Cancel",ButtonPushedFcn=@(~,~) delete(dialog));
            uibutton(grid,Text="Apply",Tag="yamada-geographic-limits-apply",ButtonPushedFcn=@(~,~) apply());

            function apply()
                % apply Parse inert vectors and publish both limits together.
                [lat,latSafe] = yamada.source.MatlabLiteralParser.parse(string(latitude.Value));
                [lon,lonSafe] = yamada.source.MatlabLiteralParser.parse(string(longitude.Value));
                if ~latSafe || ~lonSafe || ~isnumeric(lat) || ~isnumeric(lon) || ...
                        ~isvector(lat) || ~isvector(lon) || numel(lat) ~= 2 || numel(lon) ~= 2
                    status.Text = "Enter two numeric pairs, such as [10 20].";
                    return
                end
                message = commit([reshape(lat,1,2);reshape(lon,1,2)]);
                if strlength(message) == 0
                    delete(dialog);
                else
                    status.Text = message;
                end
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
