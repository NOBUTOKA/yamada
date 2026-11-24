classdef AspectRatioOverride
    % AspectRatioOverride Explain when MATLAB ignores a manual plot box aspect ratio.
    %   A manual DataAspectRatio together with two or more manual axis limits
    %   fixes the plot box shape, so MATLAB replaces a manual PlotBoxAspectRatio
    %   while its mode stays manual. The Inspector marks that row instead of
    %   refusing the edits that lead to it. Verified on R2023a through R2026b.
    %
    %   Example:
    %       message = yamada.ui.inspector.AspectRatioOverride.message(members);

    methods (Static)
        function text = message(members)
            % message Return why the plot box ratio has no effect, or an empty string.
            arguments (Input)
                members (1, :) struct
            end
            arguments (Output)
                text (1, 1) string
            end

            % Only known modes take part; an unknown mode never asserts an override.
            text = "";
            mode = @(path) yamada.ui.inspector.AspectRatioOverride.knownMode(members, path);
            if mode("PlotBoxAspectRatioMode") ~= "manual" || mode("DataAspectRatioMode") ~= "manual"
                return
            end
            limits = ["XLim", "YLim", "ZLim"];
            manual = limits(arrayfun(@(limit) mode(limit + "Mode") == "manual", limits));
            if numel(manual) < 2, return, end
            text = "PlotBoxAspectRatio has no effect: MATLAB derives it from DataAspectRatio and " + ...
                strjoin(manual, ", ") + ", which are manual.";
        end
    end

    methods (Static, Access = private)
        function value = knownMode(members, path)
            % knownMode Return a member's known mode value, or an empty string.
            arguments (Input)
                members (1, :) struct
                path (1, 1) string
            end
            arguments (Output)
                value (1, 1) string
            end

            value = "";
            member = members(string({members.Path}) == path);
            if isscalar(member) && member.IsKnown && ...
                    (ischar(member.RawValue) || (isstring(member.RawValue) && isscalar(member.RawValue)))
                value = lower(string(member.RawValue));
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
