classdef SourceLiteralTransaction
    % SourceLiteralTransaction Prepare local source and model changes before atomic document publication.
    %   Literal proof, actual insertion syntax and current positions share one candidate.
    %   The caller must verify the source revision and publish AfterSource with applyModel.

    properties (SetAccess = private)
        % BeforeRevision - Source revision that owned the prepared target positions.
        BeforeRevision uint64
        % BeforeStateId - History node against which the changes were prepared.
        BeforeStateId string
        % Batch - Forward/inverse source edits for one atomic history entry.
        Batch yamada.source.SourcePatchBatch
        % AfterSource - Exact current source and lexical data after successful publication.
        AfterSource yamada.model.CurrentSourceState
        % ComponentId - Stable edited component identity.
        ComponentId string
        % Changes - Requested literal values retained for UI invalidation and history.
        Changes struct
        % Placements - Primary insertion recipes retained for exact history replay.
        Placements struct = struct("Path", {}, "Method", {}, "Offset", {}, "OwnerMethod", {})
        % CanReuseStates - Whether the finite proof excludes semantic effects on other component owners.
        CanReuseStates logical = true
        % CanReuseEligibility - Whether placement and source-edit conditions retain their previous meaning.
        CanReuseEligibility logical = true
        % CanPreserveDocumentStates - Whether unchanged document-dependent policy inputs retain their meaning.
        CanPreserveDocumentStates logical = false
    end

    properties (Access = private)
        PreparedValidation struct = struct("Ready", false)
        NeedsDocumentValidation logical = false
        SettingProjection struct = struct()
        Settings yamada.model.PropertySetting
        FactoryArguments cell
        Updates yamada.model.SourceLocationUpdate = yamada.model.SourceLocationUpdate.empty
        Diagnostics yamada.model.Diagnostic
        Regions yamada.model.UnknownSourceRegion
        Metadata struct
        Catalog yamada.model.ComponentRegistry
        InputClock yamada.model.InputChangeClock
        InputRevision uint64
        InputsTracked logical = false
        CatalogRevision uint64
    end

    methods
        function obj = SourceLiteralTransaction(document, source, id, changes, registry)
            % SourceLiteralTransaction Prepare independent literal proofs without mutating live model records.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                source (1, 1) yamada.model.CurrentSourceState
                id (1, 1) string
                changes (1, :) struct
                registry (1, 1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                obj (1, 1) yamada.model.SourceLiteralTransaction
            end
            [obj.InputClock, obj.InputRevision, obj.InputsTracked] = document.inputStamp();
            plan = yamada.model.SourceLiteralTransaction.plan(document, source, id, changes, registry);
            component = document.getComponent(id); candidate = plan.Candidate;
            parentFactory = plan.ParentFactory; definitions = plan.Definitions; edits = plan.Edits;
            obj.NeedsDocumentValidation = plan.NeedsDocumentValidation;
            obj.CanReuseStates = plan.CanReuseStates; obj.CanReuseEligibility = plan.CanReuseEligibility;
            obj.Placements = plan.Placements;
            edits = yamada.source.SourceFormatting.separateLiteralComponents(source.Text, edits, source.Analysis, document.sourceComponentName(id));
            obj.Batch = yamada.source.SourcePatchBatch(source.Text, edits);
            [obj.AfterSource, obj.Settings, obj.FactoryArguments, execution] = yamada.model.IndexedSettingEdit.prepare( ...
                document, source, component, obj.Batch, changes, obj.Placements, registry);
            candidate.synchronizeSourceSettings(obj.Settings, obj.FactoryArguments);
            [states, diagnostics] = yamada.model.PropertyStateResolver.resolve(candidate, definitions);
            assert(~yamada.validation.ModelValidator.hasErrors(diagnostics), ...
                "yamada:SourceLiteralTransaction:InvalidValue", "%s", strjoin(string({diagnostics.Message}), newline));
            affected = string({changes.Path});
            for change = changes
                definition = definitions([definitions.Path] == string(change.Path));
                affected = union(affected, definition.Application.AffectedPaths, "stable");
            end
            dependent = [yamada.model.GridLayoutStatePolicy.inputPropertyPaths(), ...
                yamada.model.AncestorGeometryPolicy.inputPropertyPaths()];
            sameDefinitions = true;
            if ~isequaln(component.CreationArguments, obj.FactoryArguments)
                afterDefinitions = registry.getEffectiveProperties(component.Factory, parentFactory, obj.FactoryArguments);
                sameDefinitions = isequaln(definitions, afterDefinitions);
            end
            obj.CanPreserveDocumentStates = obj.CanReuseStates && sameDefinitions && ~any(ismember(affected, dependent));
            if obj.CanPreserveDocumentStates && isempty(diagnostics)
                obj.PreparedValidation = document.preparePropertyValidation(candidate, definitions, states, ...
                    string({changes.Path}), obj.Batch, registry);
                if obj.PreparedValidation.Ready, states = obj.PreparedValidation.States; end
            end
            if ~obj.PreparedValidation.Ready
                transaction = yamada.model.PropertyStateResolver.transaction(states);
                % Validate requested schemas against the proven final cross-property state.
                for change = changes
                    transaction.stage(string(change.Path), change.Value);
                end
                message = yamada.validation.PropertyBatchValidator.validate(definitions, transaction);
                assert(strlength(message) == 0, "yamada:SourceLiteralTransaction:InvalidValue", "%s", message);
            end
            for change = changes
                index = find(string({states.Path}) == string(change.Path), 1);
                assert(~isempty(index) && states(index).IsKnown && ...
                    yamada.model.PropertyStateResolver.matchesRequested(states(index), change.Value), ...
                    "yamada:SourceLiteralTransaction:WiderProof", "The final requested value needs a broader proof.");
            end
            % Transform the maintained setting index once, then prepare component/property bindings.
            obj.SettingProjection = document.prepareSettingProjection(obj.Batch, execution, id);
            for owner = document.Components
                update = yamada.model.SourceLocationUpdate(owner, obj.Batch, ...
                    struct("SettingId", {}, "Value", {}), execution, obj.AfterSource.Analysis, ...
                    document.ownerSettingProjection(owner, obj.SettingProjection));
                assert(update.CanApply, "yamada:SourceLiteralTransaction:WiderProof", "Changed syntax requires range rebinding.");
                obj.Updates(end + 1) = update;
            end
            [obj.Diagnostics, obj.Regions] = yamada.model.SourceLocationUpdate.annotations(document, obj.Batch);
            obj.Metadata = document.Metadata;
            obj.Metadata.SourceSnapshotText = obj.AfterSource.Text;
            trace = execution.Trace;
            obj.Metadata.InitializationContext = struct("Order", trace.Order, "Certain", trace.Certain, ...
                "Returns", trace.Returns, "Layout", obj.AfterSource.Analysis.Layout);
            obj.BeforeRevision = source.Revision;
            obj.BeforeStateId = source.StateId;
            obj.ComponentId = id;
            obj.Changes = changes;
            obj.Catalog = registry;
            obj.CatalogRevision = registry.Revision;
            if obj.NeedsDocumentValidation
                obj.PreparedValidation = document.validateIndexedCandidate(obj.Settings, obj.FactoryArguments, ...
                    obj.Updates, obj.AfterSource, obj.Diagnostics, obj.Regions, obj.Metadata, id, changes, registry);
            end
        end

        function result = validationResult(obj)
            % validationResult Return independent validated states and diagnostics from the exact published candidate.
            arguments (Input)
                obj (1, 1) yamada.model.SourceLiteralTransaction
            end
            arguments (Output)
                result (1, 1) struct
            end
            result = obj.PreparedValidation;
        end

        function [updates, token] = inputProjection(obj)
            % inputProjection Return immutable position candidates and the exact input version used for preparation.
            arguments (Input)
                obj (1, 1) yamada.model.SourceLiteralTransaction
            end
            arguments (Output)
                updates yamada.model.SourceLocationUpdate
                token (1, 1) struct
            end
            updates = obj.Updates;
            token = struct();
            if obj.InputsTracked
                token = struct("Clock", obj.InputClock, "Revision", obj.InputRevision, ...
                    "Registry", obj.Catalog, "RegistryRevision", obj.CatalogRevision);
            end
        end

        function applyModel(obj, document, source, registry)
            % applyModel Publish a completely prepared model projection inside the document commit barrier.
            arguments (Input)
                obj (1, 1) yamada.model.SourceLiteralTransaction
                document (1, 1) yamada.model.DocumentModel
                source (1, 1) yamada.model.CurrentSourceState
                registry (1, 1) yamada.model.ComponentRegistry
            end
            source.assertRevision(obj.BeforeRevision, obj.BeforeStateId);
            assert(registry == obj.Catalog && registry.Revision == obj.CatalogRevision, ...
                "yamada:SourceLiteralTransaction:StaleCatalog", "The catalog changed during source preparation.");
            for update = obj.Updates
                update.assertCurrent(document.getComponent(update.ComponentId));
            end
            [clock, revision, tracked] = document.inputStamp();
            assert(~obj.InputsTracked || (tracked && clock == obj.InputClock && revision == obj.InputRevision), ...
                "yamada:SourceLiteralTransaction:StaleInputs", "The document changed during source preparation.");
            document.publishSettingProjection(obj.SettingProjection);
            for update = obj.Updates
                update.applyValidated(document.getComponent(update.ComponentId));
            end
            owner = document.getComponent(obj.ComponentId);
            owner.synchronizeSourceSettings(obj.Settings, obj.FactoryArguments);
            document.Diagnostics = obj.Diagnostics;
            document.UnknownRegions = obj.Regions;
            document.Metadata = obj.Metadata;
        end
    end
    methods (Static, Access = ?yamada.model.SourceLiteralBatchTransaction)
        function result = plan(document, source, id, changes, registry)
            % plan Prove owned literal syntax and insertion recipes against one unchanged source revision.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                source (1, 1) yamada.model.CurrentSourceState
                id (1, 1) string
                changes (1, :) struct
                registry (1, 1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                result (1, 1) struct
            end
            needsDocumentValidation = false; canReuseStates = true; canReuseEligibility = true;
            placements = struct("Path", {}, "Method", {}, "Offset", {}, "OwnerMethod", {});
            component = document.getComponent(id);
            assert(~isempty(component) && component.IsEditable);
            assert(document.sourceAnalysis().matches(source.Text), ...
                "yamada:SourceLiteralTransaction:StaleSource", "The model analysis does not own this source revision.");
            assert(~yamada.model.PropertyStateResolver.hasUnresolvedExecution(document), ...
                "yamada:SourceLiteralTransaction:WiderProof", "Executable effects require the established broader proof.");
            parent = document.getComponent(component.ParentId);
            parentFactory = "";
            if ~isempty(parent), parentFactory = parent.Factory; end
            definitions = registry.getEffectiveProperties(component.Factory, parentFactory, component.CreationArguments);
            candidate = yamada.model.ComponentRecord(component.Id, component.Name, component.Factory, ...
                component.DeclaredType, component.Origin);
            candidate.ParentId = component.ParentId;
            candidate.CreationArguments = component.CreationArguments;
            candidate.SourceSpans = component.SourceSpans;
            candidate.Metadata = component.Metadata;
            properties = struct([]);
            for entry = component.Properties
                record = entry.toStruct();
                if isempty(properties), properties = record; else, properties(end + 1) = record; end %#ok<AGROW>
            end
            candidate.restoreProperties(properties);
            candidate.applyProjectedSettings(component.Settings);
            edits = struct("Start", {}, "End", {}, "Text", {});
            localPaths = yamada.model.PropertyStateResolver.ownerLocalPaths(definitions);
            for change = changes
                path = string(change.Path);
                definition = definitions(string({definitions.Path}) == path);
                assert(isscalar(definition) && definition.IsEditable && ...
                    any(definition.Application.EffectStatus == ["independent", "modeled"]), ...
                    "yamada:SourceLiteralTransaction:WiderProof", "This setting needs its coupled model scope.");
                policy = definition.Application;
                ownerLocal = any(localPaths == path);
                needsDocumentValidation = needsDocumentValidation || ~ownerLocal;
                canReuseStates = canReuseStates && ownerLocal && ...
                    (isempty(component.Children) || (~definition.AbsoluteGeometryImpact && definition.GridGeometryImpact ~= "required"));
                dependencies = yamada.model.SubtreePlacementPlanner.inputPropertyPaths();
                canReuseEligibility = canReuseEligibility && ...
                    ~any(ismember([path policy.AffectedPaths], dependencies)) && ...
                    ~(isfield(definition.ValueSchema, "kind") && string(definition.ValueSchema.kind) == "callback");
                encoded = yamada.source.LiteralEncoder.encode(change.Value);
                [decoded, literal] = yamada.source.MatlabLiteralParser.parse(encoded);
                assert(literal && isequaln(decoded, change.Value), ...
                    "yamada:SourceLiteralTransaction:WiderProof", "Literal encoding needs complete syntax validation.");
                entry = component.getProperty(path);
                if ~isempty(entry) && ~isequaln(entry.LiteralValue, change.Value)
                    assert(entry.IsEditable && entry.ValueKind == "literal" && isfield(entry.Metadata, "ValueSpan"), ...
                        "yamada:SourceLiteralTransaction:WiderProof", "Existing value ownership is not proven.");
                    span = entry.Metadata.ValueSpan;
                    assert(~isempty(span) && span.isKnown());
                    edits(end + 1) = struct("Start", span.StartOffset, "End", span.EndOffset, "Text", encoded); %#ok<AGROW>
                end
                candidate.setProperty(path, change.Value);
            end
            if yamada.source.PropertyInsertionPlanner.needsPlan(document, candidate)
                plan = yamada.source.PropertyInsertionPlanner.tentative(document, candidate, registry);
                edits = [edits plan.Edits];
                placements = plan.Placements;
            end
            result = struct("Candidate", candidate, "ParentFactory", parentFactory, "Definitions", definitions, ...
                "Edits", edits, "Placements", placements, "NeedsDocumentValidation", needsDocumentValidation, ...
                "CanReuseStates", canReuseStates, "CanReuseEligibility", canReuseEligibility);
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
