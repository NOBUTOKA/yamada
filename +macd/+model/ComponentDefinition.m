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
                propertyDefinitions, metadata)
            % ComponentDefinition Create an immutable component capability record.
            arguments (Input)
                factory string = ""
                declaredType string = ""
                allowedParentFactories string = strings(1, 0)
                isRoot logical = false
                creationArguments cell = {}
                propertyDefinitions macd.model.PropertyDefinition = ...
                    macd.model.PropertyDefinition.empty
                metadata struct = struct()
            end
            arguments (Output)
                obj (1, 1) macd.model.ComponentDefinition
            end

            % Promote stable editor capabilities while retaining extension metadata.
            obj.Factory = factory;
            obj.DeclaredType = declaredType;
            obj.AllowedParentFactories = allowedParentFactories;
            obj.IsRoot = isRoot;
            obj.CreationArguments = creationArguments;
            obj.Properties = propertyDefinitions;
            [obj.DisplayName, metadata] = macd.model.ComponentDefinition.take(metadata, ...
                "DisplayName", obj.DisplayName);
            [obj.Category, metadata] = macd.model.ComponentDefinition.take(metadata, ...
                "Category", obj.Category);
            [obj.IsProgrammaticOnly, metadata] = macd.model.ComponentDefinition.take(metadata, ...
                "ProgrammaticOnly", obj.IsProgrammaticOnly);
            [obj.RequiresParentComponent, metadata] = macd.model.ComponentDefinition.take(metadata, ...
                "RequiresParentComponent", obj.RequiresParentComponent);
            [obj.SupportedStyles, metadata] = macd.model.ComponentDefinition.take(metadata, ...
                "SupportedStyles", obj.SupportedStyles);
            [obj.DefaultStyle, metadata] = macd.model.ComponentDefinition.take(metadata, ...
                "DefaultStyle", obj.DefaultStyle);
            [obj.DeclaredTypesByStyle, metadata] = macd.model.ComponentDefinition.take(metadata, ...
                "DeclaredTypesByStyle", obj.DeclaredTypesByStyle);
            [obj.OverlayShape, metadata] = macd.model.ComponentDefinition.take(metadata, ...
                "OverlayShape", obj.OverlayShape);
            [obj.OverlayShapesByStyle, metadata] = macd.model.ComponentDefinition.take(metadata, ...
                "OverlayShapesByStyle", obj.OverlayShapesByStyle);
            [obj.ResizeConstraint, metadata] = macd.model.ComponentDefinition.take(metadata, ...
                "ResizeConstraint", obj.ResizeConstraint);
            [obj.ResizeConstraint, metadata] = macd.model.ComponentDefinition.take(metadata, ...
                "ResizePolicy", obj.ResizeConstraint);
            [obj.ResizeConstraintsByStyle, metadata] = macd.model.ComponentDefinition.take(metadata, ...
                "ResizeConstraintsByStyle", obj.ResizeConstraintsByStyle);
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

    methods (Static, Access = private)
        function [value, metadata] = take(metadata, name, defaultValue)
            % take Move one known field from extension metadata to a capability.
            arguments (Input)
                metadata struct
                name (1, 1) string
                defaultValue
            end
            arguments (Output)
                value
                metadata struct
            end

            value = defaultValue;
            key = char(name);
            if isfield(metadata, key)
                value = metadata.(key);
                metadata = rmfield(metadata, key);
            end
        end
    end
end

%{
MatlabAppClassDesigner - Typed registry definition for a UI component type.
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
