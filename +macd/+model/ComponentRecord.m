classdef ComponentRecord < handle
    % ComponentRecord Represent one UI component without hard-coded UI types.
    %   This handle class owns component identity, hierarchy links, creation data,
    %   property entries, and source metadata. Component-specific rules belong to
    %   ComponentRegistry rather than this record.
    %
    %   Example:
    %       label = macd.model.ComponentRecord( ...
    %           "label-1", "StatusLabel", "uilabel", ...
    %           "matlab.ui.control.Label", "generated");
    %       label.setProperty("Text", "Ready");

    properties (SetAccess = private)
        % Id - Stable identity used for hierarchy and source associations.
        Id string = ""
        % Factory - MATLAB UI factory function used to create the component.
        Factory string = ""
        % DeclaredType - MATLAB class declared for the generated app property.
        DeclaredType string = ""
        % Origin - Provenance label such as generated or parsed.
        Origin string = "generated"
        % Children - Ordered stable identities of direct child components.
        Children string = strings(1, 0)
        % Properties - Ordered macd.model.PropertyEntry handle objects.
        Properties macd.model.PropertyEntry = macd.model.PropertyEntry.empty
    end

    properties
        % Name - Editable MATLAB property name for the component.
        Name string = ""
        % CreationArguments - Ordered literal arguments passed to the factory.
        CreationArguments cell = {}
        % ParentId - Stable identity of the parent component, or empty for a root.
        ParentId string = ""
        % IsEditable - Whether the component can be changed by the editor.
        IsEditable logical = true
        % Diagnostics - Diagnostics currently associated with this component.
        Diagnostics macd.model.Diagnostic = macd.model.Diagnostic.empty
        % SourceSpans - Named source locations retained from parsed code.
        SourceSpans struct = struct("Declaration", [], "Creation", [])
        % Metadata - Extensible component-specific data not interpreted by the model.
        Metadata struct = struct()
    end

    methods
        function obj = ComponentRecord(id, name, factory, declaredType, origin)
            % ComponentRecord Create an extensible intermediate component record.
            arguments (Input)
                id string = ""
                name string = ""
                factory string = ""
                declaredType string = ""
                origin string = "generated"
            end
            arguments (Output)
                obj (1, 1) macd.model.ComponentRecord
            end

            % Preserve property defaults for the no-input constructor.
            if nargin == 0
                return
            end

            % Store identity and source-origin fields in the shared string form.
            obj.Id = id;
            obj.Name = name;
            obj.Factory = factory;
            obj.DeclaredType = declaredType;
            obj.Origin = origin;
        end

        function entry = setProperty(obj, path, value)
            % setProperty Add or update an editable property by its full path.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRecord
                path string
                value
            end
            arguments (Output)
                entry (1, 1) macd.model.PropertyEntry
            end

            % Reuse an existing entry so its metadata and source span survive.
            entry = obj.getProperty(path);
            if isempty(entry)
                entry = macd.model.PropertyEntry(path, value, obj.Origin);
                obj.Properties(end + 1) = entry;
            else
                if ~entry.IsEditable
                    error("macd:ComponentRecord:ReadOnlyProperty", ...
                        "Property ""%s"" is source-backed and read-only.", path);
                end
                entry.setLiteral(value);
            end
        end

        function entry = getProperty(obj, path)
            % getProperty Find a property entry by path, or return empty.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRecord
                path string
            end
            arguments (Output)
                entry
            end

            % Preserve insertion order while performing the path lookup.
            entry = [];
            for index = 1:numel(obj.Properties)
                candidate = obj.Properties(index);
                if candidate.Path == path
                    entry = candidate;
                    return
                end
            end
        end

        function addChild(obj, childId)
            % addChild Append a child identifier unless it is already present.
            arguments (Input)
                obj (1, 1) macd.model.ComponentRecord
                childId string
            end

            % Child order is significant for deterministic source generation.
            if ~any(obj.Children == childId)
                obj.Children(end + 1) = childId;
            end
        end
    end
end

%{
MatlabAppClassDesigner - Extensible intermediate UI component record.
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
