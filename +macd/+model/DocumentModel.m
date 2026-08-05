classdef DocumentModel < handle
    % DocumentModel Hold shared state for new and parsed AppBase documents.
    %   This handle class owns document identity, ordered component records,
    %   source snapshots, diagnostics, unknown regions, and pending edits. It does
    %   not parse source, render UI controls, or generate MATLAB code itself.
    %
    %   Example:
    %       document = macd.model.DocumentModel("ExampleApp");

    properties
        % ClassName - MATLAB class name represented by this document.
        ClassName string = ""
        % FilePath - Optional path of the source file represented by the document.
        FilePath string = ""
        % OriginalText - Exact source snapshot supplied to the parser.
        OriginalText string = ""
        % GeneratedText - Latest generated or rewritten source preview.
        GeneratedText string = ""
        % Components - Ordered macd.model.ComponentRecord handle objects.
        Components macd.model.ComponentRecord = ...
            macd.model.ComponentRecord.empty
        % RootComponentId - Stable identity of the root UI component.
        RootComponentId string = ""
        % Diagnostics - Current document-level diagnostics.
        Diagnostics macd.model.Diagnostic = macd.model.Diagnostic.empty
        % UnknownRegions - Preserved source regions the editor does not interpret.
        UnknownRegions cell = {}
        % PendingEdits - Structured edits awaiting source application.
        PendingEdits cell = {}
        % Encoding - Text encoding used when the document is written.
        Encoding string = "UTF-8"
        % LineEnding - Named line-ending policy used by source output.
        LineEnding string = "CRLF"
        % Metadata - Extensible document data not interpreted by the core model.
        Metadata struct = struct()
    end

    methods
        function obj = DocumentModel(className)
            % DocumentModel Create a shared document for new or parsed apps.
            arguments (Input)
                className string = ""
            end
            arguments (Output)
                obj (1, 1) macd.model.DocumentModel
            end

            % Normalize the class name while retaining all other defaults.
            obj.ClassName = className;
        end

        function addComponent(obj, component, parentId)
            % addComponent Add a component and update its ordered parent link.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
                component (1, 1) macd.model.ComponentRecord
                parentId string = ""
            end

            % Reject duplicate identities before mutating either record.
            if ~isempty(obj.getComponent(component.Id))
                error("macd:DocumentModel:DuplicateId", ...
                    "Component ID ""%s"" already exists.", component.Id);
            end
            % Resolve and update both sides of an optional parent relation.
            if strlength(parentId) > 0
                parent = obj.getComponent(parentId);
                if isempty(parent)
                    error("macd:DocumentModel:UnknownParent", ...
                        "Parent component ID ""%s"" does not exist.", parentId);
                end
                component.ParentId = parentId;
                parent.addChild(component.Id);
            end

            % Append in generation order and identify the first root component.
            obj.Components(end + 1) = component;
            if strlength(component.ParentId) == 0 && ...
                    strlength(obj.RootComponentId) == 0
                obj.RootComponentId = component.Id;
            end
        end

        function component = getComponent(obj, id)
            % getComponent Find a component by stable identifier, or return empty.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
                id string
            end
            arguments (Output)
                component
            end

            % Search the small ordered collection without changing its order.
            component = [];
            for index = 1:numel(obj.Components)
                candidate = obj.Components(index);
                if candidate.Id == id
                    component = candidate;
                    return
                end
            end
        end

        function component = getComponentByName(obj, name)
            % getComponentByName Find a component by MATLAB property name.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
                name string
            end
            arguments (Output)
                component
            end

            % Names are validated separately, so this lookup stays read-only.
            component = [];
            for index = 1:numel(obj.Components)
                candidate = obj.Components(index);
                if candidate.Name == name
                    component = candidate;
                    return
                end
            end
        end
    end
end

%{
MatlabAppClassDesigner - Shared document model for new and parsed apps.
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
