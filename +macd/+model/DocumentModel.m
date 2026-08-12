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
        UnknownRegions macd.model.UnknownSourceRegion = ...
            macd.model.UnknownSourceRegion.empty
        % PendingEdits - Structured edits awaiting source application.
        PendingEdits cell = {}
        % Encoding - Encoding preserved for opened source or used for new output.
        Encoding string = "UTF-8"
        % LineEnding - Convention preserved for opened source or used for new output.
        LineEnding string = "CRLF"
        % Metadata - Extensible document data not interpreted by the core model.
        Metadata struct = struct()
        % History - Reversible editor operations, ordered from oldest to newest.
        History cell = {}
        % HistoryIndex - Number of operations currently applied in History.
        HistoryIndex double = 0
        % HistoryLimit - Maximum number of retained undoable operations.
        HistoryLimit double = 100
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

        function component = insertComponent(obj, registry, factory, parentId)
            % insertComponent Create and insert one registry-approved component.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
                registry (1, 1) macd.model.ComponentRegistry
                factory string
                parentId string
            end
            arguments (Output)
                component (1, 1) macd.model.ComponentRecord
            end

            % Validate the factory and parent before changing document state.
            definition = registry.get(factory);
            if definition.IsRoot || definition.IsProgrammaticOnly || ...
                    definition.Category == "FigureTools" || ...
                    definition.RequiresParentComponent
                error("macd:DocumentModel:UnsupportedInsertion", ...
                    "Factory ""%s"" is not eligible for Phase 5 insertion.", factory);
            end
            parent = obj.getComponent(parentId);
            if isempty(parent)
                error("macd:DocumentModel:UnknownParent", ...
                    "Parent component ID ""%s"" does not exist.", parentId);
            end
            if ~any(definition.AllowedParentFactories == parent.Factory)
                error("macd:DocumentModel:InvalidInsertionParent", ...
                    "Factory ""%s"" cannot be inserted under ""%s"".", ...
                    factory, parent.Factory);
            end

            % Choose a stable MATLAB property name and safe initial geometry.
            name = obj.uniqueComponentName(obj.displayName(factory));
            component = macd.model.ComponentRecord(obj.newComponentId(), name, ...
                definition.Factory, definition.DeclaredType, "generated");
            component.CreationArguments = definition.CreationArguments;
            effectiveProperties = registry.getEffectiveProperties(definition.Factory, parent.Factory);
            effectivePaths = string({effectiveProperties.Path});
            if any(effectivePaths == "Layout.Row")
                component.setProperty("Layout.Row", 1);
            end
            if any(effectivePaths == "Layout.Column")
                component.setProperty("Layout.Column", 1);
            end
            if any(effectivePaths == "Position")
                component.setProperty("Position", obj.nextAbsolutePosition(parent));
            end
            obj.addComponentAt(component, parentId, numel(obj.Components) + 1);
            obj.recordHistory(struct("Kind", "insert", "Component", component, ...
                "ParentId", parentId, "Index", find(obj.Components == component, 1)));
        end

        function entry = setProperty(obj, componentId, path, value)
            % setProperty Change one component property and record its prior state.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
                componentId string
                path string
                value
            end
            arguments (Output)
                entry (1, 1) macd.model.PropertyEntry
            end

            % Validate the component before capturing the reversible old value.
            component = obj.getComponent(componentId);
            if isempty(component)
                error("macd:DocumentModel:UnknownComponent", ...
                    "Component ID ""%s"" does not exist.", componentId);
            end
            oldEntry = component.getProperty(path);
            oldValue = [];
            hadOldValue = ~isempty(oldEntry);
            if hadOldValue
                if ~oldEntry.IsEditable
                    error("macd:DocumentModel:ReadOnlyProperty", ...
                        "Property ""%s"" is source-backed and read-only.", path);
                end
                oldValue = oldEntry.LiteralValue;
            end
            entry = component.setProperty(path, value);
            obj.recordHistory(struct("Kind", "property", "ComponentId", componentId, ...
                "Path", path, "HadOldValue", hadOldValue, "OldValue", oldValue, ...
                "NewValue", value));
        end

        function states = getEffectivePropertyStates(obj, registry, componentId)
            % getEffectivePropertyStates Join effective definitions with explicit entries only.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
                registry (1, 1) macd.model.ComponentRegistry
                componentId string
            end
            arguments (Output)
                states (1, :) struct
            end

            % Resolve parent context without materializing any catalog defaults.
            component = obj.getComponent(componentId);
            if isempty(component)
                error("macd:DocumentModel:UnknownComponent", ...
                    "Component ID ""%s"" does not exist.", componentId);
            end
            parentFactory = "";
            if strlength(component.ParentId) > 0
                parent = obj.getComponent(component.ParentId);
                parentFactory = parent.Factory;
            end
            definitions = registry.getEffectiveProperties(component.Factory, parentFactory);
            states = repmat(struct("Definition", macd.model.PropertyDefinition(), ...
                "Entry", macd.model.PropertyEntry.empty, "IsExplicit", false), ...
                1, numel(definitions));
            for index = 1:numel(definitions)
                entry = component.getProperty(definitions(index).Path);
                states(index).Definition = definitions(index);
                states(index).Entry = entry;
                states(index).IsExplicit = ~isempty(entry);
            end
        end

        function resetProperty(obj, componentId, path)
            % resetProperty Remove one generated literal assignment with reversible history.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
                componentId string
                path string
            end

            % Refuse source-backed and parsed assignments until deletion ownership exists.
            component = obj.getComponent(componentId);
            if isempty(component)
                error("macd:DocumentModel:UnknownComponent", ...
                    "Component ID ""%s"" does not exist.", componentId);
            end
            entry = component.getProperty(path);
            if isempty(entry)
                return
            end
            if ~entry.IsEditable
                error("macd:DocumentModel:ReadOnlyProperty", ...
                    "Property ""%s"" is source-backed and read-only.", path);
            end
            if entry.Origin == "parsed"
                error("macd:DocumentModel:ParsedPropertyResetUnsupported", ...
                    "Parsed property ""%s"" cannot be removed safely yet.", path);
            end

            % Keep absence as a first-class history state instead of materializing a default.
            oldValue = entry.LiteralValue;
            component.removeProperty(path);
            obj.recordHistory(struct("Kind", "reset-property", ...
                "ComponentId", componentId, "Path", path, "OldValue", oldValue));
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

        function removeComponent(obj, id)
            % removeComponent Remove one leaf component and retain its deletion intent.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
                id string
            end

            % Locate the record before changing its parent or document ordering.
            component = obj.getComponent(id);
            if isempty(component)
                error("macd:DocumentModel:UnknownComponent", ...
                    "Component ID ""%s"" does not exist.", id);
            end
            if ~isempty(component.Children)
                error("macd:DocumentModel:NonLeafDeletion", ...
                    "Component ""%s"" has children and cannot be deleted safely.", id);
            end
            if id == obj.RootComponentId
                error("macd:DocumentModel:RootDeletion", ...
                    "The root component cannot be deleted.");
            end

            % Retain parsed records so the source generator can check ownership.
            index = find(obj.Components == component, 1);
            pendingIndex = obj.addDeletionIntent(component);
            obj.removeComponentAt(component);
            obj.recordHistory(struct("Kind", "delete", "Component", component, ...
                "ParentId", component.ParentId, "Index", index, ...
                "PendingIndex", pendingIndex));
        end

        function result = canUndo(obj)
            % canUndo Report whether one committed edit can be reversed.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = obj.HistoryIndex > 0;
        end

        function result = canRedo(obj)
            % canRedo Report whether one undone edit can be reapplied.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = obj.HistoryIndex < numel(obj.History);
        end

        function undo(obj)
            % undo Reverse the most recent document edit.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
            end
            if ~obj.canUndo()
                error("macd:DocumentModel:NoUndo", "There is no edit to undo.");
            end
            edit = obj.History{obj.HistoryIndex};
            obj.applyHistory(edit, false);
            obj.HistoryIndex = obj.HistoryIndex - 1;
        end

        function redo(obj)
            % redo Reapply the next edit in the document history.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
            end
            if ~obj.canRedo()
                error("macd:DocumentModel:NoRedo", "There is no edit to redo.");
            end
            edit = obj.History{obj.HistoryIndex + 1};
            obj.applyHistory(edit, true);
            obj.HistoryIndex = obj.HistoryIndex + 1;
        end
    end

    methods (Access = private)
        function addComponentAt(obj, component, parentId, index)
            % addComponentAt Insert one record at a deterministic collection index.
            parent = obj.getComponent(parentId);
            component.ParentId = parentId;
            parent.addChild(component.Id);
            index = min(max(index, 1), numel(obj.Components) + 1);
            obj.Components = [obj.Components(1:index - 1), component, ...
                obj.Components(index:end)];
        end

        function removeComponentAt(obj, component)
            % removeComponentAt Remove one already-validated leaf without history.
            parent = obj.getComponent(component.ParentId);
            if ~isempty(parent)
                parent.removeChild(component.Id);
            end
            obj.Components(obj.Components == component) = [];
        end

        function index = addDeletionIntent(obj, component)
            % addDeletionIntent Retain a parsed deletion for conservative generation.
            index = 0;
            if component.Origin ~= "parsed"
                return
            end
            pending = struct("Kind", "delete-component", "Component", component);
            obj.PendingEdits{end + 1} = pending;
            index = numel(obj.PendingEdits);
        end

        function recordHistory(obj, edit)
            % recordHistory Append an edit and discard any redo branch.
            if obj.HistoryIndex < numel(obj.History)
                obj.History = obj.History(1:obj.HistoryIndex);
            end
            obj.History{end + 1} = edit;
            obj.HistoryIndex = numel(obj.History);
            if numel(obj.History) > obj.HistoryLimit
                obj.History(1) = [];
                obj.HistoryIndex = obj.HistoryIndex - 1;
            end
        end

        function applyHistory(obj, edit, forward)
            % applyHistory Apply or reverse one history record without recording it.
            switch edit.Kind
                case "insert"
                    if forward
                        obj.addComponentAt(edit.Component, edit.ParentId, edit.Index);
                    else
                        obj.removeComponentAt(edit.Component);
                    end
                case "delete"
                    if forward
                        obj.removeComponentAt(edit.Component);
                        obj.addDeletionIntent(edit.Component);
                    else
                        obj.addComponentAt(edit.Component, edit.ParentId, edit.Index);
                        obj.removeDeletionIntent(edit.Component);
                    end
                case "property"
                    component = obj.getComponent(edit.ComponentId);
                    if forward
                        component.setProperty(edit.Path, edit.NewValue);
                    elseif edit.HadOldValue
                        component.setProperty(edit.Path, edit.OldValue);
                    else
                        component.removeProperty(edit.Path);
                    end
                case "reset-property"
                    component = obj.getComponent(edit.ComponentId);
                    if forward
                        component.removeProperty(edit.Path);
                    else
                        component.setProperty(edit.Path, edit.OldValue);
                    end
            end
        end

        function removeDeletionIntent(obj, component)
            % removeDeletionIntent Remove only the matching parsed deletion record.
            for index = numel(obj.PendingEdits):-1:1
                pending = obj.PendingEdits{index};
                if isstruct(pending) && isfield(pending, "Kind") && ...
                        pending.Kind == "delete-component" && ...
                        pending.Component.Id == component.Id
                    obj.PendingEdits(index) = [];
                    return
                end
            end
        end

        function id = newComponentId(~)
            % newComponentId Create a practical opaque identity for one component.
            id = "component-" + string(randi([0 intmax("uint32")])) + "-" + ...
                string(randi([0 intmax("uint32")]));
        end

        function name = uniqueComponentName(obj, base)
            % uniqueComponentName Make a valid unused MATLAB property name.
            name = string(matlab.lang.makeValidName(char(base)));
            suffix = 1;
            while ~isempty(obj.getComponentByName(name))
                suffix = suffix + 1;
                name = string(matlab.lang.makeValidName(char(base + suffix)));
            end
        end

        function name = displayName(~, factory)
            % displayName Convert a factory name into a readable property base.
            base = regexprep(char(factory), "^ui", "");
            name = string(upper(base(1)) + string(base(2:end)));
        end

        function position = nextAbsolutePosition(~, parent)
            % nextAbsolutePosition Choose a visible nonoverlapping default rectangle.
            position = [20 20 100 30];
            count = numel(parent.Children);
            position(1:2) = position(1:2) + [20 20] * count;
        end
    end
end

%{
Copyright (C) 2026 Nobuto Kaitoh

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
