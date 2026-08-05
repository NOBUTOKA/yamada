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

            % Store all registry capabilities in one validated definition.
            obj.Factory = factory;
            obj.DeclaredType = declaredType;
            obj.AllowedParentFactories = allowedParentFactories;
            obj.IsRoot = isRoot;
            obj.CreationArguments = creationArguments;
            obj.Properties = propertyDefinitions;
            obj.Metadata = metadata;
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
