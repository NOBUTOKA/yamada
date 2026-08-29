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
        FactoryVariantIds containers.Map
        ParentContextRules macd.model.ParentContextRule = macd.model.ParentContextRule.empty
        InspectorRowDefinitions macd.model.InspectorRowDefinition = ...
            macd.model.InspectorRowDefinition.empty
    end

    methods
        function obj = ComponentRegistry()
            % ComponentRegistry Create an empty data-driven component registry.
            arguments (Output)
                obj (1, 1) macd.model.ComponentRegistry
            end

            % Store definitions by factory without coupling the model to types.
            obj.Definitions = containers.Map("KeyType", "char", "ValueType", "any");
            obj.FactoryVariantIds = containers.Map("KeyType", "char", "ValueType", "any");
            obj.ParentContextRules = [macd.model.ParentContextRule.grid(); macd.model.ParentContextRule.absolute()];
            obj.InspectorRowDefinitions = macd.model.InspectorRowDefinition.empty;
        end

        function register(obj, definition)
            % register Add or replace one complete component definition.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRegistry
                definition (1, 1) macd.model.ComponentDefinition
            end

            % Index variants by their stable identifier and factory name.
            factoryKey = char(definition.Factory);
            variantKey = char(definition.Id);
            if isempty(factoryKey) || ~isvarname(factoryKey)
                error("macd:ComponentRegistry:InvalidFactory", ...
                    "Factory must be a valid MATLAB function name.");
            end
            if isempty(variantKey)
                error("macd:ComponentRegistry:InvalidVariantId", ...
                    "Component variant ID must not be empty.");
            end
            if isKey(obj.Definitions, variantKey)
                old = obj.Definitions(variantKey);
                if old.Factory ~= definition.Factory
                    error("macd:ComponentRegistry:DuplicateVariantId", ...
                        "Variant ID ""%s"" belongs to another factory.", variantKey);
                end
            end
            obj.Definitions(variantKey) = definition;
            if ~isKey(obj.FactoryVariantIds, factoryKey)
                obj.FactoryVariantIds(factoryKey) = string(definition.Id);
            else
                variants = string(obj.FactoryVariantIds(factoryKey));
                if ~any(variants == definition.Id)
                    obj.FactoryVariantIds(factoryKey) = [variants, definition.Id];
                end
            end
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

            result = isKey(obj.FactoryVariantIds, char(factory));
        end

        function definition = get(obj, factory, creationArguments)
            % get Return the concrete definition selected by factory arguments.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRegistry
                factory string
                creationArguments cell = {}
            end
            arguments (Output)
                definition (1, 1) macd.model.ComponentDefinition
            end

            % Fail explicitly so callers cannot infer unsafe defaults.
            key = char(factory);
            if ~isKey(obj.FactoryVariantIds, key)
                error("macd:ComponentRegistry:UnknownFactory", ...
                    "Component factory ""%s"" is not registered.", key);
            end
            variantIds = string(obj.FactoryVariantIds(key));
            candidates = macd.model.ComponentDefinition.empty;
            for index = 1:numel(variantIds)
                candidates(end + 1) = obj.Definitions(char(variantIds(index))); %#ok<AGROW>
            end
            definition = obj.selectVariant(candidates, creationArguments, factory);
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
            factories = sort(string(keys(obj.FactoryVariantIds)));
        end

        function ids = listVariantIds(obj)
            % listVariantIds Return every concrete component variant in stable order.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRegistry
            end
            arguments (Output)
                ids string
            end

            ids = sort(string(keys(obj.Definitions)));
        end

        function definition = getById(obj, id)
            % getById Return one concrete definition by its stable catalog identifier.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRegistry
                id (1, 1) string
            end
            arguments (Output)
                definition (1, 1) macd.model.ComponentDefinition
            end

            key = char(id);
            if ~isKey(obj.Definitions, key)
                error("macd:ComponentRegistry:UnknownVariantId", ...
                    "Component variant ID ""%s"" is not registered.", key);
            end
            definition = obj.Definitions(key);
        end

        function name = displayName(obj, factory)
            % displayName Return the MATLAB documentation name for a factory.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRegistry
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

        function setInspectorRowDefinitions(obj, definitions)
            % setInspectorRowDefinitions Replace validated presentation-only row templates.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRegistry
                definitions macd.model.InspectorRowDefinition
            end

            ids = string({definitions.Id});
            if numel(ids) ~= numel(unique(ids))
                error("macd:ComponentRegistry:DuplicateInspectorRowId", ...
                    "Inspector row template IDs must be unique.");
            end
            obj.InspectorRowDefinitions = definitions(:);
        end

        function definitions = inspectorRows(obj)
            % inspectorRows Return the catalog-owned Inspector presentation templates.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRegistry
            end
            arguments (Output)
                definitions macd.model.InspectorRowDefinition
            end

            definitions = obj.InspectorRowDefinitions;
        end

        function properties = getEffectiveProperties(obj, factory, parentFactory, creationArguments)
            % getEffectiveProperties Return supported properties for one direct parent context.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRegistry
                factory (1, 1) string
                parentFactory (1, 1) string = ""
                creationArguments cell = {}
            end
            arguments (Output)
                properties macd.model.PropertyDefinition
            end

            % Compose only the parent rule selected by the direct parent factory.
            definition = obj.get(factory, creationArguments);
            properties = definition.Properties;
            for index = 1:numel(obj.ParentContextRules)
                rule = obj.ParentContextRules(index);
                if ~rule.appliesTo(parentFactory), continue, end
                properties = properties(~ismember(string({properties.Path}), rule.SuppressedPaths));
                properties = vertcat(properties(:), rule.AddedProperties(:));
                break
            end
        end
    end

    methods (Access = private)
        function definition = selectVariant(obj, candidates, creationArguments, factory)
            % selectVariant Resolve the most specific creation-argument variant.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRegistry %#ok<INUSA>
                candidates macd.model.ComponentDefinition
                creationArguments cell
                factory string
            end
            arguments (Output)
                definition (1, 1) macd.model.ComponentDefinition
            end

            exact = candidates(arrayfun(@(candidate) isequal( ...
                candidate.CreationArguments, creationArguments), candidates));
            if isscalar(exact)
                definition = exact;
                return
            end
            prefixMatches = macd.model.ComponentDefinition.empty;
            for index = 1:numel(candidates)
                variantArguments = candidates(index).CreationArguments;
                if numel(variantArguments) <= numel(creationArguments) && ...
                        isequal(variantArguments, creationArguments(1:numel(variantArguments)))
                    prefixMatches(end + 1) = candidates(index); %#ok<AGROW>
                end
            end
            if ~isempty(prefixMatches)
                lengths = arrayfun(@(candidate) numel(candidate.CreationArguments), prefixMatches);
                best = prefixMatches(lengths == max(lengths));
                if isscalar(best)
                    definition = best;
                    return
                end
            end
            emptyArguments = candidates(arrayfun(@(candidate) isempty( ...
                candidate.CreationArguments), candidates));
            if isscalar(emptyArguments)
                definition = emptyArguments;
                return
            end
            error("macd:ComponentRegistry:AmbiguousVariant", ...
                "Factory ""%s"" has no unique variant for the supplied creation arguments.", factory);
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
