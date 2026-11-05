classdef EvaluationContext < handle
    % EvaluationContext Cache independent results for one exact document input state.
    %   Publicly mutable records are compared by value, not history position.
    %   Parsed configuration handles remain private; public document retrieval copies them.
    %   Internal state reads return immutable values without copying the document.
    %
    %   Example:
    %       context = document.evaluationContext(registry);
    properties (Access = private)
        InputClock yamada.model.InputChangeClock
        InputRevision uint64
        Key struct
        Registry yamada.model.ComponentRegistry
        RegistryRevision uint64
        Values containers.Map
        Plans containers.Map
        Cacheable logical = false
        ReadDepth double = 0
        TransitionToken struct = struct()
        TransitionOwner string = ""
        TransitionPaths string = strings(1, 0)
    end

    methods
        function inheritStates(obj, previous)
            % inheritStates Reuse only resolver values whose complete dependency scope is unchanged.
            arguments (Input)
                obj (1, 1) yamada.model.EvaluationContext
                previous (1, 1) yamada.model.EvaluationContext
            end
            if ~obj.Cacheable || ~previous.Cacheable || obj.Registry ~= previous.Registry || ...
                    obj.RegistryRevision ~= previous.RegistryRevision || ...
                    ~isequaln(rmfield(obj.Key, "Components"), rmfield(previous.Key, "Components"))
                return
            end
            before = previous.Key.Components;
            after = obj.Key.Components;
            if isempty(before) || numel(before) ~= numel(after), return, end
            % Structural changes may alter event ordering and source-name resolution.
            fields = ["Id", "Name", "Factory", "DeclaredType", "Origin", "ParentId", "Children"];
            for field = fields
                if ~isequaln({before.(field)}, {after.(field)}), return, end
            end
            names = string(keys(previous.Values));
            names = names(startsWith(names, "states:"));
            if isempty(names), return, end

            % Compare each component once instead of repeating overlapping scope snapshots.
            changed = false(1, numel(after));
            for index = 1:numel(after)
                changed(index) = ~isequaln(before(index), after(index));
            end
            % Nested coupled descendants share exactly the same complete dependency scope.
            groups = yamada.model.EvaluationContext.scopeGroups(after);
            componentIds = string({after.Id});
            checked = false(1, numel(after));
            retained = false(1, numel(after));
            for name = names
                id = extractAfter(name, "states:");
                index = find(componentIds == id, 1);
                if isempty(index), continue, end
                group = groups(index);
                if group > 0 && checked(group)
                    reuse = retained(group);
                else
                    indices = yamada.model.EvaluationContext.stateScope(after, id);
                    reuse = ~isempty(indices) && ~any(changed(indices));
                    if group > 0
                        checked(group) = true;
                        retained(group) = reuse;
                    end
                end
                if reuse, obj.Values(char(name)) = previous.Values(char(name)); end
            end
        end

        function [token, tracked] = revisionToken(obj)
            % revisionToken Return acyclic input and catalog identities without retaining model records.
            arguments (Input)
                obj (1, 1) yamada.model.EvaluationContext
            end
            arguments (Output)
                token (1, 1) struct
                tracked (1, 1) logical
            end
            token = struct("Clock", obj.InputClock, "Revision", obj.InputRevision, ...
                "Registry", obj.Registry, "RegistryRevision", obj.RegistryRevision);
            tracked = obj.Cacheable && obj.InputClock.IsTracked && ...
                obj.InputClock.Revision == obj.InputRevision && obj.Registry.Revision == obj.RegistryRevision;
        end

        function [inputs, safe] = inputs(obj)
            % inputs Return independent semantic inputs for conservative view invalidation.
            arguments (Input)
                obj (1, 1) yamada.model.EvaluationContext
            end
            arguments (Output)
                inputs (1, 1) struct
                safe (1, 1) logical
            end
            safe = obj.Cacheable;
            inputs = struct();
            if safe, inputs = obj.Key; end
        end

        function result = isLiteralTransition(obj, token, request)
            % isLiteralTransition Certify a view's exact previous version and the locally proven changed paths.
            arguments (Input)
                obj (1, 1) yamada.model.EvaluationContext
                token (1, 1) struct
                request (1, 1) yamada.ui.RefreshRequest
            end
            arguments (Output)
                result (1, 1) logical
            end
            [~, tracked] = obj.revisionToken();
            result = tracked && ~isempty(fieldnames(obj.TransitionToken)) && ...
                yamada.model.EvaluationContext.sameToken(obj.TransitionToken, token) && request.Kind == "properties" && ...
                isscalar(request.ComponentIds) && isscalar(obj.TransitionOwner) && request.ComponentIds == obj.TransitionOwner && ...
                all(ismember(obj.TransitionPaths, request.pathsFor(obj.TransitionOwner)));
        end

        function result = isReading(obj, registry)
            % isReading Identify nested pure evaluation in the same registry version.
            arguments (Input)
                obj (1, 1) yamada.model.EvaluationContext
                registry (1, 1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = obj.Cacheable && obj.ReadDepth > 0 && ...
                obj.Registry == registry && obj.RegistryRevision == registry.Revision && ...
                obj.InputClock.IsTracked && obj.InputClock.Revision == obj.InputRevision;
        end

        function cleanup = readScope(obj)
            % readScope Amortize input capture within a synchronous read-only computation.
            %   Do not hold this scope across native UI dispatch or model mutations.
            arguments (Input)
                obj (1, 1) yamada.model.EvaluationContext
            end
            arguments (Output)
                cleanup (1, 1) onCleanup
            end
            obj.ReadDepth = obj.ReadDepth + 1;
            cleanup = onCleanup(@() obj.finishRead());
        end

        function obj = EvaluationContext(document, registry)
            % EvaluationContext Capture semantic inputs without retaining live component records.
            arguments (Input)
                document yamada.model.DocumentModel = yamada.model.DocumentModel.empty
                registry yamada.model.ComponentRegistry = yamada.model.ComponentRegistry.empty
            end
            obj.Values = containers.Map("KeyType", "char", "ValueType", "any");
            obj.Plans = containers.Map("KeyType", "char", "ValueType", "any");
            if isempty(document), return, end
            [obj.Key, obj.Cacheable] = yamada.model.EvaluationContext.capture(document);
            [obj.InputClock, obj.InputRevision] = document.inputStamp();
            obj.Registry = registry;
            obj.RegistryRevision = registry.Revision;
        end

        function result = matches(obj, document, registry)
            % matches Reject stale results after direct edits, history branches, or registry changes.
            arguments (Input)
                obj (1, 1) yamada.model.EvaluationContext
                document (1, 1) yamada.model.DocumentModel
                registry (1, 1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = obj.Cacheable && obj.Registry == registry && obj.RegistryRevision == registry.Revision;
            if result
                [clock, revision, tracked] = document.inputStamp();
                if tracked && obj.InputClock == clock
                    result = obj.InputRevision == revision;
                else
                    % Shared ownership and live inputs retain exact comparison.
                    [key, cacheable] = yamada.model.EvaluationContext.capture(document);
                    result = cacheable && isequaln(obj.Key, key);
                end
            end
        end

        function [value, found] = lookup(obj, name)
            % lookup Return cached value-only results, never shared mutable model handles.
            arguments (Input)
                obj (1, 1) yamada.model.EvaluationContext
                name (1, 1) string
            end
            arguments (Output)
                value
                found (1, 1) logical
            end
            found = obj.Cacheable && isKey(obj.Values, char(name));
            value = [];
            if found, value = obj.Values(char(name)); end
        end

        function remember(obj, name, value)
            % remember Retain independent evaluation values only when their classes are safe.
            arguments (Input)
                obj (1, 1) yamada.model.EvaluationContext
                name (1, 1) string
                value
            end
            if ~obj.Cacheable, return, end
            [independent, safe] = yamada.model.EvaluationContext.freeze(value, false, obj.Registry);
            if safe
                obj.Values(char(name)) = independent;
            end
        end

        function [plan, found] = configuration(obj, name, componentName)
            % configuration Materialize a private parsed plan into an isolated caller-owned document.
            arguments (Input)
                obj (1, 1) yamada.model.EvaluationContext
                name (1, 1) string
                componentName (1, 1) string
            end
            arguments (Output)
                plan (1, 1) struct
                found (1, 1) logical
            end
            found = obj.Cacheable && isKey(obj.Plans, char(name));
            plan = struct();
            if ~found, return, end
            saved = obj.Plans(char(name));
            document = obj.configurationDocument(saved, true);
            component = document.getComponentByName(componentName);
            found = ~isempty(component);
            if found, plan = struct("Document", document, "Component", component); end
        end

        function [states, effectIds, found] = configurationStates(obj, name, original, definitions, document)
            % configurationStates Read value states from a private plan without exposing its mutable records.
            arguments (Input)
                obj (1, 1) yamada.model.EvaluationContext
                name (1, 1) string
                original (1, 1) yamada.model.ComponentRecord
                definitions yamada.model.PropertyDefinition
                document (1, 1) yamada.model.DocumentModel
            end
            arguments (Output)
                states yamada.model.PropertyState
                effectIds string
                found (1, 1) logical
            end
            states = yamada.model.PropertyState.empty;
            effectIds = strings(1, 0);
            owned = document.getComponent(original.Id);
            found = obj.matches(document, obj.Registry) && ~isempty(owned) && owned == original && ...
                isKey(obj.Plans, char(name));
            if ~found, return, end
            saved = obj.configurationDocument(obj.Plans(char(name)), false);
            component = saved.getComponentByName(original.Name);
            found = ~isempty(component);
            if ~found, return, end

            % Resolve synchronously and map source identities before returning immutable values.
            states = yamada.model.PropertyStateResolver.resolve(component, definitions, saved, obj.Registry);
            effectIds = strings(size(states));
            for index = 1:numel(states)
                effectIds(index) = yamada.model.PropertyStateResolver.originalEffectId(original, component, ...
                    states(index).EffectKey, document, saved);
            end
        end

        function [result, found] = configurationGridState(obj, name, grid, document, owner)
            % configurationGridState Project mapped grid values without exposing cached document handles.
            arguments (Input)
                obj (1, 1) yamada.model.EvaluationContext
                name (1, 1) string
                grid (1, 1) yamada.model.ComponentRecord
                document (1, 1) yamada.model.DocumentModel
                owner (1, 1) yamada.model.ComponentRecord
            end
            arguments (Output)
                result (1, 1) struct
                found (1, 1) logical
            end
            result = struct();
            owned = document.getComponent(grid.Id);
            ownedOwner = document.getComponent(owner.Id);
            found = obj.matches(document, obj.Registry) && grid.Factory == "uigridlayout" && ...
                ~isempty(owned) && owned == grid && ~isempty(ownedOwner) && ownedOwner == owner && ...
                isKey(obj.Plans, char(name));
            if ~found, return, end

            % Keep the version-checked private source inside a synchronous value projection.
            saved = obj.configurationDocument(obj.Plans(char(name)), false);
            found = ~isempty(saved.getComponentByName(owner.Name));
            if ~found, return, end
            result = yamada.model.GridLayoutStatePolicy.projectConfiguration(grid, document, saved, obj.Registry);
        end

        function rememberConfiguration(obj, name, document)
            % rememberConfiguration Hide an independent configuration from subsequent caller mutations.
            arguments (Input)
                obj (1, 1) yamada.model.EvaluationContext
                name (1, 1) string
                document (1, 1) yamada.model.DocumentModel
            end
            if obj.Cacheable
                obj.Plans(char(name)) = document.structuralCandidate();
            end
        end
    end

    methods (Static, Access = ?yamada.model.DocumentModel)
        function obj = fromValidated(document, registry)
            % fromValidated Snapshot values certified by a semantic proof or a model-owned callback patch projection.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                registry (1, 1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                obj (1, 1) yamada.model.EvaluationContext
            end
            [clock, revision, tracked] = document.inputStamp();
            % DocumentModel calls this after a semantic join or an owned callback-only source projection.
            safe = tracked && yamada.model.InputChangeClock.isValueData(document.Metadata) && ...
                yamada.model.InputChangeClock.isValueData(document.UnknownRegions) && isempty(document.PendingEdits) && ...
                isempty(document.CallbackEdits) && isempty(document.RenameEdits);
            components = struct([]);
            for component = document.Components
                safe = safe && yamada.model.InputChangeClock.isValueData(component.Metadata);
                properties = struct([]);
                for entry = component.Properties
                    safe = safe && yamada.model.InputChangeClock.isValueData(entry.Metadata);
                    value = rmfield(entry.toStruct(), "Diagnostics");
                    if isempty(properties), properties = value; else, properties(end + 1) = value; end %#ok<AGROW>
                end
                record = struct("Id", component.Id, "Name", component.Name, ...
                    "Factory", component.Factory, "DeclaredType", component.DeclaredType, ...
                    "Origin", component.Origin, "ParentId", component.ParentId, "Children", component.Children, ...
                    "CreationArguments", {component.CreationArguments}, "IsEditable", component.IsEditable, ...
                    "Metadata", component.Metadata, "SourceSpans", component.SourceSpans, "Settings", component.settingSnapshot());
                record.Properties = properties;
                if isempty(components), components = record; else, components(end + 1) = record; end %#ok<AGROW>
            end
            if ~safe, obj = yamada.model.EvaluationContext(document, registry); return, end
            obj = yamada.model.EvaluationContext();
            obj.Key = struct("ClassName", document.ClassName, "FilePath", document.FilePath, ...
                "OriginalText", document.CurrentText, "RootComponentId", document.RootComponentId, ...
                "Encoding", document.Encoding, "LineEnding", document.LineEnding, ...
                "Metadata", document.Metadata, "UnknownRegions", document.UnknownRegions, ...
                "PendingEdits", {document.PendingEdits}, "CallbackEdits", document.CallbackEdits, "RenameEdits", document.RenameEdits);
            obj.Key.Components = components; obj.Cacheable = true;
            obj.InputClock = clock; obj.InputRevision = revision; obj.Registry = registry; obj.RegistryRevision = registry.Revision;
        end

        function obj = projectSource(document, registry, previous, updates, ownerId, paths, token)
            % projectSource Publish a value-only key from a document-certified source transaction without whole-tree freezing.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                registry (1, 1) yamada.model.ComponentRegistry
                previous (1, 1) yamada.model.EvaluationContext
                updates yamada.model.SourceLocationUpdate
                ownerId (1, :) string
                paths (1, :) string
                token (1, 1) struct
            end
            arguments (Output)
                obj (1, 1) yamada.model.EvaluationContext
            end
            [oldToken, ~] = previous.revisionToken();
            [clock, revision, tracked] = document.inputStamp();
            reusable = previous.Cacheable && tracked && ~isempty(fieldnames(token)) && ...
                yamada.model.EvaluationContext.sameToken(oldToken, token) && clock == previous.InputClock && ...
                registry == previous.Registry && registry.Revision == previous.RegistryRevision;
            if ~reusable
                obj = yamada.model.EvaluationContext(document, registry); return
            end
            key = previous.Key;
            assert(numel(key.Components) == numel(document.Components));
            ids = string({key.Components.Id});
            for update = updates
                index = find(ids == update.ComponentId, 1);
                assert(~isempty(index));
                if ~ismember(update.ComponentId, ownerId)
                    key.Components(index) = update.projectInputs(key.Components(index));
                end
            end
            % Only the changed owner can introduce new values, types, or source occurrences.
            for id = ownerId
                [owner, safe] = yamada.model.EvaluationContext.freeze(document.getComponent(id), true, registry);
                if ~safe
                    obj = yamada.model.EvaluationContext(document, registry); return
                end
                key.Components(ids == id) = owner;
            end
            key.OriginalText = document.CurrentText;
            key.Metadata.SourceSnapshotText = document.Metadata.SourceSnapshotText;
            key.Metadata.InitializationContext = document.Metadata.InitializationContext;
            key.UnknownRegions = document.UnknownRegions;
            key.PendingEdits = document.PendingEdits;
            key.CallbackEdits = document.CallbackEdits;
            key.RenameEdits = document.RenameEdits;
            obj = yamada.model.EvaluationContext();
            obj.Key = key;
            obj.Cacheable = true;
            obj.InputClock = clock;
            obj.InputRevision = revision;
            obj.Registry = registry;
            obj.RegistryRevision = registry.Revision;
            obj.TransitionToken = token;
            obj.TransitionOwner = ownerId;
            obj.TransitionPaths = paths;
        end
    end

    methods (Access = ?yamada.model.DocumentModel)
        function plan = editScope(obj, document, changed)
            % editScope Derive checked owners and invalidated dependencies from a known edit footprint.
            arguments (Input)
                obj (1, 1) yamada.model.EvaluationContext
                document (1, 1) yamada.model.DocumentModel
                changed (1, :) string
            end
            arguments (Output)
                plan (1, 1) struct
            end
            after = document.Components; ids = string({after.Id});
            before = obj.Key.Components; oldIds = string({before.Id});
            topologyRecords = yamada.model.EvaluationContext.records(document);
            added = setdiff(ids, oldIds); removed = setdiff(oldIds, ids);
            checked = intersect(unique([changed added]), ids, "stable"); affected = checked;
            % Topology affects only the participating containers and their modeled child policies.
            for index = 1:numel(after)
                old = find(oldIds == ids(index), 1); member = after(index);
                topology = isempty(old) || before(old).ParentId ~= member.ParentId || ...
                    ~isequaln(before(old).Children, member.Children);
                if topology
                    affected(end + 1) = member.Id; %#ok<AGROW>
                    if any(member.Factory == ["uigridlayout", "uibuttongroup", "uitabgroup"])
                        checked(end + 1) = member.Id; %#ok<AGROW>
                        affected = union(affected, yamada.model.EvaluationContext.descendants(after, member.Id), "stable");
                    end
                end
                if ~any(checked == member.Id), continue, end
                affected = union(affected, ids(yamada.model.EvaluationContext.stateScope(topologyRecords, member.Id)), "stable");
                affected = union(affected, yamada.model.EvaluationContext.descendants(after, member.Id), "stable");
                parent = member.ParentId; visited = strings(1, 0);
                while parent ~= ""
                    assert(~any(visited == parent), "yamada:DocumentModel:InvalidParent", "An edited parent chain must be acyclic.");
                    visited(end + 1) = parent; %#ok<AGROW>
                    owner = document.getComponent(parent); if isempty(owner), break, end
                    if any(owner.Factory == ["uigridlayout", "uibuttongroup", "uitabgroup"])
                        checked(end + 1) = owner.Id; %#ok<AGROW>
                    end
                    parent = owner.ParentId;
                end
            end
            for field = ["HasUnresolvedLifecycleEffects", "HasUnresolvedExecutableEffects", "HasUnrecognizedSetter"]
                old = isfield(obj.Key.Metadata, field) && obj.Key.Metadata.(field);
                current = isfield(document.Metadata, field) && document.Metadata.(field);
                if old ~= current, checked = ids; affected = ids; break, end
            end
            if obj.RegistryRevision ~= obj.Registry.Revision, checked = ids; affected = ids; end
            plan = struct("Checked", unique(checked, "stable"), "Invalidated", unique([affected removed], "stable"));
        end

        function inheritPlannedStates(obj, previous, affected, batch)
            % inheritPlannedStates Rebase independent cached states outside a certified edit's affected scope.
            arguments (Input)
                obj (1, 1) yamada.model.EvaluationContext
                previous (1, 1) yamada.model.EvaluationContext
                affected (1, :) string
                batch (1, 1) yamada.source.SourcePatchBatch
            end
            if ~obj.Cacheable || ~previous.Cacheable || obj.Registry ~= previous.Registry || ...
                    obj.RegistryRevision ~= previous.RegistryRevision, return, end
            values = previous.stateValues();
            for name = string(keys(obj.Values))
                if startsWith(name, "states:"), remove(obj.Values, char(name)); end
            end
            ids = string({obj.Key.Components.Id});
            for owner = values
                id = owner.ComponentId;
                if ~any(ids == id) || any(affected == id), continue, end
                value = owner.Resolved;
                value.Diagnostics = yamada.model.SourceLocationUpdate.relocateDiagnostics(value.Diagnostics, batch);
                obj.Values(char("states:" + id)) = value;
            end
        end

        function values = stateValues(obj)
            % stateValues Export already independent computed owner states without retaining a context handle.
            arguments (Input)
                obj (1, 1) yamada.model.EvaluationContext
            end
            arguments (Output)
                values (1, :) struct
            end
            values = struct("ComponentId", {}, "Resolved", {});
            for name = string(keys(obj.Values))
                if startsWith(name, "states:")
                    values(end + 1) = struct("ComponentId", extractAfter(name, "states:"), "Resolved", obj.Values(char(name))); %#ok<AGROW>
                end
            end
        end

        function inheritSourceStates(obj, previous, changedIds, batch)
            % inheritSourceStates Retain only scopes independent of owners changed by one certified literal source patch.
            arguments (Input)
                obj (1, 1) yamada.model.EvaluationContext
                previous (1, 1) yamada.model.EvaluationContext
                changedIds (1, :) string
                batch (1, 1) yamada.source.SourcePatchBatch
            end
            if ~obj.Cacheable || ~previous.Cacheable || obj.Registry ~= previous.Registry || ...
                    obj.RegistryRevision ~= previous.RegistryRevision, return, end
            before = previous.Key.Components; after = obj.Key.Components;
            if numel(before) ~= numel(after), return, end
            for field = ["Id", "Name", "Factory", "DeclaredType", "Origin", "ParentId", "Children"]
                if ~isequaln({before.(field)}, {after.(field)}), return, end
            end
            groups = yamada.model.EvaluationContext.scopeGroups(after);
            ids = string({after.Id}); checked = false(size(groups)); reusable = checked;
            for name = string(keys(previous.Values))
                if ~startsWith(name, "states:"), continue, end
                index = find(ids == extractAfter(name, "states:"), 1);
                if isempty(index) || groups(index) == 0, continue, end
                group = groups(index);
                if ~checked(group)
                    scope = yamada.model.EvaluationContext.stateScope(after, ids(index));
                    reusable(group) = ~any(ismember(ids(scope), changedIds)); checked(group) = true;
                end
                if ~reusable(group), continue, end
                value = previous.Values(char(name));
                value.Diagnostics = yamada.model.SourceLocationUpdate.relocateDiagnostics(value.Diagnostics, batch);
                obj.Values(char(name)) = value;
            end
        end

        function rememberValidatedStates(obj, id, resolved)
            % rememberValidatedStates Adopt already independent values after DocumentValidationProof verifies their semantic join.
            arguments (Input)
                obj (1, 1) yamada.model.EvaluationContext
                id (1, 1) string
                resolved (1, 1) struct
            end
            if obj.Cacheable, obj.Values(char("states:" + id)) = resolved; end
        end

        function rememberOwnedConfiguration(obj, name, document)
            % rememberOwnedConfiguration Retain a model-owned checkpoint with an independent value snapshot.
            arguments (Input)
                obj (1, 1) yamada.model.EvaluationContext
                name (1, 1) string
                document (1, 1) yamada.model.DocumentModel
            end
            if ~obj.Cacheable, return, end
            try
                snapshot = document.configurationSnapshot();
            catch exception
                if string(exception.identifier) ~= "yamada:DocumentModel:UnsafeConfigurationSnapshot"
                    rethrow(exception)
                end
                obj.rememberConfiguration(name, document);
                return
            end
            [clock, revision, tracked] = document.inputStamp();
            obj.Plans(char(name)) = struct("Document", document, "Snapshot", snapshot, ...
                "Clock", clock, "Revision", revision, "Tracked", tracked);
        end

        function inheritLiteralStates(obj, previous, componentId, batch, preserveDocumentStates)
            % inheritLiteralStates Retain other owners' immutable states after a document-proven local semantic change.
            arguments (Input)
                obj (1, 1) yamada.model.EvaluationContext
                previous (1, 1) yamada.model.EvaluationContext
                componentId (1, 1) string
                batch (1, 1) yamada.source.SourcePatchBatch
                preserveDocumentStates (1, 1) logical = false
            end
            if ~obj.Cacheable || ~previous.Cacheable || obj.Registry ~= previous.Registry || ...
                    obj.RegistryRevision ~= previous.RegistryRevision
                return
            end
            before = previous.Key.Components;
            after = obj.Key.Components;
            if numel(before) ~= numel(after), return, end
            for field = ["Id", "Name", "Factory", "DeclaredType", "Origin", "ParentId", "Children"]
                if ~isequaln({before.(field)}, {after.(field)}), return, end
            end
            for name = string(keys(previous.Values))
                state = startsWith(name, "states:") && name ~= "states:" + componentId;
                auxiliary = preserveDocumentStates && (startsWith(name, "grid-configuration:") || ...
                    startsWith(name, "grid-unresolved-effect:"));
                if ~state && ~auxiliary, continue, end
                value = previous.Values(char(name));
                if state, value.Diagnostics = yamada.model.SourceLocationUpdate.relocateDiagnostics(value.Diagnostics, batch); end
                obj.Values(char(name)) = value;
            end
        end

        function inheritEligibility(obj, previous)
            % inheritEligibility Carry immutable condition answers after a document-proven local literal edit.
            arguments (Input)
                obj (1, 1) yamada.model.EvaluationContext
                previous (1, 1) yamada.model.EvaluationContext
            end
            if ~obj.Cacheable || ~previous.Cacheable || obj.Registry ~= previous.Registry || ...
                    obj.RegistryRevision ~= previous.RegistryRevision
                return
            end
            % Reparent answers retain their measured-rectangle guard; no native geometry is copied.
            for name = string(keys(previous.Values))
                if startsWith(name, "eligibility:")
                    obj.Values(char(name)) = previous.Values(char(name));
                end
            end
        end
    end

    methods (Access = private)
        function document = configurationDocument(~, saved, independent)
            % configurationDocument Return an isolated copy or a version-checked private read source.
            arguments (Input)
                ~
                saved
                independent (1, 1) logical
            end
            arguments (Output)
                document (1, 1) yamada.model.DocumentModel
            end
            if ~isstruct(saved)
                document = saved;
                if independent, document = saved.structuralCandidate(); end
                return
            end
            if ~independent
                [clock, revision, tracked] = saved.Document.inputStamp();
                if saved.Tracked && tracked && saved.Clock == clock && saved.Revision == revision
                    document = saved.Document;
                    return
                end
            end
            % A later edit or rollback may mutate the checkpoint, but never its saved value snapshot.
            document = yamada.model.DocumentModel.fromConfigurationSnapshot(saved.Snapshot);
        end

        function finishRead(obj)
            % finishRead Release a synchronous evaluation scope, including on errors.
            arguments (Input)
                obj (1, 1) yamada.model.EvaluationContext
            end
            obj.ReadDepth = max(0, obj.ReadDepth - 1);
        end
    end

    methods (Static, Access = private)
        function result = sameToken(first, second)
            % sameToken Require owner identity as well as input and catalog revision numbers.
            arguments (Input)
                first (1, 1) struct
                second (1, 1) struct
            end
            arguments (Output)
                result (1, 1) logical
            end
            fields = ["Clock", "Revision", "Registry", "RegistryRevision"];
            result = all(isfield(first, fields)) && all(isfield(second, fields)) && ...
                isa(first.Clock, "yamada.model.InputChangeClock") && isscalar(first.Clock) && ...
                isa(second.Clock, "yamada.model.InputChangeClock") && isscalar(second.Clock) && ...
                isa(first.Registry, "yamada.model.ComponentRegistry") && isscalar(first.Registry) && ...
                isa(second.Registry, "yamada.model.ComponentRegistry") && isscalar(second.Registry) && ...
                isequal(first.Revision, second.Revision) && isequal(first.RegistryRevision, second.RegistryRevision) && ...
                first.Clock == second.Clock && first.Registry == second.Registry;
        end

        function [key, safe] = capture(document)
            % capture Snapshot all source and model inputs while excluding derived output diagnostics.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
            end
            arguments (Output)
                key (1, 1) struct
                safe (1, 1) logical
            end
            [components, ownedSafe] = yamada.model.EvaluationContext.freeze(document.Components, true);
            key = struct("ClassName", document.ClassName, "FilePath", document.FilePath, ...
                "OriginalText", document.CurrentText, "RootComponentId", document.RootComponentId, ...
                "Encoding", document.Encoding, "LineEnding", document.LineEnding, ...
                "Metadata", document.Metadata, "UnknownRegions", document.UnknownRegions, ...
                "PendingEdits", {document.PendingEdits}, "CallbackEdits", document.CallbackEdits, ...
                "RenameEdits", document.RenameEdits);
            [key, safe] = yamada.model.EvaluationContext.freeze(key);
            key.Components = components;
            safe = safe && ownedSafe;
        end

        function groups = scopeGroups(components)
            % scopeGroups Group identical coupled scopes without changing their dependency membership.
            arguments (Input)
                components struct
            end
            arguments (Output)
                groups (1, :) double
            end
            count = numel(components);
            groups = 1:count;
            ids = string({components.Id});
            if numel(unique(ids)) ~= count
                groups(:) = 0;
                return
            end
            coupled = ismember(string({components.Factory}), ["uigridlayout", "uibuttongroup"]);
            if ~any(coupled), return, end
            [~, parents] = ismember(string({components.ParentId}), ids);
            for index = 1:count
                current = index;
                outer = 0;
                visited = false(1, count);
                while current > 0
                    if visited(current)
                        groups(index) = 0;
                        break
                    end
                    visited(current) = true;
                    if coupled(current), outer = current; end
                    current = parents(current);
                end
                % Cycles and duplicate identities retain the established conservative traversal.
                if groups(index) > 0 && outer > 0, groups(index) = outer; end
            end
        end

        function records = records(document)
            % records Read only topology needed to bound a planned edit's dependencies.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
            end
            arguments (Output)
                records (1, :) struct
            end
            members = document.Components;
            records = struct("Id", {members.Id}, "ParentId", {members.ParentId}, "Factory", {members.Factory});
        end

        function ids = descendants(members, id)
            % descendants Follow the maintained child index without interpreting source or property values.
            arguments (Input)
                members yamada.model.ComponentRecord
                id (1, 1) string
            end
            arguments (Output)
                ids (1, :) string
            end
            ids = id; names = string({members.Id}); parents = string({members.ParentId});
            while true
                next = union(ids, names(ismember(parents, ids)), "stable");
                if numel(next) == numel(ids), break, end
                ids = next;
            end
        end

        function indices = stateScope(components, id)
            % stateScope Include ancestors and complete coupled grid or button-group subtrees.
            arguments (Input)
                components struct
                id (1, 1) string
            end
            arguments (Output)
                indices (1, :) double
            end
            indices = zeros(1, 0);
            if isempty(components), return, end
            ids = string({components.Id});
            parents = string({components.ParentId});
            current = find(ids == id, 1);
            ancestors = zeros(1, 0);
            while ~isempty(current)
                if any(ancestors == current)
                    indices = 1:numel(components); return
                end
                ancestors(end + 1) = current; %#ok<AGROW>
                current = find(ids == parents(current), 1);
            end
            indices = ancestors;
            for ancestor = ancestors
                if ~any(components(ancestor).Factory == ["uigridlayout", "uibuttongroup"]), continue, end
                subtree = ancestor;
                while true
                    expanded = union(subtree, find(ismember(parents, ids(subtree))));
                    if numel(expanded) == numel(subtree), break, end
                    subtree = expanded;
                end
                indices = union(indices, subtree);
            end
            indices = reshape(sort(indices), 1, []);
        end

        function [value, safe] = freeze(value, owned, registry)
            % freeze Convert known records by value and bypass caching for unrecognized live data.
            arguments (Input)
                value
                owned (1, 1) logical = false
                registry yamada.model.ComponentRegistry = yamada.model.ComponentRegistry.empty
            end
            arguments (Output)
                value
                safe (1, 1) logical
            end
            safe = true;
            if isa(value, "yamada.model.ComponentRecord")
                if ~owned, value = []; safe = false; return, end
                records = struct([]);
                for index = 1:numel(value)
                    component = value(index);
                    [properties, independent] = yamada.model.EvaluationContext.freeze(component.Properties, true, registry);
                    safe = safe && independent;
                    record = struct("Id", component.Id, "Name", component.Name, ...
                        "Factory", component.Factory, "DeclaredType", component.DeclaredType, ...
                        "Origin", component.Origin, "ParentId", component.ParentId, ...
                        "Children", component.Children, "CreationArguments", {component.CreationArguments}, ...
                        "IsEditable", component.IsEditable, "Metadata", component.Metadata, ...
                        "SourceSpans", component.SourceSpans, ...
                        "Settings", component.settingSnapshot());
                    [record, valid] = yamada.model.EvaluationContext.freeze(record, false, registry);
                    safe = safe && valid;
                    record.Properties = properties;
                    if isempty(records), records = record; else, records(end + 1) = record; end %#ok<AGROW>
                end
                value = records;
            elseif isa(value, "yamada.model.PropertyEntry")
                if ~owned, value = []; safe = false; return, end
                records = struct([]);
                for index = 1:numel(value)
                    record = value(index).toStruct();
                    record = rmfield(record, "Diagnostics");
                    if isempty(records), records = record; else, records(end + 1) = record; end %#ok<AGROW>
                end
                [value, safe] = yamada.model.EvaluationContext.freeze(records, false, registry);
            elseif isstruct(value)
                fields = fieldnames(value);
                for index = 1:numel(value)
                    for field = 1:numel(fields)
                        [value(index).(fields{field}), valid] = yamada.model.EvaluationContext.freeze(value(index).(fields{field}), false, registry);
                        safe = safe && valid;
                    end
                end
            elseif iscell(value)
                for index = 1:numel(value)
                    [value{index}, valid] = yamada.model.EvaluationContext.freeze(value{index}, false, registry);
                    safe = safe && valid;
                end
            else
                safe = isnumeric(value) || islogical(value) || ischar(value) || isstring(value) || ...
                    isa(value, "datetime") || isa(value, "duration") || isa(value, "calendarDuration") || ...
                    isa(value, "categorical") || isa(value, "yamada.model.SourceSpan") || ...
                    isa(value, "yamada.model.UnknownSourceRegion") || isa(value, "yamada.model.Diagnostic") || ...
                    isa(value, "yamada.model.PropertyState") || isa(value, "yamada.model.PropertyDefinition") || ...
                    isa(value, "yamada.model.CallbackEdit") || isa(value, "yamada.source.CallbackMethodSignature");
                if safe && isa(value, "yamada.model.PropertyDefinition") && ~isempty(registry)
                    safe = registry.areIndependentDefinitions(value);
                elseif safe && isobject(value)
                    safe = yamada.model.InputChangeClock.isValueData(value);
                end
                if ~safe, value = []; end
            end
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
