classdef PreviewRenderer < handle
    % PreviewRenderer Render registry-approved component models on an editor surface.
    %   This class creates only known factories from a DocumentModel and applies
    %   editable literal properties. It does not instantiate an opened AppBase
    %   class, invoke callbacks, or evaluate source expressions.
    %
    %   Example:
    %       renderer = macd.ui.PreviewRenderer(registry);
    %       [handles, diagnostics] = renderer.render(document, previewPanel);

    properties (Access = private)
        Registry macd.model.ComponentRegistry
        PreviewSurface
        PreviewMargin double = 12
    end

    methods
        function obj = PreviewRenderer(registry)
            % PreviewRenderer Create a renderer backed by one component registry.
            arguments (Input)
                registry (1, 1) macd.model.ComponentRegistry = ...
                    macd.model.ComponentRegistry.createDefault()
            end
            arguments (Output)
                obj (1, 1) macd.ui.PreviewRenderer
            end

            % Use the same capability definitions as parsing and validation.
            obj.Registry = registry;
        end

        function [handles, diagnostics, surface] = render(obj, document, parent)
            % render Rebuild a safe preview and return handles by component identity.
            arguments (Input)
                obj (1, 1) macd.ui.PreviewRenderer
                document (1, 1) macd.model.DocumentModel
                parent
            end
            arguments (Output)
                handles containers.Map
                diagnostics macd.model.Diagnostic
                surface
            end

            % Dispose stale editor-owned controls before constructing the new tree.
            delete(parent.Children);
            handles = containers.Map("KeyType", "char", "ValueType", "any");
            diagnostics = macd.model.Diagnostic.empty;
            surface = [];
            obj.Diagnostics = macd.model.Diagnostic.empty;
            root = document.getComponent(document.RootComponentId);
            if isempty(root)
                return
            end

            % Recreate the source figure at its actual client-area pixel size.
            obj.createPreviewSurface(root, parent);
            surface = obj.PreviewSurface;
            for index = 1:numel(root.Children)
                obj.renderComponent(document, root.Children(index), obj.PreviewSurface, handles);
            end
            diagnostics = obj.Diagnostics;
            obj.Diagnostics = macd.model.Diagnostic.empty;
        end
    end

    properties (Access = private)
        Diagnostics macd.model.Diagnostic = macd.model.Diagnostic.empty
    end

    methods (Access = private)
        function renderComponent(obj, document, componentId, parent, handles)
            % renderComponent Construct one safe component and all of its children.
            arguments (Input)
                obj (1, 1) macd.ui.PreviewRenderer
                document (1, 1) macd.model.DocumentModel
                componentId string
                parent
                handles containers.Map
            end

            % Create only factories declared in the registry and model hierarchy.
            component = document.getComponent(componentId);
            if isempty(component) || ~obj.Registry.contains(component.Factory)
                return
            end
            if any(component.Factory == ["uicontextmenu", "uimenu", "uitoolbar", ...
                    "uipushtool", "uitoggletool"])
                return
            end
            try
                preview = obj.createPreviewComponent(component, parent);
                handles(char(component.Id)) = preview;
                obj.applyProperties(preview, component, document);
                for index = 1:numel(component.Children)
                    obj.renderComponent(document, component.Children(index), preview, handles);
                end
            catch exception
                obj.Diagnostics(end + 1) = macd.model.Diagnostic( ...
                    "preview-render-failed", "warning", ...
                    "Preview could not render " + component.Name + ": " + ...
                    string(exception.message), component.Id);
            end
        end

        function applyProperties(obj, preview, component, document)
            % applyProperties Assign editable literal properties without source evaluation.
            arguments (Input)
                obj (1, 1) macd.ui.PreviewRenderer
                preview
                component (1, 1) macd.model.ComponentRecord
                document (1, 1) macd.model.DocumentModel
            end

            % Isolate unsupported preview assignments as nonblocking diagnostics.
            definition = obj.Registry.get(component.Factory, component.CreationArguments);
            entries = obj.orderedProperties(component.Properties, definition);
            for index = 1:numel(entries)
                entry = entries(index);
                if entry.ValueKind ~= "literal" || ~entry.IsEditable
                    continue
                end
                property = definition.getProperty(entry.Path);
                imageSource = component.Factory == "uiimage" && entry.Path == "ImageSource";
                if ~imageSource && ~isempty(property) && ...
                        any(property.PreviewPolicy == ["skip", "notRendered"])
                    continue
                end
                if entry.Path == "Position" && ...
                        isa(preview.Parent, "matlab.ui.container.GridLayout")
                    % Grid layout owns child geometry through Layout.Row/Column.
                    continue
                end
                try
                    value = entry.LiteralValue;
                    if imageSource
                        value = obj.resolveImageSource(value, document);
                        if strlength(value) == 0
                            continue
                        end
                    end
                    obj.setProperty(preview, entry.Path, value, component);
                catch exception
                    obj.Diagnostics(end + 1) = macd.model.Diagnostic( ...
                        "preview-property-failed", "warning", ...
                        "Preview could not apply " + entry.Path + " on " + ...
                        component.Name + ": " + string(exception.message), ...
                        component.Id);
                end
            end
        end

        function path = resolveImageSource(obj, value, document)
            % resolveImageSource Resolve a local image path relative to its app source.
            arguments (Input)
                obj (1, 1) macd.ui.PreviewRenderer %#ok<INUSA>
                value
                document (1, 1) macd.model.DocumentModel
            end
            arguments (Output)
                path (1, 1) string
            end

            path = "";
            if ~(ischar(value) || (isstring(value) && isscalar(value)))
                return
            end
            requested = string(value);
            if strlength(requested) == 0
                return
            end

            % Opened apps interpret relative assets beside their source file.
            if strlength(document.FilePath) > 0
                sourceRelative = fullfile(fileparts(document.FilePath), requested);
                if isfile(sourceRelative)
                    path = string(sourceRelative);
                    return
                end
            end
            if isfile(requested)
                path = requested;
            end
        end
        function orderedEntries = orderedProperties(obj, entries, definition)
            % orderedProperties Apply selection dependencies before their Value.
            %   Source/model insertion order is normally preserved.  Item-backed
            %   controls are the exception: MATLAB validates Value against Items
            %   (or ItemsData), and ListBox validates it against Multiselect.
            arguments (Input)
                obj (1, 1) macd.ui.PreviewRenderer
                entries macd.model.PropertyEntry
                definition (1, 1) macd.model.ComponentDefinition
            end
            arguments (Output)
                orderedEntries macd.model.PropertyEntry
            end

            orderedEntries = entries;
            valueDefinition = definition.getProperty("Value");
            if isempty(obj.Registry)
                return
            end
            if isempty(valueDefinition) || valueDefinition.Editor ~= "itemSelection"
                return
            end

            priority = 2 * ones(1, numel(entries));
            for index = 1:numel(entries)
                switch entries(index).Path
                    case "Items"
                        priority(index) = 1;
                    case "ItemsData"
                        priority(index) = 2;
                    case "Multiselect"
                        priority(index) = 3;
                    case "Value"
                        priority(index) = 4;
                end
            end
            [~, order] = sortrows([priority(:), (1:numel(entries))'], [1 2]);
            orderedEntries = entries(order);
        end


        function createPreviewSurface(obj, root, parent)
            % createPreviewSurface Place an actual-size client area in the scroll host.
            arguments (Input)
                obj (1, 1) macd.ui.PreviewRenderer
                root (1, 1) macd.model.ComponentRecord
                parent
            end

            % Use the source figure size as the coordinate system for pixel children.
            sourceSize = [560 420];
            positionEntry = root.getProperty("Position");
            if ~isempty(positionEntry) && positionEntry.ValueKind == "literal" && ...
                    isnumeric(positionEntry.LiteralValue) && ...
                    numel(positionEntry.LiteralValue) == 4 && ...
                    all(positionEntry.LiteralValue(3:4) > 0)
                sourceSize = positionEntry.LiteralValue(3:4);
            end
            availablePosition = obj.parentInnerPosition(parent);
            frameSize = double(sourceSize) + 2;
            % Preserve a dark margin at every scroll limit, including the far edges.
            contentSize = max(double(availablePosition(3:4)), ...
                frameSize + 2 * obj.PreviewMargin);
            content = uipanel(parent, "BorderType", "none", ...
                "AutoResizeChildren", "off", ...
                "BackgroundColor", [0.35 0.36 0.38], ...
                "Position", [1 1 contentSize], ...
                "Tag", "macd-preview-scroll-content");
            frameOrigin = floor((contentSize - frameSize) ./ 2) + 1;
            frame = uipanel(content, "BorderType", "none", ...
                "AutoResizeChildren", "off", ...
                "BackgroundColor", [0.53 0.54 0.55], ...
                "Position", [frameOrigin frameSize], ...
                "Tag", "macd-preview-frame");
            obj.PreviewSurface = uipanel(frame, "BorderType", "none", ...
                "AutoResizeChildren", "off", ...
                "BackgroundColor", [0.94 0.94 0.94], ...
                "Position", [2 2 double(sourceSize)], ...
                "Tag", "macd-preview-canvas");
            colorEntry = root.getProperty("Color");
            if ~isempty(colorEntry) && colorEntry.ValueKind == "literal"
                try
                    obj.PreviewSurface.BackgroundColor = colorEntry.LiteralValue;
                catch
                    % Keep the R2024a UIFigure default for unsupported colors.
                end
            end
        end

        function preview = createPreviewComponent(obj, component, parent)
            % createPreviewComponent Create one ordinary control on the preview surface.
            arguments (Input)
                obj (1, 1) macd.ui.PreviewRenderer %#ok<INUSA>
                component (1, 1) macd.model.ComponentRecord
                parent
            end
            % Figure-only controls are filtered before this safe factory call.
            preview = feval(char(component.Factory), parent, ...
                component.CreationArguments{:});
        end

        function setProperty(obj, target, path, value, component)
            % setProperty Assign a direct or one-level nested graphics property.
            arguments (Input)
                obj (1, 1) macd.ui.PreviewRenderer
                target
                path string
                value
                component (1, 1) macd.model.ComponentRecord
            end

            % Assign nested Layout properties directly, avoiding a detached value copy.
            if isempty(obj.Registry)
                error("macd:PreviewRenderer:Uninitialized", ...
                    "Preview rendering requires a component registry.");
            end
            if path == "Items" && iscell(value) && ...
                    all(cellfun(@(item) isstring(item) && isscalar(item), value))
                value = string(value);
            end
            if path == "Position" && isnumeric(value) && numel(value) == 4 && ...
                obj.usesPixelPosition(target)
                definition = obj.Registry.get(component.Factory, component.CreationArguments);
                constraint = definition.resizeConstraintFor(component.CreationArguments);
                if constraint == "fixedHeight"
                    % Slider-like controls reject height writes entirely.
                    target.Position(1:3) = value(1:3);
                    return
                elseif constraint == "aspectRatio"
                    % Preserve the control's runtime aspect ratio while moving/scaling it.
                    current = double(target.Position);
                    ratio = current(3) / max(current(4), eps);
                    value(4) = value(3) / max(ratio, eps);
                    target.Position = value;
                    return
                end
            end
            parts = split(path, ".");
            if isscalar(parts)
                target.(parts(1)) = value;
            elseif numel(parts) == 2
                target.(parts(1)).(parts(2)) = value;
            else
                error("macd:PreviewRenderer:UnsupportedPropertyPath", ...
                    "Preview property path ""%s"" is too deeply nested.", path);
            end
        end

        function position = parentInnerPosition(obj, parent)
            % parentInnerPosition Return the usable coordinate rectangle of a UI parent.
            arguments (Input)
                obj (1, 1) macd.ui.PreviewRenderer %#ok<INUSA>
                parent
            end
            arguments (Output)
                position (1, 4) double
            end

            % Use the inner dimensions; child Position values are always parent-local.
            if isprop(parent, "InnerPosition")
                position = double(parent.InnerPosition);
            else
                position = double(parent.Position);
            end
        end

        function result = usesPixelPosition(obj, target)
            % usesPixelPosition Report whether a target interprets Position in pixels.
            arguments (Input)
                obj (1, 1) macd.ui.PreviewRenderer %#ok<INUSA>
                target
            end
            arguments (Output)
                result (1, 1) logical
            end

            % UI controls without Units use pixel Position; normalized axes do not.
            result = isprop(target, "Position") && ...
                (~isprop(target, "Units") || string(target.Units) == "pixels");
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
