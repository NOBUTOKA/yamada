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
        Batch macd.source.SourcePatchBatch
        % AfterSource - Exact current source and lexical data after successful publication.
        AfterSource macd.model.CurrentSourceState
        % ComponentId - Stable edited component identity.
        ComponentId string
        % Changes - Requested literal values retained for UI invalidation and history.
        Changes struct
        % CanReuseStates - Whether the finite proof excludes semantic effects on other component owners.
        CanReuseStates logical = true
        % CanReuseEligibility - Whether placement and source-edit conditions retain their previous meaning.
        CanReuseEligibility logical = true
    end

    properties (Access = private)
        Settings macd.model.PropertySetting
        FactoryArguments cell
        Updates macd.model.SourceLocationUpdate = macd.model.SourceLocationUpdate.empty
        Diagnostics macd.model.Diagnostic
        Regions macd.model.UnknownSourceRegion
        Metadata struct
        Catalog macd.model.ComponentRegistry
        CatalogRevision uint64
    end

    methods
        function obj = SourceLiteralTransaction(document, source, id, changes, registry)
            % SourceLiteralTransaction Prepare independent literal proofs without mutating live model records.
            arguments (Input)
                document (1, 1) macd.model.DocumentModel
                source (1, 1) macd.model.CurrentSourceState
                id (1, 1) string
                changes (1, :) struct
                registry (1, 1) macd.model.ComponentRegistry
            end
            arguments (Output)
                obj (1, 1) macd.model.SourceLiteralTransaction
            end
            component = document.getComponent(id);
            assert(~isempty(component) && component.IsEditable);
            assert(document.sourceAnalysis().matches(source.Text), ...
                "macd:SourceLiteralTransaction:StaleSource", "The model analysis does not own this source revision.");
            assert(~macd.model.PropertyStateResolver.hasUnresolvedExecution(document), ...
                "macd:SourceLiteralTransaction:WiderProof", "Executable effects require the established broader proof.");
            parent = document.getComponent(component.ParentId);
            parentFactory = "";
            if ~isempty(parent), parentFactory = parent.Factory; end
            definitions = registry.getEffectiveProperties(component.Factory, parentFactory, component.CreationArguments);
            candidate = macd.model.ComponentRecord(component.Id, component.Name, component.Factory, ...
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
            candidate.restoreSettings(component.settingSnapshot());
            edits = struct("Start", {}, "End", {}, "Text", {});
            for change = changes
                path = string(change.Path);
                definition = definitions(string({definitions.Path}) == path);
                assert(isscalar(definition) && definition.IsEditable && ...
                    any(definition.Application.EffectStatus == ["independent", "modeled"]) && ...
                    ~any(definition.Application.EffectPolicy == ["buttonSelection", "componentReference", "layout", "gridTracks"]), ...
                    "macd:SourceLiteralTransaction:WiderProof", "This setting needs its coupled model scope.");
                policy = definition.Application;
                independent = policy.EffectStatus == "independent" && policy.EffectPolicy == "none";
                numeric = policy.EffectStatus == "modeled" && policy.EffectPolicy == "numericValue";
                obj.CanReuseStates = obj.CanReuseStates && (independent || numeric) && ...
                    (isempty(component.Children) || (~definition.AbsoluteGeometryImpact && definition.GridGeometryImpact ~= "required"));
                dependencies = macd.model.SubtreePlacementPlanner.inputPropertyPaths();
                obj.CanReuseEligibility = obj.CanReuseEligibility && ...
                    ~any(ismember([path policy.AffectedPaths], dependencies)) && ...
                    ~(isfield(definition.ValueSchema, "kind") && string(definition.ValueSchema.kind) == "callback");
                encoded = macd.source.LiteralEncoder.encode(change.Value);
                [decoded, literal] = macd.source.MatlabLiteralParser.parse(encoded);
                assert(literal && isequaln(decoded, change.Value), ...
                    "macd:SourceLiteralTransaction:WiderProof", "Literal encoding needs complete syntax validation.");
                entry = component.getProperty(path);
                if ~isempty(entry) && ~isequaln(entry.LiteralValue, change.Value)
                    assert(entry.IsEditable && entry.ValueKind == "literal" && isfield(entry.Metadata, "ValueSpan"), ...
                        "macd:SourceLiteralTransaction:WiderProof", "Existing value ownership is not proven.");
                    span = entry.Metadata.ValueSpan;
                    assert(~isempty(span) && span.isKnown());
                    edits(end + 1) = struct("Start", span.StartOffset, "End", span.EndOffset, "Text", encoded); %#ok<AGROW>
                end
                candidate.setProperty(path, change.Value);
            end
            if macd.source.PropertyInsertionPlanner.needsPlan(document, candidate)
                plan = macd.source.PropertyInsertionPlanner.tentative(document, candidate, registry);
                edits = [edits plan.Edits];
            end
            edits = macd.source.SourceFormatting.separateComponents(source.Text, edits);
            obj.Batch = macd.source.SourcePatchBatch(source.Text, edits);
            obj.AfterSource = source.withBatch(obj.Batch);
            [obj.Settings, ~, obj.FactoryArguments, execution] = macd.model.SourceSettingRebinder.rebind( ...
                document, component, obj.AfterSource, obj.Batch, registry);
            candidate.synchronizeSourceSettings(obj.Settings, obj.FactoryArguments);
            [states, diagnostics] = macd.model.PropertyStateResolver.resolve(candidate, definitions);
            assert(~macd.validation.ModelValidator.hasErrors(diagnostics), ...
                "macd:SourceLiteralTransaction:InvalidValue", "%s", strjoin(string({diagnostics.Message}), newline));
            transaction = macd.model.PropertyStateResolver.transaction(states);
            % Validate requested schemas against the proven final cross-property state.
            for change = changes
                transaction.stage(string(change.Path), change.Value);
            end
            message = macd.validation.PropertyBatchValidator.validate(definitions, transaction);
            assert(strlength(message) == 0, "macd:SourceLiteralTransaction:InvalidValue", "%s", message);
            for change = changes
                index = find(string({states.Path}) == string(change.Path), 1);
                assert(~isempty(index) && states(index).IsKnown && ...
                    macd.model.PropertyStateResolver.matchesRequested(states(index), change.Value), ...
                    "macd:SourceLiteralTransaction:WiderProof", "The final requested value needs a broader proof.");
            end
            % Prepare every source position before any live property handle changes.
            for owner = document.Components
                update = macd.model.SourceLocationUpdate(owner, obj.Batch, ...
                    struct("SettingId", {}, "Value", {}), execution, obj.AfterSource.Analysis);
                assert(update.CanApply, "macd:SourceLiteralTransaction:WiderProof", "Changed syntax requires range rebinding.");
                obj.Updates(end + 1) = update;
            end
            [obj.Diagnostics, obj.Regions] = macd.model.SourceLocationUpdate.annotations(document, obj.Batch);
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
        end

        function applyModel(obj, document, source, registry)
            % applyModel Publish a completely prepared model projection inside the document commit barrier.
            arguments (Input)
                obj (1, 1) macd.model.SourceLiteralTransaction
                document (1, 1) macd.model.DocumentModel
                source (1, 1) macd.model.CurrentSourceState
                registry (1, 1) macd.model.ComponentRegistry
            end
            source.assertRevision(obj.BeforeRevision, obj.BeforeStateId);
            assert(registry == obj.Catalog && registry.Revision == obj.CatalogRevision, ...
                "macd:SourceLiteralTransaction:StaleCatalog", "The catalog changed during source preparation.");
            for update = obj.Updates
                update.assertCurrent(document.getComponent(update.ComponentId));
            end
            for update = obj.Updates
                update.apply(document.getComponent(update.ComponentId));
            end
            owner = document.getComponent(obj.ComponentId);
            owner.synchronizeSourceSettings(obj.Settings, obj.FactoryArguments);
            document.Diagnostics = obj.Diagnostics;
            document.UnknownRegions = obj.Regions;
            document.Metadata = obj.Metadata;
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
