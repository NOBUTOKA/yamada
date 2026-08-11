classdef ParentContextRule
    % ParentContextRule Describe direct-parent property contributions.
    %   This immutable value class contributes and suppresses typed properties.

    properties (SetAccess = private)
        % ParentFactories - Direct parent factories that select this rule.
        ParentFactories string = strings(1, 0)
        % AddedProperties - Ordered typed properties contributed by the parent.
        AddedProperties macd.model.PropertyDefinition = macd.model.PropertyDefinition.empty
        % SuppressedPaths - Intrinsic property paths hidden by the parent.
        SuppressedPaths string = strings(1, 0)
    end

    methods
        function obj = ParentContextRule(parentFactories, addedProperties, suppressedPaths)
            % ParentContextRule Create one direct-parent property contribution rule.
            arguments (Input)
                parentFactories string = strings(1, 0)
                addedProperties macd.model.PropertyDefinition = macd.model.PropertyDefinition.empty
                suppressedPaths string = strings(1, 0)
            end
            arguments (Output)
                obj (1, 1) macd.model.ParentContextRule
            end

            % Retain only typed declarative rule data.
            obj.ParentFactories = parentFactories;
            obj.AddedProperties = addedProperties;
            obj.SuppressedPaths = suppressedPaths;
        end

        function result = appliesTo(obj, parentFactory)
            % appliesTo Return whether this rule applies to one direct parent factory.
            arguments (Input)
                obj (1, 1) macd.model.ParentContextRule
                parentFactory (1, 1) string
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = any(obj.ParentFactories == parentFactory);
        end
    end

    methods (Static)
        function result = grid()
            % grid Create the standard GridLayout child placement rule.
            arguments (Output)
                result (1, 1) macd.model.ParentContextRule
            end
            metadata = struct("category", "Layout", "editor", "number");
            added = [macd.model.PropertyDefinition("Layout.Row", [], false, true, metadata); ...
                macd.model.PropertyDefinition("Layout.Column", [], false, true, metadata)];
            result = macd.model.ParentContextRule("uigridlayout", added, "Position");
        end

        function result = fromKind(parentFactories, kind)
            % fromKind Construct an allowlisted rule from declarative catalog data.
            arguments (Input)
                parentFactories string
                kind (1, 1) string
            end
            arguments (Output)
                result (1, 1) macd.model.ParentContextRule
            end
            switch kind
                case "grid"
                    metadata = struct("category", "Layout", "editor", "number");
                    added = [macd.model.PropertyDefinition("Layout.Row", [], false, true, metadata); ...
                        macd.model.PropertyDefinition("Layout.Column", [], false, true, metadata)];
                    result = macd.model.ParentContextRule(parentFactories, added, "Position");
                case "absolute"
                    metadata = struct("category", "Layout", "editor", "numericVector");
                    result = macd.model.ParentContextRule(parentFactories, ...
                        macd.model.PropertyDefinition("Position", [], false, true, metadata), ...
                        ["Layout.Row", "Layout.Column"]);
                case "structural"
                    result = macd.model.ParentContextRule(parentFactories, macd.model.PropertyDefinition.empty, ["Position", "Layout.Row", "Layout.Column"]);
                otherwise
                    error("macd:ParentContextRule:UnknownKind", "Unknown parent context kind.");
            end
        end

        function result = absolute()
            % absolute Create the standard absolute-positioning child rule.
            arguments (Output)
                result (1, 1) macd.model.ParentContextRule
            end
            parents = ["uifigure", "uipanel", "uitab", "uibuttongroup"];
            metadata = struct("category", "Layout", "editor", "numericVector");
            result = macd.model.ParentContextRule(parents, ...
                macd.model.PropertyDefinition("Position", [], false, true, metadata), ...
                ["Layout.Row", "Layout.Column"]);
        end
    end
end

%{
MatlabAppClassDesigner - Declarative direct-parent property applicability rule.
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
