classdef ComponentRegistry < handle
    % ComponentRegistry Store extensible definitions for supported UI factories.
    %   This handle class owns component types, permitted parents, creation
    %   arguments, editable property definitions, and extension metadata. It does
    %   not store component instances or document state.
    %
    %   Example:
    %       registry = macd.model.ComponentRegistry.createDefault();
    %       labelDefinition = registry.get("uilabel");

    properties (Access = private)
        Definitions containers.Map
        ParentContextRules macd.model.ParentContextRule = macd.model.ParentContextRule.empty
    end

    methods
        function obj = ComponentRegistry()
            % ComponentRegistry Create an empty data-driven component registry.
            arguments (Output)
                obj (1, 1) macd.model.ComponentRegistry
            end

            % Store definitions by factory without coupling the model to types.
            obj.Definitions = containers.Map("KeyType", "char", "ValueType", "any");
            obj.ParentContextRules = [macd.model.ParentContextRule.grid(); macd.model.ParentContextRule.absolute()];
        end

        function register(obj, definition)
            % register Add or replace one complete component definition.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRegistry
                definition (1, 1) macd.model.ComponentDefinition
            end

            % Validate the lookup key before updating the registry atomically.
            key = char(definition.Factory);
            if isempty(key) || ~isvarname(key)
                error("macd:ComponentRegistry:InvalidFactory", ...
                    "Factory must be a valid MATLAB function name.");
            end
            obj.Definitions(key) = definition;
        end

        function result = contains(obj, factory)
            % contains Return true when a factory has a registered definition.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRegistry
                factory string
            end
            arguments (Output)
                result (1, 1) logical
            end

            result = isKey(obj.Definitions, char(factory));
        end

        function definition = get(obj, factory)
            % get Return a registered component definition by factory name.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRegistry
                factory string
            end
            arguments (Output)
                definition (1, 1) macd.model.ComponentDefinition
            end

            % Fail explicitly so callers cannot infer unsafe defaults.
            key = char(factory);
            if ~isKey(obj.Definitions, key)
                error("macd:ComponentRegistry:UnknownFactory", ...
                    "Component factory ""%s"" is not registered.", key);
            end
            definition = obj.Definitions(key);
        end

        function factories = listFactories(obj)
            % listFactories Return registered factory names in stable order.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRegistry
            end
            arguments (Output)
                factories string
            end

            % Sorting makes palettes, tests, and generated output deterministic.
            factories = sort(string(keys(obj.Definitions)));
        end

        function name = displayName(obj, factory)
            % displayName Return the MATLAB documentation name for a factory.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRegistry %#ok<INUSA>
                factory string
            end
            arguments (Output)
                name (1, 1) string
            end

            definition = obj.get(factory);
            name = definition.DisplayName;
        end

        function setParentContextRules(obj, rules)
            % setParentContextRules Replace the validated direct-parent rule set.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRegistry
                rules macd.model.ParentContextRule
            end
            obj.ParentContextRules = rules(:);
        end

        function properties = getEffectiveProperties(obj, factory, parentFactory)
            % getEffectiveProperties Return supported properties for one direct parent context.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRegistry
                factory (1, 1) string
                parentFactory (1, 1) string = ""
            end
            arguments (Output)
                properties macd.model.PropertyDefinition
            end

            % Compose only the parent rule selected by the direct parent factory.
            definition = obj.get(factory);
            properties = definition.Properties;
            for index = 1:numel(obj.ParentContextRules)
                rule = obj.ParentContextRules(index);
                if ~rule.appliesTo(parentFactory), continue, end
                properties = properties(~ismember(string({properties.Path}), rule.SuppressedPaths));
                properties = [properties(:); rule.AddedProperties(:)]; %#ok<AGROW>
                break
            end
        end
    end

    methods (Static)
        function obj = createDefault()
            % createDefault Load the packaged MATLAB R2024a component catalog.
            arguments (Output)
                obj (1, 1) macd.model.ComponentRegistry
            end
            obj = macd.catalog.ComponentCatalogLoader.load();
        end
    end
end

%{
MatlabAppClassDesigner - Data-driven registry of supported UI components.
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
