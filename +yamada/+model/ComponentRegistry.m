classdef ComponentRegistry < handle
    % ComponentRegistry Store extensible definitions for supported UI factories.
    %   This handle class owns component types, permitted parents, creation
    %   arguments, editable property definitions, and extension metadata. It does
    %   not store component instances or document state.
    %
    %   Example:
    %       registry = yamada.model.ComponentRegistry.createDefault();
    %       labelDefinition = registry.get("uilabel");

    properties (SetAccess = private)
        % Revision - Monotonic version of capability and presentation definitions.
        Revision uint64 = uint64(0)
        % CatalogRoot - Directory of the loaded release projection, if any.
        CatalogRoot string = ""
    end

    properties (Access = private)
        % Array-valued entries use cell values because each key holds one element.
        Definitions dictionary = dictionary(string([]), yamada.model.ComponentDefinition.empty)
        FactoryVariantIds dictionary = dictionary(string([]), {})
        EffectiveProperties dictionary = dictionary(string([]), {})
        IndependentDefinitions dictionary = dictionary(string([]), {})
        UnavailableSourceProperties string = strings(1, 0)
        UnavailableSourceValues string = strings(1, 0)
        ParentContextRules yamada.model.ParentContextRule = yamada.model.ParentContextRule.empty
        InspectorRowDefinitions yamada.model.InspectorRowDefinition = ...
            yamada.model.InspectorRowDefinition.empty
    end

    methods (Access = ?yamada.model.EvaluationContext)
        function result = areIndependentDefinitions(obj, definitions)
            % areIndependentDefinitions Reuse bounded proofs for equal immutable catalog values.
            arguments (Input)
                obj (1, 1) yamada.model.ComponentRegistry
                definitions yamada.model.PropertyDefinition
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = true;
            if isempty(definitions), return, end
            definitions = reshape(definitions, 1, []);
            key = "definitions:" + strjoin(string({definitions.Path}), "|");
            if isKey(obj.IndependentDefinitions, key)
                previous = obj.IndependentDefinitions{key};
                if isequaln(previous, definitions), return, end
            end
            % Only independent values enter this map; rejected live data is never retained.
            result = yamada.model.InputChangeClock.isValueData(definitions);
            if ~result, return, end
            if numEntries(obj.IndependentDefinitions) >= 128 && ~isKey(obj.IndependentDefinitions, key)
                obj.IndependentDefinitions = dictionary(string([]), {});
            end
            obj.IndependentDefinitions{key} = definitions;
        end
    end

    methods (Access = ?yamada.catalog.ComponentCatalogLoader)
        function setSourceAvailability(obj, root, paths, values)
            % setSourceAvailability Retain release annotations for source-only settings.
            arguments (Input)
                obj (1, 1) yamada.model.ComponentRegistry
                root (1, 1) string
                paths (1, :) string
                values (1, :) string
            end

            obj.CatalogRoot = root;
            obj.UnavailableSourceProperties = paths;
            obj.UnavailableSourceValues = values;
        end

        function copy = duplicate(obj)
            % duplicate Return an independent registry with the same validated catalog state.
            arguments (Input)
                obj (1, 1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                copy (1, 1) yamada.model.ComponentRegistry
            end

            % Definitions, derived surfaces, and their dictionaries are all value data.
            copy = yamada.model.ComponentRegistry();
            copy.Definitions = obj.Definitions;
            copy.FactoryVariantIds = obj.FactoryVariantIds;
            copy.EffectiveProperties = obj.EffectiveProperties;
            copy.ParentContextRules = obj.ParentContextRules;
            copy.InspectorRowDefinitions = obj.InspectorRowDefinitions;
            copy.UnavailableSourceProperties = obj.UnavailableSourceProperties;
            copy.UnavailableSourceValues = obj.UnavailableSourceValues;
            copy.CatalogRoot = obj.CatalogRoot;
            copy.Revision = obj.Revision;
        end
    end

    methods
        function definition = sourceDefinition(obj, component)
            % sourceDefinition Resolve a component's concrete source variant for structural analysis.
            arguments (Input)
                obj (1, 1) yamada.model.ComponentRegistry
                component (1, 1) yamada.model.ComponentRecord
            end
            arguments (Output)
                definition (1, 1) yamada.model.ComponentDefinition
            end

            % A protected descendant can still have a definition in the runtime projection.
            if ~component.isReleaseUnavailable()
                definition = obj.get(component.Factory, component.CreationArguments);
                return
            end
            variantId = component.Metadata.SourceVariantId;
            if any(obj.listVariantIds() == variantId)
                definition = obj.getById(variantId);
                return
            end
            catalog = yamada.catalog.ComponentCatalogLoader.load(fullfile( ...
                fileparts(obj.CatalogRoot), component.Metadata.SourceCatalogRelease));
            definition = catalog.getById(variantId);
        end

        function setting = protectSourceSetting(obj, variantId, setting)
            % protectSourceSetting Keep unsupported explicit settings outside runtime replay.
            arguments (Input)
                obj (1, 1) yamada.model.ComponentRegistry
                variantId (1, 1) string
                setting (1, 1) yamada.model.PropertySetting
            end
            arguments (Output)
                setting (1, 1) yamada.model.PropertySetting
            end

            % Only annotated literal values qualify. Expressions retain their existing checks.
            unavailable = obj.isUnavailableSourceProperty(variantId, setting.Path);
            value = setting.LiteralValue;
            if ~unavailable && setting.ValueKind == "literal" && ...
                    ((isstring(value) && isscalar(value)) || (ischar(value) && isrow(value)))
                unavailable = any(obj.UnavailableSourceValues == variantId + "." + setting.Path + "=" + string(value));
            end
            if unavailable
                record = setting.toStruct();
                record.Location.IsReleaseUnavailable = true;
                setting = yamada.model.PropertySetting(record.Path, record.Value, record.Location);
            end
        end

        function result = isUnavailableSourceProperty(obj, variantId, path)
            % isUnavailableSourceProperty Identify a property excluded by the loaded release.
            arguments (Input)
                obj (1, 1) yamada.model.ComponentRegistry
                variantId (1, 1) string
                path (1, 1) string
            end
            arguments (Output)
                result (1, 1) logical
            end

            result = any(obj.UnavailableSourceProperties == variantId + "." + path);
        end

        function obj = ComponentRegistry()
            % ComponentRegistry Create an empty data-driven component registry.
            arguments (Output)
                obj (1, 1) yamada.model.ComponentRegistry
            end

            % Definition dictionaries start empty from their property defaults.
            obj.ParentContextRules = [yamada.model.ParentContextRule.grid(); yamada.model.ParentContextRule.absolute()];
            obj.InspectorRowDefinitions = yamada.model.InspectorRowDefinition.empty;
        end

        function register(obj, definition)
            % register Add or replace one complete component definition.
            arguments (Input)
                obj (1, 1) yamada.model.ComponentRegistry
                definition (1, 1) yamada.model.ComponentDefinition
            end

            % Index variants by their stable identifier and factory name.
            factoryKey = string(definition.Factory);
            variantKey = string(definition.Id);
            if strlength(factoryKey) == 0 || ~isvarname(char(factoryKey))
                error("yamada:ComponentRegistry:InvalidFactory", ...
                    "Factory must be a valid MATLAB function name.");
            end
            if strlength(variantKey) == 0
                error("yamada:ComponentRegistry:InvalidVariantId", ...
                    "Component variant ID must not be empty.");
            end
            if isKey(obj.Definitions, variantKey)
                old = obj.Definitions(variantKey);
                if old.Factory ~= definition.Factory
                    error("yamada:ComponentRegistry:DuplicateVariantId", ...
                        "Variant ID ""%s"" belongs to another factory.", variantKey);
                end
            end
            obj.Definitions(variantKey) = definition;
            obj.Revision = obj.Revision + 1;
            obj.EffectiveProperties = dictionary(string([]), {});
            obj.IndependentDefinitions = dictionary(string([]), {});
            if ~isKey(obj.FactoryVariantIds, factoryKey)
                obj.FactoryVariantIds{factoryKey} = variantKey;
            else
                variants = obj.FactoryVariantIds{factoryKey};
                if ~any(variants == definition.Id)
                    obj.FactoryVariantIds{factoryKey} = [variants, variantKey];
                end
            end
        end

        function result = contains(obj, factory)
            % contains Return true when a factory has a registered definition.
            arguments (Input)
                obj (1, 1) yamada.model.ComponentRegistry
                factory string
            end
            arguments (Output)
                result (1, 1) logical
            end

            result = isscalar(factory) && isKey(obj.FactoryVariantIds, factory);
        end

        function definition = get(obj, factory, creationArguments)
            % get Return the concrete definition selected by factory arguments.
            arguments (Input)
                obj (1, 1) yamada.model.ComponentRegistry
                factory string
                creationArguments cell = {}
            end
            arguments (Output)
                definition (1, 1) yamada.model.ComponentDefinition
            end

            % Fail explicitly so callers cannot infer unsafe defaults.
            if ~obj.contains(factory)
                error("yamada:ComponentRegistry:UnknownFactory", ...
                    "Component factory ""%s"" is not registered.", strjoin(factory, ", "));
            end
            candidates = obj.Definitions(obj.FactoryVariantIds{factory});
            definition = obj.selectVariant(candidates, creationArguments, factory);
        end

        function factories = listFactories(obj)
            % listFactories Return registered factory names in stable order.
            arguments (Input)
                obj (1, 1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                factories string
            end

            % Sorting makes palettes, tests, and generated output deterministic.
            factories = sort(keys(obj.FactoryVariantIds))';
        end

        function ids = listVariantIds(obj)
            % listVariantIds Return every concrete component variant in stable order.
            arguments (Input)
                obj (1, 1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                ids string
            end

            ids = sort(keys(obj.Definitions))';
        end

        function definition = getById(obj, id)
            % getById Return one concrete definition by its stable catalog identifier.
            arguments (Input)
                obj (1, 1) yamada.model.ComponentRegistry
                id (1, 1) string
            end
            arguments (Output)
                definition (1, 1) yamada.model.ComponentDefinition
            end

            if ~isKey(obj.Definitions, id)
                error("yamada:ComponentRegistry:UnknownVariantId", ...
                    "Component variant ID ""%s"" is not registered.", id);
            end
            definition = obj.Definitions(id);
        end

        function name = displayName(obj, factory)
            % displayName Return the MATLAB documentation name for a factory.
            arguments (Input)
                obj (1, 1) yamada.model.ComponentRegistry
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
                obj (1, 1) yamada.model.ComponentRegistry
                rules yamada.model.ParentContextRule
            end
            obj.ParentContextRules = rules(:);
            obj.Revision = obj.Revision + 1;
            obj.EffectiveProperties = dictionary(string([]), {});
            obj.IndependentDefinitions = dictionary(string([]), {});
        end

        function setInspectorRowDefinitions(obj, definitions)
            % setInspectorRowDefinitions Replace validated presentation-only row templates.
            arguments (Input)
                obj (1, 1) yamada.model.ComponentRegistry
                definitions yamada.model.InspectorRowDefinition
            end

            ids = string({definitions.Id});
            if numel(ids) ~= numel(unique(ids))
                error("yamada:ComponentRegistry:DuplicateInspectorRowId", ...
                    "Inspector row template IDs must be unique.");
            end
            obj.InspectorRowDefinitions = definitions(:);
            obj.Revision = obj.Revision + 1;
            obj.EffectiveProperties = dictionary(string([]), {});
            obj.IndependentDefinitions = dictionary(string([]), {});
        end

        function definitions = inspectorRows(obj)
            % inspectorRows Return the catalog-owned Inspector presentation templates.
            arguments (Input)
                obj (1, 1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                definitions yamada.model.InspectorRowDefinition
            end

            definitions = obj.InspectorRowDefinitions;
        end

        function properties = getEffectiveProperties(obj, factory, parentFactory, creationArguments)
            % getEffectiveProperties Return supported properties for one direct parent context.
            arguments (Input)
                obj (1, 1) yamada.model.ComponentRegistry
                factory (1, 1) string
                parentFactory (1, 1) string = ""
                creationArguments cell = {}
            end
            arguments (Output)
                properties yamada.model.PropertyDefinition
            end

            % Compose only the parent rule selected by the direct parent factory.
            definition = obj.get(factory, creationArguments);
            key = definition.Id + "|" + parentFactory;
            if isKey(obj.EffectiveProperties, key)
                properties = obj.EffectiveProperties{key};
                return
            end
            properties = definition.Properties;
            suppressedPaths = strings(1, 0);
            for index = 1:numel(obj.ParentContextRules)
                rule = obj.ParentContextRules(index);
                if ~rule.appliesTo(parentFactory), continue, end
                suppressedPaths = rule.SuppressedPaths;
                properties = properties(~ismember(string({properties.Path}), rule.SuppressedPaths));
                added = rule.AddedProperties;
                added = added(~ismember(string({added.Path}), string({properties.Path})));
                properties = vertcat(properties(:), added(:));
                break
            end
            % Project declared impacts through the same explicit parent suppression.
            for propertyIndex = 1:numel(properties)
                property = properties(propertyIndex);
                if ~any(ismember(property.Application.AffectedPaths, suppressedPaths)), continue, end
                metadata = property.Metadata;
                metadata.application.affectedPaths = cellstr(setdiff(property.Application.AffectedPaths, suppressedPaths, 'stable'));
                properties(propertyIndex) = yamada.model.PropertyDefinition(property.Path, ...
                    property.DefaultValue, property.HasDefault, property.IsEditable, metadata);
            end
            yamada.model.PropertyApplicationPolicy.orderDefinitions(properties, ...
                definition.Id + " under " + parentFactory, suppressedPaths);
            obj.EffectiveProperties{key} = properties;
        end

        function result = isReadOnlyProperty(obj, factory, path, creationArguments)
            % isReadOnlyProperty Identify known properties whose catalog setter is restricted.
            arguments (Input)
                obj (1, 1) yamada.model.ComponentRegistry
                factory (1, 1) string
                path (1, 1) string
                creationArguments cell = {}
            end
            arguments (Output)
                result (1, 1) logical
            end

            % Unknown paths remain source-preserved; known catalog setters govern output.
            definition = obj.get(factory, creationArguments);
            property = definition.Properties(string({definition.Properties.Path}) == path);
            result = ~isempty(property) && ~property.IsEditable;
        end
    end

    methods
        function callbacks = getEffectiveCallbacks(obj, factory, parentFactory, creationArguments)
            % getEffectiveCallbacks Return catalog-declared callback bindings for one component.
            arguments (Input)
                obj (1, 1) yamada.model.ComponentRegistry
                factory (1, 1) string
                parentFactory (1, 1) string = ""
                creationArguments cell = {}
            end
            arguments (Output)
                callbacks yamada.model.PropertyDefinition
            end

            % Preserve effective catalog order without exposing execution-control properties.
            properties = obj.getEffectiveProperties(factory, parentFactory, creationArguments);
            isCallback = false(size(properties));
            for index = 1:numel(properties)
                schema = properties(index).ValueSchema;
                isCallback(index) = isfield(schema, "kind") && string(schema.kind) == "callback";
            end
            callbacks = properties(isCallback);
        end
    end

    methods (Access = private)
        function definition = selectVariant(obj, candidates, creationArguments, factory)
            % selectVariant Resolve the most specific creation-argument variant.
            arguments (Input)
                obj (1, 1) yamada.model.ComponentRegistry %#ok<INUSA>
                candidates yamada.model.ComponentDefinition
                creationArguments cell
                factory string
            end
            arguments (Output)
                definition (1, 1) yamada.model.ComponentDefinition
            end

            exact = candidates(arrayfun(@(candidate) isequal( ...
                candidate.CreationArguments, creationArguments), candidates));
            if isscalar(exact)
                definition = exact;
                return
            end
            prefixMatches = yamada.model.ComponentDefinition.empty;
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
            error("yamada:ComponentRegistry:AmbiguousVariant", ...
                "Factory ""%s"" has no unique variant for the supplied creation arguments.", factory);
        end
    end

    methods (Static)
        function obj = createDefault()
            % createDefault Load the packaged component catalog selected for the running release.
            arguments (Output)
                obj (1, 1) yamada.model.ComponentRegistry
            end
            obj = yamada.catalog.ComponentCatalogLoader.load();
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
