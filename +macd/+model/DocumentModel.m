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

    properties (SetAccess = private)
        % RenameEdits - Simultaneous source member renames retained across generation.
        RenameEdits struct = struct("ComponentId", {}, "Kind", {}, "OldName", {}, "NewName", {})
        % CallbackEdits - Source-owned callback intentions grouped by component and property.
        CallbackEdits macd.model.CallbackEdit = macd.model.CallbackEdit.empty
        % IsDirty - Whether the document has changes that are not known to be saved.
        IsDirty logical = true
        % SavedSource - Independent parsed positions in the last successfully written source.
        SavedSource macd.model.SavedSourceCheckpoint = macd.model.SavedSourceCheckpoint.empty
    end

    properties (Access = private)
        InputClock macd.model.InputChangeClock = macd.model.InputChangeClock.empty
        Evaluation macd.model.EvaluationContext = macd.model.EvaluationContext.empty
        SavedHistoryIndex double = NaN
        HasSavedHistoryCheckpoint logical = false
    end

    methods (Access = ?macd.model.EvaluationContext)
        function [clock, revision, tracked] = inputStamp(obj)
            % inputStamp Attach one acyclic write token and return its current state.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
            end
            arguments (Output)
                clock (1, 1) macd.model.InputChangeClock
                revision (1, 1) uint64
                tracked (1, 1) logical
            end
            if isempty(obj.InputClock)
                obj.InputClock = macd.model.InputChangeClock();
                for component = reshape(obj.Components, 1, []), component.bindInputClock(obj.InputClock); end
            end
            clock = obj.InputClock;
            revision = clock.Revision;
            tracked = clock.IsTracked;
        end
    end

    methods (Access = private)
        function noteInput(obj, value)
            % noteInput Notify the token only after evaluation has attached it to a complete object.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
                value
            end
            % Construction and materialization run without an attached token.
            if ~isempty(obj.InputClock), obj.InputClock.touch(value); end
        end

        function noteInputCollection(obj, value)
            % noteInputCollection Attach new owned records before recording their collection write.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
                value macd.model.ComponentRecord
            end
            if isempty(obj.InputClock), return, end
            for item = reshape(value, 1, []), item.bindInputClock(obj.InputClock); end
            obj.InputClock.touch([]);
        end
    end

    methods
        function set.ClassName(obj, value)
            % set.ClassName Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
                value
            end
            obj.ClassName = value;
            obj.noteInput(value);
        end

        function set.FilePath(obj, value)
            % set.FilePath Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
                value
            end
            obj.FilePath = value;
            obj.noteInput(value);
        end

        function set.OriginalText(obj, value)
            % set.OriginalText Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
                value
            end
            obj.OriginalText = value;
            obj.noteInput(value);
        end

        function set.Components(obj, value)
            % set.Components Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
                value
            end
            obj.Components = value;
            obj.noteInputCollection(obj.Components);
        end

        function set.RootComponentId(obj, value)
            % set.RootComponentId Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
                value
            end
            obj.RootComponentId = value;
            obj.noteInput(value);
        end

        function set.UnknownRegions(obj, value)
            % set.UnknownRegions Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
                value
            end
            obj.UnknownRegions = value;
            obj.noteInput(value);
        end

        function set.PendingEdits(obj, value)
            % set.PendingEdits Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
                value
            end
            obj.PendingEdits = value;
            obj.noteInput(value);
        end

        function set.Encoding(obj, value)
            % set.Encoding Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
                value
            end
            obj.Encoding = value;
            obj.noteInput(value);
        end

        function set.LineEnding(obj, value)
            % set.LineEnding Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
                value
            end
            obj.LineEnding = value;
            obj.noteInput(value);
        end

        function set.Metadata(obj, value)
            % set.Metadata Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
                value
            end
            obj.Metadata = value;
            obj.noteInput(value);
        end

        function set.RenameEdits(obj, value)
            % set.RenameEdits Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
                value
            end
            obj.RenameEdits = value;
            obj.noteInput(value);
        end

        function set.CallbackEdits(obj, value)
            % set.CallbackEdits Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
                value
            end
            obj.CallbackEdits = value;
            obj.noteInput(value);
        end

        function context = evaluationContext(obj, registry)
            % evaluationContext Reuse evaluations only while all semantic inputs remain equal.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
                registry (1, 1) macd.model.ComponentRegistry
            end
            arguments (Output)
                context (1, 1) macd.model.EvaluationContext
            end
            if isempty(obj.Evaluation) || (~obj.Evaluation.isReading(registry) && ...
                    ~obj.Evaluation.matches(obj, registry))
                previous = obj.Evaluation;
                obj.Evaluation = macd.model.EvaluationContext(obj, registry);
                if ~isempty(previous), obj.Evaluation.inheritStates(previous); end
            end
            context = obj.Evaluation;
        end

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

        function component = insertComponent(obj, registry, factory, parentId, creationArguments)
            % insertComponent Create and insert one registry-approved component variant.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
                registry (1, 1) macd.model.ComponentRegistry
                factory string
                parentId string
                creationArguments cell = {}
            end
            arguments (Output)
                component (1, 1) macd.model.ComponentRecord
            end

            % Validate the factory and parent before changing document state.
            definition = registry.get(factory, creationArguments);
            if definition.IsRoot || definition.IsProgrammaticOnly || ...
                    definition.Category == "FigureTools" || ...
                    definition.RequiresParentComponent
                error("macd:DocumentModel:UnsupportedInsertion", ...
                    "Factory ""%s"" is not eligible for palette insertion.", factory);
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
            effectiveProperties = registry.getEffectiveProperties(definition.Factory, parent.Factory, ...
                definition.CreationArguments);
            effectivePaths = string({effectiveProperties([effectiveProperties.IsEditable]).Path});
            if any(effectivePaths == "Layout.Row")
                component.setProperty("Layout.Row", 1);
            end
            if any(effectivePaths == "Layout.Column")
                component.setProperty("Layout.Column", 1);
            end
            if any(effectivePaths == "Position")
                component.setProperty("Position", obj.nextAbsolutePosition(parent, definition.DefaultSize));
            end
            obj.addComponentAt(component, parentId, numel(obj.Components) + 1);
            obj.recordHistory(struct("Kind", "insert", "Component", component, ...
                "ParentId", parentId, "Index", find(obj.Components == component, 1)));
        end

        function entry = setProperty(obj, componentId, path, value, registry)
            % setProperty Change one component property and record its prior state.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
                componentId string
                path string
                value
                registry macd.model.ComponentRegistry = macd.model.ComponentRegistry.empty
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
                if isequaln(oldValue, value)
                    if ~isempty(registry)
                        states = obj.getEffectivePropertyStates(registry, componentId);
                        obj.assertRequestedStates(states, macd.model.PropertyTransaction.singleChange(path, value));
                    end
                    entry = oldEntry;
                    return
                end
            end
            if ~isempty(registry)
                obj.preflightPropertyChanges(componentId, ...
                    macd.model.PropertyTransaction.singleChange(path, value), registry);
            end
            entry = component.setProperty(path, value);
            obj.recordHistory(struct("Kind", "property", "ComponentId", componentId, ...
                "Path", path, "HadOldValue", hadOldValue, "OldValue", {oldValue}, ...
                "NewValue", {value}, "TargetSettingId", obj.propertySettingId(entry)));
        end

        function entries = setPropertyBatch(obj, componentId, changes, registry)
            % setPropertyBatch Apply one preflighted property batch as a single undoable edit.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
                componentId (1, 1) string
                changes (1, :) struct
                registry macd.model.ComponentRegistry = macd.model.ComponentRegistry.empty
            end
            arguments (Output)
                entries macd.model.PropertyEntry
            end

            % Preflight every target before changing any component property.
            component = obj.getComponent(componentId);
            if isempty(component)
                error("macd:DocumentModel:UnknownComponent", ...
                    "Component ID ""%s"" does not exist.", componentId);
            end
            if isempty(changes) || ~isfield(changes, "Path") || ~isfield(changes, "Value")
                error("macd:DocumentModel:InvalidPropertyBatch", ...
                    "Every property batch change must provide Path and Value fields.");
            end
            paths = string({changes.Path});
            if any(strlength(paths) == 0) || numel(unique(paths)) ~= numel(paths)
                error("macd:DocumentModel:InvalidPropertyBatch", ...
                    "Property batch paths must be nonempty and unique.");
            end
            historyChanges = repmat(struct("Path", "", "HadOldValue", false, ...
                "OldValue", [], "NewValue", [], "TargetSettingId", ""), 1, numel(changes));
            for index = 1:numel(changes)
                entry = component.getProperty(paths(index));
                if ~isempty(entry) && ~entry.IsEditable
                    error("macd:DocumentModel:ReadOnlyProperty", ...
                        "Property ""%s"" is source-backed and read-only.", paths(index));
                end
                historyChanges(index).Path = paths(index);
                historyChanges(index).HadOldValue = ~isempty(entry);
                if ~isempty(entry)
                    historyChanges(index).OldValue = entry.LiteralValue;
                    historyChanges(index).TargetSettingId = obj.propertySettingId(entry);
                end
                historyChanges(index).NewValue = changes(index).Value;
            end

            unchanged = arrayfun(@(change) change.HadOldValue && ...
                isequaln(change.OldValue, change.NewValue), historyChanges);
            requested = changes;
            historyChanges(unchanged) = [];
            changes(unchanged) = [];
            prepared = macd.model.DocumentModel.empty;
            if ~isempty(registry)
                if ~isempty(changes)
                    prepared = obj.preflightPropertyChanges(componentId, requested, registry);
                else
                    states = obj.getEffectivePropertyStates(registry, componentId);
                    obj.assertRequestedStates(states, requested);
                end
            end

            % Commit only after every target is known to be editable and reversible.
            entries = macd.model.PropertyEntry.empty;
            try
                for index = 1:numel(changes)
                    entries(end + 1) = component.setProperty( ...
                        historyChanges(index).Path, historyChanges(index).NewValue); %#ok<AGROW>
                    historyChanges(index).TargetSettingId = obj.propertySettingId(entries(end));
                end
            catch exception
                % Preserve all-or-nothing semantics even if a future entry setter can fail.
                for rollbackIndex = index - 1:-1:1
                    obj.restoreBatchValue(component, historyChanges(rollbackIndex));
                end
                rethrow(exception)
            end
            if ~isempty(historyChanges)
                obj.recordHistory(struct("Kind", "property-batch", ...
                    "ComponentId", componentId, "Changes", historyChanges));
            end
            if ~isempty(prepared)
                obj.evaluationContext(registry).rememberConfiguration("combined", prepared);
            end
        end

        function entries = applyGridLayoutEdit(obj, gridId, changes, registry)
            % applyGridLayoutEdit Atomically apply one grid and direct-child layout change set.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
                gridId (1, 1) string
                changes (1, :) struct
                registry macd.model.ComponentRegistry = macd.model.ComponentRegistry.empty
            end
            arguments (Output)
                entries macd.model.PropertyEntry
            end

            % Preflight every grid-owned and direct-child target before mutation.
            grid = obj.getComponent(gridId);
            if isempty(grid) || grid.Factory ~= "uigridlayout"
                error("macd:DocumentModel:InvalidGridLayoutEdit", ...
                    "Grid layout ID ""%s"" does not identify a Grid Layout.", gridId);
            end
            if ~grid.IsEditable || isempty(changes) || ...
                    ~isfield(changes, "ComponentId") || ~isfield(changes, "Path") || ...
                    ~isfield(changes, "Value")
                error("macd:DocumentModel:InvalidGridLayoutEdit", ...
                    "A grid layout edit requires editable ComponentId, Path, and Value changes.");
            end
            componentIds = string({changes.ComponentId});
            paths = string({changes.Path});
            keys = componentIds + char(0) + paths;
            if any(strlength(componentIds) == 0) || any(strlength(paths) == 0) || ...
                    numel(unique(keys)) ~= numel(keys)
                error("macd:DocumentModel:InvalidGridLayoutEdit", ...
                    "Grid layout edit targets must be nonempty and unique.");
            end

            historyChanges = repmat(struct("ComponentId", "", "Path", "", ...
                "HadOldValue", false, "OldValue", [], "NewValue", []), 1, numel(changes));
            for index = 1:numel(changes)
                component = obj.getComponent(componentIds(index));
                if isempty(component) || ~component.IsEditable
                    error("macd:DocumentModel:InvalidGridLayoutEdit", ...
                        "Every grid layout edit target must be an editable component.");
                end
                obj.validateGridLayoutTarget(grid, component, paths(index), changes(index).Value);
                entry = component.getProperty(paths(index));
                if ~isempty(entry) && ~entry.IsEditable
                    error("macd:DocumentModel:ReadOnlyProperty", ...
                        "Property ""%s"" is source-backed and read-only.", paths(index));
                end
                historyChanges(index).ComponentId = componentIds(index);
                historyChanges(index).Path = paths(index);
                historyChanges(index).HadOldValue = ~isempty(entry);
                if ~isempty(entry)
                    historyChanges(index).OldValue = entry.LiteralValue;
                end
                historyChanges(index).NewValue = changes(index).Value;
            end

            % Check the combined emitted initialization before changing parsed records.
            if any(arrayfun(@(id) obj.getComponent(id).Origin == "parsed", componentIds)) && ...
                    strlength(obj.OriginalText) > 0
                if isempty(registry), registry = macd.model.ComponentRegistry.createDefault(); end
                candidate = obj.structuralCandidate();
                for change = changes
                    target = candidate.getComponent(string(change.ComponentId));
                    target.setProperty(string(change.Path), change.Value);
                end
                [source, diagnostics] = macd.source.RoundTripGenerator(registry).generate(candidate);
                if strlength(source) == 0 || macd.validation.ModelValidator.hasErrors(diagnostics)
                    error("macd:DocumentModel:UnsafePropertyEdit", "%s", strjoin(string({diagnostics.Message}), newline));
                end
                [parsed, diagnostics] = macd.source.AppSourceParser.parseText(source, registry);
                if macd.validation.ModelValidator.hasErrors(diagnostics)
                    error("macd:DocumentModel:UnsafePropertyEdit", "%s", strjoin(string({diagnostics.Message}), newline));
                end
                for id = unique(componentIds, "stable")
                    original = obj.getComponent(id);
                    configured = parsed.getComponentByName(original.Name);
                    if isempty(configured)
                        error("macd:DocumentModel:UnsafePropertyEdit", "A grid-edit component was not retained.");
                    end
                    states = parsed.getEffectivePropertyStates(registry, configured.Id);
                    obj.assertRequestedStates(states, changes(componentIds == id));
                end
            end

            % Commit once, and restore every prior entry if any future setter fails.
            entries = macd.model.PropertyEntry.empty;
            try
                for index = 1:numel(historyChanges)
                    component = obj.getComponent(historyChanges(index).ComponentId);
                    entries(end + 1) = component.setProperty( ...
                        historyChanges(index).Path, historyChanges(index).NewValue); %#ok<AGROW>
                end
            catch exception
                for rollbackIndex = index - 1:-1:1
                    component = obj.getComponent(historyChanges(rollbackIndex).ComponentId);
                    obj.restoreBatchValue(component, historyChanges(rollbackIndex));
                end
                rethrow(exception)
            end
            obj.recordHistory(struct("Kind", "grid-layout-edit", ...
                "GridId", gridId, "Changes", historyChanges));
        end

        function [states, diagnostics] = getEffectivePropertyStates(obj, registry, componentId)
            % getEffectivePropertyStates Join definitions and source entries with independent effective states.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
                registry (1, 1) macd.model.ComponentRegistry
                componentId string
            end
            arguments (Output)
                states (1, :) struct
                diagnostics macd.model.Diagnostic
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
            definitions = registry.getEffectiveProperties(component.Factory, parentFactory, ...
                component.CreationArguments);
            [resolved, diagnostics] = macd.model.PropertyStateResolver.resolve(component, definitions, obj, registry);
            states = repmat(struct("Definition", macd.model.PropertyDefinition(), ...
                "Entry", macd.model.PropertyEntry.empty, "IsExplicit", false, ...
                "Resolution", macd.model.PropertyState()), ...
                1, numel(definitions));
            for index = 1:numel(definitions)
                entry = component.getProperty(definitions(index).Path);
                states(index).Definition = definitions(index);
                states(index).Entry = entry;
                states(index).IsExplicit = ~isempty(entry);
                states(index).Resolution = resolved(index);
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
            oldEntry = entry.toStruct();
            beforeSettings = component.settingSnapshot();
            component.removeProperty(path);
            obj.recordHistory(struct("Kind", "reset-property", ...
                "ComponentId", componentId, "Path", path, "OldValue", oldValue, ...
                "OldEntry", oldEntry, "BeforeSettings", beforeSettings));
        end

        function confirmSavedSource(obj, checkpoint, registry)
            % confirmSavedSource Attach confirmed saved positions while retaining the immutable edit baseline.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
                checkpoint (1, 1) macd.model.SavedSourceCheckpoint
                registry (1, 1) macd.model.ComponentRegistry
            end

            % Validate before committing metadata or advancing the saved history position.
            checkpoint.assertCurrent(obj, registry);
            obj.SavedSource = checkpoint;
            obj.ClassName = checkpoint.ClassName;
            obj.FilePath = checkpoint.FilePath;
            obj.GeneratedText = checkpoint.SourceText;
            obj.markSaved();
        end

        function markSaved(obj)
            % markSaved Record the current history position as a confirmed save point.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
            end

            % Saving makes the exact current history position clean until a later edit.
            obj.SavedHistoryIndex = obj.HistoryIndex;
            obj.HasSavedHistoryCheckpoint = true;
            obj.IsDirty = false;
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

        function name = sourceComponentName(obj, componentId)
            % sourceComponentName Return the identifier belonging to original source spans.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
                componentId (1, 1) string
            end
            arguments (Output)
                name (1, 1) string
            end

            component = obj.getComponent(componentId);
            name = component.Name;
            mappings = obj.RenameEdits;
            index = find(string({mappings.ComponentId}) == componentId & string({mappings.Kind}) == "property", 1);
            if ~isempty(index), name = mappings(index).OldName; end
        end

        function name = effectiveMemberName(obj, name)
            % effectiveMemberName Resolve an original handler to its current member name.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
                name (1, 1) string
            end
            arguments (Output)
                name (1, 1) string
            end

            mappings = obj.RenameEdits;
            index = find(string({mappings.OldName}) == name & string({mappings.Kind}) == "method", 1);
            if ~isempty(index), name = mappings(index).NewName; end
        end

        function renameComponent(obj, componentId, newName, registry)
            % renameComponent Atomically rename a property and its default callback methods.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
                componentId (1, 1) string
                newName (1, 1) string
                registry (1, 1) macd.model.ComponentRegistry = macd.model.ComponentRegistry.createDefault()
            end

            % Validate the complete current source before changing authoritative state.
            component = obj.getComponent(componentId);
            if isempty(component) || ~component.IsEditable
                error("macd:DocumentModel:UnsafeComponentRename", "This component cannot be renamed safely.");
            end
            if component.Origin == "parsed" && ...
                    (isempty(component.SourceSpans.Declaration) || ~component.SourceSpans.Declaration.isKnown() || ...
                    isempty(component.SourceSpans.Creation) || ~component.SourceSpans.Creation.isKnown())
                error("macd:DocumentModel:UnsafeComponentRename", "Component declaration or creation ownership is unknown.");
            end
            oldName = component.Name;
            if oldName == newName, return, end
            previousText = obj.GeneratedText;
            previousDiagnostics = obj.Diagnostics;
            before = obj.RenameEdits;
            try
                [source, diagnostics] = macd.source.RoundTripGenerator(registry).generate(obj);
                if macd.validation.ModelValidator.hasErrors(diagnostics)
                    error("macd:DocumentModel:UnsafeComponentRename", "Resolve source generation errors before renaming.");
                end
                macd.source.ComponentNameRewriter.validate(source, oldName, newName);
                inherited = [string(properties("matlab.apps.AppBase")); string(methods("matlab.apps.AppBase"))];
                if any(inherited == newName) || newName == obj.ClassName || ...
                        any(string({obj.Components.Name}) == newName) || ...
                        any(string({before.OldName}) == newName & ...
                        (string({before.ComponentId}) ~= componentId | string({before.Kind}) == "method"))
                    error("macd:DocumentModel:ComponentNameCollision", "The name '%s' is already reserved.", newName);
                end
                after = obj.updatedRenameMappings(before, componentId, "property", oldName, newName);

                % Only exclusively owned default handler names follow the component.
                states = macd.source.CallbackSourceAnalyzer.analyze(obj, componentId, registry);
                members = macd.source.ComponentNameRewriter.memberNames(source);
                code = macd.source.ComponentNameRewriter.codeMask(source);
                identifiers = string(regexp(code, '[A-Za-z]\w*', 'match'));
                used = [members, identifiers, string({before.OldName}), newName, obj.ClassName, "createComponents", "delete"];
                for state = states(:)'
                    handler = state.HandlerName;
                    if strlength(handler) == 0, continue, end
                    if state.State ~= "editable"
                        % Extra static calls may prevent deletion without preventing a rename.
                        handles = regexp(code, '@(?:app\s*\.\s*)?' + handler + '(?!\w)', 'match');
                        if ~any(members == handler) || numel(handles) ~= 1 || ...
                                ~macd.source.ComponentNameRewriter.canRenameHandler(source, handler)
                            continue
                        end
                    end
                    stem = macd.source.ComponentNameRewriter.defaultHandler(oldName, state.Name);
                    if handler ~= stem && isempty(regexp(handler, "^" + stem + "_[2-9][0-9]*$|^" + stem + "_1[0-9]+$", 'once'))
                        continue
                    end
                    suffix = extractAfter(handler, strlength(stem));
                    newStem = macd.source.ComponentNameRewriter.defaultHandler(newName, state.Name);
                    newHandler = newStem + suffix;
                    number = 1;
                    while any(used(used ~= handler) == newHandler) || any(inherited == newHandler)
                        number = number + 1;
                        newHandler = newStem + "_" + number;
                    end
                    used(used == handler) = newHandler;
                    after = obj.updatedRenameMappings(after, componentId, "method", handler, newHandler);
                end
                component.Name = newName;
                obj.RenameEdits = after;
                [renamedSource, diagnostics] = macd.source.RoundTripGenerator(registry).generate(obj);
                if macd.validation.ModelValidator.hasErrors(diagnostics) || ...
                        ~any(macd.source.ComponentNameRewriter.memberNames(renamedSource) == newName)
                    error("macd:DocumentModel:UnsafeComponentRename", "The renamed source could not be generated safely.");
                end
            catch exception
                component.Name = oldName;
                obj.RenameEdits = before;
                obj.GeneratedText = previousText;
                obj.Diagnostics = previousDiagnostics;
                rethrow(exception)
            end
            obj.recordHistory(struct("Kind", "rename", "ComponentId", componentId, ...
                "OldName", oldName, "NewName", newName, "Before", before, "After", after));
        end

        function applyCallbackAction(obj, componentId, name, action, registry)
            % applyCallbackAction Preflight and record a binding-plus-method edit as one history step.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
                componentId (1, 1) string
                name (1, 1) string
                action (1, 1) string {mustBeMember(action, ["Add", "Delete"])}
                registry (1, 1) macd.model.ComponentRegistry
            end

            % Validate current availability before changing any document or history state.
            states = macd.source.CallbackSourceAnalyzer.analyze(obj, componentId, registry);
            state = states(string({states.Name}) == name);
            if numel(state) ~= 1 || ...
                    ~(action == "Add" && state.State == "absent" || action == "Delete" && state.State == "editable")
                error("macd:DocumentModel:UnsafeCallbackEdit", "The callback action is unavailable or unsafe.");
            end
            component = obj.getComponent(componentId);
            before = obj.CallbackEdits;
            after = before;
            existing = find(string({before.ComponentId}) == componentId & string({before.Name}) == name);
            original = state;
            if ~isempty(existing)
                prior = before(existing);
                original = macd.model.CallbackState(name, state.State, "", "", ...
                    prior.BindingSpan, prior.MethodSpan, prior.BindingAnchor, prior.MethodAnchor);
                after(existing) = [];
            end
            handler = "";
            method = "";
            if action == "Add"
                % Avoid all source tokens, component names, and pending generated method names.
                stem = macd.source.ComponentNameRewriter.defaultHandler(component.Name, name);
                handler = stem;
                suffix = 1;
                used = [string({obj.Components.Name}), string({after.HandlerName}), ...
                    string({obj.RenameEdits.OldName}), string({obj.RenameEdits.NewName}), obj.ClassName, "createComponents", "delete"];
                while any(used == handler) || ~isempty(regexp(obj.OriginalText, ...
                        '(?<!\w)' + handler + '(?!\w)', 'once'))
                    suffix = suffix + 1;
                    handler = stem + "_" + suffix;
                end
                lines = ["        function " + handler + "(app, event)"; ...
                    "            % " + handler + " Handle the " + name + " callback."; ...
                    "            arguments (Input)"; "                app (1, 1) " + obj.ClassName; ...
                    "                event"; "            end"; ""; ...
                    "            % Add callback behavior here."; "        end"];
                ending = string(newline);
                if obj.LineEnding == "CRLF", ending = string(sprintf("\r\n")); end
                method = strjoin(lines, ending);
            end
            if action == "Add" || ~isempty(original.BindingSpan) || ~isempty(original.MethodSpan)
                after(end + 1) = macd.model.CallbackEdit(componentId, name, action, handler, method, original, obj.OriginalText);
            end

            % Preflight the complete generated result, restoring every temporary state on failure.
            previousText = obj.GeneratedText;
            previousDiagnostics = obj.Diagnostics;
            obj.CallbackEdits = after;
            try
                [~, diagnostics] = macd.source.RoundTripGenerator(registry).generate(obj);
                if macd.validation.ModelValidator.hasErrors(diagnostics)
                    error("macd:DocumentModel:UnsafeCallbackSource", "%s", ...
                        strjoin(string({diagnostics.Message}), newline));
                end
            catch exception
                obj.CallbackEdits = before;
                obj.GeneratedText = previousText;
                obj.Diagnostics = previousDiagnostics;
                rethrow(exception)
            end
            % Commit only a fully generated intention snapshot; original bodies remain untouched.
            obj.recordHistory(struct("Kind", "callback", "Before", before, "After", after));
        end

        function candidate = structuralCandidate(obj)
            % structuralCandidate Clone mutable document data for isolated source preflight.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
            end
            arguments (Output)
                candidate (1, 1) macd.model.DocumentModel
            end

            snapshot = macd.model.SubtreeSnapshot(obj, obj.RootComponentId);
            candidate = macd.model.DocumentModel(obj.ClassName);
            candidate.Components = snapshot.materialize();
            fields = ["FilePath", "OriginalText", "GeneratedText", "RootComponentId", ...
                "Diagnostics", "UnknownRegions", "Encoding", "LineEnding", "Metadata"];
            for field = fields, candidate.(field) = obj.(field); end
            candidate.CallbackEdits = obj.CallbackEdits;
            if isprop(obj, "RenameEdits"), candidate.("RenameEdits") = obj.("RenameEdits"); end
            % Pending deletion records are read-only inputs to generation.
            candidate.PendingEdits = obj.PendingEdits;
        end

        function removeSubtree(obj, id, registry)
            % removeSubtree Preflight and delete a complete subtree as one history step.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
                id (1, 1) string
                registry (1, 1) macd.model.ComponentRegistry = macd.model.ComponentRegistry.createDefault()
            end

            if id == obj.RootComponentId
                error("macd:DocumentModel:RootDeletion", "The root component cannot be deleted.");
            end
            snapshot = macd.model.SubtreeSnapshot(obj, id);
            ids = string({snapshot.Records.Id});
            removed = obj.Components(ismember(string({obj.Components.Id}), ids));
            for component = removed
                if ~component.IsEditable
                    error("macd:DocumentModel:UnsafeSubtreeEdit", "The subtree contains a read-only component.");
                end
                callbacks = macd.source.CallbackSourceAnalyzer.analyze(obj, component.Id, registry);
                if any(string({callbacks.State}) ~= "absent")
                    error("macd:DocumentModel:UnsafeSubtreeEdit", "Callback ownership prevents complete subtree deletion.");
                end
            end
            % Source removals retain original ownership even after placement changes.
            sourceRemoved = removed;
            if strlength(obj.OriginalText) > 0
                originalDocument = macd.source.AppSourceParser.parseText(obj.OriginalText, registry);
                for sourceIndex = 1:numel(sourceRemoved)
                    originalComponent = originalDocument.getComponent(sourceRemoved(sourceIndex).Id);
                    if ~isempty(originalComponent), sourceRemoved(sourceIndex) = originalComponent; end
                end
            end
            rewrittenReferences = macd.source.SubtreeSourceEdits.detachedParentReferences(obj, ids);
            macd.source.SubtreeSourceEdits.deletion(obj.OriginalText, sourceRemoved, rewrittenReferences);

            % Preflight on independent records before changing document or history.
            candidate = obj.structuralCandidate();
            root = obj.getComponent(id);
            parent = obj.getComponent(root.ParentId);
            beforeChildren = parent.Children;
            beforeComponents = obj.Components;
            beforePending = obj.PendingEdits;
            afterPending = beforePending;
            afterPending{end + 1} = struct("Kind", "delete-subtree", "Components", sourceRemoved, ...
                "RewrittenReferences", rewrittenReferences);
            candidate.Components(ismember(string({candidate.Components.Id}), ids)) = [];
            candidateParent = candidate.getComponent(parent.Id);
            candidateParent.removeChild(id);
            candidate.PendingEdits = afterPending;
            [source, diagnostics] = macd.source.RoundTripGenerator(registry).generate(candidate);
            if macd.validation.ModelValidator.hasErrors(diagnostics)
                error("macd:DocumentModel:UnsafeSubtreeEdit", "%s", strjoin(string({diagnostics.Message}), newline));
            end

            % Commit the validated collection and parent order with one history record.
            obj.Components = obj.Components(~ismember(string({obj.Components.Id}), ids));
            parent.removeChild(id);
            obj.PendingEdits = afterPending;
            obj.GeneratedText = source;
            obj.Diagnostics = diagnostics;
            obj.recordHistory(struct("Kind", "subtree-delete", "ParentId", parent.Id, ...
                "BeforeChildren", beforeChildren, "AfterChildren", parent.Children, ...
                "BeforeComponents", beforeComponents, "AfterComponents", obj.Components, ...
                "BeforePending", {beforePending}, "AfterPending", {afterPending}));
        end

        function reparentSubtree(obj, id, parentId, registry, measuredPosition, targetCell, targetPosition)
            % reparentSubtree Move a complete subtree with stable identities and one history step.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
                id (1, 1) string
                parentId (1, 1) string
                registry (1, 1) macd.model.ComponentRegistry = macd.model.ComponentRegistry.createDefault()
                measuredPosition double {mustBeFinite} = []
                targetCell double {mustBeFinite} = []
                targetPosition double {mustBeFinite} = []
            end

            % Unexpanded execution cannot establish safe hierarchy or placement changes.
            if macd.model.PropertyStateResolver.hasUnresolvedExecution(obj)
                error("macd:DocumentModel:UnsafeSubtreeEdit", ...
                    "Unresolved initialization effects prevent proving subtree relocation safety.");
            end
            % Resolve a side-effect-free placement plan before preparing candidate data.
            snapshot = macd.model.SubtreeSnapshot(obj, id);
            ids = string({snapshot.Records.Id});
            try
                plan = macd.model.SubtreePlacementPlanner.prepare(obj, snapshot, parentId, registry, ids, ...
                    measuredPosition, [0 0], targetCell, targetPosition);
            catch exception
                error("macd:DocumentModel:UnsafeSubtreeEdit", "%s", string(exception.message));
            end
            root = obj.getComponent(id);
            if root.ParentId == parentId, return, end
            oldParent = obj.getComponent(root.ParentId);
            newParent = obj.getComponent(parentId);
            beforeParents = struct("Id", {oldParent.Id, newParent.Id}, ...
                "Children", {oldParent.Children, newParent.Children});
            beforeComponents = obj.Components;
            beforePending = obj.PendingEdits;
            candidate = obj.structuralCandidate();
            candidateRoot = candidate.getComponent(id);
            candidateOldParent = candidate.getComponent(root.ParentId);
            candidateNewParent = candidate.getComponent(parentId);
            candidateOldParent.removeChild(id);
            candidateNewParent.addChild(id);
            candidateRoot.ParentId = parentId;
            for change = plan.Changes
                if change.Remove
                    candidateRoot.removeProperty(change.Path);
                else
                    candidateRoot.setProperty(change.Path, change.Value);
                end
            end

            % Derive generation order from the complete changed hierarchy.
            hierarchy = macd.model.SubtreeSnapshot(candidate, candidate.RootComponentId);
            orderedIds = string({hierarchy.Records.Id});
            currentIds = string({candidate.Components.Id});
            [~, indices] = ismember(orderedIds, currentIds);
            candidate.Components = candidate.Components(indices);
            candidate.PendingEdits{end + 1} = struct("Kind", "reparent-subtree", ...
                "OriginalRecords", snapshot.Records);
            [source, diagnostics] = macd.source.RoundTripGenerator(registry).generate(candidate);
            if macd.validation.ModelValidator.hasErrors(diagnostics)
                error("macd:DocumentModel:UnsafeSubtreeEdit", "%s", strjoin(string({diagnostics.Message}), newline));
            end
            % A preserved later setter must not undo the requested destination geometry.
            [placedDocument, placedDiagnostics] = macd.source.AppSourceParser.parseText(source, registry);
            if macd.validation.ModelValidator.hasErrors(placedDiagnostics)
                error("macd:DocumentModel:UnsafeSubtreeEdit", "%s", strjoin(string({placedDiagnostics.Message}), newline));
            end
            placedRoot = placedDocument.getComponentByName(root.Name);
            if isempty(placedRoot)
                error("macd:DocumentModel:UnsafeSubtreeEdit", "The relocated component is missing from generated source.");
            end
            try
                placedStates = placedDocument.getEffectivePropertyStates(registry, placedRoot.Id);
                obj.assertRequestedStates(placedStates, plan.Changes(~[plan.Changes.Remove]));
            catch exception
                error("macd:DocumentModel:UnsafeSubtreeEdit", "%s", string(exception.message));
            end
            afterSnapshot = macd.model.SubtreeSnapshot(candidate, id);
            afterRoot = afterSnapshot.Records(1);
            afterParents = struct("Id", {oldParent.Id, newParent.Id}, ...
                "Children", {candidateOldParent.Children, candidateNewParent.Children});
            currentIds = string({obj.Components.Id});
            [~, indices] = ismember(orderedIds, currentIds);
            afterComponents = obj.Components(indices);

            % Apply only validated changes, retaining existing component handles.
            obj.applySubtreeReparentState(id, afterRoot, afterParents, afterComponents, candidate.PendingEdits);
            obj.GeneratedText = source;
            obj.Diagnostics = diagnostics;
            obj.recordHistory(struct("Kind", "subtree-reparent", "RootId", id, ...
                "BeforeRoot", snapshot.Records(1), "AfterRoot", afterRoot, ...
                "BeforeParents", beforeParents, "AfterParents", afterParents, ...
                "BeforeComponents", beforeComponents, "AfterComponents", afterComponents, ...
                "BeforePending", {beforePending}, "AfterPending", {candidate.PendingEdits}));
        end

        function snapshot = copySubtree(obj, id, registry)
            % copySubtree Validate a lossless literal subtree snapshot without editing history.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
                id (1, 1) string
                registry (1, 1) macd.model.ComponentRegistry = macd.model.ComponentRegistry.createDefault()
            end
            arguments (Output)
                snapshot (1, 1) macd.model.SubtreeSnapshot
            end
            if id == obj.RootComponentId
                error("macd:DocumentModel:UnsafeSubtreeCopy", "The document root cannot be copied.");
            end
            snapshot = macd.model.SubtreeSnapshot(obj, id);
            sourceDiagnostics = obj.Diagnostics;
            if strlength(obj.OriginalText) > 0
                originalDocument = macd.source.AppSourceParser.parseText(obj.OriginalText, registry);
                sourceDiagnostics = originalDocument.Diagnostics;
            end
            for record = snapshot.Records
                if ~record.IsEditable
                    error("macd:DocumentModel:UnsafeSubtreeCopy", "A subtree component is read-only.");
                end
                definition = registry.get(record.Factory, record.CreationArguments);
                if definition.IsProgrammaticOnly || definition.Category == "FigureTools"
                    error("macd:DocumentModel:UnsafeSubtreeCopy", "This construction family is not supported for copying.");
                end
                callbacks = macd.source.CallbackSourceAnalyzer.analyze(obj, record.Id, registry);
                if any(string({callbacks.State}) ~= "absent")
                    error("macd:DocumentModel:UnsafeSubtreeCopy", "Callback bindings cannot yet be duplicated safely.");
                end
                for property = record.Properties
                    if property.ValueKind == "expression"
                        try
                            owner = obj.getComponent(record.Id);
                            if isfield(property.Metadata, "SubtreeReferenceId")
                                target = obj.getComponent(string(property.Metadata.SubtreeReferenceId));
                                if isempty(target), error("macd:DocumentModel:UnsafeSubtreeCopy", "Reference target is missing."); end
                                macd.model.SubtreeReferencePolicy.validate(obj, owner, property.Path, target, registry);
                                targetId = target.Id;
                            else
                                targetId = macd.model.SubtreeReferencePolicy.resolve(obj, owner, property.Path, property.SourceExpression, registry);
                            end
                            metadata = property.Metadata;
                            metadata.SubtreeReferenceId = targetId;
                            snapshot = snapshot.withPropertyMetadata(record.Id, property.Path, metadata);
                        catch exception
                            error("macd:DocumentModel:UnsafeSubtreeCopy", "%s", string(exception.message));
                        end
                        continue
                    end
                    if property.ValueKind ~= "literal" || ...
                            registry.isReadOnlyProperty(record.Factory, property.Path, record.CreationArguments)
                        error("macd:DocumentModel:UnsafeSubtreeCopy", "A property cannot be copied without losing source behavior.");
                    end
                    macd.source.LiteralEncoder.encode(property.LiteralValue);
                end
                for diagnostic = sourceDiagnostics
                    if diagnostic.ComponentId == record.Id && diagnostic.Code == "source-creation-property"
                        error("macd:DocumentModel:UnsafeSubtreeCopy", "The constructor contains preserved unsupported properties.");
                    end
                end
                if record.Origin == "parsed"
                    if isempty(record.SourceSpans.Creation) || ~record.SourceSpans.Creation.isKnown() || ...
                            isempty(record.SourceSpans.Declaration) || ~record.SourceSpans.Declaration.isKnown()
                        error("macd:DocumentModel:UnsafeSubtreeCopy", "Creation or declaration ownership is missing.");
                    end
                    statements = macd.source.MatlabLexicalScanner.splitStatements(obj.OriginalText);
                    [direct, ~] = macd.source.SubtreeReparentSourceEdits.directScope(statements);
                    span = record.SourceSpans.Creation;
                    matches = find(arrayfun(@(statement) statement.Span.StartOffset == span.StartOffset && ...
                        statement.Span.EndOffset == span.EndOffset, statements));
                    if numel(matches) ~= 1 || ~direct(matches)
                        error("macd:DocumentModel:UnsafeSubtreeCopy", "Component creation ownership is ambiguous.");
                    end
                end
            end
            snapshot = snapshot.withCopyConfiguration(macd.model.SubtreeCopyPlanner.prepare(obj, snapshot, registry));
        end

        function component = pasteSubtree(obj, snapshot, parentId, registry, measuredPosition, offset, preserveNames)
            % pasteSubtree Insert independently named component records as one undoable edit.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
                snapshot (1, 1) macd.model.SubtreeSnapshot
                parentId (1, 1) string
                registry (1, 1) macd.model.ComponentRegistry = macd.model.ComponentRegistry.createDefault()
                measuredPosition double {mustBeFinite} = []
                offset (1, 2) double {mustBeFinite} = [10 10]
                preserveNames (1, 1) logical = false
            end
            arguments (Output)
                component (1, 1) macd.model.ComponentRecord
            end
            configuration = snapshot.CopyConfiguration;
            if isempty(configuration)
                configuration = macd.model.SubtreeCopyPlanner.prepare(obj, snapshot, registry);
            end
            snapshot = snapshot.withCopyConfiguration(configuration);
            plan = macd.model.SubtreePlacementPlanner.prepare(obj, snapshot, parentId, registry, ...
                strings(1, 0), measuredPosition, offset);
            candidate = obj.structuralCandidate();
            oldIds = string({snapshot.Records.Id});
            newIds = strings(size(oldIds));
            newNames = strings(size(oldIds));
            usedNames = [string({obj.Components.Name}), string({obj.CallbackEdits.HandlerName}), ...
                string(methods("matlab.apps.AppBase"))', string(properties("matlab.apps.AppBase"))', ...
                obj.ClassName, "createComponents", "delete"];
            if isprop(obj, "RenameEdits")
                mappings = obj.("RenameEdits");
                usedNames = [usedNames string({mappings.OldName})];
                if ~preserveNames, usedNames = [usedNames string({mappings.NewName})]; end
            end
            % Reserve identifiers in the effective source after pending deletions.
            namingSource = obj.OriginalText;
            if preserveNames
                namingSource = macd.source.RoundTripGenerator(registry).generate(candidate);
                sourceMembers = macd.source.ComponentNameRewriter.memberNames(namingSource);
                sourceReferences = string(regexp(macd.source.ComponentNameRewriter.codeMask(namingSource), ...
                    '(?<=app\.)[A-Za-z]\w*', 'match'));
                usedNames = [usedNames, sourceMembers(:)', sourceReferences(:)'];
            end
            usedIds = string({obj.Components.Id});
            for index = 1:numel(oldIds)
                newIds(index) = obj.newComponentId();
                while any(usedIds == newIds(index)), newIds(index) = obj.newComponentId(); end
                usedIds(end + 1) = newIds(index); %#ok<AGROW>
                stem = snapshot.Records(index).Name;
                if ~preserveNames, stem = stem + "Copy"; end
                name = extractBefore(stem, min(strlength(stem), namelengthmax) + 1);
                suffix = 1;
                while any(usedNames == name) || (~preserveNames && ...
                        ~isempty(regexp(namingSource, '(?<!\w)' + name + '(?!\w)', 'once')))
                    suffix = suffix + 1;
                    suffixText = string(suffix);
                    name = extractBefore(stem, min(strlength(stem), namelengthmax - strlength(suffixText)) + 1) + suffixText;
                end
                newNames(index) = name;
                usedNames(end + 1) = name; %#ok<AGROW>
            end

            % Create fresh generated records; original source offsets never become edit targets.
            inserted = macd.model.ComponentRecord.empty;
            for index = 1:numel(oldIds)
                record = snapshot.Records(index);
                fresh = macd.model.ComponentRecord(newIds(index), newNames(index), record.Factory, record.DeclaredType, "generated");
                fresh.CreationArguments = configuration(index).CreationArguments;
                fresh.Metadata = record.Metadata;
                for property = configuration(index).Properties
                    if property.ValueKind == "expression" && isfield(property.Metadata, "SubtreeReferenceId")
                        targetId = string(property.Metadata.SubtreeReferenceId);
                        mapped = find(oldIds == targetId, 1);
                        if ~isempty(mapped)
                            targetId = newIds(mapped);
                            targetName = newNames(mapped);
                        else
                            target = obj.getComponent(targetId);
                            if isempty(target), error("macd:DocumentModel:UnsafeSubtreeCopy", "Reference target no longer exists."); end
                            targetName = target.Name;
                        end
                        entry = fresh.setProperty(property.Path, []);
                        entry.setSourceExpression("app." + targetName);
                        entry.Metadata.SubtreeReferenceId = targetId;
                        continue
                    end
                    if property.ValueKind ~= "literal" || ...
                            registry.isReadOnlyProperty(record.Factory, property.Path, record.CreationArguments)
                        error("macd:DocumentModel:UnsafeSubtreeCopy", "Paste requires a validated literal snapshot.");
                    end
                    fresh.setProperty(property.Path, property.LiteralValue);
                end
                destinationId = parentId;
                if index > 1, destinationId = newIds(oldIds == record.ParentId); end
                candidate.addComponent(fresh, destinationId);
                inserted(end + 1) = fresh; %#ok<AGROW>
            end
            component = inserted(1);
            for change = plan.Changes
                if change.Remove, component.removeProperty(change.Path); else, component.setProperty(change.Path, change.Value); end
            end
            [source, diagnostics] = macd.source.RoundTripGenerator(registry).generate(candidate);
            if macd.validation.ModelValidator.hasErrors(diagnostics)
                error("macd:DocumentModel:UnsafeSubtreeEdit", "%s", strjoin(string({diagnostics.Message}), newline));
            end
            [reparsed, parsedDiagnostics] = macd.source.AppSourceParser.parseText(source, registry);
            if macd.validation.ModelValidator.hasErrors(parsedDiagnostics)
                error("macd:DocumentModel:UnsafeSubtreeEdit", "%s", strjoin(string({parsedDiagnostics.Message}), newline));
            end
            macd.model.SubtreeCopyPlanner.verify(reparsed, configuration, inserted, plan.Changes, registry);
            parent = obj.getComponent(parentId);
            beforeChildren = parent.Children;
            beforeComponents = obj.Components;
            obj.Components = [obj.Components inserted];
            parent.addChild(component.Id);
            obj.GeneratedText = source;
            obj.Diagnostics = diagnostics;
            obj.recordHistory(struct("Kind", "subtree-insert", "ParentId", parentId, ...
                "BeforeChildren", beforeChildren, "AfterChildren", parent.Children, ...
                "BeforeComponents", beforeComponents, "AfterComponents", obj.Components));
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
            obj.IsDirty = ~(obj.HasSavedHistoryCheckpoint && ...
                obj.HistoryIndex == obj.SavedHistoryIndex);
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
            % Redo remains conservatively dirty even when it revisits a save point.
            obj.IsDirty = true;
        end
    end

    methods (Access = private)
        function parsed = preflightPropertyChanges(obj, componentId, changes, registry)
            % preflightPropertyChanges Validate generated candidate source before mutating live records.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
                componentId (1, 1) string
                changes (1, :) struct
                registry (1, 1) macd.model.ComponentRegistry
            end
            arguments (Output)
                parsed (1, 1) macd.model.DocumentModel
            end

            % Use independent records and avoid recording candidate-only user history.
            candidate = obj.structuralCandidate();
            component = candidate.getComponent(componentId);
            for change = changes
                component.setProperty(string(change.Path), change.Value);
            end
            [source, diagnostics] = macd.source.RoundTripGenerator(registry).generate(candidate);
            if strlength(source) == 0 || macd.validation.ModelValidator.hasErrors(diagnostics)
                error("macd:DocumentModel:UnsafePropertyEdit", "%s", ...
                    strjoin(string({diagnostics.Message}), newline));
            end

            % Reparse output without executing the app and check each requested literal.
            [parsed, diagnostics] = macd.source.AppSourceParser.parseText(source, registry);
            if macd.validation.ModelValidator.hasErrors(diagnostics)
                error("macd:DocumentModel:UnsafePropertyEdit", "%s", ...
                    strjoin(string({diagnostics.Message}), newline));
            end
            reparsed = parsed.getComponentByName(component.Name);
            if isempty(reparsed)
                error("macd:DocumentModel:UnsafePropertyEdit", "The edited component was not preserved by generation.");
            end
            states = parsed.getEffectivePropertyStates(registry, reparsed.Id);
            for change = changes
                entry = reparsed.getProperty(string(change.Path));
                if isempty(entry) || entry.ValueKind ~= "literal" || ~isequaln(entry.LiteralValue, change.Value)
                    error("macd:DocumentModel:UnsafePropertyEdit", ...
                        "Generated source does not retain requested property %s.", change.Path);
                end
            end
            obj.assertRequestedStates(states, changes);
        end

        function assertRequestedStates(~, states, changes)
            % assertRequestedStates Reject requests lost to later setters or unresolved constraints.
            arguments (Input)
                ~
                states (1, :) struct
                changes (1, :) struct
            end
            for change = changes
                stateIndex = find(arrayfun(@(state) state.Definition.Path == string(change.Path), states), 1);
                if isempty(stateIndex)
                    error("macd:DocumentModel:UnsafePropertyEdit", "Property %s is not supported in this context.", change.Path);
                end
                state = states(stateIndex).Resolution;
                if ~state.IsKnown
                    error("macd:DocumentModel:UnsafePropertyEdit", "Cannot confirm %s after initialization: %s", change.Path, state.Reason);
                end
                if ~macd.model.PropertyStateResolver.matchesRequested(state, change.Value)
                    error("macd:DocumentModel:UnsafePropertyEdit", ...
                        "Initialization changes requested %s to %s; update the constraining settings or choose a surviving value.", ...
                        change.Path, macd.source.LiteralEncoder.encode(state.EffectiveValue));
                end
                valueIndex = find(arrayfun(@(state) state.Definition.Path == "Value", states), 1);
                if ~isempty(valueIndex) && any(states(valueIndex).Resolution.ReasonCode == ["constraint", "adjustment"]) && ...
                        any(states(valueIndex).Definition.Application.ApplyAfter == string(change.Path))
                    error("macd:DocumentModel:UnsafePropertyEdit", ...
                        "Cannot confirm Value after changing %s: %s", change.Path, states(valueIndex).Resolution.Reason);
                end
            end
        end

        function id = propertySettingId(~, entry)
            % propertySettingId Read the immutable occurrence targeted by a value edit.
            arguments (Input)
                ~
                entry (1, 1) macd.model.PropertyEntry
            end
            arguments (Output)
                id (1, 1) string
            end

            id = "";
            if isfield(entry.Metadata, "SourceSettingId")
                id = entry.Metadata.SourceSettingId;
            elseif isfield(entry.Metadata, "PendingSettingId")
                id = entry.Metadata.PendingSettingId;
            end
        end

        function assertPropertySettingTarget(obj, component, change, forward)
            % assertPropertySettingTarget Refuse history replay against a different occurrence.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
                component (1, 1) macd.model.ComponentRecord
                change (1, 1) struct
                forward (1, 1) logical
            end

            if ~isfield(change, "TargetSettingId") || strlength(change.TargetSettingId) == 0, return, end
            entry = component.getProperty(string(change.Path));
            if forward && ~change.HadOldValue && isempty(entry), return, end
            if isempty(entry) || obj.propertySettingId(entry) ~= change.TargetSettingId
                error("macd:DocumentModel:StalePropertySetting", ...
                    "Property history no longer targets the same source occurrence.");
            end
        end

        function mappings = updatedRenameMappings(~, mappings, componentId, kind, oldName, newName)
            % updatedRenameMappings Retarget all historical aliases without cascading source edits.
            arguments (Input)
                ~
                mappings struct
                componentId (1, 1) string
                kind (1, 1) string
                oldName (1, 1) string
                newName (1, 1) string
            end
            arguments (Output)
                mappings struct
            end

            for index = 1:numel(mappings)
                if mappings(index).ComponentId == componentId && mappings(index).Kind == kind && mappings(index).NewName == oldName
                    mappings(index).NewName = newName;
                end
            end
            existing = find(string({mappings.OldName}) == oldName & string({mappings.Kind}) == kind, 1);
            if isempty(existing)
                mappings(end + 1) = struct("ComponentId", componentId, "Kind", kind, "OldName", oldName, "NewName", newName);
            else
                mappings(existing).NewName = newName;
            end
        end

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
                % A replacement branch makes every previous checkpoint uncertain.
                obj.History = obj.History(1:obj.HistoryIndex);
                obj.HasSavedHistoryCheckpoint = false;
                obj.SavedHistoryIndex = NaN;
            end
            obj.History{end + 1} = edit;
            obj.HistoryIndex = numel(obj.History);
            if numel(obj.History) > obj.HistoryLimit
                obj.History(1) = [];
                obj.HistoryIndex = obj.HistoryIndex - 1;
                if obj.HasSavedHistoryCheckpoint
                    if obj.SavedHistoryIndex == 0
                        obj.HasSavedHistoryCheckpoint = false;
                        obj.SavedHistoryIndex = NaN;
                    else
                        obj.SavedHistoryIndex = obj.SavedHistoryIndex - 1;
                    end
                end
            end
            obj.IsDirty = true;
        end

        function applySubtreeReparentState(obj, id, rootState, parentStates, components, pending)
            % applySubtreeReparentState Restore one validated hierarchy and placement state.
            arguments (Input)
                obj (1, 1) macd.model.DocumentModel
                id (1, 1) string
                rootState (1, 1) struct
                parentStates struct
                components macd.model.ComponentRecord
                pending cell
            end

            obj.Components = components;
            root = obj.getComponent(id);
            root.restoreProperties(rootState.Properties);
            if isfield(rootState, "Settings"), root.restoreSettings(rootState.Settings); end
            root.ParentId = rootState.ParentId;
            for state = parentStates
                parent = obj.getComponent(state.Id);
                for child = parent.Children, parent.removeChild(child); end
                for child = state.Children, parent.addChild(child); end
            end
            obj.PendingEdits = pending;
        end

        function applyHistory(obj, edit, forward)
            % applyHistory Apply or reverse one history record without recording it.
            switch edit.Kind
                case "subtree-reparent"
                    if forward
                        obj.applySubtreeReparentState(edit.RootId, edit.AfterRoot, edit.AfterParents, ...
                            edit.AfterComponents, edit.AfterPending);
                    else
                        obj.applySubtreeReparentState(edit.RootId, edit.BeforeRoot, edit.BeforeParents, ...
                            edit.BeforeComponents, edit.BeforePending);
                    end
                case "subtree-insert"
                    parent = obj.getComponent(edit.ParentId);
                    if forward
                        obj.Components = edit.AfterComponents;
                        children = edit.AfterChildren;
                    else
                        obj.Components = edit.BeforeComponents;
                        children = edit.BeforeChildren;
                    end
                    for child = parent.Children, parent.removeChild(child); end
                    for child = children, parent.addChild(child); end
                case "subtree-delete"
                    parent = obj.getComponent(edit.ParentId);
                    if forward
                        obj.Components = edit.AfterComponents;
                        obj.PendingEdits = edit.AfterPending;
                        children = edit.AfterChildren;
                    else
                        obj.Components = edit.BeforeComponents;
                        obj.PendingEdits = edit.BeforePending;
                        children = edit.BeforeChildren;
                    end
                    for child = parent.Children, parent.removeChild(child); end
                    for child = children, parent.addChild(child); end
                case "rename"
                    component = obj.getComponent(edit.ComponentId);
                    if forward
                        component.Name = edit.NewName;
                        obj.RenameEdits = edit.After;
                    else
                        component.Name = edit.OldName;
                        obj.RenameEdits = edit.Before;
                    end
                case "callback"
                    if forward, obj.CallbackEdits = edit.After; else, obj.CallbackEdits = edit.Before; end
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
                    obj.assertPropertySettingTarget(component, edit, forward);
                    if forward
                        component.setProperty(edit.Path, edit.NewValue);
                    elseif edit.HadOldValue
                        component.setProperty(edit.Path, edit.OldValue);
                    else
                        component.removeProperty(edit.Path);
                    end
                case "property-batch"
                    component = obj.getComponent(edit.ComponentId);
                    for index = 1:numel(edit.Changes)
                        obj.assertPropertySettingTarget(component, edit.Changes(index), forward);
                    end
                    for index = 1:numel(edit.Changes)
                        change = edit.Changes(index);
                        if forward
                            component.setProperty(change.Path, change.NewValue);
                        else
                            obj.restoreBatchValue(component, change);
                        end
                    end
                case "grid-layout-edit"
                    for index = 1:numel(edit.Changes)
                        change = edit.Changes(index);
                        component = obj.getComponent(change.ComponentId);
                        if forward
                            component.setProperty(change.Path, change.NewValue);
                        else
                            obj.restoreBatchValue(component, change);
                        end
                    end
                case "reset-property"
                    component = obj.getComponent(edit.ComponentId);
                    if forward
                        component.removeProperty(edit.Path);
                    else
                        if isfield(edit, "OldEntry")
                            component.restoreProperty(edit.OldEntry);
                            component.restoreSettings(edit.BeforeSettings);
                        else
                            component.setProperty(edit.Path, edit.OldValue);
                        end
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

        function restoreBatchValue(~, component, change)
            % restoreBatchValue Restore one prior batch value or its absent-property state.
            arguments (Input)
                ~
                component (1, 1) macd.model.ComponentRecord
                change (1, 1) struct
            end

            if change.HadOldValue
                component.setProperty(change.Path, change.OldValue);
            else
                component.removeProperty(change.Path);
            end
        end

        function validateGridLayoutTarget(~, grid, component, path, value)
            % validateGridLayoutTarget Restrict a grid change set to its owned layout surface.
            arguments (Input)
                ~
                grid (1, 1) macd.model.ComponentRecord
                component (1, 1) macd.model.ComponentRecord
                path (1, 1) string
                value
            end

            if component == grid
                if ~any(path == ["RowHeight", "ColumnWidth"])
                    error("macd:DocumentModel:InvalidGridLayoutEdit", ...
                        "Grid layout edits may change only RowHeight or ColumnWidth on the grid.");
                end
                message = macd.model.GridTrackList.validate(value);
                if strlength(message) > 0
                    error("macd:DocumentModel:InvalidGridLayoutEdit", "%s", message);
                end
                return
            end
            if component.ParentId ~= grid.Id || ...
                    ~any(path == ["Layout.Row", "Layout.Column"])
                error("macd:DocumentModel:InvalidGridLayoutEdit", ...
                    "Grid layout edits may change only direct-child Layout.Row or Layout.Column values.");
            end
            if ~isnumeric(value) || ~isvector(value) || isempty(value) || ...
                    numel(value) > 2 || any(~isfinite(value)) || any(value < 1) || ...
                    any(value ~= floor(value))
                error("macd:DocumentModel:InvalidGridLayoutEdit", ...
                    "Grid row and column values must be positive integer scalars or spans.");
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
            reserved = [string({obj.RenameEdits.OldName}), string({obj.RenameEdits.NewName})];
            while ~isempty(obj.getComponentByName(name)) || any(reserved == name)
                suffix = suffix + 1;
                name = string(matlab.lang.makeValidName(char(base + suffix)));
            end
        end

        function name = displayName(~, factory)
            % displayName Convert a factory name into a readable property base.
            base = regexprep(char(factory), "^ui", "");
            name = string(upper(base(1)) + string(base(2:end)));
        end

        function position = nextAbsolutePosition(~, parent, defaultSize)
            % nextAbsolutePosition Choose a visible nonoverlapping default rectangle.
            arguments (Input)
                ~
                parent (1, 1) macd.model.ComponentRecord
                defaultSize (1, 2) double = [100 30]
            end

            position = [20 20 defaultSize];
            count = numel(parent.Children);
            position(1:2) = position(1:2) + [20 20] * count;
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
