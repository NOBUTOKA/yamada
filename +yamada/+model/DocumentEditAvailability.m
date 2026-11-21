classdef DocumentEditAvailability
    % DocumentEditAvailability Check declared subtree conditions without rehearsing commands.
    %   Queries inspect source ownership, hierarchy and placement only. They never
    %   clone a document, generate candidate source or edit history. Actual commands
    %   validate their chosen edit atomically before publishing it.
    methods (Static)
        function state = deletion(document, id, registry)
            % deletion Check owned source and subtree links without deleting a candidate.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                id (1, 1) string
                registry (1, 1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                state (1, 1) struct
            end
            % Reuse only a small value result for the exact current semantic input.
            context = document.evaluationContext(registry);
            key = "eligibility:delete:" + id;
            [state, found] = context.lookup(key);
            if found, return, end
            state = struct("Enabled", false, "Reason", "");
            try
                snapshot = yamada.model.DocumentEditAvailability.inspect(document, id, true);
                for record = snapshot.Records
                    callbacks = yamada.source.CallbackSourceAnalyzer.analyze(document, record.Id, registry, false, true);
                    if any(string({callbacks.State}) ~= "absent")
                        error("yamada:DocumentEditAvailability:Callbacks", "Callback ownership prevents complete subtree deletion.");
                    end
                end
                state.Enabled = true;
            catch exception
                state.Reason = string(exception.message);
            end
            context.remember(key, state);
        end

        function state = copying(document, id, registry)
            % copying Check transferable values and ownership without evaluating a copied document.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                id (1, 1) string
                registry (1, 1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                state (1, 1) struct
            end
            % Reuse only a small value result for the exact current semantic input.
            context = document.evaluationContext(registry);
            key = "eligibility:copy:" + id;
            [state, found] = context.lookup(key);
            if found, return, end
            state = struct("Enabled", false, "Reason", "");
            try
                if id == document.RootComponentId
                    error("yamada:DocumentEditAvailability:Root", "The document root cannot be copied.");
                end
                snapshot = yamada.model.DocumentEditAvailability.inspect(document, id, true);
                yamada.model.DocumentEditAvailability.ownership(document, snapshot);
                catalog = yamada.model.SubtreeCopyPlanner.sourceCatalog(snapshot, registry);
                for record = snapshot.Records
                    definition = catalog.get(record.Factory, record.CreationArguments);
                    if definition.IsProgrammaticOnly || definition.Category == "FigureTools"
                        error("yamada:DocumentEditAvailability:Factory", "This construction family is not supported for copying.");
                    end
                    callbackPaths = yamada.model.SubtreeCopyPlanner.callbackPaths(document, record.Id, catalog);
                    owner = document.getComponent(record.Id);
                    for entry = record.Properties
                        if any(callbackPaths == entry.Path), continue, end
                        if owner.isReleaseUnavailable()
                            settings = owner.getSettings(entry.Path);
                            if ~isempty(settings) && settings(end).IsCertain && settings(end).ValueKind == "literal"
                                if catalog.isReadOnlyProperty(record.Factory, entry.Path, record.CreationArguments)
                                    error("yamada:DocumentEditAvailability:Value", "A property cannot be copied without losing source behavior.");
                                end
                                yamada.source.LiteralEncoder.encode(settings(end).LiteralValue);
                                continue
                            end
                        end
                        if entry.ValueKind == "expression"
                            if isfield(entry.Metadata, "SubtreeReferenceId")
                                target = document.getComponent(string(entry.Metadata.SubtreeReferenceId));
                                if isempty(target)
                                    error("yamada:DocumentEditAvailability:Reference", "Reference target is missing.");
                                end
                                yamada.model.SubtreeReferencePolicy.validate(document, owner, entry.Path, target, catalog);
                            else
                                yamada.model.SubtreeReferencePolicy.resolve(document, owner, entry.Path, entry.SourceExpression, catalog);
                            end
                        elseif entry.ValueKind ~= "literal" || catalog.isReadOnlyProperty(record.Factory, entry.Path, record.CreationArguments)
                            error("yamada:DocumentEditAvailability:Value", "A property cannot be copied without losing source behavior.");
                        else
                            yamada.source.LiteralEncoder.encode(entry.LiteralValue);
                        end
                    end
                    % Constructor ownership comes from source tokens, not replaceable display diagnostics.
                    yamada.model.SubtreeCopyPlanner.validateConstructor(document, record, catalog, callbackPaths);
                end
                state.Enabled = true;
            catch exception
                state.Reason = string(exception.message);
            end
            context.remember(key, state);
        end

        function states = reparenting(document, id, registry, measuredPosition)
            % reparenting Inspect all destinations using one subtree and side-effect-free placement rules.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                id (1, 1) string
                registry (1, 1) yamada.model.ComponentRegistry
                measuredPosition double {mustBeFinite} = []
            end
            arguments (Output)
                states struct
            end
            % Geometry participates in eligibility even when document inputs are unchanged.
            context = document.evaluationContext(registry);
            key = "eligibility:reparent:" + id;
            [cached, found] = context.lookup(key);
            if found && isequaln(cached.Measured, measuredPosition)
                states = cached.States;
                return
            end
            states = struct("Id", {}, "Name", {}, "Enabled", {}, "Reason", {});
            source = document.getComponent(id);
            reason = "";
            snapshot = yamada.model.SubtreeSnapshot.empty;
            try
                snapshot = yamada.model.DocumentEditAvailability.inspect(document, id, true);
                yamada.model.DocumentEditAvailability.ownership(document, snapshot, true);
                if yamada.model.PropertyStateResolver.hasUnresolvedExecution(document)
                    error("yamada:DocumentEditAvailability:UnknownHierarchy", "Unresolved initialization effects prevent proving subtree relocation safety.");
                end
            catch exception
                reason = string(exception.message);
            end
            % Collect the finite incoming reference constraints once for all destinations.
            requiredParents = strings(1, 0);
            if strlength(reason) == 0
                definition = registry.sourceDefinition(source);
                for owner = document.Components
                    entry = owner.getProperty("SelectedTab");
                    if ~isempty(entry) && isfield(entry.Metadata, "SubtreeReferenceId") && ...
                            string(entry.Metadata.SubtreeReferenceId) == id
                        requiredParents(end + 1) = owner.Id; %#ok<AGROW>
                    end
                end
            end
            for parent = document.Components
                state = struct("Id", parent.Id, "Name", parent.Name, "Enabled", false, "Reason", reason);
                if strlength(reason) == 0
                    if source.ParentId == parent.Id
                        state.Reason = "Current parent.";
                    elseif ~any(definition.AllowedParentFactories == parent.Factory)
                        state.Reason = "This component type cannot use that parent.";
                    elseif any(requiredParents ~= parent.Id)
                        state.Reason = "An editor-owned SelectedTab reference requires its current tab group.";
                    else
                        try
                            yamada.model.SubtreePlacementPlanner.prepare(document, snapshot, parent.Id, registry, ...
                                string({snapshot.Records.Id}), measuredPosition);
                            state.Enabled = true;
                        catch exception
                            state.Reason = string(exception.message);
                        end
                    end
                end
                states(end + 1) = state; %#ok<AGROW>
            end
            context.remember(key, struct("Measured", measuredPosition, "States", states));
        end

        function state = pasting(document, snapshot, parentId, registry, measuredPosition, offset)
            % pasting Check the stored subtree against current destination geometry without inserting it.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                snapshot (1, 1) yamada.model.SubtreeSnapshot
                parentId (1, 1) string
                registry (1, 1) yamada.model.ComponentRegistry
                measuredPosition double {mustBeFinite} = []
                offset (1, 2) double {mustBeFinite} = [10 10]
            end
            arguments (Output)
                state (1, 1) struct
            end
            state = struct("Enabled", false, "Reason", "");
            try
                % Internal references are remapped; external generated references must still exist.
                ids = string({snapshot.Records.Id});
                for record = snapshot.Records
                    for entry = record.Properties
                        if ~isfield(entry.Metadata, "SubtreeReferenceId"), continue, end
                        targetId = string(entry.Metadata.SubtreeReferenceId);
                        if any(ids == targetId), continue, end
                        target = document.getComponent(targetId);
                        if isempty(target) || entry.Path ~= "ContextMenu" || target.Factory ~= "uicontextmenu" || ...
                                target.ParentId ~= document.RootComponentId
                            error("yamada:DocumentEditAvailability:Reference", "The stored external component reference is no longer valid.");
                        end
                    end
                end
                yamada.model.SubtreePlacementPlanner.prepare(document, snapshot, parentId, registry, ...
                    strings(1, 0), measuredPosition, offset);
                state.Enabled = true;
            catch exception
                state.Reason = string(exception.message);
            end
        end
    end

    methods (Static, Access = ?yamada.model.DocumentModel)
        function result = canInheritProperties(document, prepared, id, paths, registry)
            % canInheritProperties Prove accepted literal changes preserve command and placement conditions.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                prepared (1, 1) yamada.model.DocumentModel
                id (1, 1) string
                paths (1, :) string
                registry (1, 1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = false;
            source = document.getComponent(id);
            target = prepared.getComponentByName(source.Name);
            if isempty(target) || ~isequaln(source.CreationArguments, target.CreationArguments) || ...
                    yamada.model.PropertyStateResolver.hasUnresolvedExecution(document) ~= ...
                    yamada.model.PropertyStateResolver.hasUnresolvedExecution(prepared)
                return
            end
            parent = document.getComponent(source.ParentId);
            parentFactory = "";
            if ~isempty(parent), parentFactory = parent.Factory; end
            definitions = registry.getEffectiveProperties(source.Factory, parentFactory, source.CreationArguments);
            dependencies = yamada.model.SubtreePlacementPlanner.inputPropertyPaths();
            for path = paths
                definition = definitions(string({definitions.Path}) == path);
                if ~isscalar(definition), return, end
                policy = definition.Application;
                schema = definition.ValueSchema;
                if ~definition.IsEditable || definition.AuditDisposition ~= "editable" || ...
                        ~any(policy.EffectStatus == ["independent", "modeled"]) || ...
                        any(policy.EffectPolicy == ["buttonSelection", "componentReference", "layout", "gridTracks"]) || ...
                        any(ismember([path policy.AffectedPaths], dependencies)) || ...
                        (isfield(schema, "kind") && string(schema.kind) == "callback") || ...
                        registry.isReadOnlyProperty(source.Factory, path, source.CreationArguments)
                    return
                end
                before = source.getProperty(path);
                after = target.getProperty(path);
                if (~isempty(before) && (before.ValueKind ~= "literal" || ~before.IsEditable || ...
                        isfield(before.Metadata, "SubtreeReferenceId"))) || ...
                        isempty(after) || after.ValueKind ~= "literal" || ~after.IsEditable || ...
                        isfield(after.Metadata, "SubtreeReferenceId")
                    return
                end
                if ~isempty(before)
                    try
                        encoded = yamada.source.LiteralEncoder.encode(before.LiteralValue);
                        if any(ismissing(encoded), "all"), return, end
                    catch
                        return
                    end
                end
            end
            % The caller has already proved literal encoding, insertion ownership and requested values.
            result = true;
        end
    end

    methods (Static, Access = private)
        function snapshot = inspect(document, id, allowUnavailable)
            % inspect Validate complete subtree identities and editable records once per query.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                id (1, 1) string
                allowUnavailable (1, 1) logical = false
            end
            arguments (Output)
                snapshot (1, 1) yamada.model.SubtreeSnapshot
            end
            if id == document.RootComponentId
                error("yamada:DocumentEditAvailability:Root", "The document root cannot be moved or deleted.");
            end
            snapshot = yamada.model.SubtreeSnapshot(document, id);
            readOnly = ~[snapshot.Records.IsEditable];
            if allowUnavailable
                readOnly = readOnly & ~arrayfun(@(record) isfield(record.Metadata, "UnavailableRelease"), snapshot.Records);
            end
            if any(readOnly)
                error("yamada:DocumentEditAvailability:ReadOnly", "The subtree contains a read-only component.");
            end
        end

        function ownership(document, snapshot, moving)
            % ownership Require identifiable initialization statements without planning replacement source.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                snapshot (1, 1) yamada.model.SubtreeSnapshot
                moving (1, 1) logical = false
            end
            parsed = snapshot.Records(arrayfun(@yamada.model.SourceOwnership.hasSource, snapshot.Records));
            if isempty(parsed), return, end
            analysis = document.sourceAnalysis();
            statements = analysis.Statements;
            [direct, ~] = yamada.source.SubtreeReparentSourceEdits.directScope(statements);
            for record = parsed
                spans = record.SourceSpans.Creation;
                if isempty(spans) || isempty(record.SourceSpans.Declaration) || ~record.SourceSpans.Declaration.isKnown()
                    error("yamada:DocumentEditAvailability:Ownership", "Creation or declaration ownership is missing.");
                end
                if moving
                    for entry = record.Properties
                        if ~isempty(entry.SourceSpan), spans = [spans entry.SourceSpan]; end %#ok<AGROW>
                    end
                    for setting = record.Settings
                        if ~isempty(setting.Location.SourceSpan), spans = [spans setting.Location.SourceSpan]; end %#ok<AGROW>
                    end
                end
                for span = spans
                    matches = analysis.statementIndices(span);
                    if ~span.isKnown() || numel(matches) ~= 1 || ~direct(matches)
                        error("yamada:DocumentEditAvailability:Ownership", "Initialization ownership is not a unique direct statement.");
                    end
                end
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
