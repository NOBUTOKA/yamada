classdef SourceLiteralBatchTransaction
    % SourceLiteralBatchTransaction Prepare one indexed atomic literal patch spanning multiple component owners.
    %   Syntax planning uses the original source for every owner. Final document
    %   validation runs once after all values and positions have been projected.
    properties (SetAccess = private)
        % Batch - Exact primary forward and inverse source edits.
        Batch macd.source.SourcePatchBatch
        % AfterSource - Fully prepared source and execution indexes.
        AfterSource macd.model.CurrentSourceState
        % Specs - Per-owner primary values and insertion recipes.
        Specs struct
        % Bindings - Independent canonical setting values for changed owners.
        Bindings struct
    end
    properties (Access = private)
        BeforeRevision uint64
        BeforeStateId string
        InputClock macd.model.InputChangeClock
        InputRevision uint64
        InputsTracked logical
        Catalog macd.model.ComponentRegistry
        CatalogRevision uint64
        Projection struct
        Updates macd.model.SourceLocationUpdate = macd.model.SourceLocationUpdate.empty
        Diagnostics macd.model.Diagnostic
        Regions macd.model.UnknownSourceRegion
        Metadata struct
        Validation struct
    end
    methods
        function obj = SourceLiteralBatchTransaction(document, source, changes, registry)
            % SourceLiteralBatchTransaction Prepare all owners against one source and validate their combined final state.
            arguments (Input)
                document (1, 1) macd.model.DocumentModel
                source (1, 1) macd.model.CurrentSourceState
                changes (1, :) struct
                registry (1, 1) macd.model.ComponentRegistry
            end
            arguments (Output)
                obj (1, 1) macd.model.SourceLiteralBatchTransaction
            end
            [obj.InputClock, obj.InputRevision, obj.InputsTracked] = document.inputStamp();
            obj.BeforeRevision = source.Revision; obj.BeforeStateId = source.StateId;
            obj.Catalog = registry; obj.CatalogRevision = registry.Revision;
            obj.Specs = struct("ComponentId", {}, "Changes", {}, "Placements", {}, "RemovedIds", {});
            edits = struct("Start", {}, "End", {}, "Text", {});
            names = strings(1, 0);
            for id = unique(string({changes.ComponentId}), "stable")
                requested = rmfield(changes(string({changes.ComponentId}) == id), "ComponentId");
                plan = macd.model.SourceLiteralTransaction.plan(document, source, id, requested, registry);
                edits = [edits plan.Edits]; %#ok<AGROW>
                names(end + 1) = document.sourceComponentName(id); %#ok<AGROW>
                obj.Specs(end + 1) = struct("ComponentId", id, "Changes", requested, ...
                    "Placements", plan.Placements, "RemovedIds", zeros(1, 0));
            end
            edits = macd.source.SourceFormatting.separateLiteralComponents(source.Text, edits, source.Analysis, names);
            obj.Batch = macd.source.SourcePatchBatch(source.Text, edits);
            [obj.AfterSource, obj.Bindings, execution] = macd.model.IndexedSettingEdit.prepareMany( ...
                document, source, obj.Specs, obj.Batch, registry);
            obj.Projection = document.prepareSettingProjection(obj.Batch, execution, string({obj.Specs.ComponentId}));
            for owner = document.Components
                update = macd.model.SourceLocationUpdate(owner, obj.Batch, ...
                    struct("SettingId", {}, "Value", {}), execution, obj.AfterSource.Analysis, ...
                    document.ownerSettingProjection(owner, obj.Projection));
                assert(update.CanApply, "macd:SourceLiteralTransaction:WiderProof", "Changed syntax requires range rebinding.");
                obj.Updates(end + 1) = update;
            end
            [obj.Diagnostics, obj.Regions] = macd.model.SourceLocationUpdate.annotations(document, obj.Batch);
            obj.Metadata = document.Metadata; obj.Metadata.SourceSnapshotText = obj.AfterSource.Text;
            trace = execution.Trace;
            obj.Metadata.InitializationContext = struct("Order", trace.Order, "Certain", trace.Certain, ...
                "Returns", trace.Returns, "Layout", obj.AfterSource.Analysis.Layout);
            obj.Validation = document.validateIndexedBatchCandidate(obj.Bindings, obj.Updates, ...
                obj.AfterSource, obj.Diagnostics, obj.Regions, obj.Metadata, obj.Specs, registry);
        end

        function result = validationResult(obj)
            % validationResult Return independent final diagnostics and effective values for publication.
            arguments (Input)
                obj (1, 1) macd.model.SourceLiteralBatchTransaction
            end
            arguments (Output)
                result (1, 1) struct
            end
            result = obj.Validation;
        end

        function applyModel(obj, document, source, registry)
            % applyModel Publish only after all source, catalog, input and occurrence guards still hold.
            arguments (Input)
                obj (1, 1) macd.model.SourceLiteralBatchTransaction
                document (1, 1) macd.model.DocumentModel
                source (1, 1) macd.model.CurrentSourceState
                registry (1, 1) macd.model.ComponentRegistry
            end
            source.assertRevision(obj.BeforeRevision, obj.BeforeStateId);
            assert(registry == obj.Catalog && registry.Revision == obj.CatalogRevision, ...
                "macd:SourceLiteralTransaction:StaleCatalog", "The catalog changed during source preparation.");
            for update = obj.Updates, update.assertCurrent(document.getComponent(update.ComponentId)); end
            [clock, revision, tracked] = document.inputStamp();
            assert(~obj.InputsTracked || (tracked && clock == obj.InputClock && revision == obj.InputRevision), ...
                "macd:SourceLiteralTransaction:StaleInputs", "The document changed during source preparation.");
            document.publishSettingProjection(obj.Projection);
            for update = obj.Updates, update.applyValidated(document.getComponent(update.ComponentId)); end
            for binding = obj.Bindings
                document.getComponent(binding.ComponentId).synchronizeSourceSettings(binding.Settings, binding.FactoryArguments);
            end
            document.Diagnostics = obj.Validation.Diagnostics;
            document.UnknownRegions = obj.Regions; document.Metadata = obj.Metadata;
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
