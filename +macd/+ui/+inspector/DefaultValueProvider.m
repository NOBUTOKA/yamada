classdef DefaultValueProvider < handle
    % DefaultValueProvider Resolve display-only defaults through safe metadata and fixtures.

    properties (Access = private)
        Registry macd.model.ComponentRegistry
        Cache containers.Map = containers.Map("KeyType", "char", "ValueType", "any")
        ProbeCount double = 0
    end

    methods
        function obj = DefaultValueProvider(registry)
            % DefaultValueProvider Create a resolver for one allowlisted registry.
            arguments (Input)
                registry (1, 1) macd.model.ComponentRegistry
            end
            obj.Registry = registry;
        end

        function [found, value] = resolve(obj, component, parentFactory, property)
            % resolve Return one effective default without changing document state.
            arguments (Input)
                obj (1, 1) macd.ui.inspector.DefaultValueProvider
                component (1, 1) macd.model.ComponentRecord
                parentFactory (1, 1) string
                property (1, 1) macd.model.PropertyDefinition
            end
            arguments (Output)
                found (1, 1) logical
                value
            end
            results = obj.resolveAll(component, parentFactory, property);
            found = results.Found;
            value = results.Values{1};
        end

        function results = resolveAll(obj, component, parentFactory, properties)
            % resolveAll Resolve every property for one fixture surface using at most one probe.
            arguments (Input)
                obj (1, 1) macd.ui.inspector.DefaultValueProvider
                component (1, 1) macd.model.ComponentRecord
                parentFactory (1, 1) string
                properties macd.model.PropertyDefinition
            end
            arguments (Output)
                results (1, 1) struct
            end
            key = obj.surfaceKey(component, parentFactory);
            if isKey(obj.Cache, key)
                cached = obj.Cache(key);
                results = obj.selectProperties(cached, properties);
            else
                results = obj.resolveSurface(component, parentFactory, properties);
                obj.Cache(key) = results;
            end
        end

        function count = cacheEntryCount(obj)
            % cacheEntryCount Return the number of resolved fixture surfaces.
            arguments (Input)
                obj (1, 1) macd.ui.inspector.DefaultValueProvider
            end
            arguments (Output)
                count (1, 1) double
            end
            count = obj.Cache.Count;
        end

        function count = fixtureProbeCount(obj)
            % fixtureProbeCount Return the number of hidden fixture constructions.
            arguments (Input)
                obj (1, 1) macd.ui.inspector.DefaultValueProvider
            end
            arguments (Output)
                count (1, 1) double
            end
            count = obj.ProbeCount;
        end
    end

    methods (Access = private)
        function key = surfaceKey(obj, component, parentFactory)
            % surfaceKey Identify one release-specific default fixture surface.
            definition = obj.Registry.get(component.Factory);
            style = definition.styleFor(component.CreationArguments);
            argumentsText = string(jsonencode(component.CreationArguments));
            key = char(strjoin([string(version("-release")), component.Factory, parentFactory, ...
                style, argumentsText], "|"));
        end

        function results = resolveSurface(obj, component, parentFactory, properties)
            % resolveSurface Read metadata first then all unresolved paths from one fixture.
            results = struct("Paths", string({properties.Path}), "Found", false(1, numel(properties)), ...
                "Values", {cell(1, numel(properties))});
            unresolved = false(1, numel(properties));
            for index = 1:numel(properties)
                if properties(index).HasDefault
                    results.Found(index) = true;
                    results.Values{index} = properties(index).DefaultValue;
                else
                    [results.Found(index), results.Values{index}] = obj.fromMetadata( ...
                        component.Factory, properties(index).Path);
                    unresolved(index) = ~results.Found(index);
                end
            end
            if any(unresolved)
                results = obj.probeUnresolved(results, component, parentFactory, unresolved);
            end
        end

        function results = selectProperties(~, cached, properties)
            % selectProperties Project one cached surface result onto requested property order.
            results = struct("Paths", string({properties.Path}), "Found", false(1, numel(properties)), ...
                "Values", {cell(1, numel(properties))});
            for index = 1:numel(properties)
                cachedIndex = find(cached.Paths == properties(index).Path, 1);
                if ~isempty(cachedIndex)
                    results.Found(index) = cached.Found(cachedIndex);
                    results.Values{index} = cached.Values{cachedIndex};
                end
            end
        end

        function [found, value] = fromMetadata(obj, factory, path)
            % fromMetadata Read an explicit class property default when it is exposed.
            found = false; value = [];
            if contains(path, "."), return, end
            try
                definition = obj.Registry.get(factory);
                classInfo = meta.class.fromName(char(definition.DeclaredType));
                properties = classInfo.PropertyList;
                match = properties(strcmp(string({properties.Name}), path));
                if ~isempty(match) && isprop(match(1), "DefaultValue")
                    value = match(1).DefaultValue;
                    found = obj.isDisplayValue(value);
                end
            catch
                found = false; value = [];
            end
        end

        function results = probeUnresolved(obj, results, component, parentFactory, unresolved)
            % probeUnresolved Construct one fixture and read every remaining property path.
            fixture = uifigure("Visible", "off");
            obj.ProbeCount = obj.ProbeCount + 1;
            cleanup = onCleanup(@() deleteIfValid(fixture));
            try
                parent = fixtureParent(fixture, parentFactory);
                if component.Factory == "uifigure"
                    target = fixture;
                else
                    target = feval(char(component.Factory), parent, component.CreationArguments{:});
                end
                drawnow;
                for index = find(unresolved)
                    try
                        value = readPath(target, results.Paths(index));
                        if isa(value, "matlab.lang.OnOffSwitchState")
                            value = string(value);
                        end
                        results.Found(index) = macd.ui.inspector.DefaultValueProvider.isDisplayValue(value);
                        if results.Found(index), results.Values{index} = value; end
                    catch
                        results.Found(index) = false;
                    end
                end
            catch
                results.Found(unresolved) = false;
            end
            clear cleanup
        end
    end

    methods (Static, Access = private)
        function result = isDisplayValue(value)
            % isDisplayValue Reject values that cannot be shown as inert inspector data.
            result = ~(isa(value, "handle") || isa(value, "function_handle"));
        end
    end
end

function parent = fixtureParent(figure, parentFactory)
% fixtureParent Build one controlled direct parent for a registered factory.
switch parentFactory
    case {"", "uifigure"}, parent = figure;
    case "uipanel", parent = uipanel(figure);
    case "uibuttongroup", parent = uibuttongroup(figure);
    case "uigridlayout", parent = uigridlayout(figure, [2 2]);
    case "uitab", parent = uitab(uitabgroup(figure));
    case "uitabgroup", parent = uitabgroup(figure);
    otherwise, error("macd:DefaultValueProvider:UnsupportedParent", "Unsupported fixture parent.");
end
end

function value = readPath(target, path)
% readPath Read one direct or one-level nested property without evaluation.
parts = split(path, ".");
if numel(parts) == 1
    value = target.(parts);
else
    nested = target.(parts(1));
    value = nested.(parts(2));
end
end

function deleteIfValid(value)
% deleteIfValid Delete one owned UI fixture when it remains valid.
if ~isempty(value) && isvalid(value), delete(value); end
end

%{
MatlabAppClassDesigner - Runtime inspector default resolver.
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
