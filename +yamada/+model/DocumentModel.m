classdef DocumentModel < handle
    % DocumentModel Hold shared state for new and parsed handle-based documents.
    %   This handle class owns document identity, ordered component records,
    %   source snapshots, diagnostics, unknown regions, and pending edits. It does
    %   not parse source, render UI controls, or generate MATLAB code itself.
    %
    %   Example:
    %       document = yamada.model.DocumentModel("ExampleApp");

    properties
        % ClassName - MATLAB class name represented by this document.
        ClassName string = ""
        % FilePath - Optional path of the source file represented by the document.
        FilePath string = ""
        % OriginalText - Exact source snapshot supplied to the parser.
        OriginalText string = ""
        % GeneratedText - Latest generated or rewritten source preview.
        GeneratedText string = ""
        % Components - Ordered yamada.model.ComponentRecord handle objects.
        Components yamada.model.ComponentRecord = ...
            yamada.model.ComponentRecord.empty
        % RootComponentId - Stable identity of the root UI component.
        RootComponentId string = ""
        % Diagnostics - Current document-level diagnostics.
        Diagnostics yamada.model.Diagnostic = yamada.model.Diagnostic.empty
        % UnknownRegions - Preserved source regions the editor does not interpret.
        UnknownRegions yamada.model.UnknownSourceRegion = ...
            yamada.model.UnknownSourceRegion.empty
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

    properties (Dependent, SetAccess = private)
        % CurrentText - Exact source for the currently published editor state.
        CurrentText string
    end

    properties (SetAccess = private)
        % RenameEdits - Simultaneous source member renames retained across generation.
        RenameEdits struct = struct("ComponentId", {}, "Kind", {}, "OldName", {}, "NewName", {})
        % CallbackEdits - Source-owned callback intentions grouped by component and property.
        CallbackEdits yamada.model.CallbackEdit = yamada.model.CallbackEdit.empty
        % IsDirty - Whether the document has changes that are not known to be saved.
        IsDirty logical = true
        % SavedSource - Independent parsed positions in the last successfully written source.
        SavedSource yamada.model.SavedSourceCheckpoint = yamada.model.SavedSourceCheckpoint.empty
    end

    properties (Access = private)
        CurrentSource yamada.model.CurrentSourceState = yamada.model.CurrentSourceState.empty
        SourceRegistry yamada.model.ComponentRegistry = yamada.model.ComponentRegistry.empty
        SourcePublication logical = false
        SourceInputRevision uint64 = uint64(0)
        HasPublishedInputStamp logical = false
        SourceAnalysisData yamada.source.SourceAnalysis = yamada.source.SourceAnalysis.empty
        InputClock yamada.model.InputChangeClock = yamada.model.InputChangeClock.empty
        Evaluation yamada.model.EvaluationContext = yamada.model.EvaluationContext.empty
        CallbackPreparation struct = struct()
        PlanBaseline yamada.model.EvaluationContext = yamada.model.EvaluationContext.empty
        PlannedValidation logical = false
        PlannedScope struct = struct()
        PropertyValidationNames string = strings(1, 0)
        PropertyValidationContext yamada.model.EvaluationContext = yamada.model.EvaluationContext.empty
        PropertyValidationDiagnostics yamada.model.Diagnostic = yamada.model.Diagnostic.empty
        SavedHistoryIndex double = NaN
        HasSavedHistoryCheckpoint logical = false
        ComponentLookup containers.Map
        ComponentLookupReady logical = false
        SettingStore yamada.model.SourceSettingStore = yamada.model.SourceSettingStore.empty
    end

    methods (Access = {?yamada.model.EvaluationContext, ?yamada.model.SourceLiteralTransaction, ?yamada.model.SourceLiteralBatchTransaction})
        function [clock, revision, tracked] = inputStamp(obj)
            % inputStamp Attach one acyclic write token and return its current state.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
            end
            arguments (Output)
                clock (1, 1) yamada.model.InputChangeClock
                revision (1, 1) uint64
                tracked (1, 1) logical
            end
            if isempty(obj.InputClock)
                obj.InputClock = yamada.model.InputChangeClock();
                obj.SettingStore = yamada.model.SourceSettingStore();
                for component = reshape(obj.Components, 1, []), obj.SettingStore.reserveIds([component.Settings.Id]); end
                for component = reshape(obj.Components, 1, [])
                    component.bindSettingStore(obj.SettingStore);
                    component.bindInputClock(obj.InputClock);
                end
            end
            clock = obj.InputClock;
            revision = clock.Revision;
            tracked = clock.IsTracked;
        end
    end

    methods
        function settings = canonicalizeSettings(obj, settings)
            % canonicalizeSettings Reserve identities in the live document's canonical address space.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                settings yamada.model.PropertySetting
            end
            arguments (Output)
                settings yamada.model.PropertySetting
            end
            obj.inputStamp();
            for index = 1:numel(settings), settings(index) = obj.SettingStore.canonicalize(settings(index)); end
        end
    end

    methods (Access = ?yamada.source.RoundTripGenerator)
        function diagnostics = generationDiagnostics(obj, registry, names)
            % generationDiagnostics Check only unpublished input owners when an editor-owned baseline exists.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                registry (1, 1) yamada.model.ComponentRegistry
                names (1, :) string = strings(1, 0)
            end
            arguments (Output)
                diagnostics yamada.model.Diagnostic
            end
            if isempty(names) && obj.hasCurrentValidation(registry)
                diagnostics = obj.PropertyValidationDiagnostics; return
            end
            if isempty(obj.PlanBaseline) && isempty(obj.Evaluation)
                diagnostics = yamada.validation.ModelValidator.validate(obj, registry, names); return
            end
            changed = string({obj.Components(ismember(string({obj.Components.Name}), names)).Id});
            if isempty(names)
                for member = obj.Components
                    pending = ~yamada.model.SourceOwnership.hasSource(member);
                    for entry = member.Properties
                        settings = member.getSettings(entry.Path);
                        if isempty(entry.SourceSpan) || isempty(settings)
                            pending = true; break
                        end
                        last = settings(end);
                        if entry.ValueKind ~= last.ValueKind || ~isequaln(entry.LiteralValue, last.LiteralValue) || ...
                                entry.SourceExpression ~= last.SourceExpression
                            pending = true; break
                        end
                    end
                    if pending, changed(end + 1) = member.Id; end %#ok<AGROW>
                end
            end
            previous = obj.planBaseline(registry); scope = previous.editScope(obj, changed);
            checked = yamada.validation.ModelValidator.validateOwners(obj, registry, scope.Checked, true);
            retained = obj.Diagnostics;
            if ~isempty(retained), retained = retained(~ismember(string({retained.ComponentId}), scope.Checked)); end
            diagnostics = [retained checked];
        end
    end

    methods (Access = {?yamada.source.SubtreeReparentSourceEdits, ?yamada.source.PropertyInsertionPlanner, ?yamada.source.PropertySourcePlan})
        function [candidate, state] = editedSourceCandidate(obj, text, edits, registry, stateId, callback)
            % editedSourceCandidate Bind only changed owners against projected lexical and initialization indexes.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                text (1, 1) string
                edits (1, :) struct
                registry (1, 1) yamada.model.ComponentRegistry
                stateId (1, 1) string = ""
                callback (1, 1) struct = struct()
            end
            arguments (Output)
                candidate (1, 1) yamada.model.DocumentModel
                state (1, 1) yamada.model.CurrentSourceState
            end
            batch = yamada.source.SourcePatchBatch(obj.CurrentText, edits); assert(batch.AfterText == text);
            before = obj.sourceAnalysis();
            indexed = obj;
            if any(arrayfun(@(record) isempty(record.SourceSpans.Creation), obj.Components))
                indexed = obj.structuralCandidate();
                indexed.Components = indexed.Components(arrayfun(@(record) ~isempty(record.SourceSpans.Creation), indexed.Components));
            end
            yamada.model.SourceSettingRebinder.executionSequences(indexed, obj.CurrentSource, yamada.source.SourcePatchBatch(obj.CurrentText), registry);
            analysis = before.withEditorPatches(batch, obj.Components, registry);
            execution = analysis.executionIndex(); state = obj.CurrentSource.withBatch(batch, stateId, analysis);
            mapping = yamada.source.EditorSourceProjection.statementMap(before, analysis, batch);
            changed = strings(1, 0);
            for component = obj.Components
                if isempty(component.SourceSpans.Creation) || any(arrayfun(@(setting) isempty(setting.SourceSpan), component.Settings))
                    changed(end + 1) = component.Id; %#ok<AGROW>
                    continue
                end
                ranges = [component.SourceSpans.Declaration component.SourceSpans.Creation component.Settings.SourceSpan];
                [~, survives] = batch.mapSpanCells(arrayfun(@(span) {span}, ranges));
                if ~all(survives), changed(end + 1) = component.Id; continue, end %#ok<AGROW>
                for span = ranges
                    if any(arrayfun(@(edit) edit.Start <= span.EndOffset && edit.End >= span.StartOffset || ...
                            edit.Start > span.StartOffset && edit.Start <= span.EndOffset, batch.Edits))
                        changed(end + 1) = component.Id; break %#ok<AGROW>
                    end
                end
            end
            additions = setdiff(1:numel(analysis.Statements), mapping(mapping > 0));
            for index = additions
                name = regexp(analysis.Statements(index).Text, '^app\.(\w+)(?:\.|\s*=)', 'tokens', 'once');
                if isempty(name), continue, end
                component = obj.getComponentByName(string(name{1}));
                if ~isempty(component), changed(end + 1) = component.Id; end %#ok<AGROW>
            end
            changed = unique(changed, "stable"); candidate = obj.structuralCandidate();
            projectionExecution = execution; projectionExecution.ScopeMethods = analysis.Layout.Methods;
            projection = obj.prepareSettingProjection(batch, projectionExecution, changed);
            rangeExecution = rmfield(execution, "Trace");
            for component = obj.Components
                other = candidate.getComponent(component.Id);
                owner = find(string({obj.Components.Id}) == component.Id, 1);
                if execution.Owners(owner) == 0
                    changed(changed == component.Id) = []; continue
                end
                if any(changed == component.Id)
                    [declaration, valid] = batch.mapSpan(component.SourceSpans.Declaration);
                    if ~valid
                        original = before.statementIndices(component.SourceSpans.Declaration);
                        if isscalar(original) && mapping(original) > 0
                            declaration = analysis.Statements(mapping(original)).Span; valid = true;
                        end
                    end
                    if isempty(declaration)
                        for position = additions
                            if ~isempty(regexp(analysis.Statements(position).Text, '^' + regexptranslate('escape', component.Name) + '\s+[A-Za-z]\w*(?:\.\w+)*$', 'once'))
                                declaration = analysis.Statements(position).Span; valid = true; break
                            end
                        end
                    end
                    assert(valid);
                    owner = find(string({obj.Components.Id}) == component.Id, 1);
                    creation = analysis.Statements(execution.Owners(owner)).Span;
                    other.SourceSpans = struct("Declaration", declaration, "Creation", creation);
                else
                    update = yamada.model.SourceLocationUpdate(component, batch, struct("SettingId", {}, "Value", {}), ...
                        rangeExecution, analysis, obj.ownerSettingProjection(component, projection));
                    update.assertCurrent(component); update.applyToCandidate(other);
                end
                visits = find(execution.Trace.Order == analysis.statementIndices(other.SourceSpans.Creation));
                assert(~isempty(visits)); other.Metadata.InitializationCreationSequence = execution.Creation(visits(end));
                other.Metadata.InitializationCreationCertain = isscalar(visits) && execution.Trace.Certain(visits(end));
            end
            % Partial builder plans exclude generated records that were not emitted.
            for index = fliplr(find(execution.Owners == 0))
                candidate.removeComponentAt(candidate.getComponent(obj.Components(index).Id));
            end
            execution.Owners = execution.Owners(execution.Owners > 0); analysis.rememberExecution(execution);
            [candidate.Diagnostics, candidate.UnknownRegions] = yamada.model.SourceLocationUpdate.annotations(obj, batch);
            trace = execution.Trace;
            candidate.Metadata.InitializationContext = struct("Order", trace.Order, "Certain", trace.Certain, ...
                "Returns", trace.Returns, "Layout", analysis.Layout);
            if isfield(candidate.Metadata, "ResolvingCombinedPropertySource")
                candidate.Metadata = rmfield(candidate.Metadata, "ResolvingCombinedPropertySource");
            end
            candidate.OriginalText = state.Text;
            candidate.publishCurrentSource(state);
            identity = yamada.source.SourcePatchBatch(state.Text);
            for id = changed
                other = candidate.getComponent(id); old = other.Settings;
                other.applyProjectedSettings(yamada.model.PropertySetting.empty);
                [settings, ~, factoryArguments] = yamada.model.SourceSettingRebinder.rebind(candidate, other, state, identity, registry);
                for index = 1:numel(settings)
                    setting = settings(index); matches = old(string({old.Path}) == setting.Path & string({old.Method}) == setting.Method);
                    preceding = settings(1:index); ordinal = nnz(string({preceding.Path}) == setting.Path & string({preceding.Method}) == setting.Method);
                    if ordinal <= numel(matches)
                        record = setting.toStruct(); previous = matches(ordinal);
                        record.Location.Id = previous.Id; record.Location.SourceSnapshotId = previous.SourceSnapshotId;
                        record.Location.StatementId = previous.StatementId; record.Location.InitializationScopeId = previous.InitializationScopeId;
                        settings(index) = yamada.model.PropertySetting(record.Path, record.Value, record.Location);
                    end
                end
                settings = obj.canonicalizeSettings(settings);
                other.synchronizeSourceSettings(settings, factoryArguments);
            end
            yamada.model.SourceEffectSummary.refresh(candidate, registry);
            candidate.publishCurrentSource(state);
            if isempty(fieldnames(callback))
                diagnostics = candidate.finishPlannedValidation(registry, obj.planBaseline(registry), changed, batch);
            else
                % Callback commands preserve non-callback semantics and existing diagnostics.
                context = candidate.evaluationContext(registry);
                context.inheritLiteralStates(callback.Context, callback.ComponentId, batch, true);
                candidate.getEffectivePropertyStates(registry, callback.ComponentId);
                candidate.PropertyValidationContext = context;
                candidate.PropertyValidationNames = strings(1, 0);
                candidate.PropertyValidationDiagnostics = candidate.Diagnostics;
                diagnostics = candidate.Diagnostics;
            end
            if yamada.validation.ModelValidator.hasErrors(diagnostics)
                error("yamada:DocumentModel:UnsafeSourceCommit", "%s", strjoin(string({diagnostics.Message}), newline));
            end
        end
    end

    methods (Access = ?yamada.model.SavedSourceCheckpoint)
        function proof = captureValidationProof(obj, registry)
            % captureValidationProof Capture only a tracked, exact and fully validated immutable result set.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                registry (1, 1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                proof yamada.model.DocumentValidationProof
            end
            proof = yamada.model.DocumentValidationProof.empty;
            context = obj.PropertyValidationContext;
            if isempty(context) || ~isempty(obj.PropertyValidationNames) || ~context.matches(obj, registry) || ...
                    yamada.validation.ModelValidator.hasErrors(obj.PropertyValidationDiagnostics), return, end
            [~, tracked] = context.revisionToken(); if ~tracked, return, end
            for owner = obj.Components
                [~, found] = context.lookup("states:" + owner.Id);
                if ~found, return, end
            end
            proof = yamada.model.DocumentValidationProof(obj, registry, obj.PropertyValidationDiagnostics);
        end
    end

    methods (Access = {?yamada.model.SourceLiteralTransaction, ?yamada.model.SourceLiteralBatchTransaction})
        function result = validateIndexedCandidate(obj, settings, factoryArguments, updates, state, diagnostics, regions, metadata, id, changes, registry, batch)
            % validateIndexedCandidate Validate document-dependent literal policies without reparsing their known source edits.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                settings yamada.model.PropertySetting
                factoryArguments cell
                updates yamada.model.SourceLocationUpdate
                state (1, 1) yamada.model.CurrentSourceState
                diagnostics yamada.model.Diagnostic
                regions yamada.model.UnknownSourceRegion
                metadata (1, 1) struct
                id (1, 1) string
                changes (1, :) struct
                registry (1, 1) yamada.model.ComponentRegistry
                batch (1, 1) yamada.source.SourcePatchBatch
            end
            arguments (Output)
                result (1, 1) struct
            end
            candidate = obj.structuralCandidate();
            for update = updates, update.applyToCandidate(candidate.getComponent(update.ComponentId)); end
            owner = candidate.getComponent(id);
            owner.synchronizeSourceSettings(settings, factoryArguments);
            candidate.Diagnostics = diagnostics; candidate.UnknownRegions = regions; candidate.Metadata = metadata;
            candidate.publishCurrentSource(state);
            diagnostics = candidate.finishPlannedValidation(registry, obj.planBaseline(registry), id, batch);
            assert(~yamada.validation.ModelValidator.hasErrors(diagnostics), ...
                "yamada:SourceLiteralTransaction:InvalidValue", "%s", strjoin(string({diagnostics.Message}), newline));
            states = candidate.getEffectivePropertyStates(registry, id);
            definitions = [states.Definition]; resolutions = [states.Resolution];
            for change = changes
                target = resolutions(string({definitions.Path}) == string(change.Path));
                assert(isscalar(target) && target.IsKnown && yamada.model.PropertyStateResolver.matchesRequested(target, change.Value), ...
                    "yamada:SourceLiteralTransaction:WiderProof", "A dependent setting needs a complete proven final value.");
            end
            result = struct("Ready", true, "States", resolutions, "Definitions", definitions, ...
                "StateDiagnostics", yamada.model.Diagnostic.empty, "Diagnostics", diagnostics, ...
                "Plan", candidate.plannedResult());
        end

        function result = validateIndexedBatchCandidate(obj, bindings, updates, state, diagnostics, regions, metadata, specs, registry, batch)
            % validateIndexedBatchCandidate Validate the complete final multi-owner state without regenerating or parsing source.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                bindings (1, :) struct
                updates yamada.model.SourceLocationUpdate
                state (1, 1) yamada.model.CurrentSourceState
                diagnostics yamada.model.Diagnostic
                regions yamada.model.UnknownSourceRegion
                metadata (1, 1) struct
                specs (1, :) struct
                registry (1, 1) yamada.model.ComponentRegistry
                batch (1, 1) yamada.source.SourcePatchBatch
            end
            arguments (Output)
                result (1, 1) struct
            end
            candidate = obj.structuralCandidate();
            for update = updates, update.applyToCandidate(candidate.getComponent(update.ComponentId)); end
            for binding = bindings
                candidate.getComponent(binding.ComponentId).synchronizeSourceSettings(binding.Settings, binding.FactoryArguments);
            end
            candidate.Diagnostics = diagnostics; candidate.UnknownRegions = regions; candidate.Metadata = metadata;
            candidate.publishCurrentSource(state);
            diagnostics = candidate.finishPlannedValidation(registry, obj.planBaseline(registry), string({specs.ComponentId}), batch);
            assert(~yamada.validation.ModelValidator.hasErrors(diagnostics), ...
                "yamada:SourceLiteralTransaction:InvalidValue", "%s", strjoin(string({diagnostics.Message}), newline));
            owners = struct("ComponentId", {}, "Definitions", {}, "States", {});
            for spec = specs
                states = candidate.getEffectivePropertyStates(registry, spec.ComponentId);
                definitions = [states.Definition]; resolutions = [states.Resolution];
                transaction = yamada.model.PropertyStateResolver.transaction(resolutions);
                for change = spec.Changes, transaction.stage(string(change.Path), change.Value); end
                message = yamada.validation.PropertyBatchValidator.validate(definitions, transaction);
                assert(strlength(message) == 0, "yamada:SourceLiteralTransaction:InvalidValue", "%s", message);
                obj.assertRequestedStates(states, spec.Changes);
                owners(end + 1) = struct("ComponentId", spec.ComponentId, "Definitions", definitions, ...
                    "States", resolutions); %#ok<AGROW>
            end
            result = struct("Diagnostics", diagnostics, "Owners", owners, "Plan", candidate.plannedResult());
        end

        function result = preparePropertyValidation(obj, component, definitions, states, paths, batch, registry)
            % preparePropertyValidation Complete a local candidate only from an exact fully validated baseline.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                component (1, 1) yamada.model.ComponentRecord
                definitions yamada.model.PropertyDefinition
                states yamada.model.PropertyState
                paths (1, :) string
                batch (1, 1) yamada.source.SourcePatchBatch
                registry (1, 1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                result (1, 1) struct
            end
            result = struct("Ready", false);
            context = obj.PropertyValidationContext;
            if isempty(context) || ~isempty(obj.PropertyValidationNames) || ~context.matches(obj, registry) || ...
                    yamada.validation.ModelValidator.hasErrors(obj.PropertyValidationDiagnostics), return, end
            [~, tracked] = context.revisionToken();
            if ~tracked, return, end
            [previous, found] = context.lookup("states:" + component.Id);
            if ~found || ~isequaln(previous.Definitions, definitions), return, end
            result = yamada.validation.ModelValidator.prepareIndependentProperties(component, definitions, ...
                states, previous.States, paths, obj.PropertyValidationDiagnostics, batch);
        end

        function projection = prepareSettingProjection(obj, batch, execution, excludedOwner)
            % prepareSettingProjection Use the persistent canonical range index for every live source setting.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                batch (1, 1) yamada.source.SourcePatchBatch
                execution (1, 1) struct
                excludedOwner (1, :) string
            end
            arguments (Output)
                projection (1, 1) struct
            end
            projection = struct();
            if isempty(obj.SettingStore), return, end
            for component = obj.Components
                if ~component.usesSettingStore(obj.SettingStore), return, end
            end
            projection = obj.SettingStore.prepare(batch, execution, excludedOwner);
        end

        function settings = ownerSettingProjection(~, component, projection)
            % ownerSettingProjection Slice prepared values using an owner's stable canonical slots.
            arguments (Input)
                ~
                component (1, 1) yamada.model.ComponentRecord
                projection (1, 1) struct
            end
            arguments (Output)
                settings (1, 1) struct
            end
            settings = struct();
            if isfield(projection, "Before"), settings = component.projectedSettings(projection); end
        end

        function publishSettingProjection(obj, projection)
            % publishSettingProjection Commit derived positions without storing them as independent history edits.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                projection (1, 1) struct
            end
            if ~isfield(projection, "Before"), return, end
            obj.SettingStore.publish(projection);
            obj.noteInput([]);
        end
    end

    methods
        function [settings, owners] = settingsInSourceOrder(obj)
            % settingsInSourceOrder Return independent canonical values in maintained physical source order.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
            end
            arguments (Output)
                settings yamada.model.PropertySetting
                owners (1, :) string
            end
            obj.inputStamp();
            for component = obj.Components
                assert(component.usesSettingStore(obj.SettingStore), ...
                    "yamada:DocumentModel:SharedSettingOwner", "A source-order view requires exclusive component ownership.");
            end
            [settings, owners] = obj.SettingStore.inSourceOrder();
        end
    end

    methods (Access = ?yamada.model.EvaluationContext)
        function snapshot = configurationSnapshot(obj)
            % configurationSnapshot Capture value data from a detached parsed checkpoint for independent future copies.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
            end
            arguments (Output)
                snapshot (1, 1) struct
            end
            % Borrow only private parsed checkpoints that cannot retain their owning editor document.
            if strlength(obj.CurrentText) == 0 || ~isempty(obj.History) || ...
                    any(~arrayfun(@yamada.model.SourceOwnership.hasSource, obj.Components))
                error("yamada:DocumentModel:UnsafeConfigurationSnapshot", "A detached parsed checkpoint is required.");
            end
            values = struct();
            fields = ["FilePath", "OriginalText", "GeneratedText", "RootComponentId", ...
                "Diagnostics", "UnknownRegions", "Encoding", "LineEnding", "Metadata", ...
                "CallbackEdits", "RenameEdits", "PendingEdits"];
            for field = fields, values.(field) = obj.(field); end
            if ~yamada.model.InputChangeClock.isValueData(values)
                error("yamada:DocumentModel:UnsafeConfigurationSnapshot", "Configuration fields contain mutable data.");
            end
            snapshot = struct("ClassName", obj.ClassName, ...
                "Components", yamada.model.SubtreeSnapshot(obj, obj.RootComponentId), ...
                "Values", values, "Analysis", obj.SourceAnalysisData, "CurrentSource", obj.CurrentSource, "Registry", obj.SourceRegistry);
        end
    end

    methods (Static, Access = ?yamada.model.EvaluationContext)
        function document = fromConfigurationSnapshot(snapshot)
            % fromConfigurationSnapshot Materialize caller-owned records with the same fields as structuralCandidate.
            arguments (Input)
                snapshot (1, 1) struct
            end
            arguments (Output)
                document (1, 1) yamada.model.DocumentModel
            end
            document = yamada.model.DocumentModel(snapshot.ClassName);
            document.Components = snapshot.Components.materialize();
            for field = reshape(string(fieldnames(snapshot.Values)), 1, [])
                document.(field) = snapshot.Values.(field);
            end
            % SourceAnalysis is a source-only index already shared by structuralCandidate.
            document.SourceAnalysisData = snapshot.Analysis;
            document.CurrentSource = snapshot.CurrentSource;
            document.SourceRegistry = snapshot.Registry;
        end
    end

    methods (Access = private)
        function noteInput(obj, value)
            % noteInput Notify the token only after evaluation has attached it to a complete object.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                value
            end
            % Construction and materialization run without an attached token.
            if ~isempty(obj.InputClock), obj.InputClock.touch(value); end
        end

        function detachRemovedSettings(obj, components)
            % detachRemovedSettings Keep structural-history components independent when they leave the document.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                components yamada.model.ComponentRecord
            end
            if isempty(obj.SettingStore), return, end
            for component = obj.Components
                if ~any(components == component), component.detachSettingStore(obj.SettingStore); end
            end
        end

        function noteInputCollection(obj, value)
            % noteInputCollection Invalidate identity reuse and attach records before their collection write.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                value yamada.model.ComponentRecord
            end
            obj.ComponentLookupReady = false;
            if isempty(obj.InputClock), return, end
            for item = reshape(value, 1, []), obj.SettingStore.reserveIds([item.Settings.Id]); end
            for item = reshape(value, 1, [])
                item.bindSettingStore(obj.SettingStore);
                item.bindInputClock(obj.InputClock);
            end
            obj.InputClock.touch([]);
        end
    end

    methods (Access = ?yamada.source.AppSourceParser)
        function finishParsedSource(obj, registry, diagnostics, fullValidation)
            % finishParsedSource Bind completed full-load diagnostics and resolved states to the final input revision.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                registry (1, 1) yamada.model.ComponentRegistry
                diagnostics yamada.model.Diagnostic
                fullValidation (1, 1) logical
            end
            [~, revision] = obj.inputStamp();
            obj.SourceInputRevision = revision;
            obj.HasPublishedInputStamp = true;
            if fullValidation && ~yamada.validation.ModelValidator.hasErrors(diagnostics)
                if all(arrayfun(@yamada.model.SourceOwnership.hasSource, obj.Components))
                    yamada.model.SourceSettingRebinder.executionSequences(obj, obj.CurrentSource, ...
                        yamada.source.SourcePatchBatch(obj.CurrentText), registry);
                end
                obj.PropertyValidationContext = obj.evaluationContext(registry);
                obj.PropertyValidationNames = strings(1, 0);
                obj.PropertyValidationDiagnostics = diagnostics;
            end
        end

        function rememberSourceAnalysis(obj, analysis, registry)
            % rememberSourceAnalysis Attach parser-owned derived data for the exact current source.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                analysis (1, 1) yamada.source.SourceAnalysis
                registry (1, 1) yamada.model.ComponentRegistry
            end
            obj.SourceRegistry = registry;
            assert(analysis.matches(obj.CurrentText), "yamada:DocumentModel:SourceAnalysisMismatch", ...
                "Derived analysis must match the current source text.");
            obj.SourceAnalysisData = analysis;
            obj.CurrentSource = yamada.model.CurrentSourceState(obj.OriginalText, analysis);
        end
    end

    methods
        function result = isSourceOnlyTransition(obj, previous, kind)
            % isSourceOnlyTransition Prove one published nonvisual history transition from an earlier exact source.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                previous (1, 1) string
                kind (1, 1) string {mustBeMember(kind, ["callback", "rename"])}
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = false;
            if ~obj.HasPublishedInputStamp || isempty(obj.CurrentSource) || isempty(obj.InputClock) || ~obj.InputClock.IsTracked || ...
                    obj.InputClock.Revision ~= obj.SourceInputRevision
                return
            end
            for index = [obj.HistoryIndex obj.HistoryIndex + 1]
                if index < 1 || index > numel(obj.History), continue, end
                edit = obj.History{index};
                if edit.Kind ~= kind || ~isfield(edit, "SourceForward"), continue, end
                edits = edit.SourceForward;
                if index > obj.HistoryIndex, edits = edit.SourceInverse; end
                try
                    batch = yamada.source.SourcePatchBatch(previous, edits);
                    if batch.AfterText == obj.CurrentText, result = true; return, end
                catch exception
                    if ~startsWith(string(exception.identifier), "yamada:SourcePatchBatch:"), rethrow(exception), end
                end
            end
        end

        function result = isPropertySourceTransition(obj, previous, request)
            % isPropertySourceTransition Prove that an exact source transition changes only requested setting targets.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                previous (1, 1) string
                request (1, 1) yamada.ui.RefreshRequest
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = false;
            if ~obj.HasPublishedInputStamp || isempty(obj.CurrentSource) || isempty(obj.InputClock) || ~obj.InputClock.IsTracked || ...
                    obj.InputClock.Revision ~= obj.SourceInputRevision
                return
            end
            requested = strings(1, 0);
            for id = request.ComponentIds
                requested = [requested id + ":" + request.pathsFor(id)]; %#ok<AGROW>
            end
            for index = [obj.HistoryIndex obj.HistoryIndex + 1]
                if index < 1 || index > numel(obj.History), continue, end
                edit = obj.History{index};
                if ~isfield(edit, "SourceForward"), continue, end
                switch edit.Kind
                    case {"source-property", "property-batch"}
                        changed = edit.ComponentId + ":" + string({edit.Changes.Path});
                    case "property"
                        changed = edit.ComponentId + ":" + edit.Path;
                    case {"grid-layout-edit", "source-property-batch"}
                        changed = string({edit.Changes.ComponentId}) + ":" + string({edit.Changes.Path});
                    otherwise
                        continue
                end
                if ~all(ismember(changed, requested)), continue, end
                edits = edit.SourceForward;
                if index > obj.HistoryIndex, edits = edit.SourceInverse; end
                try
                    batch = yamada.source.SourcePatchBatch(previous, edits);
                    if batch.AfterText == obj.CurrentText, result = true; return, end
                catch exception
                    if ~startsWith(string(exception.identifier), "yamada:SourcePatchBatch:"), rethrow(exception), end
                end
            end
        end

        function result = hasPublishedModel(obj)
            % hasPublishedModel Identify an exact managed source/model state without rebuilding source on a read.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = obj.HasPublishedInputStamp && ~isempty(obj.CurrentSource) && ~isempty(obj.InputClock) && obj.InputClock.IsTracked && ...
                obj.InputClock.Revision == obj.SourceInputRevision;
        end

        function initializeSource(obj, registry)
            % initializeSource Establish the canonical current source before presenting a new document to the UI.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                registry (1, 1) yamada.model.ComponentRegistry
            end
            obj.ensureCurrentSource(registry);
        end

        function text = get.CurrentText(obj)
            % get.CurrentText Read the sole published source or the initial construction input.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
            end
            arguments (Output)
                text (1, 1) string
            end
            text = obj.OriginalText;
            if ~isempty(obj.CurrentSource), text = obj.CurrentSource.Text; end
        end

        function analysis = sourceAnalysis(obj)
            % sourceAnalysis Return read-only derived data without changing semantic inputs.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
            end
            arguments (Output)
                analysis (1, 1) yamada.source.SourceAnalysis
            end
            if isempty(obj.SourceAnalysisData) || ~obj.SourceAnalysisData.matches(obj.CurrentText)
                obj.SourceAnalysisData = yamada.source.SourceAnalysis(obj.CurrentText);
            end
            analysis = obj.SourceAnalysisData;
        end

        function set.ClassName(obj, value)
            % set.ClassName Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                value
            end
            obj.ClassName = value;
            obj.noteInput(value);
        end

        function set.FilePath(obj, value)
            % set.FilePath Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                value
            end
            obj.FilePath = value;
            obj.noteInput(value);
        end

        function set.OriginalText(obj, value)
            % set.OriginalText Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                value
            end
            obj.OriginalText = value;
            obj.resetSourceInput();
            obj.noteInput(value);
        end

        function set.Components(obj, value)
            % set.Components Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                value
            end
            obj.detachRemovedSettings(value);
            obj.Components = value;
            obj.noteInputCollection(obj.Components);
        end

        function set.RootComponentId(obj, value)
            % set.RootComponentId Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                value
            end
            obj.RootComponentId = value;
            obj.noteInput(value);
        end

        function set.UnknownRegions(obj, value)
            % set.UnknownRegions Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                value
            end
            obj.UnknownRegions = value;
            obj.noteInput(value);
        end

        function set.PendingEdits(obj, value)
            % set.PendingEdits Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                value
            end
            obj.PendingEdits = value;
            obj.noteInput(value);
        end

        function set.Encoding(obj, value)
            % set.Encoding Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                value
            end
            obj.Encoding = value;
            obj.noteInput(value);
        end

        function set.LineEnding(obj, value)
            % set.LineEnding Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                value
            end
            obj.LineEnding = value;
            obj.noteInput(value);
        end

        function set.Metadata(obj, value)
            % set.Metadata Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                value
            end
            obj.Metadata = value;
            obj.noteInput(value);
        end

        function set.RenameEdits(obj, value)
            % set.RenameEdits Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                value
            end
            obj.RenameEdits = value;
            obj.noteInput(value);
        end

        function set.CallbackEdits(obj, value)
            % set.CallbackEdits Track assignments that affect semantic evaluation inputs.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                value
            end
            obj.CallbackEdits = value;
            obj.noteInput(value);
        end

        function context = evaluationContext(obj, registry)
            % evaluationContext Reuse evaluations only while all semantic inputs remain equal.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                registry (1, 1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                context (1, 1) yamada.model.EvaluationContext
            end
            if isempty(obj.Evaluation) || (~obj.Evaluation.isReading(registry) && ...
                    ~obj.Evaluation.matches(obj, registry))
                previous = obj.Evaluation;
                obj.Evaluation = yamada.model.EvaluationContext(obj, registry);
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
                obj (1, 1) yamada.model.DocumentModel
            end

            % Keep the identity map private to this document and normalize its class name.
            obj.ComponentLookup = containers.Map("KeyType", "char", "ValueType", "double");
            obj.ComponentLookupReady = true;
            obj.ClassName = className;
        end

        function addComponent(obj, component, parentId)
            % addComponent Add a component and update its ordered parent link.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                component (1, 1) yamada.model.ComponentRecord
                parentId string = ""
            end

            % Reject duplicate identities before mutating either record.
            if ~isempty(obj.getComponent(component.Id))
                error("yamada:DocumentModel:DuplicateId", ...
                    "Component ID ""%s"" already exists.", component.Id);
            end
            % Resolve and update both sides of an optional parent relation.
            if strlength(parentId) > 0
                parent = obj.getComponent(parentId);
                if isempty(parent)
                    error("yamada:DocumentModel:UnknownParent", ...
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
                obj (1, 1) yamada.model.DocumentModel
                registry (1, 1) yamada.model.ComponentRegistry
                factory string
                parentId string
                creationArguments cell = {}
            end
            arguments (Output)
                component (1, 1) yamada.model.ComponentRecord
            end

            obj.ensureCurrentSource(registry);
            % Validate the factory and parent before changing document state.
            definition = registry.get(factory, creationArguments);
            if definition.IsRoot || definition.IsProgrammaticOnly || ...
                    definition.Category == "FigureTools" || ...
                    definition.RequiresParentComponent
                error("yamada:DocumentModel:UnsupportedInsertion", ...
                    "Factory ""%s"" is not eligible for palette insertion.", factory);
            end
            parent = obj.getComponent(parentId);
            if isempty(parent)
                error("yamada:DocumentModel:UnknownParent", ...
                    "Parent component ID ""%s"" does not exist.", parentId);
            end
            if ~yamada.model.SubtreePlacementPlanner.accepts(obj, parent, definition)
                error("yamada:DocumentModel:InvalidInsertionParent", ...
                    "Factory ""%s"" cannot be inserted under ""%s"".", ...
                    factory, parent.Factory);
            end

            % Choose a stable MATLAB property name and safe initial geometry.
            name = obj.uniqueComponentName(obj.displayName(factory));
            component = yamada.model.ComponentRecord(obj.newComponentId(), name, ...
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
            [base, staged] = obj.prepareStagedLiterals(registry);
            candidate = base.structuralCandidate(); candidate.addComponent(component, parentId);
            edits = yamada.source.RoundTripGenerator(registry).componentInsertionEdits(candidate, component);
            batch = yamada.source.SourcePatchBatch(base.CurrentText, edits);
            [candidate, state] = base.prepareComponentPublication(candidate, batch, component.Name, registry, "", obj);
            frozen = yamada.model.SubtreeSnapshot(candidate, component.Id);
            inserted = frozen.materialize(); component = inserted(1);
            before = obj.CurrentSource; beforeChildren = parent.Children;
            obj.addComponentAt(component, parentId, numel(obj.Components) + 1);
            obj.publishParsedSource(state, registry, candidate, true);
            combined = batch;
            if ~isempty(staged), combined = obj.sourceDifference(before.Text, state.Text); end
            edit = struct("Kind", "source-subtree-insert", "ParentId", parentId, ...
                "Snapshot", frozen, "InsertedComponents", inserted, "BeforeChildren", beforeChildren, "AfterChildren", parent.Children, ...
                "SourceForward", combined.Edits, "SourceInverse", combined.InverseEdits, ...
                "ComponentForward", batch.Edits, "ComponentInverse", batch.InverseEdits, "StagedEdit", staged, ...
                "SourceBeforeId", before.StateId, "SourceAfterId", obj.CurrentSource.StateId);
            obj.SourcePublication = true; cleanup = onCleanup(@() obj.endSourcePublication());
            obj.recordHistory(edit);
        end

        function entry = setProperty(obj, componentId, path, value, registry)
            % setProperty Change one component property and record its prior state.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                componentId string
                path string
                value
                registry yamada.model.ComponentRegistry = yamada.model.ComponentRegistry.empty
            end
            arguments (Output)
                entry (1, 1) yamada.model.PropertyEntry
            end

            if isempty(registry), registry = obj.SourceRegistry; end
            % Validate the component before capturing the reversible old value.
            component = obj.getComponent(componentId);
            if isempty(component)
                error("yamada:DocumentModel:UnknownComponent", ...
                    "Component ID ""%s"" does not exist.", componentId);
            end
            oldEntry = component.getProperty(path);
            oldValue = [];
            hadOldValue = ~isempty(oldEntry);
            if hadOldValue
                if ~oldEntry.IsEditable
                    error("yamada:DocumentModel:ReadOnlyProperty", ...
                        "Property ""%s"" is source-backed and read-only.", path);
                end
                oldValue = oldEntry.LiteralValue;
                if isequaln(oldValue, value)
                    if ~isempty(registry)
                        states = obj.getEffectivePropertyStates(registry, componentId);
                        obj.assertRequestedStates(states, yamada.model.PropertyTransaction.singleChange(path, value));
                    end
                    entry = oldEntry;
                    return
                end
            end
            changes = yamada.model.PropertyTransaction.singleChange(path, value);
            if obj.tryImmediateProperties(componentId, changes, registry)
                entry = component.getProperty(path);
                return
            end
            if ~isempty(registry)
                obj.preflightPropertyChanges(componentId, ...
                    yamada.model.PropertyTransaction.singleChange(path, value), registry);
            end
            entry = component.setProperty(path, value);
            obj.recordHistory(struct("Kind", "property", "ComponentId", componentId, ...
                "Path", path, "HadOldValue", hadOldValue, "OldValue", {oldValue}, ...
                "NewValue", {value}, "TargetSettingId", obj.propertySettingId(entry)));
        end

        function entries = setPropertyBatch(obj, componentId, changes, registry)
            % setPropertyBatch Apply one preflighted property batch as a single undoable edit.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                componentId (1, 1) string
                changes (1, :) struct
                registry yamada.model.ComponentRegistry = yamada.model.ComponentRegistry.empty
            end
            arguments (Output)
                entries yamada.model.PropertyEntry
            end

            if isempty(registry), registry = obj.SourceRegistry; end
            % Preflight every target before changing any component property.
            component = obj.getComponent(componentId);
            if isempty(component)
                error("yamada:DocumentModel:UnknownComponent", ...
                    "Component ID ""%s"" does not exist.", componentId);
            end
            if isempty(changes) || ~isfield(changes, "Path") || ~isfield(changes, "Value")
                error("yamada:DocumentModel:InvalidPropertyBatch", ...
                    "Every property batch change must provide Path and Value fields.");
            end
            paths = string({changes.Path});
            if any(strlength(paths) == 0) || numel(unique(paths)) ~= numel(paths)
                error("yamada:DocumentModel:InvalidPropertyBatch", ...
                    "Property batch paths must be nonempty and unique.");
            end
            historyChanges = repmat(struct("Path", "", "HadOldValue", false, ...
                "OldValue", [], "NewValue", [], "TargetSettingId", 0), 1, numel(changes));
            for index = 1:numel(changes)
                entry = component.getProperty(paths(index));
                if ~isempty(entry) && ~entry.IsEditable
                    error("yamada:DocumentModel:ReadOnlyProperty", ...
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
            if ~isempty(changes) && obj.tryImmediateProperties(componentId, requested, registry)
                entries = yamada.model.PropertyEntry.empty;
                for path = string({changes.Path}), entries(end + 1) = component.getProperty(path); end %#ok<AGROW>
                return
            end
            if ~isempty(registry)
                if ~isempty(changes)
                    obj.preflightPropertyChanges(componentId, requested, registry);
                else
                    states = obj.getEffectivePropertyStates(registry, componentId);
                    obj.assertRequestedStates(states, requested);
                end
            end

            % Commit only after every target is known to be editable and reversible.
            entries = yamada.model.PropertyEntry.empty;
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
        end

        function diagnostics = validatePropertyCommit(obj, registry)
            % validatePropertyCommit Publish full diagnostics or reuse proof of a bounded independent edit.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                registry (1, 1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                diagnostics yamada.model.Diagnostic
            end

            % Only this editor post-commit path consumes proof; generation and saving still validate fully.
            if ~isempty(obj.PropertyValidationContext) && obj.PropertyValidationContext.matches(obj, registry)
                if ~isempty(obj.PropertyValidationNames)
                    ids = string({obj.Components(ismember(string({obj.Components.Name}), obj.PropertyValidationNames)).Id});
                    checked = yamada.validation.ModelValidator.validateOwners(obj, registry, ids);
                    retained = obj.PropertyValidationDiagnostics;
                    if ~isempty(retained), retained = retained(~ismember(string({retained.ComponentId}), ids)); end
                    obj.PropertyValidationDiagnostics = [retained checked];
                    obj.PropertyValidationNames = strings(1, 0);
                end
                diagnostics = obj.PropertyValidationDiagnostics;
                obj.Diagnostics = diagnostics;
                return
            end
            diagnostics = yamada.validation.ModelValidator.validate(obj, registry);
            obj.PropertyValidationNames = strings(1, 0);
            obj.PropertyValidationContext = obj.evaluationContext(registry);
            obj.PropertyValidationDiagnostics = diagnostics;
        end

        function entries = applyGridLayoutEdit(obj, gridId, changes, registry)
            % applyGridLayoutEdit Atomically apply one grid and direct-child layout change set.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                gridId (1, 1) string
                changes (1, :) struct
                registry yamada.model.ComponentRegistry = yamada.model.ComponentRegistry.empty
            end
            arguments (Output)
                entries yamada.model.PropertyEntry
            end

            obj.ensureCurrentSource(registry);
            % Preflight every grid-owned and direct-child target before mutation.
            grid = obj.getComponent(gridId);
            if isempty(grid) || grid.Factory ~= "uigridlayout"
                error("yamada:DocumentModel:InvalidGridLayoutEdit", ...
                    "Grid layout ID ""%s"" does not identify a Grid Layout.", gridId);
            end
            if ~grid.IsEditable || isempty(changes) || ...
                    ~isfield(changes, "ComponentId") || ~isfield(changes, "Path") || ...
                    ~isfield(changes, "Value")
                error("yamada:DocumentModel:InvalidGridLayoutEdit", ...
                    "A grid layout edit requires editable ComponentId, Path, and Value changes.");
            end
            componentIds = string({changes.ComponentId});
            paths = string({changes.Path});
            keys = componentIds + char(0) + paths;
            if any(strlength(componentIds) == 0) || any(strlength(paths) == 0) || ...
                    numel(unique(keys)) ~= numel(keys)
                error("yamada:DocumentModel:InvalidGridLayoutEdit", ...
                    "Grid layout edit targets must be nonempty and unique.");
            end

            historyChanges = repmat(struct("ComponentId", "", "Path", "", ...
                "HadOldValue", false, "OldValue", [], "NewValue", []), 1, numel(changes));
            for index = 1:numel(changes)
                component = obj.getComponent(componentIds(index));
                if isempty(component) || ~component.IsEditable
                    error("yamada:DocumentModel:InvalidGridLayoutEdit", ...
                        "Every grid layout edit target must be an editable component.");
                end
                obj.validateGridLayoutTarget(grid, component, paths(index), changes(index).Value);
                entry = component.getProperty(paths(index));
                if ~isempty(entry) && ~entry.IsEditable
                    error("yamada:DocumentModel:ReadOnlyProperty", ...
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

            if obj.tryImmediatePropertyBatch(changes, registry)
                entries = yamada.model.PropertyEntry.empty;
                for change = changes
                    entries(end + 1) = obj.getComponent(string(change.ComponentId)).getProperty(string(change.Path)); %#ok<AGROW>
                end
                return
            end

            % Check the combined emitted initialization before changing parsed records.
            if any(arrayfun(@(id) yamada.model.SourceOwnership.hasSource(obj.getComponent(id)), componentIds)) && ...
                    strlength(obj.CurrentText) > 0
                if isempty(registry), registry = yamada.model.ComponentRegistry.createDefault(); end
                candidate = obj.structuralCandidate();
                for change = changes
                    target = candidate.getComponent(string(change.ComponentId));
                    target.setProperty(string(change.Path), change.Value);
                end
                [source, diagnostics, sourcePatches] = yamada.source.RoundTripGenerator(registry).generate(candidate);
                if strlength(source) == 0 || yamada.validation.ModelValidator.hasErrors(diagnostics)
                    error("yamada:DocumentModel:UnsafePropertyEdit", "%s", strjoin(string({diagnostics.Message}), newline));
                end
                [parsed, ~] = candidate.editedSourceCandidate(source, sourcePatches, registry);
                diagnostics = parsed.Diagnostics;
                if yamada.validation.ModelValidator.hasErrors(diagnostics)
                    error("yamada:DocumentModel:UnsafePropertyEdit", "%s", strjoin(string({diagnostics.Message}), newline));
                end
                for id = unique(componentIds, "stable")
                    original = obj.getComponent(id);
                    configured = parsed.getComponentByName(original.Name);
                    if isempty(configured)
                        error("yamada:DocumentModel:UnsafePropertyEdit", "A grid-edit component was not retained.");
                    end
                    states = parsed.getEffectivePropertyStates(registry, configured.Id);
                    obj.assertRequestedStates(states, changes(componentIds == id));
                end
            end

            % Commit once, and restore every prior entry if any future setter fails.
            entries = yamada.model.PropertyEntry.empty;
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
                obj (1, 1) yamada.model.DocumentModel
                registry (1, 1) yamada.model.ComponentRegistry
                componentId string
            end
            arguments (Output)
                states (1, :) struct
                diagnostics yamada.model.Diagnostic
            end

            % Resolve parent context without materializing any catalog defaults.
            component = obj.getComponent(componentId);
            if isempty(component)
                error("yamada:DocumentModel:UnknownComponent", ...
                    "Component ID ""%s"" does not exist.", componentId);
            end
            parentFactory = "";
            if strlength(component.ParentId) > 0
                parent = obj.getComponent(component.ParentId);
                parentFactory = parent.Factory;
            end
            definitions = registry.getEffectiveProperties(component.Factory, parentFactory, ...
                component.CreationArguments);
            [resolved, diagnostics] = yamada.model.PropertyStateResolver.resolve(component, definitions, obj, registry);
            states = repmat(struct("Definition", yamada.model.PropertyDefinition(), ...
                "Entry", yamada.model.PropertyEntry.empty, "IsExplicit", false, ...
                "Resolution", yamada.model.PropertyState()), ...
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
                obj (1, 1) yamada.model.DocumentModel
                componentId string
                path string
            end

            % Refuse source-backed and parsed assignments until deletion ownership exists.
            component = obj.getComponent(componentId);
            if isempty(component)
                error("yamada:DocumentModel:UnknownComponent", ...
                    "Component ID ""%s"" does not exist.", componentId);
            end
            entry = component.getProperty(path);
            if isempty(entry)
                return
            end
            if ~entry.IsEditable
                error("yamada:DocumentModel:ReadOnlyProperty", ...
                    "Property ""%s"" is source-backed and read-only.", path);
            end
            if entry.Origin == "parsed"
                error("yamada:DocumentModel:ParsedPropertyResetUnsupported", ...
                    "Parsed property ""%s"" cannot be removed safely yet.", path);
            end

            % Keep absence as a first-class history state instead of materializing a default.
            oldValue = entry.LiteralValue;
            oldEntry = entry.toStruct();
            beforeSettings = component.settingSnapshot();
            source = "";
            if ~isempty(obj.CurrentSource)
                edits = struct("Start", {}, "End", {}, "Text", {});
                analysis = obj.sourceAnalysis();
                for setting = component.getSettings(path)
                    if setting.Method == "nameValue"
                        statement = analysis.Statements(analysis.statementIndices(setting.SourceSpan));
                        edits = [edits yamada.source.FactoryCallEditor.remove(statement, setting)]; %#ok<AGROW>
                    elseif ~isempty(setting.SourceSpan)
                        edits(end + 1) = struct("Start", setting.SourceSpan.StartOffset, ...
                            "End", setting.SourceSpan.EndOffset, "Text", ""); %#ok<AGROW>
                    end
                end
                edits = yamada.source.SourceFormatting.cleanDeletions(obj.CurrentText, edits);
                source = yamada.source.SourcePatchBatch(obj.CurrentText, edits).AfterText;
            end
            component.removeProperty(path);
            obj.recordHistory(struct("Kind", "reset-property", ...
                "ComponentId", componentId, "Path", path, "OldValue", oldValue, ...
                "OldEntry", oldEntry, "BeforeSettings", beforeSettings, "SourceCandidateText", source));
        end

        function confirmSavedSource(obj, checkpoint, registry)
            % confirmSavedSource Attach confirmed saved positions while retaining the immutable edit baseline.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                checkpoint (1, 1) yamada.model.SavedSourceCheckpoint
                registry (1, 1) yamada.model.ComponentRegistry
            end

            % Validate before committing metadata or advancing the saved history position.
            checkpoint.assertCurrent(obj, registry);
            if ~isempty(obj.CurrentSource) && checkpoint.ClassName ~= obj.ClassName
                [text, history] = yamada.model.SourceHistoryRebaser.rename(obj.CurrentText, obj.History, ...
                    obj.HistoryIndex, checkpoint.ClassName);
                batch = yamada.model.SourceHistoryRebaser.lineChanges(obj.CurrentText, text);
                obj.publishParsedSource(obj.CurrentSource.withBatch(batch, obj.CurrentSource.StateId), registry);
                obj.History = history;
            end
            obj.SavedSource = checkpoint;
            obj.ClassName = checkpoint.ClassName;
            obj.FilePath = checkpoint.FilePath;
            obj.GeneratedText = checkpoint.SourceText;
            obj.markSaved();
            if ~isempty(obj.CurrentSource)
                obj.publishCurrentSource(obj.CurrentSource);
                obj.adoptValidationProof(checkpoint.validationProof(), registry);
            end
        end

        function markSaved(obj)
            % markSaved Record the current history position as a confirmed save point.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
            end

            % Saving makes the exact current history position clean until a later edit.
            obj.SavedHistoryIndex = obj.HistoryIndex;
            obj.HasSavedHistoryCheckpoint = true;
            obj.IsDirty = false;
        end
        function component = getComponent(obj, id)
            % getComponent Find a component by stable identifier, or return empty.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                id string
            end
            arguments (Output)
                component
            end

            % Reuse only successful identities; structural assignments invalidate numeric indices.
            component = [];
            reusable = isscalar(id) && ~ismissing(id) && strlength(id) > 0 && ...
                all(isvalid(obj.Components), "all");
            if reusable
                if ~obj.ComponentLookupReady
                    if obj.ComponentLookup.Count > 0
                        obj.ComponentLookup = containers.Map("KeyType", "char", "ValueType", "double");
                    end
                    obj.ComponentLookupReady = true;
                end
                key = char(id);
                if isKey(obj.ComponentLookup, key)
                    component = obj.Components(obj.ComponentLookup(key));
                    return
                end
            end
            % Keep first-match order and legacy behavior for invalid handles or non-scalar IDs.
            for index = 1:numel(obj.Components)
                candidate = obj.Components(index);
                if candidate.Id == id
                    component = candidate;
                    if reusable, obj.ComponentLookup(key) = index; end
                    return
                end
            end
        end

        function component = getComponentByName(obj, name)
            % getComponentByName Find a component by MATLAB property name.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
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
                obj (1, 1) yamada.model.DocumentModel
                id string
            end

            obj.ensureCurrentSource(obj.SourceRegistry);
            % Locate the record before changing its parent or document ordering.
            component = obj.getComponent(id);
            if isempty(component)
                error("yamada:DocumentModel:UnknownComponent", ...
                    "Component ID ""%s"" does not exist.", id);
            end
            if ~isempty(component.Children)
                error("yamada:DocumentModel:NonLeafDeletion", ...
                    "Component ""%s"" has children and cannot be deleted safely.", id);
            end
            if id == obj.RootComponentId
                error("yamada:DocumentModel:RootDeletion", ...
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
                obj (1, 1) yamada.model.DocumentModel
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = obj.HistoryIndex > 0;
        end

        function result = canRedo(obj)
            % canRedo Report whether one undone edit can be reapplied.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = obj.HistoryIndex < numel(obj.History);
        end

        function name = sourceComponentName(obj, componentId)
            % sourceComponentName Return the identifier belonging to original source spans.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
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
                obj (1, 1) yamada.model.DocumentModel
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
                obj (1, 1) yamada.model.DocumentModel
                componentId (1, 1) string
                newName (1, 1) string
                registry (1, 1) yamada.model.ComponentRegistry = yamada.model.ComponentRegistry.createDefault()
            end

            obj.ensureCurrentSource(registry);
            [base, staged] = obj.prepareStagedLiterals(registry);
            if ~isempty(staged)
                before = obj.CurrentSource; oldName = obj.getComponent(componentId).Name;
                base.renameComponent(componentId, newName, registry);
                if oldName == newName, return, end
                edit = base.History{end};
                combined = obj.sourceDifference(before.Text, base.CurrentText);
                edit.StagedEdit = staged; edit.IdentifierForward = edit.SourceForward; edit.IdentifierInverse = edit.SourceInverse;
                edit.SourceForward = combined.Edits; edit.SourceInverse = combined.InverseEdits;
                edit.SourceBeforeId = before.StateId;
                component = obj.getComponent(componentId); component.Name = newName;
                obj.publishParsedSource(base.CurrentSource, registry, base, true);
                obj.SourcePublication = true; cleanup = onCleanup(@() obj.endSourcePublication());
                obj.recordHistory(edit); return
            end
            % Validate the complete current source before changing authoritative state.
            component = obj.getComponent(componentId);
            if isempty(component) || ~component.IsEditable
                error("yamada:DocumentModel:UnsafeComponentRename", "This component cannot be renamed safely.");
            end
            if yamada.model.SourceOwnership.hasSource(component) && ...
                    (isempty(component.SourceSpans.Declaration) || ~component.SourceSpans.Declaration.isKnown() || ...
                    isempty(component.SourceSpans.Creation) || ~component.SourceSpans.Creation.isKnown())
                error("yamada:DocumentModel:UnsafeComponentRename", "Component declaration or creation ownership is unknown.");
            end
            oldName = component.Name;
            if oldName == newName, return, end
            previousText = obj.GeneratedText;
            previousDiagnostics = obj.Diagnostics;
            before = obj.RenameEdits;
            try
                source = obj.CurrentText; diagnostics = obj.validatePropertyCommit(registry);
                analysis = obj.sourceAnalysis(); names = analysis.nameIndex();
                if yamada.validation.ModelValidator.hasErrors(diagnostics)
                    error("yamada:DocumentModel:UnsafeComponentRename", "Resolve source generation errors before renaming.");
                end
                yamada.source.ComponentNameRewriter.validate(source, oldName, newName, names);
                inherited = [string(properties("handle")); string(methods("handle"))];
                if any(inherited == newName) || newName == obj.ClassName || ...
                        any(string({obj.Components.Name}) == newName) || ...
                        any(string({before.OldName}) == newName & ...
                        (string({before.ComponentId}) ~= componentId | string({before.Kind}) == "method"))
                    error("yamada:DocumentModel:ComponentNameCollision", "The name '%s' is already reserved.", newName);
                end
                after = obj.updatedRenameMappings(before, componentId, "property", oldName, newName);

                % Only exclusively owned default handler names follow the component.
                states = yamada.source.CallbackSourceAnalyzer.analyze(obj, componentId, registry);
                parentFactory = "";
                if component.ParentId ~= "", parentFactory = obj.getComponent(component.ParentId).Factory; end
                definitions = registry.getEffectiveCallbacks(component.Factory, parentFactory, component.CreationArguments);
                members = names.Members;
                code = names.Code;
                identifiers = string(regexp(code, '[A-Za-z]\w*', 'match'));
                used = [members, identifiers, string({before.OldName}), newName, obj.ClassName, "createComponents", "delete", "figureDeleted"];
                for state = states(:)'
                    handler = state.HandlerName;
                    if strlength(handler) == 0, continue, end
                    if state.State ~= "editable"
                        % Extra static calls may prevent deletion without preventing a rename.
                        handles = regexp(code, '@(?:app\s*\.\s*)?' + handler + '(?!\w)', 'match');
                        if ~any(members == handler) || numel(handles) ~= 1 || ...
                                ~yamada.source.ComponentNameRewriter.canRenameHandler(source, handler, code)
                            continue
                        end
                    end
                    definition = definitions(string({definitions.Path}) == state.Name);
                    stems = unique([yamada.source.ComponentNameRewriter.defaultHandler(oldName, state.Name, definition.HandlerSuffix), ...
                        yamada.source.ComponentNameRewriter.defaultHandler(oldName, state.Name)], "stable");
                    stem = "";
                    for candidate = stems
                        if handler == candidate || ~isempty(regexp(handler, "^" + candidate + "_(?:[2-9][0-9]*|1[0-9]+)$", 'once'))
                            stem = candidate; break
                        end
                    end
                    if stem == "", continue, end
                    suffix = extractAfter(handler, strlength(stem));
                    newStem = yamada.source.ComponentNameRewriter.defaultHandler(newName, state.Name, definition.HandlerSuffix);
                    newHandler = newStem + suffix;
                    number = 1;
                    while any(used(used ~= handler) == newHandler) || any(inherited == newHandler)
                        number = number + 1;
                        newHandler = newStem + "_" + number;
                    end
                    used(used == handler) = newHandler;
                    after = obj.updatedRenameMappings(after, componentId, "method", handler, newHandler);
                end
                [~, edits] = yamada.source.ComponentNameRewriter.rewrite(source, after, names);
                batch = yamada.source.SourcePatchBatch(source, edits);
                execution = analysis.executionIndex();
                [projected, ~] = analysis.withLiteralPatches(batch, yamada.source.SourceStatement.empty, ...
                    [], [], zeros(size(execution.Counts)), execution, strings(1, 0), after);
            catch exception
                component.Name = oldName;
                obj.RenameEdits = before;
                obj.GeneratedText = previousText;
                obj.Diagnostics = previousDiagnostics;
                rethrow(exception)
            end
            sourceBefore = obj.CurrentSource;
            obj.publishIdentifierPatch(batch, projected, after, componentId, newName);
            edit = struct("Kind", "rename", "ComponentId", componentId, ...
                "OldName", oldName, "NewName", newName, "Before", before, "After", after, ...
                "IndexedRename", true, "StagedEdit", struct([]), ...
                "IdentifierForward", batch.Edits, "IdentifierInverse", batch.InverseEdits, ...
                "SourceForward", batch.Edits, "SourceInverse", batch.InverseEdits, ...
                "SourceBeforeId", sourceBefore.StateId, "SourceAfterId", obj.CurrentSource.StateId);
            obj.SourcePublication = true;
            cleanup = onCleanup(@() obj.endSourcePublication());
            obj.recordHistory(edit);
        end

        function revision = callbackRevision(obj, registry)
            % callbackRevision Identify the exact model, source and catalog used to populate a callback list.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                registry (1, 1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                revision (1, 1) struct
            end
            [clock, counter, tracked] = obj.inputStamp();
            revision = struct("Clock", clock, "Counter", counter, "Tracked", tracked, ...
                "SourceId", obj.CurrentSource.StateId, "Registry", registry, "CatalogRevision", registry.Revision);
        end

        function states = callbackStates(obj, componentId, registry, bindingOnly)
            % callbackStates Prepare callback ownership once per source and catalog revision.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                componentId (1, 1) string
                registry (1, 1) yamada.model.ComponentRegistry
                bindingOnly (1, 1) logical = true
            end
            arguments (Output)
                states yamada.model.CallbackState
            end
            obj.ensureCurrentSource(registry);
            revision = obj.callbackRevision(registry); cached = obj.CallbackPreparation;
            if revision.Tracked && ~isempty(fieldnames(cached)) && cached.ComponentId == componentId && ...
                    cached.BindingOnly == bindingOnly && isequaln(cached.Revision, revision)
                states = cached.States; return
            end
            states = yamada.source.CallbackSourceAnalyzer.analyze(obj, componentId, registry, bindingOnly);
            obj.CallbackPreparation = struct("Revision", revision, "ComponentId", componentId, ...
                "BindingOnly", bindingOnly, "States", states, ...
                "Targets", struct("Name", {}, "Values", {}));
        end

        function targets = callbackTargets(obj, componentId, name, registry)
            % callbackTargets Retain the eligible method values shown by the current callback dropdown.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                componentId (1, 1) string
                name (1, 1) string
                registry (1, 1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                targets (1, :) struct
            end
            obj.callbackStates(componentId, registry);
            cached = obj.CallbackPreparation; found = find(string({cached.Targets.Name}) == name, 1);
            if ~isempty(found), targets = cached.Targets(found).Values; return, end
            targets = yamada.source.CallbackMethodTargets.list(obj, componentId, name, registry);
            cached.Targets(end + 1) = struct("Name", name, "Values", targets);
            obj.CallbackPreparation = cached;
        end

        function applyCallbackAction(obj, componentId, name, action, registry, requestedHandler)
            % applyCallbackAction Preflight and record a binding-plus-method edit as one history step.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                componentId (1, 1) string
                name (1, 1) string
                action (1, 1) string {mustBeMember(action, ["Add", "Delete", "New", "Connect", "Disconnect"])}
                registry (1, 1) yamada.model.ComponentRegistry
                requestedHandler (1, 1) string = ""
            end

            try
                obj.ensureCurrentSource(registry);
            catch exception
                failure = MException("yamada:DocumentModel:UnsafeCallbackSource", "%s", exception.message);
                throw(addCause(failure, exception));
            end
            % Validate current availability before changing any document or history state.
            bindingOnly = any(action == ["New", "Connect", "Disconnect"]);
            states = obj.callbackStates(componentId, registry, bindingOnly);
            state = states(string({states.Name}) == name);
            if numel(state) ~= 1 || ...
                    ~(action == "Add" && state.State == "absent" || action == "Delete" && state.State == "editable" || ...
                    bindingOnly && state.State ~= "unsupported")
                error("yamada:DocumentModel:UnsafeCallbackEdit", "The callback action is unavailable or unsafe.");
            end
            if action == "Disconnect" && state.State == "absent", return, end
            component = obj.getComponent(componentId);
            before = obj.CallbackEdits;
            after = before;
            existing = find(string({before.ComponentId}) == componentId & string({before.Name}) == name);
            original = state;
            if ~isempty(existing)
                prior = before(existing);
                original = yamada.model.CallbackState(name, state.State, "", "", ...
                    prior.BindingSpan, prior.MethodSpan, prior.BindingAnchor, prior.MethodAnchor);
                after(existing) = [];
            end
            handler = "";
            method = "";
            expression = "";
            if action == "Connect"
                targets = obj.callbackTargets(componentId, name, registry);
                target = targets(string({targets.Name}) == requestedHandler);
                if ~isscalar(target)
                    error("yamada:DocumentModel:UnsafeCallbackTarget", "The selected method is no longer an eligible callback target.");
                end
                handler = target.Name;
                expression = target.Expression;
                if state.State == "editable" && state.HandlerName == handler, return, end
            end
            if any(action == ["Add", "New"])
                parentFactory = "";
                if component.ParentId ~= "", parentFactory = obj.getComponent(component.ParentId).Factory; end
                definition = registry.getEffectiveCallbacks(component.Factory, parentFactory, component.CreationArguments);
                definition = definition(string({definition.Path}) == name);
                % Share collision-aware naming with the callback name popup.
                if action == "Add", handler = yamada.source.CallbackMethodTargets.defaultName(obj, componentId, name, registry); end
                if action == "New"
                    names = obj.sourceAnalysis().nameIndex();
                    reserved = [string({obj.Components.Name}), string({after.HandlerName}), ...
                        names.Members, obj.ClassName, "createComponents", "delete", "figureDeleted", ...
                        string(properties("handle"))', string(methods("handle"))'];
                    if ~isvarname(requestedHandler) || iskeyword(requestedHandler) || ...
                            strlength(requestedHandler) > namelengthmax || any(reserved == requestedHandler)
                        error("yamada:DocumentModel:CallbackNameCollision", "Enter a valid, unused callback method name.");
                    end
                    handler = requestedHandler;
                end
                ending = string(newline);
                if obj.LineEnding == "CRLF", ending = string(sprintf("\r\n")); end
                method = yamada.source.CallbackSourceEdits.handlerText(handler, name, obj.ClassName, ending, ...
                    component.Factory == "uifigure" && name == "CloseRequestFcn", definition.CallbackSignature);
            end
            if any(action == ["Add", "New", "Connect"]) || ~isempty(original.BindingSpan) || ~isempty(original.MethodSpan)
                after(end + 1) = yamada.model.CallbackEdit(componentId, name, action, handler, method, original, obj.CurrentText, expression);
            end

            % Apply only owned callback patches; value and hierarchy validation remains valid.
            previousContext = obj.evaluationContext(registry);
            callbackOnly = obj.currentModelIsBound();
            obj.CallbackEdits = after;
            try
                if callbackOnly
                    [patches, diagnostics] = yamada.source.CallbackSourceEdits.build(obj);
                else
                    % Detached builders may still have primary values that need their own source edits.
                    [~, diagnostics, patches] = yamada.source.RoundTripGenerator(registry).generate(obj);
                end
                if yamada.validation.ModelValidator.hasErrors(diagnostics)
                    error("yamada:DocumentModel:UnsafeCallbackSource", "%s", strjoin(string({diagnostics.Message}), newline));
                end
                patches = yamada.source.CallbackSourceEdits.combineInsertions(patches);
                patches = yamada.source.SourceFormatting.cleanDeletions(obj.CurrentText, patches);
                batch = yamada.source.SourcePatchBatch(obj.CurrentText, patches);
                callback = struct();
                if callbackOnly, callback = struct("Context", previousContext, "ComponentId", componentId); end
                [candidate, ~] = obj.editedSourceCandidate(batch.AfterText, batch.Edits, registry, "", callback);
            catch exception
                obj.CallbackEdits = before;
                rethrow(exception)
            end
            beforeSource = obj.CurrentSource;
            if callbackOnly
                obj.publishCallbackSource(candidate.CurrentSource, candidate, registry, componentId);
            else
                obj.publishPlannedSource(candidate.CurrentSource, candidate, registry);
            end
            edit = struct("Kind", "callback", "ComponentId", componentId, "Before", before, ...
                "After", after, "DeletedHandler", state.HandlerName, "CallbackOnly", callbackOnly, "SourceForward", batch.Edits, ...
                "SourceInverse", batch.InverseEdits, "SourceBeforeId", beforeSource.StateId, "SourceAfterId", obj.CurrentSource.StateId);
            obj.SourcePublication = true; cleanup = onCleanup(@() obj.endSourcePublication());
            obj.recordHistory(edit);
        end

        function candidate = structuralCandidate(obj, registry)
            % structuralCandidate Clone mutable data and optionally inherit unchanged value resolutions.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                registry yamada.model.ComponentRegistry = yamada.model.ComponentRegistry.empty
            end
            arguments (Output)
                candidate (1, 1) yamada.model.DocumentModel
            end

            snapshot = yamada.model.SubtreeSnapshot(obj, obj.RootComponentId);
            candidate = yamada.model.DocumentModel(obj.ClassName);
            candidate.Components = snapshot.materialize();
            fields = ["FilePath", "OriginalText", "GeneratedText", "RootComponentId", ...
                "Diagnostics", "UnknownRegions", "Encoding", "LineEnding", "Metadata"];
            for field = fields, candidate.(field) = obj.(field); end
            candidate.CallbackEdits = obj.CallbackEdits;
            if isprop(obj, "RenameEdits"), candidate.("RenameEdits") = obj.("RenameEdits"); end
            % Pending deletion records are read-only inputs to generation.
            candidate.PendingEdits = obj.PendingEdits;
            candidate.SourceAnalysisData = obj.SourceAnalysisData;
            candidate.CurrentSource = obj.CurrentSource;
            candidate.SourceRegistry = obj.SourceRegistry;
            candidate.PlanBaseline = obj.PlanBaseline;
            catalog = registry; if isempty(catalog), catalog = obj.SourceRegistry; end
            if isempty(candidate.PlanBaseline) || ~isempty(catalog) && obj.hasCurrentValidation(catalog)
                candidate.PlanBaseline = obj.Evaluation;
            end
            % Resolver entries are independent values; mutation invalidates their normal scopes.
            if ~isempty(registry) && ~isempty(obj.Evaluation)
                previous = obj.evaluationContext(registry);
                current = candidate.evaluationContext(registry);
                current.inheritStates(previous);
                if obj.hasCurrentValidation(registry)
                    current.inheritPlannedStates(previous, strings(1, 0), yamada.source.SourcePatchBatch(obj.CurrentText));
                    candidate.PropertyValidationContext = current; candidate.PropertyValidationNames = strings(1, 0);
                    candidate.PropertyValidationDiagnostics = obj.PropertyValidationDiagnostics;
                    candidate.PlannedValidation = true; candidate.PlannedScope = obj.PlannedScope;
                end
            end
        end

        function removeSubtree(obj, id, registry)
            % removeSubtree Preflight and delete a complete subtree as one history step.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                id (1, 1) string
                registry (1, 1) yamada.model.ComponentRegistry = yamada.model.ComponentRegistry.createDefault()
            end

            obj.ensureCurrentSource(registry);
            if id == obj.RootComponentId
                error("yamada:DocumentModel:RootDeletion", "The root component cannot be deleted.");
            end
            snapshot = yamada.model.SubtreeSnapshot(obj, id);
            ids = string({snapshot.Records.Id});
            removed = obj.Components(ismember(string({obj.Components.Id}), ids));
            for component = removed
                if ~component.IsEditable
                    error("yamada:DocumentModel:UnsafeSubtreeEdit", "The subtree contains a read-only component.");
                end
                callbacks = yamada.source.CallbackSourceAnalyzer.analyze(obj, component.Id, registry);
                if any(string({callbacks.State}) ~= "absent")
                    error("yamada:DocumentModel:UnsafeSubtreeEdit", "Callback ownership prevents complete subtree deletion.");
                end
            end
            % The live canonical ranges already describe the exact current source.
            rewrittenReferences = yamada.source.SubtreeSourceEdits.detachedParentReferences(obj, ids);
            edits = yamada.source.SubtreeSourceEdits.deletion(obj.CurrentText, removed, rewrittenReferences);
            edits = yamada.source.SourceFormatting.completeLineDeletions(obj.CurrentText, edits);
            batch = yamada.source.SourcePatchBatch(obj.CurrentText, edits);
            candidate = obj.structuralCandidate(); root = obj.getComponent(id); parent = obj.getComponent(root.ParentId);
            beforeChildren = parent.Children; beforeOrder = string({obj.Components.Id});
            candidate.Components = candidate.Components(~ismember(string({candidate.Components.Id}), ids));
            candidateParent = candidate.getComponent(parent.Id); candidateParent.removeChild(id);
            [candidate, state] = obj.prepareComponentPublication(candidate, batch, string({removed.Name}), registry);
            before = obj.CurrentSource;
            obj.Components = obj.Components(~ismember(string({obj.Components.Id}), ids)); parent.removeChild(id);
            obj.publishParsedSource(state, registry, candidate, true);
            edit = struct("Kind", "source-subtree-delete", "ParentId", parent.Id, ...
                "Snapshot", snapshot, "InsertedComponents", removed, "BeforeChildren", beforeChildren, "AfterChildren", parent.Children, ...
                "BeforeOrder", beforeOrder, "AfterOrder", string({obj.Components.Id}), ...
                "SourceForward", batch.Edits, "SourceInverse", batch.InverseEdits, ...
                "ComponentForward", batch.Edits, "ComponentInverse", batch.InverseEdits, "StagedEdit", struct([]), ...
                "SourceBeforeId", before.StateId, "SourceAfterId", obj.CurrentSource.StateId);
            obj.SourcePublication = true; cleanup = onCleanup(@() obj.endSourcePublication());
            obj.recordHistory(edit);
        end

        function reparentSubtree(obj, id, parentId, registry, measuredPosition, targetCell, targetPosition)
            % reparentSubtree Move a complete subtree with stable identities and one history step.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                id (1, 1) string
                parentId (1, 1) string
                registry (1, 1) yamada.model.ComponentRegistry = yamada.model.ComponentRegistry.createDefault()
                measuredPosition double {mustBeFinite} = []
                targetCell double {mustBeFinite} = []
                targetPosition double {mustBeFinite} = []
            end

            % Unexpanded execution cannot establish safe hierarchy or placement changes.
            if yamada.model.PropertyStateResolver.hasUnresolvedExecution(obj)
                error("yamada:DocumentModel:UnsafeSubtreeEdit", ...
                    "Unresolved initialization effects prevent proving subtree relocation safety.");
            end
            % Resolve a side-effect-free placement plan before preparing candidate data.
            snapshot = yamada.model.SubtreeSnapshot(obj, id);
            ids = string({snapshot.Records.Id});
            try
                plan = yamada.model.SubtreePlacementPlanner.prepare(obj, snapshot, parentId, registry, ids, ...
                    measuredPosition, [0 0], targetCell, targetPosition, true);
            catch exception
                error("yamada:DocumentModel:UnsafeSubtreeEdit", "%s", string(exception.message));
            end
            obj.ensureCurrentSource(registry);
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
            hierarchy = yamada.model.SubtreeSnapshot(candidate, candidate.RootComponentId);
            orderedIds = string({hierarchy.Records.Id});
            currentIds = string({candidate.Components.Id});
            [~, indices] = ismember(orderedIds, currentIds);
            candidate.Components = candidate.Components(indices);
            candidate.PendingEdits{end + 1} = struct("Kind", "reparent-subtree", ...
                "OriginalRecords", snapshot.Records);
            try
                if obj.currentModelIsBound()
                    [sourcePatches, ~, placedDocument] = yamada.source.SubtreeReparentSourceEdits.build(candidate, registry);
                else
                    [text, diagnostics, sourcePatches] = yamada.source.RoundTripGenerator(registry).generate(candidate);
                    if yamada.validation.ModelValidator.hasErrors(diagnostics)
                        error("yamada:DocumentModel:UnsafeSubtreeEdit", "%s", strjoin(string({diagnostics.Message}), newline));
                    end
                    [placedDocument, ~] = candidate.editedSourceCandidate(text, sourcePatches, registry);
                end
            catch exception
                error("yamada:DocumentModel:UnsafeSubtreeEdit", "%s", string(exception.message));
            end
            source = placedDocument.CurrentText; diagnostics = placedDocument.Diagnostics;
            afterSnapshot = yamada.model.SubtreeSnapshot(placedDocument, id);
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
                "BeforePending", {beforePending}, "AfterPending", {candidate.PendingEdits}), source, placedDocument, sourcePatches);
        end

        function snapshot = copySubtree(obj, id, registry)
            % copySubtree Freeze supported subtree configuration while leaving callbacks on the original.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                id (1, 1) string
                registry (1, 1) yamada.model.ComponentRegistry = yamada.model.ComponentRegistry.createDefault()
            end
            arguments (Output)
                snapshot (1, 1) yamada.model.SubtreeSnapshot
            end
            if id == obj.RootComponentId
                error("yamada:DocumentModel:UnsafeSubtreeCopy", "The document root cannot be copied.");
            end
            snapshot = yamada.model.SubtreeSnapshot(obj, id);
            analysis = obj.sourceAnalysis();
            direct = false(1, 0);
            if any(arrayfun(@yamada.model.SourceOwnership.hasSource, snapshot.Records)), [direct, ~] = analysis.directInitializationScope(); end
            for record = snapshot.Records
                if ~record.IsEditable
                    error("yamada:DocumentModel:UnsafeSubtreeCopy", "A subtree component is read-only.");
                end
                definition = registry.get(record.Factory, record.CreationArguments);
                if definition.IsProgrammaticOnly || definition.Category == "FigureTools"
                    error("yamada:DocumentModel:UnsafeSubtreeCopy", "This construction family is not supported for copying.");
                end
                callbackPaths = yamada.model.SubtreeCopyPlanner.callbackPaths(obj, record.Id, registry);
                for property = record.Properties
                    if any(callbackPaths == property.Path), continue, end
                    if property.ValueKind == "expression"
                        try
                            owner = obj.getComponent(record.Id);
                            if isfield(property.Metadata, "SubtreeReferenceId")
                                target = obj.getComponent(string(property.Metadata.SubtreeReferenceId));
                                if isempty(target), error("yamada:DocumentModel:UnsafeSubtreeCopy", "Reference target is missing."); end
                                yamada.model.SubtreeReferencePolicy.validate(obj, owner, property.Path, target, registry);
                                targetId = target.Id;
                            else
                                targetId = yamada.model.SubtreeReferencePolicy.resolve(obj, owner, property.Path, property.SourceExpression, registry);
                            end
                            metadata = property.Metadata;
                            metadata.SubtreeReferenceId = targetId;
                            snapshot = snapshot.withPropertyMetadata(record.Id, property.Path, metadata);
                        catch exception
                            error("yamada:DocumentModel:UnsafeSubtreeCopy", "%s", string(exception.message));
                        end
                        continue
                    end
                    if property.ValueKind ~= "literal" || ...
                            registry.isReadOnlyProperty(record.Factory, property.Path, record.CreationArguments)
                        error("yamada:DocumentModel:UnsafeSubtreeCopy", "A property cannot be copied without losing source behavior.");
                    end
                    yamada.source.LiteralEncoder.encode(property.LiteralValue);
                end
                if yamada.model.SourceOwnership.hasSource(record)
                    if isempty(record.SourceSpans.Creation) || ~record.SourceSpans.Creation.isKnown() || ...
                            isempty(record.SourceSpans.Declaration) || ~record.SourceSpans.Declaration.isKnown()
                        error("yamada:DocumentModel:UnsafeSubtreeCopy", "Creation or declaration ownership is missing.");
                    end
                    span = record.SourceSpans.Creation;
                    matches = analysis.statementIndices(span);
                    if numel(matches) ~= 1 || ~direct(matches)
                        error("yamada:DocumentModel:UnsafeSubtreeCopy", "Component creation ownership is ambiguous.");
                    end
                    yamada.model.SubtreeCopyPlanner.validateConstructor(obj, record, registry, callbackPaths);
                end
            end
            snapshot = snapshot.withCopyConfiguration(yamada.model.SubtreeCopyPlanner.prepare(obj, snapshot, registry));
        end

        function component = pasteSubtree(obj, snapshot, parentId, registry, measuredPosition, offset, preserveNames)
            % pasteSubtree Insert independently named component records as one undoable edit.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                snapshot (1, 1) yamada.model.SubtreeSnapshot
                parentId (1, 1) string
                registry (1, 1) yamada.model.ComponentRegistry = yamada.model.ComponentRegistry.createDefault()
                measuredPosition double {mustBeFinite} = []
                offset (1, 2) double {mustBeFinite} = [10 10]
                preserveNames (1, 1) logical = false
            end
            arguments (Output)
                component (1, 1) yamada.model.ComponentRecord
            end
            obj.ensureCurrentSource(registry);
            [base, staged] = obj.prepareStagedLiterals(registry);
            configuration = snapshot.CopyConfiguration;
            if isempty(configuration)
                configuration = yamada.model.SubtreeCopyPlanner.prepare(obj, snapshot, registry);
            end
            snapshot = snapshot.withCopyConfiguration(configuration);
            plan = yamada.model.SubtreePlacementPlanner.prepare(base, snapshot, parentId, registry, ...
                strings(1, 0), measuredPosition, offset);
            candidate = base.structuralCandidate();
            oldIds = string({snapshot.Records.Id});
            newIds = strings(size(oldIds));
            newNames = strings(size(oldIds));
            usedNames = [string({obj.Components.Name}), string({obj.CallbackEdits.HandlerName}), ...
                string(methods("handle"))', string(properties("handle"))', ...
                obj.ClassName, "createComponents", "delete", "figureDeleted"];
            if isprop(obj, "RenameEdits")
                mappings = obj.("RenameEdits");
                usedNames = [usedNames string({mappings.OldName})];
                if ~preserveNames, usedNames = [usedNames string({mappings.NewName})]; end
            end
            % Reserve identifiers in the effective source after pending deletions.
            namingSource = base.CurrentText;
            if preserveNames
                namingSource = base.CurrentText;
                sourceMembers = yamada.source.ComponentNameRewriter.memberNames(namingSource);
                sourceReferences = string(regexp(yamada.source.ComponentNameRewriter.codeMask(namingSource), ...
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
            inserted = yamada.model.ComponentRecord.empty;
            for index = 1:numel(oldIds)
                record = snapshot.Records(index);
                fresh = yamada.model.ComponentRecord(newIds(index), newNames(index), record.Factory, record.DeclaredType, "generated");
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
                            if isempty(target), error("yamada:DocumentModel:UnsafeSubtreeCopy", "Reference target no longer exists."); end
                            targetName = target.Name;
                        end
                        entry = fresh.setProperty(property.Path, []);
                        entry.setSourceExpression("app." + targetName);
                        entry.Metadata.SubtreeReferenceId = targetId;
                        continue
                    end
                    if property.ValueKind ~= "literal" || ...
                            registry.isReadOnlyProperty(record.Factory, property.Path, record.CreationArguments)
                        error("yamada:DocumentModel:UnsafeSubtreeCopy", "Paste requires a validated literal snapshot.");
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
            % Emit and recognize only the newly inserted component block.
            obj.ensureCurrentSource(registry);
            edits = yamada.source.RoundTripGenerator(registry).componentInsertionEdits(candidate, inserted);
            batch = yamada.source.SourcePatchBatch(base.CurrentText, edits);
            [candidate, state] = base.prepareComponentPublication(candidate, batch, newNames, registry, "", obj);
            yamada.model.SubtreeCopyPlanner.verify(candidate, configuration, inserted, plan.Changes, registry);
            frozen = yamada.model.SubtreeSnapshot(candidate, component.Id);
            inserted = frozen.materialize(); component = inserted(1);
            parent = obj.getComponent(parentId); beforeChildren = parent.Children;
            before = obj.CurrentSource;
            obj.Components = [obj.Components inserted]; parent.addChild(component.Id);
            obj.publishParsedSource(state, registry, candidate, true);
            combined = batch;
            if ~isempty(staged), combined = obj.sourceDifference(before.Text, state.Text); end
            edit = struct("Kind", "source-subtree-insert", "ParentId", parentId, ...
                "Snapshot", frozen, "InsertedComponents", inserted, "BeforeChildren", beforeChildren, "AfterChildren", parent.Children, ...
                "SourceForward", combined.Edits, "SourceInverse", combined.InverseEdits, ...
                "ComponentForward", batch.Edits, "ComponentInverse", batch.InverseEdits, "StagedEdit", staged, ...
                "SourceBeforeId", before.StateId, "SourceAfterId", obj.CurrentSource.StateId);
            obj.SourcePublication = true; cleanup = onCleanup(@() obj.endSourcePublication());
            obj.recordHistory(edit);
        end

        function undo(obj)
            % undo Reverse the most recent document edit.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
            end
            if ~obj.canUndo()
                error("yamada:DocumentModel:NoUndo", "There is no edit to undo.");
            end
            edit = obj.History{obj.HistoryIndex};
            obj.assertHistorySource(edit, false);
            if any(edit.Kind == ["source-subtree-insert", "source-subtree-delete"])
                obj.applyComponentHistory(edit, false);
            elseif edit.Kind == "rename" && isfield(edit, "IndexedRename")
                obj.applyIdentifierHistory(edit, false);
            elseif edit.Kind == "source-property"
                obj.applySourcePropertyHistory(edit, false);
            elseif edit.Kind == "source-property-batch"
                obj.applySourceBatchHistory(edit, false);
            else
                obj.SourcePublication = isfield(edit, "SourceForward");
                cleanup = onCleanup(@() obj.endSourcePublication());
                obj.applyHistory(edit, false);
                obj.restoreHistorySource(edit, false);
            end
            obj.HistoryIndex = obj.HistoryIndex - 1;
            obj.IsDirty = ~(obj.HasSavedHistoryCheckpoint && ...
                obj.HistoryIndex == obj.SavedHistoryIndex);
        end

        function redo(obj)
            % redo Reapply the next edit in the document history.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
            end
            if ~obj.canRedo()
                error("yamada:DocumentModel:NoRedo", "There is no edit to redo.");
            end
            edit = obj.History{obj.HistoryIndex + 1};
            obj.assertHistorySource(edit, true);
            if any(edit.Kind == ["source-subtree-insert", "source-subtree-delete"])
                obj.applyComponentHistory(edit, true);
            elseif edit.Kind == "rename" && isfield(edit, "IndexedRename")
                obj.applyIdentifierHistory(edit, true);
            elseif edit.Kind == "source-property"
                obj.applySourcePropertyHistory(edit, true);
            elseif edit.Kind == "source-property-batch"
                obj.applySourceBatchHistory(edit, true);
            else
                obj.SourcePublication = isfield(edit, "SourceForward");
                cleanup = onCleanup(@() obj.endSourcePublication());
                obj.applyHistory(edit, true);
                obj.restoreHistorySource(edit, true);
            end
            obj.HistoryIndex = obj.HistoryIndex + 1;
            % Redo remains conservatively dirty even when it revisits a save point.
            obj.IsDirty = true;
        end
    end

    methods (Access = private)
        function resetSourceInput(obj)
            % resetSourceInput Invalidate derived revisions after an explicit input replacement.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
            end
            obj.CurrentSource = yamada.model.CurrentSourceState.empty;
            obj.HasPublishedInputStamp = false;
        end

        function ensureCurrentSource(obj, registry)
            % ensureCurrentSource Emit the initial canonical source once before the first user mutation.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                registry yamada.model.ComponentRegistry
            end
            if isempty(registry), registry = obj.SourceRegistry; end
            if isempty(registry), return, end
            obj.SourceRegistry = registry;
            if ~isempty(obj.CurrentSource)
                obj.discardUnownedReadOnlyInputs(registry);
                return
            end
            if strlength(obj.OriginalText) > 0
                obj.CurrentSource = yamada.model.CurrentSourceState(obj.OriginalText, obj.sourceAnalysis());
            else
                previousDiagnostics = obj.Diagnostics;
                previousText = obj.GeneratedText;
                [text, diagnostics] = yamada.source.NewAppGenerator(registry).generate(obj);
                obj.Diagnostics = previousDiagnostics;
                obj.GeneratedText = previousText;
                if yamada.validation.ModelValidator.hasErrors(diagnostics)
                    error("yamada:DocumentModel:UnsafeInitialSource", "%s", strjoin(string({diagnostics.Message}), newline));
                end
                obj.publishInitialGeneratedSource(text, registry, diagnostics);
            end
        end

        function publishInitialGeneratedSource(obj, text, registry, diagnostics)
            % publishInitialGeneratedSource Bind trusted initial output to the existing model without whole-source parsing.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                text (1, 1) string
                registry (1, 1) yamada.model.ComponentRegistry
                diagnostics yamada.model.Diagnostic
            end

            % Match generated declarations and factories against known component identities.
            state = yamada.model.CurrentSourceState(text);
            analysis = state.Analysis;
            candidate = obj.structuralCandidate();
            candidate.SourceRegistry = registry;
            candidate.publishCurrentSource(state);
            statements = analysis.Statements;
            texts = string({statements.Text});
            for component = candidate.Components
                declaration = find(startsWith(texts, component.Name + " "));
                creation = find(~cellfun(@isempty, regexp(cellstr(texts), ...
                    '^app\.' + regexptranslate('escape', component.Name) + '\s*=', 'once')));
                assert(isscalar(declaration) && isscalar(creation), ...
                    "yamada:DocumentModel:UnsafeInitialSource", "Initial output needs unique declarations and factories.");
                component.SourceSpans = struct("Declaration", statements(declaration).Span, "Creation", statements(creation).Span);
                definition = registry.get(component.Factory, component.CreationArguments);
                [~, ~, settings, ~, supported] = yamada.source.PropertySettingSyntax.factory(statements(creation), definition, state.StateId);
                assert(supported, "yamada:DocumentModel:UnsafeInitialSource", "Initial factory syntax must match the known model.");
                % Seed constructor occurrence counts before compiling initialization sequences.
                for setting = settings, component.recordSetting(setting); end
            end

            % Reuse the same emitted-token binder and validation proof as component insertion.
            execution = yamada.model.SourceSettingRebinder.executionSequences(candidate, state, ...
                yamada.source.SourcePatchBatch(text), registry);
            obj.inputStamp();
            obj.SettingStore.reserveAfter(candidate.SettingStore);
            candidate.bindInsertedComponents(statements, string({candidate.Components.Name}), analysis, state, registry, obj);
            trace = execution.Trace;
            candidate.Metadata.SourceSnapshotId = state.StateId;
            candidate.Metadata.InitializationContext = struct("Order", trace.Order, "Certain", trace.Certain, ...
                "Returns", trace.Returns, "Layout", analysis.Layout);
            candidate.Metadata.HasUnresolvedInitialization = false;
            candidate.Diagnostics = diagnostics;
            yamada.model.SourceEffectSummary.refresh(candidate, registry);
            candidate.publishCurrentSource(state);
            diagnostics = candidate.validatePropertyCommit(registry);
            if yamada.validation.ModelValidator.hasErrors(diagnostics)
                error("yamada:DocumentModel:UnsafeInitialSource", "%s", strjoin(string({diagnostics.Message}), newline));
            end
            obj.publishParsedSource(state, registry, candidate, true);
        end

        function discardUnownedReadOnlyInputs(obj, registry)
            % discardUnownedReadOnlyInputs Omit legacy builder requests that never owned writable source.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                registry (1, 1) yamada.model.ComponentRegistry
            end
            for component = obj.Components
                if ~registry.contains(component.Factory), continue, end
                for entry = component.Properties
                    if entry.Origin ~= "generated" || ~isempty(entry.SourceSpan), continue, end
                    settings = component.getSettings(entry.Path);
                    if any(string({settings.Method}) ~= "generated"), continue, end
                    if registry.isReadOnlyProperty(component.Factory, entry.Path, component.CreationArguments)
                        component.removeProperty(entry.Path);
                    end
                end
            end
        end

        function result = currentModelIsBound(obj)
            % currentModelIsBound Keep staged builder changes out of the already-published literal fast path.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = false;
            if ~isempty(obj.PendingEdits) || ~isempty(obj.CallbackEdits) || ~isempty(obj.RenameEdits), return, end
            for component = obj.Components
                if isempty(component.SourceSpans.Creation) || any(string({component.Settings.Method}) == "generated"), return, end
                for entry = component.Properties
                    if ~isfield(entry.Metadata, "SourceSettingId"), return, end
                    settings = component.getSettings(entry.Path);
                    index = find(string({settings.Id}) == string(entry.Metadata.SourceSettingId), 1);
                    if isempty(index), return, end
                    setting = settings(index);
                    if setting.IsEditable && (setting.ValueKind ~= entry.ValueKind || ...
                            (entry.ValueKind == "literal" && ~isequaln(setting.LiteralValue, entry.LiteralValue)))
                        return
                    end
                end
            end
            result = true;
        end

        function result = tryImmediateProperties(obj, id, changes, registry)
            % tryImmediateProperties Prove local literals and publish source, bindings and history as one edit.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                id (1, 1) string
                changes (1, :) struct
                registry yamada.model.ComponentRegistry
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = false;
            if isempty(registry), registry = obj.SourceRegistry; end
            if isempty(registry), return, end
            obj.ensureCurrentSource(registry);
            if ~obj.currentModelIsBound(), return, end
            component = obj.getComponent(id);
            previousContext = obj.evaluationContext(registry);
            carryValidation = ~isempty(obj.PropertyValidationContext) && isempty(obj.PropertyValidationNames) && ...
                obj.PropertyValidationContext.matches(obj, registry) && ...
                ~yamada.validation.ModelValidator.hasErrors(obj.PropertyValidationDiagnostics);
            previousDiagnostics = obj.PropertyValidationDiagnostics;
            beforeSettings = component.Settings;
            before = obj.CurrentSource;
            if isfield(obj.Metadata, "SourceSnapshotText") && obj.Metadata.SourceSnapshotText ~= before.Text
                error("yamada:DocumentModel:UnsafePropertyEdit", "The input source changed without parsing.");
            end
            try
                prepared = yamada.model.SourceLiteralTransaction(obj, before, id, changes, registry);
            catch exception
                if startsWith(string(exception.identifier), "yamada:LiteralEncoder:") || ...
                        (string(exception.identifier) == "yamada:SourceLiteralTransaction:InvalidValue" && ...
                        all(ismember(string({changes.Path}), string({beforeSettings.Path}))))
                    error("yamada:DocumentModel:UnsafePropertyEdit", "%s", exception.message);
                end
                if any(string(exception.identifier) == ["yamada:SourceLiteralTransaction:WiderProof", "yamada:SourceLiteralTransaction:InvalidValue", ...
                        "yamada:SourceSettingRebinder:NeedsModelParse", "yamada:PropertyInsertionPlanner:UnsafePlacement"])
                    return
                end
                rethrow(exception)
            end
            prepared.applyModel(obj, before, registry);
            obj.publishCurrentSource(prepared.AfterSource);
            [updates, token] = prepared.inputProjection();
            currentContext = yamada.model.EvaluationContext.projectSource(obj, registry, previousContext, ...
                updates, id, string({changes.Path}), token);
            obj.Evaluation = currentContext;
            if prepared.CanReuseStates
                currentContext.inheritLiteralStates(previousContext, id, prepared.Batch, prepared.CanPreserveDocumentStates);
            end
            if prepared.CanReuseEligibility
                currentContext.inheritEligibility(previousContext);
            end
            validation = prepared.validationResult();
            if isfield(validation, "Plan")
                obj.adoptPlannedResult(validation.Plan, registry, currentContext);
            elseif isfield(validation, "Proof") && obj.adoptValidationProof(validation.Proof, registry, currentContext)
                % The exact complete candidate already supplied every dependency-scoped state.
            elseif validation.Ready
                currentContext.remember("states:" + id, struct("Definitions", validation.Definitions, ...
                    "States", validation.States, "Diagnostics", validation.StateDiagnostics));
                obj.PropertyValidationContext = currentContext;
                obj.PropertyValidationNames = strings(1, 0);
                obj.PropertyValidationDiagnostics = validation.Diagnostics;
                obj.Diagnostics = validation.Diagnostics;
            elseif carryValidation && prepared.CanReuseStates
                obj.PropertyValidationContext = currentContext;
                obj.PropertyValidationNames = component.Name;
                if all(ismember(string({changes.Path}), string({beforeSettings.Path})))
                    % Existing owned slots need no second check after their finite local proof.
                    obj.PropertyValidationNames = strings(1, 0);
                end
                obj.PropertyValidationDiagnostics = yamada.model.SourceLocationUpdate.relocateDiagnostics(previousDiagnostics, prepared.Batch);
            end
            edit = struct("Kind", "source-property", "ComponentId", id, "Changes", changes, ...
                "SettingIdentities", yamada.model.SourcePropertyHistory.capture(beforeSettings, component.Settings, string({changes.Path})), ...
                "Insertions", prepared.Placements, ...
                "SourceForward", prepared.Batch.Edits, "SourceInverse", prepared.Batch.InverseEdits, ...
                "SourceBeforeId", before.StateId, "SourceAfterId", obj.CurrentSource.StateId);
            obj.SourcePublication = true;
            cleanup = onCleanup(@() obj.endSourcePublication());
            obj.recordHistory(edit);
            result = true;
        end

        function result = tryImmediatePropertyBatch(obj, changes, registry)
            % tryImmediatePropertyBatch Publish multiple literal owners as one exact-source and history transaction.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                changes (1, :) struct
                registry yamada.model.ComponentRegistry
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = false;
            if isempty(registry), registry = obj.SourceRegistry; end
            if isempty(registry), return, end
            obj.ensureCurrentSource(registry);
            if ~obj.currentModelIsBound(), return, end
            before = obj.CurrentSource;
            ids = unique(string({changes.ComponentId}), "stable");
            beforeSettings = cell(1, numel(ids));
            for index = 1:numel(ids), beforeSettings{index} = obj.getComponent(ids(index)).Settings; end
            try
                prepared = yamada.model.SourceLiteralBatchTransaction(obj, before, changes, registry);
            catch exception
                if any(string(exception.identifier) == ["yamada:SourceLiteralTransaction:WiderProof", ...
                        "yamada:SourceLiteralTransaction:InvalidValue", "yamada:SourceSettingRebinder:NeedsModelParse", ...
                        "yamada:PropertyInsertionPlanner:UnsafePlacement"])
                    return
                end
                rethrow(exception)
            end
            prepared.applyModel(obj, before, registry);
            obj.publishCurrentSource(prepared.AfterSource);
            validation = prepared.validationResult();
            if isfield(validation, "Plan")
                obj.adoptPlannedResult(validation.Plan, registry);
            elseif ~obj.adoptValidationProof(validation.Proof, registry)
                context = obj.evaluationContext(registry);
                for owner = validation.Owners
                    context.remember("states:" + owner.ComponentId, struct("Definitions", owner.Definitions, ...
                        "States", owner.States, "Diagnostics", yamada.model.Diagnostic.empty));
                end
                obj.PropertyValidationContext = context; obj.PropertyValidationNames = strings(1, 0);
                obj.PropertyValidationDiagnostics = validation.Diagnostics;
            end
            owners = struct("ComponentId", {}, "Changes", {}, "SettingIdentities", {}, "Insertions", {});
            for index = 1:numel(prepared.Specs)
                spec = prepared.Specs(index); component = obj.getComponent(spec.ComponentId);
                identities = yamada.model.SourcePropertyHistory.capture(beforeSettings{index}, component.Settings, string({spec.Changes.Path}));
                owners(end + 1) = struct("ComponentId", spec.ComponentId, "Changes", spec.Changes, ...
                    "SettingIdentities", identities, "Insertions", spec.Placements); %#ok<AGROW>
            end
            edit = struct("Kind", "source-property-batch", "Changes", changes, "Owners", owners, ...
                "SourceForward", prepared.Batch.Edits, "SourceInverse", prepared.Batch.InverseEdits, ...
                "SourceBeforeId", before.StateId, "SourceAfterId", obj.CurrentSource.StateId);
            obj.SourcePublication = true; cleanup = onCleanup(@() obj.endSourcePublication());
            obj.recordHistory(edit); result = true;
        end

        function ready = hasCurrentValidation(obj, registry)
            % hasCurrentValidation Require a fully checked baseline for carrying unrelated validation through a local patch.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                registry (1, 1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                ready (1, 1) logical
            end
            ready = ~isempty(obj.PropertyValidationContext) && isempty(obj.PropertyValidationNames) && ...
                obj.PropertyValidationContext.matches(obj, registry) && ...
                ~yamada.validation.ModelValidator.hasErrors(obj.PropertyValidationDiagnostics);
            if ready, [~, ready] = obj.PropertyValidationContext.revisionToken(); end
        end

        function carryHistoryValidation(obj, previous, ready, diagnostics, batch, changes)
            % carryHistoryValidation Check changed dependency scopes and preserve the proven unrelated document baseline.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                previous (1, 1) yamada.model.EvaluationContext
                ready (1, 1) logical
                diagnostics yamada.model.Diagnostic
                batch (1, 1) yamada.source.SourcePatchBatch
                changes (1, :) struct
            end
            if ~ready, return, end
            registry = obj.SourceRegistry; context = obj.evaluationContext(registry);
            ids = unique(string({changes.ComponentId}), "stable");
            if isscalar(ids)
                component = obj.getComponent(ids); parent = obj.getComponent(component.ParentId); parentFactory = "";
                if ~isempty(parent), parentFactory = parent.Factory; end
                definitions = registry.getEffectiveProperties(component.Factory, parentFactory, component.CreationArguments);
                paths = string({changes.Path}); localPaths = yamada.model.PropertyStateResolver.ownerLocalPaths(definitions);
                local = all(ismember(paths, localPaths));
                for path = paths
                    definition = definitions([definitions.Path] == path);
                    local = local && (isempty(component.Children) || ...
                        (~definition.AbsoluteGeometryImpact && definition.GridGeometryImpact ~= "required"));
                end
                [baseline, found] = previous.lookup("states:" + ids);
                if local && found && isequaln(baseline.Definitions, definitions)
                    context.inheritLiteralStates(previous, ids, batch, true);
                    [states, stateDiagnostics] = yamada.model.PropertyStateResolver.resolve(component, definitions, obj, registry);
                    if isempty(stateDiagnostics)
                        try
                            result = yamada.validation.ModelValidator.prepareIndependentProperties(component, definitions, ...
                                states, baseline.States, paths, diagnostics, batch);
                        catch exception
                            if string(exception.identifier) ~= "yamada:SourceLiteralTransaction:InvalidValue", rethrow(exception), end
                            result = struct("Ready", false);
                        end
                        if result.Ready
                            context.rememberValidatedStates(ids, struct("Definitions", definitions, "States", result.States, ...
                                "Diagnostics", result.StateDiagnostics));
                            obj.PropertyValidationContext = context; obj.PropertyValidationNames = strings(1, 0);
                            obj.PropertyValidationDiagnostics = result.Diagnostics; obj.Diagnostics = result.Diagnostics;
                            return
                        end
                    end
                end
            end
            % Replayed primary changes use the same bounded accepted-input checks.
            obj.finishPlannedValidation(registry, previous, ids, batch);
        end

        function adopted = adoptValidationProof(obj, proof, registry, context)
            % adoptValidationProof Publish independent proven values only after exact source, input and catalog joins.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                proof yamada.model.DocumentValidationProof
                registry (1, 1) yamada.model.ComponentRegistry
                context yamada.model.EvaluationContext = yamada.model.EvaluationContext.empty
            end
            arguments (Output)
                adopted (1, 1) logical
            end
            adopted = false;
            if isempty(proof), return, end
            [clock, revision, tracked] = obj.inputStamp(); if ~tracked, return, end
            [owners, diagnostics, ready] = proof.rebind(obj, registry);
            if ~ready, return, end
            if isempty(context), context = yamada.model.EvaluationContext.fromValidated(obj, registry); end
            if ~context.matches(obj, registry), return, end
            [currentClock, currentRevision, currentTracked] = obj.inputStamp();
            if ~currentTracked || currentClock ~= clock || currentRevision ~= revision, return, end
            for owner = owners, context.rememberValidatedStates(owner.ComponentId, owner.Resolved); end
            obj.Evaluation = context; obj.PropertyValidationContext = context;
            obj.PropertyValidationNames = strings(1, 0); obj.PropertyValidationDiagnostics = diagnostics;
            obj.Diagnostics = diagnostics; adopted = true;
        end

        function endSourcePublication(obj)
            % endSourcePublication Release the internal commit barrier even if history publication fails.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
            end
            obj.SourcePublication = false;
        end

        function publishCurrentSource(obj, state)
            % publishCurrentSource Retain one exact current source and retire command-local generation intentions.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                state (1, 1) yamada.model.CurrentSourceState
            end
            obj.PlannedValidation = false;
            obj.CurrentSource = state;
            obj.SourceAnalysisData = state.Analysis;
            obj.GeneratedText = state.Text;
            obj.PendingEdits = {};
            obj.CallbackEdits = yamada.model.CallbackEdit.empty;
            obj.RenameEdits = struct("ComponentId", {}, "Kind", {}, "OldName", {}, "NewName", {});
            obj.PropertyValidationContext = yamada.model.EvaluationContext.empty;
            obj.PropertyValidationNames = strings(1, 0);
            obj.Metadata.SourceSnapshotText = state.Text;
            [clock, revision] = obj.inputStamp();
            obj.SourceInputRevision = revision;
            obj.HasPublishedInputStamp = true;
            assert(~isempty(clock));
        end

        function publishParsedSource(obj, state, registry, parsed, requirePrepared)
            % publishParsedSource Adopt a broader proof while preserving live component and occurrence identities.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                state (1, 1) yamada.model.CurrentSourceState
                registry (1, 1) yamada.model.ComponentRegistry
                parsed yamada.model.DocumentModel = yamada.model.DocumentModel.empty
                requirePrepared (1, 1) logical = false
            end
            if requirePrepared && ~isempty(parsed) && parsed.PlannedValidation && parsed.CurrentText == state.Text && ...
                    parsed.hasCurrentValidation(registry)
                obj.publishPlannedSource(state, parsed, registry); return
            end
            % A command-local candidate is reusable only while its exact complete source proof still holds.
            if isempty(parsed) || ~isscalar(parsed) || parsed.CurrentText ~= state.Text || ...
                    ~parsed.hasCurrentValidation(registry) || ~parsed.currentModelIsBound()
                assert(~requirePrepared, "yamada:DocumentModel:InvalidPreparedSource", ...
                    "An indexed structural publication requires its existing complete model proof.");
                [parsed, diagnostics] = yamada.source.AppSourceParser.parseText(state.Text, registry);
            else
                diagnostics = parsed.PropertyValidationDiagnostics;
            end
            if yamada.validation.ModelValidator.hasErrors(diagnostics)
                error("yamada:DocumentModel:UnsafeSourceCommit", "%s", strjoin(string({diagnostics.Message}), newline));
            end
            assert(numel(parsed.Components) == numel(obj.Components), ...
                "yamada:DocumentModel:SourceComponentMismatch", "Current source must retain the committed component set.");
            % Validate the complete join before changing any live record.
            for component = obj.Components
                other = parsed.getComponentByName(component.Name);
                assert(~isempty(other) && component.Factory == other.Factory);
            end
            for component = obj.Components
                other = parsed.getComponentByName(component.Name);
                settings = other.Settings;
                for index = 1:numel(settings)
                    setting = settings(index);
                    previous = component.Settings(string({component.Settings.Path}) == setting.Path & ...
                        string({component.Settings.Method}) == setting.Method);
                    ordinal = nnz(string({settings(1:index).Path}) == setting.Path & ...
                        string({settings(1:index).Method}) == setting.Method);
                    if ordinal <= numel(previous)
                        record = setting.toStruct();
                        record.Location.Id = previous(ordinal).Id;
                        record.Location.SourceSnapshotId = previous(ordinal).SourceSnapshotId;
                        record.Location.StatementId = previous(ordinal).StatementId;
                        record.Location.InitializationScopeId = previous(ordinal).InitializationScopeId;
                        settings(index) = yamada.model.PropertySetting(record.Path, record.Value, record.Location);
                    elseif ~requirePrepared || setting.Id <= 0
                        settings(index) = setting.withIdentity(yamada.model.SettingIdAllocator.temporary(), setting.SourceSnapshotId);
                    end
                end
                settings = obj.canonicalizeSettings(settings);
                component.SourceSpans = other.SourceSpans;
                component.Metadata = other.Metadata;
                component.synchronizeSourceSettings(settings, other.CreationArguments);
            end
            obj.Diagnostics = parsed.Diagnostics;
            obj.UnknownRegions = parsed.UnknownRegions;
            obj.Metadata = parsed.Metadata;
            obj.publishCurrentSource(state.withAnalysis(parsed.sourceAnalysis()));
            obj.adoptValidationProof(parsed.captureValidationProof(registry), registry);
        end

        function previous = planBaseline(obj, registry)
            % planBaseline Read the last accepted source state while a command's semantic delta is being prepared.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                registry (1, 1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                previous (1, 1) yamada.model.EvaluationContext
            end
            previous = obj.PlanBaseline;
            if obj.hasCurrentValidation(registry) || isempty(previous), previous = obj.Evaluation; end
            if isempty(previous), previous = obj.evaluationContext(registry); end
        end

        function diagnostics = finishPlannedValidation(obj, registry, previous, changed, batch)
            % finishPlannedValidation Check an edit's accepted inputs and retain unrelated diagnostics and states.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                registry (1, 1) yamada.model.ComponentRegistry
                previous (1, 1) yamada.model.EvaluationContext
                changed (1, :) string
                batch (1, 1) yamada.source.SourcePatchBatch
            end
            arguments (Output)
                diagnostics yamada.model.Diagnostic
            end
            scope = previous.editScope(obj, changed);
            [token, ~] = previous.revisionToken();
            if token.Registry ~= registry || token.RegistryRevision ~= registry.Revision
                scope.Checked = string({obj.Components.Id}); scope.Invalidated = scope.Checked;
            end
            context = obj.evaluationContext(registry);
            context.inheritPlannedStates(previous, scope.Invalidated, batch);
            checked = yamada.validation.ModelValidator.validateOwners(obj, registry, scope.Checked);
            retained = obj.Diagnostics;
            if ~isempty(retained)
                retained = retained(~ismember(string({retained.ComponentId}), scope.Checked) & ...
                    ismember(string({retained.ComponentId}), ["" string({obj.Components.Id})]));
            end
            diagnostics = [retained checked]; obj.Diagnostics = diagnostics;
            obj.Evaluation = context; obj.PropertyValidationContext = context;
            obj.PropertyValidationNames = strings(1, 0); obj.PropertyValidationDiagnostics = diagnostics;
            obj.PlannedValidation = true; obj.PlannedScope = scope;
        end

        function plan = plannedResult(obj)
            % plannedResult Export independent cached values and diagnostics for an already accepted source plan.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
            end
            arguments (Output)
                plan (1, 1) struct
            end
            plan = struct("States", obj.Evaluation.stateValues(), "Diagnostics", obj.Diagnostics, ...
                "Scope", obj.PlannedScope);
        end

        function adoptPlannedResult(obj, plan, registry, context)
            % adoptPlannedResult Bind independent plan values to this exact post-edit input revision.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                plan (1, 1) struct
                registry (1, 1) yamada.model.ComponentRegistry
                context yamada.model.EvaluationContext = yamada.model.EvaluationContext.empty
            end
            if isempty(context), context = yamada.model.EvaluationContext.fromValidated(obj, registry); end
            for owner = plan.States, context.rememberValidatedStates(owner.ComponentId, owner.Resolved); end
            obj.Evaluation = context; obj.PropertyValidationContext = context;
            obj.PropertyValidationNames = strings(1, 0); obj.PropertyValidationDiagnostics = plan.Diagnostics;
            obj.Diagnostics = plan.Diagnostics; obj.PlannedValidation = true; obj.PlannedScope = plan.Scope;
        end

        function publishPlannedSource(obj, state, candidate, registry)
            % publishPlannedSource Publish the known source binding delta without comparing unchanged primary values again.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                state (1, 1) yamada.model.CurrentSourceState
                candidate (1, 1) yamada.model.DocumentModel
                registry (1, 1) yamada.model.ComponentRegistry
            end
            for component = obj.Components
                other = candidate.getComponent(component.Id);
                component.SourceSpans = other.SourceSpans; component.Metadata = other.Metadata;
                component.synchronizeSourceSettings(other.Settings, other.CreationArguments);
            end
            obj.Diagnostics = candidate.Diagnostics; obj.UnknownRegions = candidate.UnknownRegions;
            obj.Metadata = candidate.Metadata; obj.publishCurrentSource(state);
            obj.adoptPlannedResult(candidate.plannedResult(), registry);
        end

        function publishCallbackSource(obj, state, candidate, registry, componentId)
            % publishCallbackSource Apply a known callback projection without rechecking unrelated primary values.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                state (1, 1) yamada.model.CurrentSourceState
                candidate (1, 1) yamada.model.DocumentModel
                registry (1, 1) yamada.model.ComponentRegistry
                componentId (1, 1) string
            end
            % Stable component and occurrence IDs come directly from the owned patch projection.
            for component = obj.Components
                other = candidate.getComponent(component.Id);
                component.SourceSpans = other.SourceSpans;
                component.Metadata = other.Metadata;
                component.synchronizeSourceSettings(other.Settings, other.CreationArguments);
            end
            obj.Diagnostics = candidate.Diagnostics; obj.UnknownRegions = candidate.UnknownRegions;
            obj.Metadata = candidate.Metadata; obj.publishCurrentSource(state);
            % Retain independent computed values, rather than adopting a candidate document or context.
            prepared = candidate.evaluationContext(registry);
            context = yamada.model.EvaluationContext.fromValidated(obj, registry);
            context.inheritLiteralStates(prepared, componentId, yamada.source.SourcePatchBatch(state.Text), true);
            [resolved, found] = prepared.lookup("states:" + componentId);
            assert(found, "yamada:DocumentModel:MissingCallbackState", "The callback projection must retain its edited owner's states.");
            context.rememberValidatedStates(componentId, resolved);
            obj.Evaluation = context; obj.PropertyValidationContext = context;
            obj.PropertyValidationNames = strings(1, 0); obj.PropertyValidationDiagnostics = candidate.Diagnostics;
        end

        function [candidate, staged] = prepareStagedLiterals(obj, registry)
            % prepareStagedLiterals Prepare direct builder writes locally without publishing a partial command.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                registry (1, 1) yamada.model.ComponentRegistry
            end
            candidate = obj; staged = struct([]);
            if obj.currentModelIsBound(), return, end
            candidate = obj.structuralCandidate();
            candidate.inputStamp(); obj.inputStamp();
            candidate.SettingStore.reserveAfter(obj.SettingStore);
            changes = struct("ComponentId", {}, "Path", {}, "Value", {});
            for component = obj.Components
                other = candidate.getComponent(component.Id);
                settings = other.Settings(string({other.Settings.Method}) ~= "generated");
                other.synchronizeSourceSettings(settings, other.CreationArguments);
                for entry = component.Properties
                    if entry.ValueKind ~= "literal", continue, end
                    previous = other.getProperty(entry.Path);
                    if isempty(previous) || previous.ValueKind ~= "literal" || ~isequaln(previous.LiteralValue, entry.LiteralValue)
                        changes(end + 1) = struct("ComponentId", component.Id, "Path", entry.Path, "Value", {entry.LiteralValue}); %#ok<AGROW>
                    end
                end
            end
            if isempty(changes), return, end
            assert(candidate.tryImmediatePropertyBatch(changes, registry), ...
                "yamada:DocumentModel:UnpublishedSourceChanges", "Direct builder values need a supported local literal binding before this command.");
            candidate.validatePropertyCommit(registry);
            staged = candidate.History{end};
        end

        function [candidate, state] = prepareComponentPublication(obj, candidate, batch, names, registry, stateId, allocator)
            % prepareComponentPublication Bind emitted statements and rebase existing records without whole-source parsing.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                candidate (1, 1) yamada.model.DocumentModel
                batch (1, 1) yamada.source.SourcePatchBatch
                names (1, :) string
                registry (1, 1) yamada.model.ComponentRegistry
                stateId (1, 1) string = ""
                allocator (1, 1) yamada.model.DocumentModel = obj
            end
            arguments (Output)
                candidate (1, 1) yamada.model.DocumentModel
                state (1, 1) yamada.model.CurrentSourceState
            end
            [analysis, additions] = obj.sourceAnalysis().withComponentPatches(batch, names, candidate, registry);
            execution = analysis.executionIndex();
            state = obj.CurrentSource.withBatch(batch, stateId, analysis);
            removed = string({obj.Components.Id}); removed = removed(~ismember(removed, string({candidate.Components.Id})));
            projection = obj.prepareSettingProjection(batch, execution, removed);
            for component = obj.Components
                other = candidate.getComponent(component.Id); if isempty(other), continue, end
                update = yamada.model.SourceLocationUpdate(component, batch, struct("SettingId", {}, "Value", {}), ...
                    execution, analysis, obj.ownerSettingProjection(component, projection));
                update.assertCurrent(component); update.applyToCandidate(other);
            end
            candidate.bindInsertedComponents(additions, names, analysis, state, registry, allocator);
            [candidate.Diagnostics, candidate.UnknownRegions] = yamada.model.SourceLocationUpdate.annotations(obj, batch);
            trace = execution.Trace;
            candidate.Metadata.InitializationContext = struct("Order", trace.Order, "Certain", trace.Certain, ...
                "Returns", trace.Returns, "Layout", analysis.Layout);
            yamada.model.SourceEffectSummary.refresh(candidate, registry);
            candidate.publishCurrentSource(state);
            ids = unique([string({candidate.Components(ismember(string({candidate.Components.Name}), names)).Id}) removed], "stable");
            diagnostics = candidate.finishPlannedValidation(registry, obj.planBaseline(registry), ids, batch);
            if yamada.validation.ModelValidator.hasErrors(diagnostics)
                error("yamada:DocumentModel:UnsafeSubtreeEdit", "%s", strjoin(string({diagnostics.Message}), newline));
            end
            assert(candidate.hasCurrentValidation(registry), ...
                "yamada:DocumentModel:InvalidPreparedSource", "The emitted component block must retain its accepted input checks.");
        end

        function bindInsertedComponents(obj, statements, names, analysis, state, registry, allocator)
            % bindInsertedComponents Recover only editor-emitted factory and property tokens with stable numeric identities.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                statements yamada.source.SourceStatement
                names (1, :) string
                analysis (1, 1) yamada.source.SourceAnalysis
                state (1, 1) yamada.model.CurrentSourceState
                registry (1, 1) yamada.model.ComponentRegistry
                allocator (1, 1) yamada.model.DocumentModel
            end
            if isempty(statements), return, end
            execution = analysis.executionIndex();
            for name = names
                component = obj.getComponentByName(name); if isempty(component), continue, end
                previous = component.Settings;
                settings = yamada.model.PropertySetting.empty;
                declaration = yamada.model.SourceSpan.empty; creation = declaration;
                arguments = component.CreationArguments;
                for statement = statements
                    code = statement.Text;
                    if startsWith(code, name + " "), declaration = statement.Span; continue, end
                    if isempty(regexp(code, '^app\.' + regexptranslate('escape',name) + '(?:\.|\s*=)', 'once')), continue, end
                    index = analysis.statementIndices(statement.Span); visit = find(execution.Trace.Order == index);
                    assert(isscalar(visit), "yamada:DocumentModel:UnsafeSubtreeEdit", "An emitted statement requires one initialization visit.");
                    if ~isempty(regexp(code, '^app\.' + regexptranslate('escape',name) + '\s*=', 'once'))
                        creation = statement.Span;
                        definition = registry.get(component.Factory, component.CreationArguments);
                        [parentName, arguments, factorySettings, ~, supported] = yamada.source.PropertySettingSyntax.factory(statement, definition, state.StateId);
                        parent = obj.getComponent(component.ParentId);
                        root = component.Id == obj.RootComponentId && component.Factory == "uifigure" && isempty(parent) && parentName == "";
                        assert(supported && (root || ~isempty(parent) && parentName == parent.Name), ...
                            "yamada:DocumentModel:UnsafeSubtreeEdit", "Emitted factories must match the prepared parent and positional arguments.");
                        component.Metadata.InitializationCreationSequence = execution.Creation(visit);
                        component.Metadata.InitializationCreationCertain = execution.Trace.Certain(visit);
                        owner = analysis.Layout.Owner(index); scopes = analysis.Layout.Methods;
                        scope = scopes(string({scopes.Name}) == owner); assert(isscalar(scope));
                        for factoryIndex = 1:numel(factorySettings)
                            record = factorySettings(factoryIndex).toStruct();
                            record.Location.Sequence = execution.Creation(visit) + factoryIndex;
                            captured = yamada.model.PropertySetting(record.Path, record.Value, record.Location).withScope(owner, scope.Span);
                            old = previous(string({previous.Path}) == captured.Path & string({previous.Method}) == "nameValue");
                            if isscalar(old), captured = captured.withIdentity(old.Id, old.SourceSnapshotId); end
                            settings(end + 1) = allocator.canonicalizeSettings(captured); %#ok<AGROW>
                        end
                        continue
                    end
                    setting = yamada.source.PropertySettingSyntax.assignment(statement, state.StateId, ...
                        execution.Assignment(visit), execution.Trace.Certain(visit));
                    owner = analysis.Layout.Owner(index); methods = analysis.Layout.Methods;
                    scope = methods(string({methods.Name}) == owner);
                    assert(isscalar(scope)); setting = setting.withScope(owner, scope.Span);
                    old = previous(string({previous.Path}) == setting.Path & string({previous.Method}) == setting.Method);
                    if isscalar(old), setting = setting.withIdentity(old.Id, old.SourceSnapshotId); end
                    setting = allocator.canonicalizeSettings(setting);
                    settings(end + 1) = setting; %#ok<AGROW>
                end
                assert(~isempty(declaration) && ~isempty(creation), ...
                    "yamada:DocumentModel:UnsafeSubtreeEdit", "Every inserted component needs its declaration and factory.");
                component.SourceSpans = struct("Declaration", declaration, "Creation", creation);
                component.synchronizeSourceSettings(settings, arguments);
            end
        end

        function applyComponentHistory(obj, edit, forward)
            % applyComponentHistory Replay one inserted subtree by splicing its primary source patch and deriving indexes.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                edit (1, 1) struct
                forward (1, 1) logical
            end
            base = obj;
            if forward && ~isempty(edit.StagedEdit)
                base = obj.structuralCandidate(obj.SourceRegistry); base.applySourceBatchHistory(edit.StagedEdit, true);
            end
            candidate = base.structuralCandidate(); names = string({edit.Snapshot.Records.Name});
            ids = string({edit.Snapshot.Records.Id}); parent = candidate.getComponent(edit.ParentId);
            adding = forward ~= (edit.Kind == "source-subtree-delete");
            if adding
                inserted = edit.Snapshot.materialize(); candidate.Components = [candidate.Components inserted];
            else
                candidate.Components = candidate.Components(~ismember(string({candidate.Components.Id}), ids));
            end
            if forward
                children = edit.AfterChildren; edits = edit.ComponentForward; stateId = edit.SourceAfterId;
            else
                children = edit.BeforeChildren; edits = edit.ComponentInverse; stateId = edit.SourceBeforeId;
                if ~isempty(edit.StagedEdit), stateId = edit.StagedEdit.SourceAfterId; end
            end
            if isfield(edit, "BeforeOrder")
                order = edit.BeforeOrder; if forward, order = edit.AfterOrder; end
                [~, indices] = ismember(order, string({candidate.Components.Id})); candidate.Components = candidate.Components(indices);
            end
            for child = parent.Children, parent.removeChild(child); end
            for child = children, parent.addChild(child); end
            batch = yamada.source.SourcePatchBatch(base.CurrentText, edits);
            [candidate, state] = base.prepareComponentPublication(candidate, batch, names, obj.SourceRegistry, stateId, obj);
            if ~forward && ~isempty(edit.StagedEdit)
                candidate.applySourceBatchHistory(edit.StagedEdit, false); state = candidate.CurrentSource;
            end
            if adding
                obj.Components = [obj.Components edit.InsertedComponents];
            else
                obj.Components = obj.Components(~ismember(string({obj.Components.Id}), ids));
            end
            if isfield(edit, "BeforeOrder")
                [~, indices] = ismember(order, string({obj.Components.Id})); obj.Components = obj.Components(indices);
            end
            parent = obj.getComponent(edit.ParentId);
            for child = parent.Children, parent.removeChild(child); end
            for child = children, parent.addChild(child); end
            obj.publishParsedSource(state, obj.SourceRegistry, candidate, true);
        end

        function publishIdentifierPatch(obj, batch, analysis, mappings, id, name, stateId)
            % publishIdentifierPatch Rebase existing ownership and references without interpreting unchanged source.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                batch (1, 1) yamada.source.SourcePatchBatch
                analysis (1, 1) yamada.source.SourceAnalysis
                mappings (1, :) struct
                id (1, 1) string
                name (1, 1) string
                stateId (1, 1) string = ""
            end
            registry = obj.SourceRegistry;
            previous = obj.evaluationContext(registry); ready = obj.hasCurrentValidation(registry);
            diagnostics = yamada.model.SourceLocationUpdate.relocateDiagnostics(obj.Diagnostics, batch);
            execution = analysis.executionIndex();
            projection = obj.prepareSettingProjection(batch, execution, strings(1, 0));
            updates = yamada.model.SourceLocationUpdate.empty;
            for component = obj.Components
                updates(end + 1) = yamada.model.SourceLocationUpdate(component, batch, ...
                    struct("SettingId", {}, "Value", {}), execution, analysis, obj.ownerSettingProjection(component, projection)); %#ok<AGROW>
                updates(end).assertCurrent(component);
            end
            state = obj.CurrentSource.withBatch(batch, stateId, analysis);
            % All range and source assertions precede the first live mutation.
            obj.publishSettingProjection(projection);
            for update = updates, update.applyValidated(obj.getComponent(update.ComponentId)); end
            renamed = obj.getComponent(id); renamed.Name = name;
            for component = obj.Components
                settings = component.Settings;
                for index = 1:numel(settings)
                    setting = settings(index); record = setting.toStruct();
                    for mapping = mappings
                        if isfield(mapping, "Kind") && mapping.Kind == "method" && record.Location.OwnerMethod == mapping.OldName
                            record.Location.OwnerMethod = mapping.NewName;
                        end
                    end
                    if setting.ValueKind == "expression" && ~isempty(setting.ValueSpan)
                        record.Location.SourceExpression = extractBetween(state.Text, setting.ValueSpan.StartOffset, setting.ValueSpan.EndOffset);
                    end
                    settings(index) = yamada.model.PropertySetting(record.Path, record.Value, record.Location);
                end
                component.synchronizeSourceSettings(settings, component.CreationArguments);
            end
            regions = yamada.model.UnknownSourceRegion.empty;
            for region = obj.UnknownRegions
                [span, valid] = batch.mapSpan(region.Span); assert(valid);
                regions(end + 1) = yamada.model.UnknownSourceRegion( ...
                    extractBetween(state.Text, span.StartOffset, span.EndOffset), span, region.Reason); %#ok<AGROW>
            end
            obj.UnknownRegions = regions; obj.Diagnostics = diagnostics;
            trace = execution.Trace;
            obj.Metadata.InitializationContext = struct("Order", trace.Order, "Certain", trace.Certain, ...
                "Returns", trace.Returns, "Layout", analysis.Layout);
            obj.publishCurrentSource(state);
            % An identifier change preserves settings, execution order and every literal value.
            if ready
                context = obj.evaluationContext(registry);
                for component = obj.Components
                    [resolved, found] = previous.lookup("states:" + component.Id);
                    if ~found, continue, end
                    resolved.States = resolved.States.withSourceSettings(component.Settings);
                    resolved.Diagnostics = yamada.model.SourceLocationUpdate.relocateDiagnostics(resolved.Diagnostics, batch);
                    context.rememberValidatedStates(component.Id, resolved);
                end
                if ready
                    obj.PropertyValidationContext = context; obj.PropertyValidationNames = strings(1, 0);
                    obj.PropertyValidationDiagnostics = diagnostics;
                    obj.PlannedValidation = true; obj.PlannedScope = struct("Checked", strings(1, 0), "Invalidated", strings(1, 0));
                end
            end
        end

        function applyIdentifierHistory(obj, edit, forward)
            % applyIdentifierHistory Replay primary token edits and derive locations without a whole-source parse.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                edit (1, 1) struct
                forward (1, 1) logical
            end
            if ~isempty(edit.StagedEdit)
                candidate = obj.structuralCandidate(); staged = edit.StagedEdit;
                token = edit; token.StagedEdit = struct([]);
                token.SourceForward = edit.IdentifierForward; token.SourceInverse = edit.IdentifierInverse;
                token.SourceBeforeId = staged.SourceAfterId;
                if forward, candidate.applySourceBatchHistory(staged, true); end
                candidate.applyIdentifierHistory(token, forward);
                if ~forward, candidate.applySourceBatchHistory(staged, false); end
                owner = obj.getComponent(edit.ComponentId); owner.Name = candidate.getComponent(edit.ComponentId).Name;
                candidate.validatePropertyCommit(obj.SourceRegistry);
                obj.publishParsedSource(candidate.CurrentSource, obj.SourceRegistry, candidate, true); return
            end
            mappings = edit.After;
            if forward
                edits = edit.SourceForward; name = edit.NewName; stateId = edit.SourceAfterId;
            else
                edits = edit.SourceInverse; name = edit.OldName; stateId = edit.SourceBeforeId;
                for index = 1:numel(mappings)
                    old = mappings(index).OldName; mappings(index).OldName = mappings(index).NewName; mappings(index).NewName = old;
                end
            end
            batch = yamada.source.SourcePatchBatch(obj.CurrentText, edits);
            analysis = obj.sourceAnalysis(); execution = analysis.executionIndex();
            [analysis, ~] = analysis.withLiteralPatches(batch, yamada.source.SourceStatement.empty, ...
                [], [], zeros(size(execution.Counts)), execution, strings(1, 0), mappings);
            obj.publishIdentifierPatch(batch, analysis, mappings, edit.ComponentId, name, stateId);
        end

        function assertHistorySource(obj, edit, forward)
            % assertHistorySource Verify the current node before replaying any model history mutation.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                edit (1, 1) struct
                forward (1, 1) logical
            end
            if ~isfield(edit, "SourceForward"), return, end
            stateId = edit.SourceAfterId;
            if forward, stateId = edit.SourceBeforeId; end
            obj.CurrentSource.assertRevision(obj.CurrentSource.Revision, stateId);
        end

        function restoreHistorySource(obj, edit, forward)
            % restoreHistorySource Restore an already validated structural source patch after semantic history replay.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                edit (1, 1) struct
                forward (1, 1) logical
            end
            if ~isfield(edit, "SourceForward"), return, end
            if forward
                edits = edit.SourceForward;
                stateId = edit.SourceAfterId;
            else
                edits = edit.SourceInverse;
                stateId = edit.SourceBeforeId;
            end
            batch = yamada.source.SourcePatchBatch(obj.CurrentText, edits);
            callback = struct();
            if edit.Kind == "callback" && isfield(edit, "ComponentId") && ...
                    (~isfield(edit, "CallbackOnly") || edit.CallbackOnly)
                callback = struct("Context", obj.Evaluation, "ComponentId", edit.ComponentId);
            end
            [candidate, state] = obj.editedSourceCandidate(batch.AfterText, batch.Edits, obj.SourceRegistry, stateId, callback);
            if isempty(fieldnames(callback))
                obj.publishParsedSource(state, obj.SourceRegistry, candidate, true);
            else
                obj.publishCallbackSource(state, candidate, obj.SourceRegistry, callback.ComponentId);
            end
        end

        function applySourcePropertyHistory(obj, edit, forward)
            % applySourcePropertyHistory Apply primary text edits and derive current settings, positions and indexes anew.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                edit (1, 1) struct
                forward (1, 1) logical
            end
            previousContext = obj.evaluationContext(obj.SourceRegistry);
            carryValidation = obj.hasCurrentValidation(obj.SourceRegistry); previousDiagnostics = obj.PropertyValidationDiagnostics;
            [token, tracked] = previousContext.revisionToken();
            if ~tracked, token = struct(); end
            if forward
                edits = edit.SourceForward;
                identities = edit.SettingIdentities.Added;
                stateId = edit.SourceAfterId;
            else
                edits = edit.SourceInverse;
                identities = edit.SettingIdentities.Removed;
                stateId = edit.SourceBeforeId;
            end
            owner = obj.getComponent(edit.ComponentId);
            for target = edit.SettingIdentities.Targets
                expected = target.AfterId;
                if forward, expected = target.BeforeId; end
                if expected == 0, continue, end
                entry = owner.getProperty(target.Path);
                assert(~isempty(entry) && isfield(entry.Metadata, "SourceSettingId") && ...
                    entry.Metadata.SourceSettingId == expected, ...
                    "yamada:DocumentModel:StalePropertySetting", "History no longer owns the same value projection.");
            end
            batch = yamada.source.SourcePatchBatch(obj.CurrentText, edits);
            changes = struct("Path", {}, "Value", {});
            placements = struct("Path", {}, "Method", {}, "Offset", {}, "OwnerMethod", {});
            if forward, placements = edit.Insertions; end
            for target = edit.SettingIdentities.Targets
                if forward, id = target.AfterId; value = target.AfterValue;
                else, id = target.BeforeId; value = target.BeforeValue; end
                if id > 0, changes(end + 1) = struct("Path", target.Path, "Value", {value}); end %#ok<AGROW>
            end
            removed = edit.SettingIdentities.Added;
            if forward, removed = edit.SettingIdentities.Removed; end
            [state, settings, factoryArguments, execution] = yamada.model.IndexedSettingEdit.prepare( ...
                obj, obj.CurrentSource, owner, batch, changes, placements, obj.SourceRegistry, [removed.Id], stateId);
            settings = yamada.model.SourcePropertyHistory.restoreIdentities(settings, identities);
            projection = obj.prepareSettingProjection(batch, execution, owner.Id);
            [diagnostics, regions] = yamada.model.SourceLocationUpdate.annotations(obj, batch);
            updates = yamada.model.SourceLocationUpdate.empty;
            for component = obj.Components
                if component.Id == owner.Id, continue, end
                update = yamada.model.SourceLocationUpdate(component, batch, ...
                    struct("SettingId", {}, "Value", {}), execution, state.Analysis, ...
                    obj.ownerSettingProjection(component, projection));
                update.assertCurrent(component);
                updates(end + 1) = update; %#ok<AGROW>
            end
            [creation, valid] = batch.mapSpan(owner.SourceSpans.Creation);
            assert(valid);
            [declaration, valid] = batch.mapSpan(owner.SourceSpans.Declaration);
            assert(valid);
            obj.publishSettingProjection(projection);
            for update = updates, update.applyValidated(obj.getComponent(update.ComponentId)); end
            owner.SourceSpans = struct("Declaration", declaration, "Creation", creation);
            owner.synchronizeSourceSettings(settings, factoryArguments);
            obj.Diagnostics = diagnostics;
            obj.UnknownRegions = regions;
            visits = find(execution.Trace.Order == state.Analysis.statementIndices(creation));
            owner.Metadata.InitializationCreationSequence = execution.Creation(visits);
            trace = execution.Trace;
            obj.Metadata.InitializationContext = struct("Order", trace.Order, "Certain", trace.Certain, ...
                "Returns", trace.Returns, "Layout", state.Analysis.Layout);
            obj.publishCurrentSource(state);
            obj.Evaluation = yamada.model.EvaluationContext.projectSource(obj, obj.SourceRegistry, ...
                previousContext, updates, edit.ComponentId, string({edit.Changes.Path}), token);
            changed = struct("ComponentId", {}, "Path", {});
            for path = string({edit.Changes.Path}), changed(end + 1) = struct("ComponentId", edit.ComponentId, "Path", path); end %#ok<AGROW>
            obj.carryHistoryValidation(previousContext, carryValidation, previousDiagnostics, batch, changed);
        end

        function applySourceBatchHistory(obj, edit, forward)
            % applySourceBatchHistory Replay primary multi-owner edits and derive all positions from one maintained index.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                edit (1, 1) struct
                forward (1, 1) logical
            end
            previousContext = obj.evaluationContext(obj.SourceRegistry);
            carryValidation = obj.hasCurrentValidation(obj.SourceRegistry); previousDiagnostics = obj.PropertyValidationDiagnostics;
            [token, tracked] = previousContext.revisionToken(); if ~tracked, token = struct(); end
            if forward, edits = edit.SourceForward; stateId = edit.SourceAfterId;
            else, edits = edit.SourceInverse; stateId = edit.SourceBeforeId; end
            batch = yamada.source.SourcePatchBatch(obj.CurrentText, edits);
            specs = struct("ComponentId", {}, "Changes", {}, "Placements", {}, "RemovedIds", {});
            for owned = edit.Owners
                component = obj.getComponent(owned.ComponentId);
                changes = struct("Path", {}, "Value", {});
                placements = struct("Path", {}, "Method", {}, "Offset", {}, "OwnerMethod", {});
                if forward, placements = owned.Insertions; removed = owned.SettingIdentities.Removed;
                else, removed = owned.SettingIdentities.Added; end
                for target = owned.SettingIdentities.Targets
                    if forward, expected = target.BeforeId; id = target.AfterId; value = target.AfterValue;
                    else, expected = target.AfterId; id = target.BeforeId; value = target.BeforeValue; end
                    if expected > 0
                        entry = component.getProperty(target.Path);
                        assert(~isempty(entry) && isfield(entry.Metadata, "SourceSettingId") && entry.Metadata.SourceSettingId == expected, ...
                            "yamada:DocumentModel:StalePropertySetting", "History no longer owns the same value projection.");
                    end
                    if id > 0, changes(end + 1) = struct("Path", target.Path, "Value", {value}); end %#ok<AGROW>
                end
                specs(end + 1) = struct("ComponentId", owned.ComponentId, "Changes", changes, ...
                    "Placements", placements, "RemovedIds", [removed.Id]); %#ok<AGROW>
            end
            [state, bindings, execution] = yamada.model.IndexedSettingEdit.prepareMany( ...
                obj, obj.CurrentSource, specs, batch, obj.SourceRegistry, stateId);
            ids = string({specs.ComponentId});
            projection = obj.prepareSettingProjection(batch, execution, ids);
            [diagnostics, regions] = yamada.model.SourceLocationUpdate.annotations(obj, batch);
            updates = yamada.model.SourceLocationUpdate.empty;
            for component = obj.Components
                if ismember(component.Id, ids), continue, end
                update = yamada.model.SourceLocationUpdate(component, batch, ...
                    struct("SettingId", {}, "Value", {}), execution, state.Analysis, obj.ownerSettingProjection(component, projection));
                update.assertCurrent(component); updates(end + 1) = update; %#ok<AGROW>
            end
            % Prepare every changed owner's occurrence identities and spans before any publication.
            spans = cell(1, numel(bindings));
            for index = 1:numel(bindings)
                owner = obj.getComponent(bindings(index).ComponentId); owned = edit.Owners(index);
                if forward, identities = owned.SettingIdentities.Added; else, identities = owned.SettingIdentities.Removed; end
                bindings(index).Settings = yamada.model.SourcePropertyHistory.restoreIdentities(bindings(index).Settings, identities);
                [creation, valid] = batch.mapSpan(owner.SourceSpans.Creation); assert(valid);
                [declaration, valid] = batch.mapSpan(owner.SourceSpans.Declaration); assert(valid);
                spans{index} = struct("Declaration", declaration, "Creation", creation);
            end
            obj.publishSettingProjection(projection);
            for update = updates, update.applyValidated(obj.getComponent(update.ComponentId)); end
            for index = 1:numel(bindings)
                binding = bindings(index); owner = obj.getComponent(binding.ComponentId);
                owner.SourceSpans = spans{index};
                owner.synchronizeSourceSettings(binding.Settings, binding.FactoryArguments);
                visit = find(execution.Trace.Order == state.Analysis.statementIndices(spans{index}.Creation));
                owner.Metadata.InitializationCreationSequence = execution.Creation(visit);
            end
            obj.Diagnostics = diagnostics; obj.UnknownRegions = regions;
            trace = execution.Trace;
            obj.Metadata.InitializationContext = struct("Order", trace.Order, "Certain", trace.Certain, ...
                "Returns", trace.Returns, "Layout", state.Analysis.Layout);
            obj.publishCurrentSource(state);
            obj.Evaluation = yamada.model.EvaluationContext.projectSource(obj, obj.SourceRegistry, previousContext, ...
                updates, ids, unique(string({edit.Changes.Path})), token);
            obj.carryHistoryValidation(previousContext, carryValidation, previousDiagnostics, batch, edit.Changes);
        end

        function batch = sourceDifference(~, before, after)
            % sourceDifference Bound a broader source rewrite with exact common prefix and suffix guards.
            arguments (Input)
                ~
                before (1, 1) string
                after (1, 1) string
            end
            arguments (Output)
                batch (1, 1) yamada.source.SourcePatchBatch
            end
            old = char(before);
            current = char(after);
            limit = min(numel(old), numel(current));
            first = 1;
            while first <= limit && old(first) == current(first), first = first + 1; end
            lastOld = numel(old);
            lastNew = numel(current);
            while lastOld >= first && lastNew >= first && old(lastOld) == current(lastNew)
                lastOld = lastOld - 1;
                lastNew = lastNew - 1;
            end
            edits = struct("Start", {}, "End", {}, "Text", {});
            if first <= lastOld || first <= lastNew
                edits = struct("Start", first, "End", lastOld, "Text", string(current(first:lastNew)));
            end
            batch = yamada.source.SourcePatchBatch(before, edits);
        end

        function parsed = preflightPropertyChanges(obj, componentId, changes, registry)
            % preflightPropertyChanges Validate generated candidate source before mutating live records.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                componentId (1, 1) string
                changes (1, :) struct
                registry (1, 1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                parsed (1, 1) yamada.model.DocumentModel
            end

            % Use independent records and avoid recording candidate-only user history.
            for change = changes
                try
                    encoded = yamada.source.LiteralEncoder.encode(change.Value);
                    if any(ismissing(encoded), "all")
                        error("yamada:DocumentModel:MissingLiteral", "Missing text cannot be emitted as a literal.");
                    end
                catch exception
                    error("yamada:DocumentModel:UnsafePropertyEdit", "%s", exception.message);
                end
            end
            candidate = obj.structuralCandidate(registry);
            component = candidate.getComponent(componentId);
            for change = changes
                component.setProperty(string(change.Path), change.Value);
            end
            generator = yamada.source.RoundTripGenerator(registry);
            [source, diagnostics, sourcePatches] = generator.generate(candidate);
            if strlength(source) == 0 || yamada.validation.ModelValidator.hasErrors(diagnostics)
                error("yamada:DocumentModel:UnsafePropertyEdit", "%s", ...
                    strjoin(string({diagnostics.Message}), newline));
            end

            % Reparse output without executing the app and check each requested literal.
            [parsed, ~] = candidate.editedSourceCandidate(source, sourcePatches, registry);
            diagnostics = parsed.Diagnostics;
            if yamada.validation.ModelValidator.hasErrors(diagnostics)
                error("yamada:DocumentModel:UnsafePropertyEdit", "%s", ...
                    strjoin(string({diagnostics.Message}), newline));
            end
            reparsed = parsed.getComponentByName(component.Name);
            if isempty(reparsed)
                error("yamada:DocumentModel:UnsafePropertyEdit", "The edited component was not preserved by generation.");
            end
            states = parsed.getEffectivePropertyStates(registry, reparsed.Id);
            for change = changes
                entry = reparsed.getProperty(string(change.Path));
                if isempty(entry) || entry.ValueKind ~= "literal" || ~isequaln(entry.LiteralValue, change.Value)
                    error("yamada:DocumentModel:UnsafePropertyEdit", ...
                        "Generated source does not retain requested property %s.", change.Path);
                end
            end
            obj.assertRequestedStates(states, changes);
            parsed.GeneratedText = source;
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
                    error("yamada:DocumentModel:UnsafePropertyEdit", "Property %s is not supported in this context.", change.Path);
                end
                state = states(stateIndex).Resolution;
                if ~state.IsKnown
                    error("yamada:DocumentModel:UnsafePropertyEdit", "Cannot confirm %s after initialization: %s", change.Path, state.Reason);
                end
                if ~yamada.model.PropertyStateResolver.matchesRequested(state, change.Value)
                    error("yamada:DocumentModel:UnsafePropertyEdit", ...
                        "Initialization changes requested %s to %s; update the constraining settings or choose a surviving value.", ...
                        change.Path, yamada.source.LiteralEncoder.encode(state.EffectiveValue));
                end
                valueIndex = find(arrayfun(@(state) state.Definition.Path == "Value", states), 1);
                if ~isempty(valueIndex) && any(states(valueIndex).Resolution.ReasonCode == ["constraint", "adjustment"]) && ...
                        any(states(valueIndex).Definition.Application.ApplyAfter == string(change.Path))
                    error("yamada:DocumentModel:UnsafePropertyEdit", ...
                        "Cannot confirm Value after changing %s: %s", change.Path, states(valueIndex).Resolution.Reason);
                end
            end
        end

        function id = propertySettingId(~, entry)
            % propertySettingId Read the immutable occurrence targeted by a value edit.
            arguments (Input)
                ~
                entry (1, 1) yamada.model.PropertyEntry
            end
            arguments (Output)
                id (1, 1) double
            end

            id = 0;
            if isfield(entry.Metadata, "SourceSettingId")
                id = entry.Metadata.SourceSettingId;
            elseif isfield(entry.Metadata, "PendingSettingId")
                id = entry.Metadata.PendingSettingId;
            end
        end

        function assertPropertySettingTarget(obj, component, change, forward)
            % assertPropertySettingTarget Refuse history replay against a different occurrence.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                component (1, 1) yamada.model.ComponentRecord
                change (1, 1) struct
                forward (1, 1) logical
            end

            if obj.SourcePublication, return, end
            if ~isfield(change, "TargetSettingId") || change.TargetSettingId == 0, return, end
            entry = component.getProperty(string(change.Path));
            if forward && ~change.HadOldValue && isempty(entry), return, end
            if isempty(entry) || obj.propertySettingId(entry) ~= change.TargetSettingId
                error("yamada:DocumentModel:StalePropertySetting", ...
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
            if ~yamada.model.SourceOwnership.hasSource(component)
                return
            end
            pending = struct("Kind", "delete-component", "Record", yamada.model.SourceOwnership.snapshot(component));
            obj.PendingEdits{end + 1} = pending;
            index = numel(obj.PendingEdits);
        end

        function recordHistory(obj, edit, preparedSource, parsedCandidate, preparedEdits)
            % recordHistory Publish an already prepared source candidate and retain only primary reversible edits.
            arguments (Input)
                obj (1, 1) yamada.model.DocumentModel
                edit (1, 1) struct
                preparedSource (1, 1) string = ""
                parsedCandidate yamada.model.DocumentModel = yamada.model.DocumentModel.empty
                preparedEdits struct = struct([])
            end
            if ~obj.SourcePublication && ~isempty(obj.SourceRegistry)
                obj.ensureCurrentSource(obj.SourceRegistry);
                before = obj.CurrentSource;
                try
                    if strlength(preparedSource) > 0
                        text = preparedSource; diagnostics = yamada.model.Diagnostic.empty;
                    elseif isfield(edit, "SourceCandidateText") && strlength(edit.SourceCandidateText) > 0
                        text = edit.SourceCandidateText;
                        diagnostics = yamada.model.Diagnostic.empty;
                    else
                        [text, diagnostics, preparedEdits] = yamada.source.RoundTripGenerator(obj.SourceRegistry).generate(obj);
                    end
                if yamada.validation.ModelValidator.hasErrors(diagnostics)
                    error("yamada:DocumentModel:UnsafeSourceCommit", "%s", strjoin(string({diagnostics.Message}), newline));
                end
                if isempty(preparedEdits), batch = obj.sourceDifference(before.Text, text);
                else, batch = yamada.source.SourcePatchBatch(before.Text, preparedEdits); end
                assert(batch.AfterText == text);
                if isempty(parsedCandidate)
                    [parsedCandidate, state] = obj.editedSourceCandidate(text, batch.Edits, obj.SourceRegistry);
                else
                    state = before.withBatch(batch, "", parsedCandidate.sourceAnalysis());
                end
                obj.publishParsedSource(state, obj.SourceRegistry, parsedCandidate, true);
                catch exception
                    obj.SourcePublication = true;
                    cleanup = onCleanup(@() obj.endSourcePublication());
                    obj.applyHistory(edit, false);
                    rethrow(exception)
                end
                edit.SourceForward = batch.Edits;
                edit.SourceInverse = batch.InverseEdits;
                edit.SourceBeforeId = before.StateId;
                edit.SourceAfterId = obj.CurrentSource.StateId;
            end
            if isfield(edit, "SourceCandidateText"), edit = rmfield(edit, "SourceCandidateText"); end
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
                obj (1, 1) yamada.model.DocumentModel
                id (1, 1) string
                rootState (1, 1) struct
                parentStates struct
                components yamada.model.ComponentRecord
                pending cell
            end

            obj.Components = components;
            root = obj.getComponent(id);
            root.restoreProperties(rootState.Properties);
            % Source-backed replay derives current bindings from the primary patch.
            if ~obj.SourcePublication && isfield(rootState, "Settings"), root.restoreSettings(rootState.Settings); end
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
                if ~isstruct(pending) || ~isfield(pending, "Kind") || pending.Kind ~= "delete-component", continue, end
                id = "";
                if isfield(pending, "Record"), id = pending.Record.Id;
                elseif isfield(pending, "Component"), id = pending.Component.Id; end
                if id == component.Id
                    obj.PendingEdits(index) = [];
                    return
                end
            end
        end

        function restoreBatchValue(~, component, change)
            % restoreBatchValue Restore one prior batch value or its absent-property state.
            arguments (Input)
                ~
                component (1, 1) yamada.model.ComponentRecord
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
                grid (1, 1) yamada.model.ComponentRecord
                component (1, 1) yamada.model.ComponentRecord
                path (1, 1) string
                value
            end

            if component == grid
                if ~any(path == ["RowHeight", "ColumnWidth"])
                    error("yamada:DocumentModel:InvalidGridLayoutEdit", ...
                        "Grid layout edits may change only RowHeight or ColumnWidth on the grid.");
                end
                message = yamada.model.GridTrackList.validate(value);
                if strlength(message) > 0
                    error("yamada:DocumentModel:InvalidGridLayoutEdit", "%s", message);
                end
                return
            end
            if component.ParentId ~= grid.Id || ...
                    ~any(path == ["Layout.Row", "Layout.Column"])
                error("yamada:DocumentModel:InvalidGridLayoutEdit", ...
                    "Grid layout edits may change only direct-child Layout.Row or Layout.Column values.");
            end
            if ~isnumeric(value) || ~isvector(value) || isempty(value) || ...
                    numel(value) > 2 || any(~isfinite(value)) || any(value < 1) || ...
                    any(value ~= floor(value))
                error("yamada:DocumentModel:InvalidGridLayoutEdit", ...
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
            for item = obj.History
                edit = item{1};
                if edit.Kind == "rename", reserved = [reserved edit.OldName edit.NewName]; end %#ok<AGROW>
            end
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
                parent (1, 1) yamada.model.ComponentRecord
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
