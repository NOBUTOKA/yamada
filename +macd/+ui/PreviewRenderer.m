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

        function [handles, diagnostics] = render(obj, document, parent)
            % render Rebuild a safe preview and return handles by component identity.
            arguments (Input)
                obj (1, 1) macd.ui.PreviewRenderer
                document (1, 1) macd.model.DocumentModel
                parent
            end
            arguments (Output)
                handles containers.Map
                diagnostics macd.model.Diagnostic
            end

            % Dispose stale editor-owned controls before constructing the new tree.
            delete(parent.Children);
            handles = containers.Map("KeyType", "char", "ValueType", "any");
            diagnostics = macd.model.Diagnostic.empty;
            root = document.getComponent(document.RootComponentId);
            if isempty(root)
                return
            end
            for index = 1:numel(root.Children)
                obj.renderComponent(document, root.Children(index), parent, handles);
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
            try
                preview = feval(char(component.Factory), parent, ...
                    component.CreationArguments{:});
                handles(char(component.Id)) = preview;
                obj.applyProperties(preview, component);
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

        function applyProperties(obj, preview, component)
            % applyProperties Assign editable literal properties without source evaluation.
            arguments (Input)
                obj (1, 1) macd.ui.PreviewRenderer
                preview
                component (1, 1) macd.model.ComponentRecord
            end

            % Isolate unsupported preview assignments as nonblocking diagnostics.
            for index = 1:numel(component.Properties)
                entry = component.Properties(index);
                if entry.ValueKind ~= "literal" || ~entry.IsEditable
                    continue
                end
                try
                    obj.setProperty(preview, entry.Path, entry.LiteralValue);
                catch exception
                    obj.Diagnostics(end + 1) = macd.model.Diagnostic( ...
                        "preview-property-failed", "warning", ...
                        "Preview could not apply " + entry.Path + " on " + ...
                        component.Name + ": " + string(exception.message), ...
                        component.Id);
                end
            end
        end

        function setProperty(obj, target, path, value)
            % setProperty Assign a direct or one-level nested graphics property.
            arguments (Input)
                obj (1, 1) macd.ui.PreviewRenderer
                target
                path string
                value
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
    end
end

%{
MatlabAppClassDesigner - Safe registry-only preview renderer.
Copyright (C) 2026 MatlabAppClassDesigner contributors

This file is part of MatlabAppClassDesigner.

MatlabAppClassDesigner is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

MatlabAppClassDesigner is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with MatlabAppClassDesigner. If not, see <https://www.gnu.org/licenses/>.
%}
