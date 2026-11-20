classdef AxesInspectorProperties
    % AxesInspectorProperties Define editable text members and geographic formatting.
    %   This surface describes owned axes settings without holding graphics handles.

    methods (Static)
        function result = groups(factory)
            % groups List text objects available on the specified axes factory.
            arguments (Input)
                factory (1,1) string
            end
            arguments (Output)
                result (1,:) string
            end
            result = strings(1,0);
            if factory == "colorbar", result = "Label"; return, end
            if any(factory == yamada.model.ColorbarDefinition.targets())
                result = ["Title","Subtitle"];
            end
            if any(factory == ["axes","uiaxes"])
                result = [result "XLabel" "YLabel" "ZLabel"];
            end
        end

        function result = names()
            % names List the supported details in presentation order.
            arguments (Output)
                result (1,:) string
            end
            result = ["Color","FontName","FontSize","FontWeight","FontAngle","Interpreter"];
        end

        function result = formats()
            % formats List the documented geographic tick label formats.
            arguments (Output)
                result (1,:) string
            end
            result = ["dd","dm","dms","-dd","-dm","-dms"];
        end

        function result = paths(factory)
            % paths Return the owned settings editable through the axes Inspector.
            arguments (Input)
                factory (1,1) string
            end
            arguments (Output)
                result (1,:) string
            end
            result = strings(1,0);
            for group = yamada.model.AxesInspectorProperties.groups(factory)
                result = [result group + "." + ["String" yamada.model.AxesInspectorProperties.names()]]; %#ok<AGROW>
            end
            if factory == "geoaxes", result(end+1) = "TickLabelFormat"; end
            if any(factory == yamada.model.ColorbarDefinition.targets()), result(end+1) = "Colormap"; end
        end

        function definitionsOut = extend(factory, definitions)
            % extend Supply definitions for text members and geographic tick format.
            arguments (Input)
                factory (1,1) string
                definitions yamada.model.PropertyDefinition
            end
            arguments (Output)
                definitionsOut yamada.model.PropertyDefinition
            end
            definitionsOut = reshape(definitions,1,[]);
            groups = yamada.model.AxesInspectorProperties.groups(factory);
            if isempty(groups), return, end
            if any(factory == yamada.model.ColorbarDefinition.targets())
                mapIndex = find(string({definitionsOut.Path}) == "Colormap",1);
                metadata = struct("category","Color and Transparency Maps","editor","colormap", ...
                    "previewPolicy","apply","absoluteGeometryImpact",false,"gridGeometryImpact","none", ...
                    "application",struct("effectStatus","independent","effectReason", ...
                    "The RGB matrix changes the color mapping without changing axes geometry."), ...
                    "valueSchema",struct("kind","literal","shape","matrix", ...
                    "matlabClasses","double","allowsEmpty",false));
                mapDefinition = yamada.model.PropertyDefinition("Colormap",[],false,true,metadata);
                if isempty(mapIndex)
                    definitionsOut(end+1) = mapDefinition;
                else
                    definitionsOut(mapIndex) = mapDefinition;
                end
            end
            % Retain the original object-level definitions for source compatibility.
            for index = 1:numel(groups)
                group = groups(index);
                display = replace(group,["XLabel","YLabel","ZLabel"],["X Label","Y Label","Z Label"]);
                for member = ["String" yamada.model.AxesInspectorProperties.names()]
                    metadata = struct("category","Labels","displayName",display,"order",index, ...
                        "axesTextMember",member,"axesTextGroup",group,"editor","text");
                    seed = [];
                    switch member
                        case "String"
                            metadata.editor = "multilineText";
                            seed = "";
                        case "Color"
                            metadata.editor = "color";
                        case "FontSize"
                            metadata.editor = "number";
                            metadata.valueSchema = struct("minimum",0,"exclusiveMinimum",true);
                        case "FontWeight"
                            metadata.editor = "enum";
                            metadata.valueSchema = struct("values",["normal","bold"]);
                        case "FontAngle"
                            metadata.editor = "enum";
                            metadata.valueSchema = struct("values",["normal","italic"]);
                        case "Interpreter"
                            metadata.editor = "enum";
                            metadata.valueSchema = struct("values",["tex","latex","none"]);
                    end
                    definitionsOut(end+1) = yamada.model.PropertyDefinition(group+"."+member, ...
                        seed,member=="String",true,metadata); %#ok<AGROW>
                end
            end
            if factory == "geoaxes"
                index = find(string({definitionsOut.Path}) == "TickLabelFormat",1);
                if ~isempty(index)
                    previous = definitionsOut(index);
                    metadata = previous.Metadata;
                    metadata.editor = "enum";
                    metadata.auditDisposition = "editable";
                    metadata.previewPolicy = "apply";
                    metadata.valueSchema = struct("values",yamada.model.AxesInspectorProperties.formats());
                    definitionsOut(index) = yamada.model.PropertyDefinition(previous.Path,"dms",true,true,metadata);
                end
            end
        end

        function [shared, canShare, titleValue] = subtitleLink(component, path)
            % subtitleLink Resolve an existing shared source argument and reversible override.
            arguments (Input)
                component (1,1) yamada.model.ComponentRecord
                path (1,1) string
            end
            arguments (Output)
                shared (1,1) logical
                canShare (1,1) logical
                titleValue
            end
            shared = false; canShare = false; titleValue = [];
            if ~startsWith(path,"Subtitle.") || path == "Subtitle.String", return, end
            title = component.getSettings("Title." + extractAfter(path,"Subtitle."));
            subtitle = component.getSettings(path);
            if isempty(title) || isempty(subtitle), return, end
            title = title(end);
            if ~title.IsCertain || title.ValueKind ~= "literal" || title.Method ~= "functionCall", return, end
            for index = numel(subtitle):-1:1
                item = subtitle(index);
                if item.IsCertain && item.Method == "functionCall" && ...
                        isequal(item.SourceSpan,title.SourceSpan) && isequal(item.ValueSpan,title.ValueSpan)
                    shared = index == numel(subtitle);
                    later = subtitle(index+1:end);
                    canShare = shared || (numel(later) == 1 && later.IsCertain && ...
                        later.IsEditable && later.Method == "assignment");
                    titleValue = title.LiteralValue;
                    return
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
