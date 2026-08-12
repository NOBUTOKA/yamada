classdef ComponentDefinition
    % ComponentDefinition Describe one component type supported by the editor.
    %   This immutable value class owns factory identity, declared MATLAB type,
    %   permitted parents, creation arguments, supported property definitions,
    %   and extension metadata. It does not store component instances or current
    %   document values.
    %
    %   Example:
    %       definition = macd.model.ComponentDefinition( ...
    %           "uilabel", "matlab.ui.control.Label", ...
    %           ["uifigure", "uipanel"], false, {}, properties, struct());

    properties (SetAccess = private)
        % Factory - MATLAB factory function used to create this component type.
        Factory string = ""
        % DeclaredType - MATLAB class used in AppBase property declarations.
        DeclaredType string = ""
        % AllowedParentFactories - Factories permitted to contain this type.
        AllowedParentFactories string = strings(1, 0)
        % IsRoot - Whether this component type may be the document root.
        IsRoot logical = false
        % CreationArguments - Ordered literal arguments passed after the parent.
        CreationArguments cell = {}
        % Properties - Ordered property capabilities supported by this type.
        Properties macd.model.PropertyDefinition = ...
            macd.model.PropertyDefinition.empty
        % DisplayName - Human-readable MATLAB documentation name for this component.
        DisplayName string = ""
        % Category - Palette and editor category for this component.
        Category string = ""
        % IsProgrammaticOnly - Whether palette creation is intentionally disabled.
        IsProgrammaticOnly logical = false
        % RequiresParentComponent - Whether creation requires a nonroot parent.
        RequiresParentComponent logical = false
        % SupportedStyles - Factory styles the editor can preserve and generate.
        SupportedStyles string = strings(1, 0)
        % DefaultStyle - Style used when a new component omits an explicit style.
        DefaultStyle string = ""
        % DeclaredTypesByStyle - Declared AppBase type for each supported style.
        DeclaredTypesByStyle struct = struct()
        % OverlayShape - Default SVG silhouette used by the editor interaction layer.
        OverlayShape string = "rectangle"
        % OverlayShapesByStyle - SVG silhouette overrides keyed by factory style.
        OverlayShapesByStyle struct = struct()
        % ResizeConstraint - Default editor resize constraint for this component.
        ResizeConstraint string = "free"
        % ResizeConstraintsByStyle - Resize constraint overrides keyed by style.
        ResizeConstraintsByStyle struct = struct()
        % Metadata - Extensible component capability and editor metadata.
        Metadata struct = struct()
    end

    methods
        function obj = ComponentDefinition(factory, declaredType, ...
                allowedParentFactories, isRoot, creationArguments, ...
                propertyDefinitions, displayName, category, isProgrammaticOnly, ...
                requiresParentComponent, supportedStyles, defaultStyle, ...
                declaredTypesByStyle, overlayShape, overlayShapesByStyle, ...
                resizeConstraint, resizeConstraintsByStyle, metadata)
            % ComponentDefinition Create an immutable component capability record.
            arguments (Input)
                factory string = ""
                declaredType string = ""
                allowedParentFactories string = strings(1, 0)
                isRoot logical = false
                creationArguments cell = {}
                propertyDefinitions macd.model.PropertyDefinition = ...
                    macd.model.PropertyDefinition.empty
                displayName string = ""
                category string = ""
                isProgrammaticOnly logical = false
                requiresParentComponent logical = false
                supportedStyles string = strings(1, 0)
                defaultStyle string = ""
                declaredTypesByStyle struct = struct()
                overlayShape string = "rectangle"
                overlayShapesByStyle struct = struct()
                resizeConstraint string = "free"
                resizeConstraintsByStyle struct = struct()
                metadata struct = struct()
            end
            arguments (Output)
                obj (1, 1) macd.model.ComponentDefinition
            end

            % Store explicit capabilities separately from arbitrary extension metadata.
            obj.Factory = factory;
            obj.DeclaredType = declaredType;
            obj.AllowedParentFactories = allowedParentFactories;
            obj.IsRoot = isRoot;
            obj.CreationArguments = creationArguments;
            obj.Properties = propertyDefinitions;
            obj.DisplayName = displayName;
            obj.Category = category;
            obj.IsProgrammaticOnly = isProgrammaticOnly;
            obj.RequiresParentComponent = requiresParentComponent;
            obj.SupportedStyles = supportedStyles;
            obj.DefaultStyle = defaultStyle;
            obj.DeclaredTypesByStyle = declaredTypesByStyle;
            obj.OverlayShape = overlayShape;
            obj.OverlayShapesByStyle = overlayShapesByStyle;
            obj.ResizeConstraint = resizeConstraint;
            obj.ResizeConstraintsByStyle = resizeConstraintsByStyle;
            obj.Metadata = metadata;
            if strlength(obj.DisplayName) == 0
                typeParts = split(obj.DeclaredType, ".");
                obj.DisplayName = typeParts(end);
            end
        end

        function style = styleFor(obj, creationArguments)
            % styleFor Resolve a factory style from literal creation arguments.
            arguments (Input)
                obj (1, 1) macd.model.ComponentDefinition
                creationArguments cell
            end
            arguments (Output)
                style (1, 1) string
            end

            style = obj.DefaultStyle;
            if isempty(creationArguments) || isempty(obj.SupportedStyles)
                return
            end
            candidate = string(creationArguments{1});
            if any(obj.SupportedStyles == candidate)
                style = candidate;
            end
        end

        function shape = overlayShapeFor(obj, creationArguments)
            % overlayShapeFor Return the SVG silhouette for one factory style.
            arguments (Input)
                obj (1, 1) macd.model.ComponentDefinition
                creationArguments cell
            end
            arguments (Output)
                shape (1, 1) string
            end

            shape = obj.OverlayShape;
            style = obj.styleFor(creationArguments);
            key = char(style);
            if ~isempty(key) && isfield(obj.OverlayShapesByStyle, key)
                shape = string(obj.OverlayShapesByStyle.(key));
            end
        end

        function constraint = resizeConstraintFor(obj, creationArguments)
            % resizeConstraintFor Return the resize constraint for one factory style.
            arguments (Input)
                obj (1, 1) macd.model.ComponentDefinition
                creationArguments cell
            end
            arguments (Output)
                constraint (1, 1) string
            end

            constraint = obj.ResizeConstraint;
            style = obj.styleFor(creationArguments);
            key = char(style);
            if ~isempty(key) && isfield(obj.ResizeConstraintsByStyle, key)
                constraint = string(obj.ResizeConstraintsByStyle.(key));
            end
        end

        function definition = getProperty(obj, path)
            % getProperty Return a supported property definition by full path.
            arguments (Input)
                obj (1, 1) macd.model.ComponentDefinition
                path string
            end
            arguments (Output)
                definition macd.model.PropertyDefinition
            end

            % Preserve definition order while locating a matching capability.
            definition = macd.model.PropertyDefinition.empty;
            for index = 1:numel(obj.Properties)
                candidate = obj.Properties(index);
                if candidate.Path == path
                    definition = candidate;
                    return
                end
            end
        end
    end

    methods (Static)
        function result = fromPaths(factory, declaredType, parents, isRoot, args, paths, capabilities)
            % fromPaths Create a definition from property paths and capabilities.
            arguments (Input)
                factory string
                declaredType string
                parents string
                isRoot (1, 1) logical
                args cell
                paths
                capabilities struct = struct()
            end
            arguments (Output)
                result (1, 1) macd.model.ComponentDefinition
            end

            % Expand paths into independently typed property capabilities.
            if isa(paths, "macd.model.PropertyDefinition")
                propertyDefinitions = paths;
            else
                propertyDefinitions = macd.model.PropertyDefinition.empty;
                for index = 1:numel(paths)
                    propertyDefinitions(end + 1) = ...
                        macd.model.PropertyDefinition(paths(index)); %#ok<AGROW>
                end
            end
            result = macd.model.ComponentDefinition(factory, declaredType, ...
                parents, isRoot, args, propertyDefinitions, ...
                macd.model.ComponentDefinition.capability(capabilities, "DisplayName", ""), ...
                macd.model.ComponentDefinition.capability(capabilities, "Category", ""), ...
                macd.model.ComponentDefinition.capability(capabilities, "ProgrammaticOnly", false), ...
                macd.model.ComponentDefinition.capability(capabilities, "RequiresParentComponent", false), ...
                macd.model.ComponentDefinition.capability(capabilities, "SupportedStyles", strings(1, 0)), ...
                macd.model.ComponentDefinition.capability(capabilities, "DefaultStyle", ""), ...
                macd.model.ComponentDefinition.capability(capabilities, "DeclaredTypesByStyle", struct()), ...
                macd.model.ComponentDefinition.capability(capabilities, "OverlayShape", "rectangle"), ...
                macd.model.ComponentDefinition.capability(capabilities, "OverlayShapesByStyle", struct()), ...
                macd.model.ComponentDefinition.capability(capabilities, "ResizeConstraint", "free"), ...
                macd.model.ComponentDefinition.capability(capabilities, "ResizeConstraintsByStyle", struct()), ...
                macd.model.ComponentDefinition.extensionMetadata(capabilities));
        end

    end

    methods (Static, Access = private)
        function value = capability(capabilities, name, defaultValue)
            % capability Return one explicitly named capability or its default.
            arguments (Input)
                capabilities struct
                name (1, 1) string
                defaultValue
            end
            arguments (Output)
                value
            end

            value = defaultValue;
            key = char(name);
            if isfield(capabilities, key)
                value = capabilities.(key);
            end
        end

        function metadata = extensionMetadata(capabilities)
            % extensionMetadata Retain only capabilities that have no typed property.
            arguments (Input)
                capabilities struct
            end
            arguments (Output)
                metadata struct
            end

            metadata = capabilities;
            known = ["DisplayName", "Category", "ProgrammaticOnly", ...
                "RequiresParentComponent", "SupportedStyles", "DefaultStyle", ...
                "DeclaredTypesByStyle", "OverlayShape", "OverlayShapesByStyle", ...
                "ResizeConstraint", "ResizeConstraintsByStyle"];
            for index = 1:numel(known)
                key = char(known(index));
                if isfield(metadata, key)
                    metadata = rmfield(metadata, key);
                end
            end
        end
    end
end

%{
Copyright (C) 2026 Nobuto Kaitoh

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
