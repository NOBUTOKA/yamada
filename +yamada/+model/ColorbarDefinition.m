classdef ColorbarDefinition
    % ColorbarDefinition Describe the ColorBar attached to a modeled axes.
    %   The document parent is the colorbar factory target. MATLAB manages
    %   the resulting graphics object's physical parent.

    properties (Constant)
        % Targets - Supported factories that can own a ColorBar.
        Targets string = ["axes","uiaxes","polaraxes","geoaxes"]
    end

    methods (Static)
        function definition = create()
            % create Build the dedicated Inspector surface for an axes attachment.
            arguments (Output)
                definition (1,1) yamada.model.ComponentDefinition
            end
            locations = ["eastoutside","westoutside","northoutside","southoutside", ...
                "east","west","north","south"];
            props = [yamada.model.ColorbarDefinition.choice("Location","eastoutside",locations,true) ...
                yamada.model.ColorbarDefinition.choice("Direction","normal",["normal","reverse"],false) ...
                yamada.model.ColorbarDefinition.choice("TickLabelInterpreter","tex",["tex","latex","none"],false) ...
                yamada.model.PropertyDefinition("Ticks",[],false,true,struct("editor","numericVector")) ...
                yamada.model.PropertyDefinition("TickLabels",[],false,true,struct("editor","literal")) ...
                yamada.model.PropertyDefinition("FontSize",[],false,true,struct("editor","number", ...
                    "valueSchema",struct("minimum",0,"exclusiveMinimum",true)))];
            definition = yamada.model.ComponentDefinition("colorbar","matlab.graphics.illustration.ColorBar", ...
                yamada.model.ColorbarDefinition.Targets,false,{},props,"ColorBar","Axes",true,true);
        end

    end

    methods (Static, Access = private)
        function property = choice(path, value, choices, geometry)
            % choice Define one enumerated property and its geometry impact.
            arguments (Input)
                path (1,1) string
                value (1,1) string
                choices (1,:) string
                geometry (1,1) logical
            end
            arguments (Output)
                property (1,1) yamada.model.PropertyDefinition
            end
            property = yamada.model.PropertyDefinition(path,value,true,true,struct("editor","enum", ...
                "absoluteGeometryImpact",geometry,"valueSchema",struct("values",choices)));
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
