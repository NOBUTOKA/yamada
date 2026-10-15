classdef PropertyApplicationPolicy
    % PropertyApplicationPolicy Describe declarative property initialization rules.
    %   This value class validates catalog policy data and orders a complete
    %   property surface. It does not apply setters or evaluate user source.
    %
    %   Example:
    %       policy = macd.model.PropertyApplicationPolicy( ...
    %           struct("applyAfter", {{"Items"}}, "nameValue", "supported"));

    properties (SetAccess = private)
        % ApplyAfter - Property paths that must be initialized before this value.
        ApplyAfter string = strings(1, 0)
        % NameValue - Verified constructor support, or unknown for unaudited data.
        NameValue string = "unknown"
        % EffectPolicy - Allowlisted policy for resolving implicit setter effects.
        EffectPolicy string = "none"
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
                ["applyAfter", "nameValue", "effectPolicy"]);
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
                    "tickMode", "componentReference", "layout"], context + ".effectPolicy");
            end
        end
    end

    methods (Static)
        function order = orderDefinitions(definitions, context)
            % orderDefinitions Validate dependencies and return a stable topological order.
            arguments (Input)
                definitions macd.model.PropertyDefinition
                context (1, 1) string = "properties"
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
