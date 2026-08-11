classdef DefaultValueProvider < handle
    % DefaultValueProvider Resolve display-only defaults through safe metadata and fixtures.

    properties (Access = private)
        Registry macd.model.ComponentRegistry
        Cache containers.Map = containers.Map("KeyType", "char", "ValueType", "any")
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
            if property.HasDefault
                found = true;
                value = property.DefaultValue;
                return
            end
            key = char(strjoin([string(version("-release")), component.Factory, parentFactory, ...
                string(property.Path)], "|"));
            if isKey(obj.Cache, key)
                result = obj.Cache(key);
                found = result.Found;
                value = result.Value;
                return
            end
            [found, value] = obj.fromMetadata(component.Factory, property.Path);
            if ~found
                [found, value] = obj.fromFixture(component, parentFactory, property.Path);
            end
            obj.Cache(key) = struct("Found", found, "Value", value);
        end

        function count = cacheEntryCount(obj)
            % cacheEntryCount Return the number of resolved release/context/property keys.
            arguments (Input)
                obj (1, 1) macd.ui.inspector.DefaultValueProvider
            end
            arguments (Output)
                count (1, 1) double
            end
            count = obj.Cache.Count;
        end
    end

    methods (Access = private)
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

        function [found, value] = fromFixture(~, component, parentFactory, path)
            % fromFixture Probe one registry-owned component inside a hidden fixture hierarchy.
            found = false; value = [];
            fixture = uifigure("Visible", "off");
            cleanup = onCleanup(@() deleteIfValid(fixture));
            try
                parent = fixtureParent(fixture, parentFactory);
                if component.Factory == "uifigure"
                    target = fixture;
                else
                    target = feval(char(component.Factory), parent, component.CreationArguments{:});
                end
                drawnow;
                value = readPath(target, path);
                if isa(value, "matlab.lang.OnOffSwitchState")
                    value = string(value);
                end
                found = macd.ui.inspector.DefaultValueProvider.isDisplayValue(value);
            catch
                found = false; value = [];
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
if numel(parts) == 1, value = target.(parts); else, value = target.(parts(1)).(parts(2)); end
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
