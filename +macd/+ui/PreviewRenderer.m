classdef PreviewRenderer < handle
    % PreviewRenderer Render registry-approved component models on an editor surface.
    %   This class creates only known factories from a DocumentModel and applies
    %   editable literal properties. It does not instantiate an opened handle-based
    %   class, invoke callbacks, or evaluate source expressions.
    %
    %   Example:
    %       renderer = macd.ui.PreviewRenderer(registry);
    %       [handles, diagnostics] = renderer.render(document, previewPanel);

    properties (Access = private)
        Registry macd.model.ComponentRegistry
        PreviewSurface
        PreviewMargin double = 12
        CombinedConfiguration macd.model.DocumentModel = macd.model.DocumentModel.empty
        UsesCombinedConfiguration logical = false
        RenderedInputs struct = struct()
        RenderedVisualInputs struct = struct()
        RenderedToken struct = struct()
        RenderedRegistryRevision uint64 = uint64(0)
        RenderCount double = 0
        SynchronizationCount double = 0
        SubtreeRebuildCount double = 0
        FallbackReason string = ""
    end

    methods
        function [applied, diagnostics, geometryChanged] = synchronize(obj, document, handles, request)
            % synchronize Apply resolved property changes across every catalog component capability.
            %   Uncertain local transitions rebuild their owning subtree; unrelated
            %   source, structure, or registry changes retain full reconstruction.
            arguments (Input)
                obj (1, 1) macd.ui.PreviewRenderer
                document (1, 1) macd.model.DocumentModel
                handles containers.Map
                request (1, 1) macd.ui.RefreshRequest
            end
            arguments (Output)
                applied (1, 1) logical
                diagnostics macd.model.Diagnostic
                geometryChanged (1, 1) logical
            end
            applied = false;
            diagnostics = macd.model.Diagnostic.empty;
            geometryChanged = false;
            obj.FallbackReason = "unsupported-change";
            if request.Kind ~= "properties" || isempty(request.Paths) || isempty(request.ComponentIds), return, end
            context = document.evaluationContext(obj.Registry);
            [inputs, safe] = context.inputs();
            if ~safe || isempty(fieldnames(obj.RenderedInputs)) || ...
                    obj.RenderedRegistryRevision ~= obj.Registry.Revision
                obj.FallbackReason = "untracked-inputs";
                return
            end
            certified = context.isLiteralTransition(obj.RenderedToken, request);
            if inputs.OriginalText == obj.RenderedInputs.OriginalText && isequaln(inputs, obj.RenderedInputs)
                obj.FallbackReason = "";
                applied = true;
                return
            end
            beforeComparison = obj.RenderedInputs;
            afterComparison = inputs;
            visualAfter = struct();
            if certified
                mappings = struct("ComponentId", {}, "Kind", {}, "OldName", {}, "NewName", {});
                if isempty(fieldnames(obj.RenderedVisualInputs))
                    obj.RenderedVisualInputs = obj.visualSourceInputs(beforeComparison, mappings);
                end
                visualAfter = obj.patchVisualInputs(obj.RenderedVisualInputs, inputs, request);
                beforeComparison = visualAfter;
                afterComparison = visualAfter;
            elseif document.isPropertySourceTransition(obj.RenderedInputs.OriginalText, request)
                mappings = struct("ComponentId", {}, "Kind", {}, "OldName", {}, "NewName", {});
                if isempty(fieldnames(obj.RenderedVisualInputs))
                    obj.RenderedVisualInputs = obj.visualSourceInputs(beforeComparison, mappings);
                end
                beforeComparison = obj.RenderedVisualInputs;
                afterComparison = obj.visualSourceInputs(afterComparison, mappings);
                visualAfter = afterComparison;
            end
            if ~certified && ~isequaln(obj.maskRequestedInputs(beforeComparison, request), obj.maskRequestedInputs(afterComparison, request))
                obj.FallbackReason = "unrelated-inputs";
                return
            end
            reconstructed = false;
            % Reuse existing model resolution and catalog policies, without rehearsing a document edit.
            for id = request.ComponentIds
                component = document.getComponent(id);
                localPaths = request.pathsFor(id);
                componentRequest = macd.ui.RefreshRequest("properties", id, localPaths);
                if isempty(component), return, end
                if id == document.RootComponentId
                    if isempty(obj.PreviewSurface) || ~isvalid(obj.PreviewSurface), return, end
                    obj.updatePreviewSurface(component, obj.PreviewSurface.Parent.Parent.Parent);
                    geometryChanged = geometryChanged || componentRequest.affectsGeometry(document, obj.Registry, handles);
                    continue
                end
                states = document.getEffectivePropertyStates(obj.Registry, id);
                paths = string(arrayfun(@(state) state.Definition.Path, states));
                [found, requested] = ismember(localPaths, paths);
                if ~all(found), return, end
                visible = arrayfun(@(state) ~any(state.Definition.PreviewPolicy == ["skip", "notRendered"]), states);
                if ~any(visible(requested)), continue, end
                if ~isKey(handles, char(id)) || ~isvalid(handles(char(id)))
                    obj.FallbackReason = "stale-handle";
                    return
                end
                preview = handles(char(id));
                reason = "";
                for index = requested(visible(requested))
                    state = states(index);
                    if ~state.Resolution.IsKnown || ~state.Resolution.IsEditable || ...
                            ~any(state.Definition.Application.EffectStatus == ["independent", "modeled"])
                        reason = "unresolved-local-effect";
                        break
                    end
                end
                try
                    if strlength(reason) > 0, error("macd:PreviewRenderer:Reconstruct", "%s", reason); end
                    indices = macd.ui.PreviewUpdatePlanner.plan(states, localPaths, preview);
                    if obj.prepareNativeTransition(preview, states, indices)
                        indices = macd.ui.PreviewUpdatePlanner.plan(states, localPaths, preview);
                    end
                    for index = indices
                        state = states(index);
                        if state.Definition.Application.EffectPolicy == "buttonSelection", continue, end
                        value = state.Resolution.EffectiveValue;
                        if state.Definition.PreviewPolicy == "adapt" && state.Definition.Editor == "asset"
                            value = obj.resolveImageSource(value, document);
                        end
                        obj.setProperty(preview, state.Definition.Path, value, component);
                    end
                    obj.synchronizeCoupledScope(document, component, handles, states(requested));
                    if ~isempty(component.Children) && componentRequest.affectsGeometry(document, obj.Registry, handles)
                        obj.synchronizeDescendantGeometry(document, component, handles);
                    end
                    componentRequest = macd.ui.RefreshRequest("properties", id, unique([localPaths paths(indices)], "stable"));
                    geometryChanged = geometryChanged || componentRequest.affectsGeometry(document, obj.Registry, handles);
                catch exception
                    % A failed native transition is repaired from the accepted model, never left half-applied.
                    obj.FallbackReason = "local-reconstruction:" + string(exception.identifier);
                    [repaired, localDiagnostics] = obj.rebuildScope(document, component, handles);
                    diagnostics = [diagnostics localDiagnostics]; %#ok<AGROW>
                    if ~repaired, return, end
                    geometryChanged = true;
                    reconstructed = true;
                end
            end
            obj.RenderedInputs = inputs;
            obj.RenderedToken = document.evaluationContext(obj.Registry).revisionToken();
            obj.RenderedVisualInputs = visualAfter;
            obj.SynchronizationCount = obj.SynchronizationCount + 1;
            if ~reconstructed, obj.FallbackReason = ""; end
            applied = true;
        end

        function applied = acknowledgeCallbackChanges(obj, document)
            % acknowledgeCallbackChanges Advance source-only callback intentions without touching native controls.
            arguments (Input)
                obj (1, 1) macd.ui.PreviewRenderer
                document (1, 1) macd.model.DocumentModel
            end
            arguments (Output)
                applied (1, 1) logical
            end
            applied = false;
            [inputs, safe] = document.evaluationContext(obj.Registry).inputs();
            if ~safe || isempty(fieldnames(obj.RenderedInputs)) || obj.RenderedRegistryRevision ~= obj.Registry.Revision
                return
            end
            % Source position changes are harmless only for an exact published callback transaction.
            if ~document.isSourceOnlyTransition(obj.RenderedInputs.OriginalText, "callback") || ...
                    ~obj.sameSourceOnlyInputs(obj.RenderedInputs, inputs, false)
                return
            end
            obj.RenderedInputs = inputs;
            obj.RenderedToken = document.evaluationContext(obj.Registry).revisionToken();
            obj.RenderedVisualInputs = struct();
            obj.FallbackReason = "";
            applied = true;
        end

        function applied = acknowledgeRenameChanges(obj, document)
            % acknowledgeRenameChanges Retain native controls when only source member names changed.
            arguments (Input)
                obj (1, 1) macd.ui.PreviewRenderer
                document (1, 1) macd.model.DocumentModel
            end
            arguments (Output)
                applied (1, 1) logical
            end
            applied = false;
            [inputs, safe] = document.evaluationContext(obj.Registry).inputs();
            if ~safe || isempty(fieldnames(obj.RenderedInputs)) || ...
                    obj.RenderedRegistryRevision ~= obj.Registry.Revision
                return
            end
            if ~document.isSourceOnlyTransition(obj.RenderedInputs.OriginalText, "rename") || ...
                    ~obj.sameSourceOnlyInputs(obj.RenderedInputs, inputs, true)
                return
            end
            obj.RenderedInputs = inputs;
            obj.RenderedToken = document.evaluationContext(obj.Registry).revisionToken();
            obj.RenderedVisualInputs = struct();
            obj.FallbackReason = "";
            applied = true;
        end

        function value = statistics(obj)
            % statistics Return bounded diagnostic counters for developer measurements.
            arguments (Input)
                obj (1, 1) macd.ui.PreviewRenderer
            end
            arguments (Output)
                value (1, 1) struct
            end
            value = struct("renders", obj.RenderCount, "synchronizations", obj.SynchronizationCount, ...
                "fallbackReason", obj.FallbackReason, "subtreeRebuilds", obj.SubtreeRebuildCount);
        end

        function obj = PreviewRenderer(registry)
            % PreviewRenderer Create a renderer backed by one component registry.
            arguments (Input)
                registry (1, 1) macd.model.ComponentRegistry = ...
                    macd.model.ComponentRegistry.createDefault()
            end
            arguments (Output)
                obj (1, 1) macd.ui.PreviewRenderer
            end

            % Use the same capability definitions as parsing and validation.
            obj.Registry = registry;
        end

        function [handles, diagnostics, surface] = render(obj, document, parent)
            % render Rebuild a safe preview and return handles by component identity.
            arguments (Input)
                obj (1, 1) macd.ui.PreviewRenderer
                document (1, 1) macd.model.DocumentModel
                parent
            end
            arguments (Output)
                handles containers.Map
                diagnostics macd.model.Diagnostic
                surface
            end

            % Dispose stale editor-owned controls before constructing the new tree.
            obj.RenderCount = obj.RenderCount + 1;
            obj.RenderedInputs = struct();
            obj.RenderedToken = struct();
            obj.RenderedVisualInputs = struct();
            delete(parent.Children);
            handles = containers.Map("KeyType", "char", "ValueType", "any");
            diagnostics = macd.model.Diagnostic.empty;
            surface = [];
            obj.Diagnostics = macd.model.Diagnostic.empty;
            obj.CombinedConfiguration = macd.model.DocumentModel.empty;
            obj.UsesCombinedConfiguration = false;
            root = document.getComponent(document.RootComponentId);
            if isempty(root)
                return
            end

            % Cross-component pending grid writes share one complete parsed configuration.
            obj.UsesCombinedConfiguration = any(arrayfun(@(component) ...
                (macd.model.GridLayoutStatePolicy.requiresCombinedPlan(component, document, obj.Registry) || ...
                macd.model.ButtonSelectionPolicy.requiresCombinedPlan(component, document)), document.Components));
            if obj.UsesCombinedConfiguration
                try
                    plan = macd.source.PropertySourcePlan.combined(document, root, obj.Registry);
                    obj.CombinedConfiguration = plan.Document;
                    obj.CombinedConfiguration.FilePath = document.FilePath;
                catch exception
                    obj.Diagnostics(end + 1) = macd.model.Diagnostic("preview-grid-unknown", "warning", ...
                        "Cannot resolve combined grid initialization: " + string(exception.message));
                end
            end

            % Recreate the source figure at its actual client-area pixel size.
            obj.createPreviewSurface(root, parent);
            surface = obj.PreviewSurface;
            for index = 1:numel(root.Children)
                obj.renderComponent(document, root.Children(index), obj.PreviewSurface, handles);
            end
            diagnostics = obj.Diagnostics;
            obj.Diagnostics = macd.model.Diagnostic.empty;
            [inputs, safe] = document.evaluationContext(obj.Registry).inputs();
            if safe
                obj.RenderedInputs = inputs;
                obj.RenderedToken = document.evaluationContext(obj.Registry).revisionToken();
            end
            obj.RenderedRegistryRevision = obj.Registry.Revision;
        end
    end

    properties (Access = private)
        Diagnostics macd.model.Diagnostic = macd.model.Diagnostic.empty
    end

    methods (Access = private)
        function result = sameSourceOnlyInputs(obj, before, after, allowRename)
            % sameSourceOnlyInputs Compare visual model values independently from published source coordinates.
            arguments (Input)
                obj (1, 1) macd.ui.PreviewRenderer
                before (1, 1) struct
                after (1, 1) struct
                allowRename (1, 1) logical
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = false;
            if numel(before.Components) ~= numel(after.Components), return, end
            mappings = struct("ComponentId", {}, "Kind", {}, "OldName", {}, "NewName", {});
            if allowRename
                for index = 1:numel(before.Components)
                    old = before.Components(index);
                    current = after.Components(index);
                    if old.Id ~= current.Id, return, end
                    if old.Name ~= current.Name
                        mappings(end + 1) = struct("ComponentId", old.Id, "Kind", "property", ...
                            "OldName", old.Name, "NewName", current.Name); %#ok<AGROW>
                    end
                end
            end
            before = obj.visualSourceInputs(before, mappings);
            after = obj.visualSourceInputs(after, struct("ComponentId", {}, "Kind", {}, "OldName", {}, "NewName", {}));
            result = isequaln(before, after);
        end

        function inputs = visualSourceInputs(obj, inputs, mappings)
            % visualSourceInputs Strip only source ownership from a proven source-only command's visual comparison.
            arguments (Input)
                obj (1, 1) macd.ui.PreviewRenderer
                inputs (1, 1) struct
                mappings struct
            end
            arguments (Output)
                inputs (1, 1) struct
            end
            inputs = rmfield(inputs, ["OriginalText", "Metadata", "UnknownRegions", "CallbackEdits", "RenameEdits"]);
            for index = 1:numel(inputs.Components)
                inputs.Components(index) = obj.visualComponentInputs(inputs.Components(index), inputs.Components, mappings);
            end
        end

        function inputs = patchVisualInputs(obj, inputs, after, request)
            % patchVisualInputs Rebuild only owners certified by the current source transition.
            arguments (Input)
                obj (1, 1) macd.ui.PreviewRenderer
                inputs (1, 1) struct
                after (1, 1) struct
                request (1, 1) macd.ui.RefreshRequest
            end
            arguments (Output)
                inputs (1, 1) struct
            end
            mappings = struct("ComponentId", {}, "Kind", {}, "OldName", {}, "NewName", {});
            for id = request.ComponentIds
                index = find(string({after.Components.Id}) == id, 1);
                assert(~isempty(index));
                inputs.Components(index) = obj.visualComponentInputs(after.Components(index), after.Components, mappings);
            end
        end

        function component = visualComponentInputs(obj, component, components, mappings)
            % visualComponentInputs Normalize one immutable record without traversing unrelated component values.
            arguments (Input)
                obj (1, 1) macd.ui.PreviewRenderer
                component (1, 1) struct
                components struct
                mappings struct
            end
            arguments (Output)
                component (1, 1) struct
            end
            parentFactory = "";
            parent = components(string({components.Id}) == component.ParentId);
            if ~isempty(parent), parentFactory = parent.Factory; end
            callbacks = obj.Registry.getEffectiveCallbacks(component.Factory, parentFactory, component.CreationArguments);
            callbackPaths = string({callbacks.Path});
            properties = component.Properties;
            if ~isempty(properties)
                properties = properties(~ismember(string({properties.Path}), callbackPaths));
            end
            if ~isempty(properties), properties = rmfield(properties, ["SourceSpan", "Metadata"]); end
            for propertyIndex = 1:numel(properties)
                properties(propertyIndex).SourceExpression = macd.source.ComponentNameRewriter.rewrite( ...
                    properties(propertyIndex).SourceExpression, mappings);
            end
            settings = component.Settings;
            if ~isempty(settings)
                settings = settings(~ismember(string({settings.Path}), callbackPaths));
            end
            for settingIndex = 1:numel(settings)
                location = settings(settingIndex).Location;
                expression = "";
                if isfield(location, "SourceExpression")
                    expression = macd.source.ComponentNameRewriter.rewrite(location.SourceExpression, mappings);
                end
                settings(settingIndex).Location = struct("IsCertain", location.IsCertain, ...
                    "IsEditable", location.IsEditable, "Method", location.Method, "SourceExpression", expression);
            end
            if isempty(properties), properties = struct([]); end
            if isempty(settings), settings = struct([]); end
            definition = obj.Registry.get(component.Factory, component.CreationArguments);
            first = macd.model.PropertyApplicationPlanner.nameValueStart(definition, component.CreationArguments);
            component.CreationArguments = component.CreationArguments(1:first - 1);
            component.Properties = properties;
            component.Settings = settings;
            component.Metadata = struct();
            component.SourceSpans = struct();
            match = find(string({mappings.ComponentId}) == component.Id, 1);
            if ~isempty(match), component.Name = mappings(match).NewName; end
        end

        function prepared = prepareNativeTransition(~, target, states, indices)
            % prepareNativeTransition Bridge disjoint valid ranges and item-data replacements.
            arguments (Input)
                ~
                target
                states (1, :) struct
                indices (1, :) double
            end
            arguments (Output)
                prepared (1, 1) logical
            end
            prepared = false;
            paths = string(arrayfun(@(state) state.Definition.Path, states));
            policies = string(arrayfun(@(state) state.Definition.Application.EffectPolicy, states(indices)));
            % ItemsData must not constrain an intermediate replacement of Items.
            if any(policies == "itemSelection") && any(ismember(paths(indices), ["Items", "ItemsData"])) && isprop(target, "ItemsData")
                target.ItemsData = [];
                prepared = true;
            end
            % Join valid old and final domains before restoring the final constraints.
            for family = ["numericValue", "boundedValue", "textValue"]
                if ~any(policies == family), continue, end
                range = "Limits";
                if family == "textValue", range = "CharacterLimits"; end
                rangeIndex = find(paths == range & ismember(1:numel(paths), indices), 1);
                valueIndex = find(paths == "Value", 1);
                if isempty(rangeIndex) || isempty(valueIndex) || ~states(valueIndex).Resolution.IsKnown, continue, end
                current = target.(range);
                desired = states(rangeIndex).Resolution.EffectiveValue;
                if ~isnumeric(current) || ~isnumeric(desired) || numel(current) ~= 2 || numel(desired) ~= 2, continue, end
                if isequaln(current, desired), continue, end
                target.(range) = [min(current(1), desired(1)), max(current(2), desired(2))];
                if family == "numericValue"
                    for path = ["LowerLimitInclusive", "UpperLimitInclusive"]
                        if isprop(target, path), target.(path) = "on"; end
                    end
                    if isempty(states(valueIndex).Resolution.EffectiveValue) && isprop(target, "AllowEmpty")
                        target.AllowEmpty = "on";
                    end
                end
                target.Value = states(valueIndex).Resolution.EffectiveValue;
                prepared = true;
            end
        end

        function synchronizeCoupledScope(obj, document, component, handles, changed)
            % synchronizeCoupledScope Publish resolved group selection and grid-child placement locally.
            arguments (Input)
                obj (1, 1) macd.ui.PreviewRenderer
                document (1, 1) macd.model.DocumentModel
                component (1, 1) macd.model.ComponentRecord
                handles containers.Map
                changed (1, :) struct
            end
            policies = string(arrayfun(@(state) state.Definition.Application.EffectPolicy, changed));
            if any(policies == "buttonSelection")
                group = document.getComponent(component.ParentId);
                if isempty(group) || ~isKey(handles, char(group.Id)), return, end
                nativeGroup = handles(char(group.Id));
                for id = group.Children
                    states = document.getEffectivePropertyStates(obj.Registry, id);
                    for state = states
                        if state.Definition.Application.EffectPolicy == "buttonSelection" && state.Resolution.IsKnown && ...
                                logical(state.Resolution.EffectiveValue) && isKey(handles, char(id))
                            nativeGroup.SelectedObject = handles(char(id));
                            break
                        end
                    end
                end
            end
            if any(policies == "gridTracks")
                for id = component.Children
                    if ~isKey(handles, char(id)), continue, end
                    states = document.getEffectivePropertyStates(obj.Registry, id);
                    child = document.getComponent(id);
                    for state = states
                        if state.Definition.Application.EffectPolicy == "layout" && ...
                                state.Resolution.IsKnown && state.Resolution.IsEditable
                            obj.setProperty(handles(char(id)), state.Definition.Path, state.Resolution.EffectiveValue, child);
                        end
                    end
                end
            end
        end

        function synchronizeDescendantGeometry(obj, document, component, handles)
            % synchronizeDescendantGeometry Restore final child coordinates after native container reflow.
            arguments (Input)
                obj (1, 1) macd.ui.PreviewRenderer
                document (1, 1) macd.model.DocumentModel
                component (1, 1) macd.model.ComponentRecord
                handles containers.Map
            end
            % Restore only the descendants owned by this layout change.
            pending = component.Children;
            while ~isempty(pending)
                id = pending(1); pending(1) = [];
                child = document.getComponent(id);
                pending = [pending child.Children]; %#ok<AGROW>
                if ~isKey(handles, char(id)), continue, end
                states = document.getEffectivePropertyStates(obj.Registry, id);
                paths = string(arrayfun(@(state) state.Definition.Path, states));
                index = find(paths == "Position", 1);
                if isempty(index), continue, end
                if ~states(index).Resolution.IsKnown
                    error("macd:PreviewRenderer:UnknownChildGeometry", "Child geometry needs local reconstruction.");
                end
                obj.setProperty(handles(char(id)), "Position", states(index).Resolution.EffectiveValue, child);
            end
        end

        function [repaired, diagnostics] = rebuildScope(obj, document, component, handles)
            % rebuildScope Reconstruct only the local ownership scope after an uncertain or failed transition.
            arguments (Input)
                obj (1, 1) macd.ui.PreviewRenderer
                document (1, 1) macd.model.DocumentModel
                component (1, 1) macd.model.ComponentRecord
                handles containers.Map
            end
            arguments (Output)
                repaired (1, 1) logical
                diagnostics macd.model.Diagnostic
            end
            repaired = false;
            diagnostics = macd.model.Diagnostic.empty;
            scope = component;
            parent = document.getComponent(component.ParentId);
            if ~isempty(parent) && isKey(handles, char(parent.Id))
                nativeParent = handles(char(parent.Id));
                if isprop(nativeParent, "RowHeight") || isprop(nativeParent, "SelectedObject")
                    scope = parent;
                end
            end
            if scope.Id == document.RootComponentId || ~isKey(handles, char(scope.Id)), return, end
            target = handles(char(scope.Id));
            if ~isvalid(target), return, end
            nativeParent = target.Parent;
            % Freeze stacking and transient tab selection before native disposal.
            siblingOrder = nativeParent.Children;
            slot = find(siblingOrder == target, 1);
            selectedTab = [];
            replacesSelectedTab = false;
            if isprop(nativeParent, "SelectedTab")
                selectedTab = nativeParent.SelectedTab;
                replacesSelectedTab = ~isempty(selectedTab) && selectedTab == target;
            end
            try
                obj.prepareConfiguration(document);
                % Native deletion owns descendants; retire every corresponding map entry.
                pending = scope.Id;
                ids = strings(1, 0);
                while ~isempty(pending)
                    id = pending(1); pending(1) = [];
                    record = document.getComponent(id);
                    ids(end + 1) = id; %#ok<AGROW>
                    pending = [pending record.Children]; %#ok<AGROW>
                end
                delete(target);
                for id = ids
                    if isKey(handles, char(id)), remove(handles, char(id)); end
                end
                obj.renderComponent(document, scope.Id, nativeParent, handles);
                if isKey(handles, char(scope.Id)) && ~isempty(slot)
                    % Preserve native tab order and stacking among unchanged siblings.
                    siblingOrder(slot) = handles(char(scope.Id));
                    try
                        nativeParent.Children = siblingOrder;
                    catch orderException
                        enclosing = document.getComponent(scope.ParentId);
                        if ~isempty(enclosing) && enclosing.Id ~= document.RootComponentId
                            [repaired, diagnostics] = obj.rebuildScope(document, enclosing, handles);
                            return
                        end
                        rethrow(orderException);
                    end
                end
                if replacesSelectedTab
                    nativeParent.SelectedTab = handles(char(scope.Id));
                elseif ~isempty(selectedTab) && isvalid(selectedTab)
                    nativeParent.SelectedTab = selectedTab;
                end
                diagnostics = obj.Diagnostics;
                obj.Diagnostics = macd.model.Diagnostic.empty;
                repaired = isKey(handles, char(scope.Id)) && isvalid(handles(char(scope.Id)));
                if repaired, obj.SubtreeRebuildCount = obj.SubtreeRebuildCount + 1; end
            catch
                % The caller retains complete reconstruction as the final repair boundary.
            end
        end

        function prepareConfiguration(obj, document)
            % prepareConfiguration Reuse the existing source-plan projection for full or subtree construction.
            arguments (Input)
                obj (1, 1) macd.ui.PreviewRenderer
                document (1, 1) macd.model.DocumentModel
            end
            obj.Diagnostics = macd.model.Diagnostic.empty;
            obj.CombinedConfiguration = macd.model.DocumentModel.empty;
            obj.UsesCombinedConfiguration = any(arrayfun(@(component) ...
                macd.model.GridLayoutStatePolicy.requiresCombinedPlan(component, document, obj.Registry) || ...
                macd.model.ButtonSelectionPolicy.requiresCombinedPlan(component, document), document.Components));
            if obj.UsesCombinedConfiguration
                root = document.getComponent(document.RootComponentId);
                plan = macd.source.PropertySourcePlan.combined(document, root, obj.Registry);
                obj.CombinedConfiguration = plan.Document;
                obj.CombinedConfiguration.FilePath = document.FilePath;
            end
        end

        function inputs = maskRequestedInputs(~, inputs, request)
            % maskRequestedInputs Prove that every other source and model input stayed unchanged.
            arguments (Input)
                ~
                inputs (1, 1) struct
                request (1, 1) macd.ui.RefreshRequest
            end
            arguments (Output)
                inputs (1, 1) struct
            end
            for index = 1:numel(inputs.Components)
                component = inputs.Components(index);
                if ~any(request.ComponentIds == component.Id), continue, end
                if ~isempty(component.Properties)
                    component.Properties(ismember(string({component.Properties.Path}), request.pathsFor(component.Id))) = [];
                end
                if ~isempty(component.Settings)
                    component.Settings(ismember(string({component.Settings.Path}), request.pathsFor(component.Id))) = [];
                end
                if isempty(component.Properties), component.Properties = struct([]); end
                if isempty(component.Settings), component.Settings = struct([]); end
                inputs.Components(index) = component;
            end
        end

        function renderComponent(obj, document, componentId, parent, handles)
            % renderComponent Construct one safe component and all of its children.
            arguments (Input)
                obj (1, 1) macd.ui.PreviewRenderer
                document (1, 1) macd.model.DocumentModel
                componentId string
                parent
                handles containers.Map
            end

            % Create only factories declared in the registry and model hierarchy.
            component = document.getComponent(componentId);
            if isempty(component) || ~obj.Registry.contains(component.Factory)
                return
            end
            if any(component.Factory == ["uicontextmenu", "uimenu", "uitoolbar", ...
                    "uipushtool", "uitoggletool"])
                return
            end
            try
                configured = component;
                configurationDocument = document;
                if obj.UsesCombinedConfiguration && ~isempty(obj.CombinedConfiguration)
                    configurationDocument = obj.CombinedConfiguration;
                    configured = configurationDocument.getComponentByName(component.Name);
                elseif ~obj.UsesCombinedConfiguration && macd.source.PropertySourcePlan.needsPlan(document, component)
                    plan = macd.source.PropertySourcePlan.plan(document, component, obj.Registry);
                    configured = plan.Component;
                    configurationDocument = plan.Document;
                    configurationDocument.FilePath = document.FilePath;
                end
                preview = obj.createPreviewComponent(configured, parent);
                handles(char(component.Id)) = preview;
                obj.applyProperties(preview, configured, configurationDocument);
                for index = 1:numel(component.Children)
                    obj.renderComponent(document, component.Children(index), preview, handles);
                end
                if component.Factory == "uibuttongroup"
                    for childId = component.Children
                        child = configurationDocument.getComponentByName(document.getComponent(childId).Name);
                        if isempty(child) || ~any(child.Factory == ["uiradiobutton", "uitogglebutton"]), continue, end
                        states = configurationDocument.getEffectivePropertyStates(obj.Registry, child.Id);
                        value = states(arrayfun(@(item) item.Definition.Path == "Value", states)).Resolution;
                        if value.IsKnown && logical(value.EffectiveValue) && isKey(handles, char(childId))
                            selected = handles(char(childId));
                            preview.SelectedObject = selected;
                        end
                    end
                end
            catch exception
                obj.Diagnostics(end + 1) = macd.model.Diagnostic( ...
                    "preview-render-failed", "warning", ...
                    "Preview could not render " + component.Name + ": " + ...
                    string(exception.message), component.Id);
            end
        end

        function applyProperties(obj, preview, component, document)
            % applyProperties Assign editable literal properties without source evaluation.
            arguments (Input)
                obj (1, 1) macd.ui.PreviewRenderer
                preview
                component (1, 1) macd.model.ComponentRecord
                document (1, 1) macd.model.DocumentModel
            end

            % Isolate unsupported preview assignments as nonblocking diagnostics.
            definition = obj.Registry.get(component.Factory, component.CreationArguments);
            [entries, positionReason, gridReason] = macd.model.PropertyApplicationPlanner.forPreview( ...
                component, document, obj.Registry);
            if strlength(positionReason) > 0
                obj.Diagnostics(end + 1) = macd.model.Diagnostic("preview-position-unknown", "warning", ...
                    "Preview position is uncertain for " + component.Name + ": " + positionReason, component.Id);
            end
            if strlength(gridReason) > 0
                obj.Diagnostics(end + 1) = macd.model.Diagnostic("preview-grid-unknown", "warning", ...
                    "Preview layout is uncertain for " + component.Name + ": " + gridReason, component.Id);
            end
            for index = 1:numel(entries)
                entry = entries(index);
                if entry.ValueKind ~= "literal" || ~entry.IsEditable
                    continue
                end
                property = definition.getProperty(entry.Path);
                imageSource = ~isempty(property) && property.PreviewPolicy == "adapt" && property.Editor == "asset";
                if ~imageSource && ~isempty(property) && ...
                        any(property.PreviewPolicy == ["skip", "notRendered"])
                    continue
                end
                if entry.Path == "Position" && ...
                        isa(preview.Parent, "matlab.ui.container.GridLayout")
                    % Grid layout owns child geometry through Layout.Row/Column.
                    continue
                end
                try
                    value = entry.LiteralValue;
                    if imageSource
                        value = obj.resolveImageSource(value, document);
                        if strlength(value) == 0
                            continue
                        end
                    end
                    obj.setProperty(preview, entry.Path, value, component);
                catch exception
                    obj.Diagnostics(end + 1) = macd.model.Diagnostic( ...
                        "preview-property-failed", "warning", ...
                        "Preview could not apply " + entry.Path + " on " + ...
                        component.Name + ": " + string(exception.message), ...
                        component.Id);
                end
            end
        end

        function path = resolveImageSource(obj, value, document)
            % resolveImageSource Resolve a local image path relative to its app source.
            arguments (Input)
                obj (1, 1) macd.ui.PreviewRenderer %#ok<INUSA>
                value
                document (1, 1) macd.model.DocumentModel
            end
            arguments (Output)
                path (1, 1) string
            end

            path = "";
            if ~(ischar(value) || (isstring(value) && isscalar(value)))
                return
            end
            requested = string(value);
            if strlength(requested) == 0
                return
            end

            % Opened apps interpret relative assets beside their source file.
            if strlength(document.FilePath) > 0
                sourceRelative = fullfile(fileparts(document.FilePath), requested);
                if isfile(sourceRelative)
                    path = string(sourceRelative);
                    return
                end
            end
            if isfile(requested)
                path = requested;
            end
        end

        function createPreviewSurface(obj, root, parent)
            % createPreviewSurface Place an actual-size client area in the scroll host.
            arguments (Input)
                obj (1, 1) macd.ui.PreviewRenderer
                root (1, 1) macd.model.ComponentRecord
                parent
            end

            % Construct editor-owned wrappers once; subsequent root edits reuse them.
            content = uipanel(parent, BorderType="none", AutoResizeChildren="off", ...
                BackgroundColor=[0.35 0.36 0.38], Tag="macd-preview-scroll-content");
            frame = uipanel(content, BorderType="none", AutoResizeChildren="off", ...
                BackgroundColor=[0.53 0.54 0.55], Tag="macd-preview-frame");
            obj.PreviewSurface = uipanel(frame, BorderType="none", AutoResizeChildren="off", ...
                BackgroundColor=[0.94 0.94 0.94], Tag="macd-preview-canvas");
            obj.updatePreviewSurface(root, parent);
        end

        function updatePreviewSurface(obj, root, parent)
            % updatePreviewSurface Adapt figure client size and color without replacing preview children.
            arguments (Input)
                obj (1, 1) macd.ui.PreviewRenderer
                root (1, 1) macd.model.ComponentRecord
                parent
            end
            sourceSize = [560 420];
            entry = root.getProperty("Position");
            if ~isempty(entry) && entry.ValueKind == "literal" && isnumeric(entry.LiteralValue) && ...
                    isreal(entry.LiteralValue) && numel(entry.LiteralValue) == 4 && ...
                    all(isfinite(entry.LiteralValue)) && all(entry.LiteralValue(3:4) > 0)
                sourceSize = reshape(entry.LiteralValue(3:4), 1, []);
            end
            available = obj.parentInnerPosition(parent);
            frameSize = double(sourceSize) + 2;
            contentSize = max(double(available(3:4)), frameSize + 2 * obj.PreviewMargin);
            frame = obj.PreviewSurface.Parent;
            frame.Parent.Position = [1 1 contentSize];
            frame.Position = [floor((contentSize - frameSize) ./ 2) + 1 frameSize];
            obj.PreviewSurface.Position = [2 2 double(sourceSize)];
            colorEntry = root.getProperty("Color");
            if ~isempty(colorEntry) && colorEntry.ValueKind == "literal"
                try
                    obj.PreviewSurface.BackgroundColor = colorEntry.LiteralValue;
                catch
                    % Keep the R2024a UIFigure default for unsupported colors.
                end
            end
        end

        function preview = createPreviewComponent(obj, component, parent)
            % createPreviewComponent Create one ordinary control on the preview surface.
            arguments (Input)
                obj (1, 1) macd.ui.PreviewRenderer
                component (1, 1) macd.model.ComponentRecord
                parent
            end
            % Figure-only controls are filtered before this safe factory call.
            factoryArguments = macd.model.PropertyApplicationPlanner.forPreviewArguments(component, obj.Registry);
            preview = feval(char(component.Factory), parent, ...
                factoryArguments{:});
        end

        function setProperty(obj, target, path, value, component)
            % setProperty Assign a direct or one-level nested graphics property.
            arguments (Input)
                obj (1, 1) macd.ui.PreviewRenderer
                target
                path string
                value
                component (1, 1) macd.model.ComponentRecord
            end

            % Assign nested Layout properties directly, avoiding a detached value copy.
            if isempty(obj.Registry)
                error("macd:PreviewRenderer:Uninitialized", ...
                    "Preview rendering requires a component registry.");
            end
            if path == "Items" && iscell(value) && ...
                    all(cellfun(@(item) isstring(item) && isscalar(item), value))
                value = string(value);
            end
            if path == "Position" && isnumeric(value) && numel(value) == 4 && ...
                obj.usesPixelPosition(target)
                definition = obj.Registry.get(component.Factory, component.CreationArguments);
                property = definition.getProperty("Position");
                if ~isempty(property) && macd.model.PositionGeometry.applies(property.Application.EffectPolicy)
                    orientation = "";
                    if isprop(target, "Orientation"), orientation = string(target.Orientation); end
                    spec = macd.model.PositionGeometry.constraint(property.Application.EffectPolicy, ...
                        orientation, strlength(orientation) > 0);
                    target.Position = macd.model.PositionGeometry.normalize(reshape(double(value), 1, 4), spec);
                    return
                end
                constraint = definition.resizeConstraintFor(component.CreationArguments);
                if constraint == "fixedHeight"
                    % Slider-like controls reject height writes entirely.
                    target.Position(1:3) = value(1:3);
                    return
                elseif constraint == "aspectRatio"
                    % Preserve the control's runtime aspect ratio while moving/scaling it.
                    current = double(target.Position);
                    ratio = current(3) / max(current(4), eps);
                    value(4) = value(3) / max(ratio, eps);
                    target.Position = value;
                    return
                end
            end
            parts = split(path, ".");
            if isscalar(parts)
                target.(parts(1)) = value;
            elseif numel(parts) == 2
                target.(parts(1)).(parts(2)) = value;
            else
                error("macd:PreviewRenderer:UnsupportedPropertyPath", ...
                    "Preview property path ""%s"" is too deeply nested.", path);
            end
        end

        function position = parentInnerPosition(obj, parent)
            % parentInnerPosition Return the usable coordinate rectangle of a UI parent.
            arguments (Input)
                obj (1, 1) macd.ui.PreviewRenderer %#ok<INUSA>
                parent
            end
            arguments (Output)
                position (1, 4) double
            end

            % Use the inner dimensions; child Position values are always parent-local.
            if isprop(parent, "InnerPosition")
                position = double(parent.InnerPosition);
            else
                position = double(parent.Position);
            end
        end

        function result = usesPixelPosition(obj, target)
            % usesPixelPosition Report whether a target interprets Position in pixels.
            arguments (Input)
                obj (1, 1) macd.ui.PreviewRenderer %#ok<INUSA>
                target
            end
            arguments (Output)
                result (1, 1) logical
            end

            % UI controls without Units use pixel Position; normalized axes do not.
            result = isprop(target, "Position") && ...
                (~isprop(target, "Units") || string(target.Units) == "pixels");
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
