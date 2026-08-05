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
    end

    methods
        function obj = ComponentRegistry()
            % ComponentRegistry Create an empty data-driven component registry.
            arguments (Output)
                obj (1, 1) macd.model.ComponentRegistry
            end

            % Store definitions by factory without coupling the model to types.
            obj.Definitions = containers.Map("KeyType", "char", "ValueType", "any");
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
    end

    methods (Static)
        function obj = createDefault()
            % createDefault Build the initial extensible component registry.
            arguments (Output)
                obj (1, 1) macd.model.ComponentRegistry
            end

            % Define reusable parent and property groups for initial entries.
            obj = macd.model.ComponentRegistry();
            allContainers = ["uifigure", "uipanel", "uigridlayout"];
            common = ["Position", "Visible", "Enable"];
            layout = ["Layout.Row", "Layout.Column"];

            % Register each component independently so future types stay additive.
            obj.register(macd.model.ComponentRegistry.definition( ...
                "uifigure", "matlab.ui.Figure", strings(1, 0), true, {}, ...
                ["Position", "Visible", "Name"]));
            obj.register(macd.model.ComponentRegistry.definition( ...
                "uipanel", "matlab.ui.container.Panel", allContainers, false, {}, ...
                [common, "Title", layout]));
            obj.register(macd.model.ComponentRegistry.definition( ...
                "uigridlayout", "matlab.ui.container.GridLayout", allContainers, false, {}, ...
                ["Position", "Visible", "RowHeight", "ColumnWidth", ...
                "Layout.Row", "Layout.Column"]));
            obj.register(macd.model.ComponentRegistry.definition( ...
                "uilabel", "matlab.ui.control.Label", allContainers, false, {}, ...
                [common, "Text", layout]));
            obj.register(macd.model.ComponentRegistry.definition( ...
                "uibutton", "matlab.ui.control.Button", allContainers, false, {"push"}, ...
                [common, "Text", layout]));
            obj.register(macd.model.ComponentRegistry.definition( ...
                "uieditfield", "matlab.ui.control.EditField", allContainers, false, {}, ...
                [common, "Value", "Limits", layout]));
            obj.register(macd.model.ComponentRegistry.definition( ...
                "uidropdown", "matlab.ui.control.DropDown", allContainers, false, {}, ...
                [common, "Value", "Items", layout]));
            obj.register(macd.model.ComponentRegistry.definition( ...
                "uiaxes", "matlab.ui.control.UIAxes", allContainers, false, {}, ...
                [common, "XLim", "YLim", layout]));
        end
    end

    methods (Static, Access = private)
        function result = definition(factory, declaredType, parents, isRoot, args, paths)
            % definition Build a typed component definition and its properties.
            arguments (Input)
                factory string
                declaredType string
                parents string
                isRoot (1, 1) logical
                args cell
                paths string
            end
            arguments (Output)
                result (1, 1) macd.model.ComponentDefinition
            end

            % Expand paths into independently typed property capabilities.
            propertyDefinitions = macd.model.PropertyDefinition.empty;
            for index = 1:numel(paths)
                propertyDefinitions(end + 1) = ...
                    macd.model.PropertyDefinition(paths(index)); %#ok<AGROW>
            end

            % Assemble the immutable component capability object.
            result = macd.model.ComponentDefinition( ...
                factory, declaredType, parents, isRoot, args, ...
                propertyDefinitions, struct());
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
