classdef PropertyApplicationPolicy
    % PropertyApplicationPolicy Describe declarative property initialization rules.
    %   This value class validates catalog policy data and orders a complete
    %   property surface. It does not apply setters or evaluate user source.
    %
    %   Example:
    %       policy = macd.model.PropertyApplicationPolicy( ...
    %           struct("applyAfter", {{"Items"}}, "nameValue", "supported"));

    properties (SetAccess = private)
        % ApplyAfter - Prerequisites used when planning new initialization.
        % Preserved source order requires separate state-aware validation.
        ApplyAfter string = strings(1, 0)
        % NameValue - Verified constructor support, or unknown for unaudited data.
        NameValue string = "unknown"
        % EffectPolicy - Allowlisted policy for resolving implicit setter effects.
        EffectPolicy string = "none"
        % EffectStatus - Unknown, independent, modeled, or explicitly unsupported setter semantics.
        EffectStatus string = "unknown"
        % AffectedPaths - States invalidated by unsupported or uncertain writes; empty means all.
        AffectedPaths string = strings(1, 0)
        % EffectReason - Audited explanation of an unresolved setter boundary.
        EffectReason string = "Setter effects have not been reviewed."
        % DefaultLiteral - Audited inert MATLAB literal used to seed state resolution.
        DefaultLiteral string = ""
        % HasInitialValue - Whether the audited seed was parsed without evaluation.
        HasInitialValue logical = false
        % InitialValue - Parsed audited default, separate from explicit source settings.
        InitialValue = []
    end

    methods
        function obj = PropertyApplicationPolicy(data, context)
            % PropertyApplicationPolicy Validate optional application policy metadata.
            arguments (Input)
                data = struct()
                context (1, 1) string = "application"
            end
            arguments (Output)
                obj (1, 1) macd.model.PropertyApplicationPolicy
            end

            % Keep catalog failures contextual and reject executable extensions.
            if ~isstruct(data) || ~isscalar(data)
                obj.fail(context, "Expected one application policy object.");
            end
            unknown = setdiff(string(fieldnames(data)), ...
                ["applyAfter", "nameValue", "effectPolicy", "defaultLiteral", "effectStatus", "affectedPaths", "effectReason"]);
            if ~isempty(unknown)
                obj.fail(context + "." + unknown(1), "Unknown application policy field.");
            end
            if isfield(data, "applyAfter")
                raw = data.applyAfter;
                textCells = iscell(raw) && all(cellfun(@(value) ...
                    (ischar(value) && isrow(value)) || ...
                    (isstring(value) && isscalar(value)), raw), "all");
                if ~(isstring(raw) || textCells || ...
                        (isnumeric(raw) && isempty(raw))) || ...
                        (~isempty(raw) && ~isvector(raw))
                    obj.fail(context + ".applyAfter", "Expected a JSON string array.");
                end
                paths = reshape(string(raw), 1, []);
                if any(ismissing(paths)) || any(strlength(paths) == 0) || ...
                        any(cellfun(@isempty, regexp(cellstr(paths), ...
                        '^[A-Za-z]\w*(\.[A-Za-z]\w*)*$', 'once')))
                    obj.fail(context + ".applyAfter", "Expected valid property paths.");
                end
                if numel(unique(paths)) ~= numel(paths)
                    obj.fail(context + ".applyAfter", "Dependency paths must be unique.");
                end
                obj.ApplyAfter = paths;
            end
            if isfield(data, "nameValue")
                obj.NameValue = obj.identifier(data.nameValue, ...
                    ["supported", "unsupported", "unknown"], context + ".nameValue");
            end
            if isfield(data, "effectPolicy")
                obj.EffectPolicy = obj.identifier(data.effectPolicy, ...
                    ["none", "itemSelection", "boundedValue", "numericValue", ...
                    "tickMode", "valueMode", "modeFlag", "axisWidth", "positionAlias", "squarePositionAlias", ...
                    "textValue", "componentReference", "layout", "gridTracks", "buttonSelection", "positionInput", "sliderPosition", "squarePosition", "switchPosition", "semicircularPosition"], context + ".effectPolicy");
            end
            if isfield(data, "effectStatus")
                obj.EffectStatus = obj.identifier(data.effectStatus, ...
                    ["unknown", "independent", "modeled", "unsupported"], context + ".effectStatus");
            end
            if isfield(data, "affectedPaths")
                raw = data.affectedPaths;
                if ~(isstring(raw) || (iscell(raw) && all(cellfun(@(item) ...
                        (ischar(item) && isrow(item)) || (isstring(item) && isscalar(item)), raw), "all")) || (isnumeric(raw) && isempty(raw)))
                    obj.fail(context + ".affectedPaths", "Expected property paths as a string array.");
                end
                paths = reshape(string(raw), 1, []);
                if any(ismissing(paths)) || numel(unique(paths)) ~= numel(paths) || ...
                        any(cellfun(@isempty, regexp(cellstr(paths), '^[A-Za-z]\w*(\.[A-Za-z]\w*)*$', 'once')))
                    obj.fail(context + ".affectedPaths", "Expected unique valid property paths.");
                end
                obj.AffectedPaths = paths;
            end
            if isfield(data, "effectReason")
                if ~((ischar(data.effectReason) && isrow(data.effectReason)) || ...
                        (isstring(data.effectReason) && isscalar(data.effectReason))) || ...
                        ismissing(string(data.effectReason)) || strlength(strtrim(string(data.effectReason))) == 0
                    obj.fail(context + ".effectReason", "Expected a nonempty explanation.");
                end
                obj.EffectReason = string(data.effectReason);
            end
            if isfield(data, "defaultLiteral")
                raw = data.defaultLiteral;
                if ~((ischar(raw) && isrow(raw)) || (isstring(raw) && isscalar(raw)))
                    obj.fail(context + ".defaultLiteral", "Expected one inert MATLAB literal string.");
                end
                obj.DefaultLiteral = string(raw);
                if ismissing(obj.DefaultLiteral) || strlength(strtrim(obj.DefaultLiteral)) == 0
                    obj.fail(context + ".defaultLiteral", "Expected a nonempty MATLAB literal string.");
                end
                [obj.InitialValue, obj.HasInitialValue] = macd.source.MatlabLiteralParser.parse(obj.DefaultLiteral);
                if ~obj.HasInitialValue
                    obj.fail(context + ".defaultLiteral", "Unsupported seed literal; expressions are never evaluated.");
                end
            end
        end
    end

    methods (Static)
        function order = orderDefinitions(definitions, context, suppressedPaths)
            % orderDefinitions Validate dependencies and return a stable topological order.
            arguments (Input)
                definitions macd.model.PropertyDefinition
                context (1, 1) string = "properties"
                suppressedPaths string = strings(1, 0)
            end
            arguments (Output)
                order (1, :) double
            end

            % Validate the expanded concrete surface rather than reusable fragments.
            count = numel(definitions);
            paths = string({definitions.Path});
            if numel(unique(paths)) ~= count
                macd.model.PropertyApplicationPolicy.fail(context, "Property paths must be unique.");
            end
            edges = false(count);
            for index = 1:count
                affected = definitions(index).Application.AffectedPaths;
                if any(~ismember(affected, [paths reshape(suppressedPaths, 1, [])]))
                    macd.model.PropertyApplicationPolicy.fail(context + "." + paths(index), ...
                        "Unknown affected property path outside the declared parent suppression.");
                end
                dependencies = definitions(index).Application.ApplyAfter;
                for dependency = dependencies
                    target = find(paths == dependency, 1);
                    if isempty(target)
                        macd.model.PropertyApplicationPolicy.fail(context + "." + paths(index), ...
                            "Unknown application dependency " + dependency + ".");
                    end
                    if target == index
                        macd.model.PropertyApplicationPolicy.fail(context + "." + paths(index), ...
                            "Application dependencies must not reference themselves.");
                    end
                    edges(target, index) = true;
                end
            end

            % Prefer the earliest original property whenever multiple nodes are ready.
            order = zeros(1, count);
            remaining = true(1, count);
            for index = 1:count
                ready = find(remaining & ~any(edges, 1), 1);
                if isempty(ready)
                    macd.model.PropertyApplicationPolicy.fail(context, ...
                        "Cyclic application dependencies: " + strjoin(paths(remaining), ", ") + ".");
                end
                order(index) = ready;
                remaining(ready) = false;
                edges(ready, :) = false;
            end
        end
    end

    methods (Static, Access = private)
        function value = identifier(raw, allowed, context)
            % identifier Check one symbolic token without coercing numeric values.
            arguments (Input)
                raw
                allowed (1, :) string
                context (1, 1) string
            end
            arguments (Output)
                value (1, 1) string
            end

            if ~(ischar(raw) && isrow(raw)) && ~(isstring(raw) && isscalar(raw))
                macd.model.PropertyApplicationPolicy.fail(context, "Expected one string identifier.");
            end
            value = string(raw);
            if ismissing(value) || ~any(allowed == value)
                macd.model.PropertyApplicationPolicy.fail(context, ...
                    "Expected one of: " + strjoin(allowed, ", ") + ".");
            end
        end

        function fail(context, message)
            % fail Report one contextual catalog contract violation.
            arguments (Input)
                context (1, 1) string
                message (1, 1) string
            end

            error("macd:ComponentCatalogLoader:InvalidCatalog", "%s: %s", context, message);
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
