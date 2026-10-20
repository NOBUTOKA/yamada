classdef PreviewRenderer < handle
    % PreviewRenderer Render registry-approved component models on an editor surface.
    %   This class creates only known factories from a DocumentModel and applies
    %   editable literal properties. It does not instantiate an opened AppBase
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
        RenderedRegistryRevision uint64 = uint64(0)
        RenderCount double = 0
        SynchronizationCount double = 0
        FallbackReason string = ""
    end

    methods
        function [applied, diagnostics, geometryChanged] = synchronize(obj, document, handles, request)
            % synchronize Apply audited label and numeric Value changes without replacing native handles.
            %   Any unrelated input change or uncertain setter uses the existing renderer.
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
            if request.Kind ~= "properties" || isempty(request.Paths) || numel(request.ComponentIds) ~= 1
                return
            end
            [inputs, safe] = document.evaluationContext(obj.Registry).inputs();
            if ~safe || isempty(fieldnames(obj.RenderedInputs)) || ...
                    obj.RenderedRegistryRevision ~= obj.Registry.Revision
                obj.FallbackReason = "untracked-inputs";
                return
            end
            if isequaln(inputs, obj.RenderedInputs)
                obj.FallbackReason = "";
                applied = true;
                return
            end
            before = obj.maskRequestedInputs(obj.RenderedInputs, request);
            after = obj.maskRequestedInputs(inputs, request);
            if ~isequaln(before, after)
                obj.FallbackReason = "unrelated-inputs";
                return
            end
            id = request.ComponentIds(1);
            component = document.getComponent(id);
            allowed = ["Text", "FontSize", "FontName", "FontWeight", "FontAngle", ...
                "FontColor", "BackgroundColor", "HorizontalAlignment", "VerticalAlignment", ...
                "WordWrap", "Visible", "Enable", "Tooltip"];
            if isempty(component) || ~isKey(handles, char(id)), return, end
            label = component.Factory == "uilabel" && all(ismember(request.Paths, allowed));
            numericValue = component.Factory == "uieditfield" && ...
                component.DeclaredType == "matlab.ui.control.NumericEditField" && isequal(request.Paths, "Value");
            if ~(label || numericValue), return, end
            preview = handles(char(id));
            if ~isvalid(preview)
                obj.FallbackReason = "stale-handle";
                return
            end
            if numericValue && ~isa(preview, "matlab.ui.control.NumericEditField")
                obj.FallbackReason = "native-type";
                return
            end
            states = document.getEffectivePropertyStates(obj.Registry, id);
            paths = string(arrayfun(@(item) item.Definition.Path, states));
            [found, indices] = ismember(request.Paths, paths);
            if ~all(found), return, end
            if numericValue
                % All non-requested inputs, including constraints, format, parent and constructor, must match.
                constraints = ["Value", "Limits", "AllowEmpty", "RoundFractionalValues", ...
                    "LowerLimitInclusive", "UpperLimitInclusive"];
                [known, constraintIndices] = ismember(constraints, paths);
                if ~all(known) || ~all(arrayfun(@(state) state.Resolution.IsKnown, states(constraintIndices)))
                    obj.FallbackReason = "unknown-constraints";
                    return
                end
            end
            for index = indices
                state = states(index);
                audited = label && state.Definition.Application.EffectStatus == "independent";
                if numericValue
                    value = state.Resolution.EffectiveValue;
                    audited = state.Definition.Application.EffectStatus == "modeled" && ...
                        state.Definition.Application.EffectPolicy == "numericValue" && ...
                        isa(value, "double") && isscalar(value) && isreal(value) && isfinite(value);
                end
                if ~audited || state.Definition.PreviewPolicy ~= "apply" || ~state.Resolution.IsKnown || ...
                        ~state.Resolution.IsEditable
                    obj.FallbackReason = "unsupported-effect";
                    return
                end
            end
            try
                for index = indices
                    state = states(index);
                    obj.setProperty(preview, state.Definition.Path, state.Resolution.EffectiveValue, component);
                end
            catch
                obj.FallbackReason = "native-setter";
                return
            end
            obj.RenderedInputs = inputs;
            obj.SynchronizationCount = obj.SynchronizationCount + 1;
            obj.FallbackReason = "";
            % Keep fit/layout publication conservative while reusing the native numeric widget.
            geometryChanged = request.affectsGeometry() || numericValue;
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
                "fallbackReason", obj.FallbackReason);
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
            if safe, obj.RenderedInputs = inputs; end
            obj.RenderedRegistryRevision = obj.Registry.Revision;
        end
    end

    properties (Access = private)
        Diagnostics macd.model.Diagnostic = macd.model.Diagnostic.empty
    end

    methods (Access = private)
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
                    component.Properties(ismember(string({component.Properties.Path}), request.Paths)) = [];
                end
                if ~isempty(component.Settings)
                    component.Settings(ismember(string({component.Settings.Path}), request.Paths)) = [];
                end
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
                imageSource = component.Factory == "uiimage" && entry.Path == "ImageSource";
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

            % Use the source figure size as the coordinate system for pixel children.
            sourceSize = [560 420];
            positionEntry = root.getProperty("Position");
            if ~isempty(positionEntry) && positionEntry.ValueKind == "literal" && ...
                    isnumeric(positionEntry.LiteralValue) && ...
                    numel(positionEntry.LiteralValue) == 4 && ...
                    all(positionEntry.LiteralValue(3:4) > 0)
                sourceSize = positionEntry.LiteralValue(3:4);
            end
            availablePosition = obj.parentInnerPosition(parent);
            frameSize = double(sourceSize) + 2;
            % Preserve a dark margin at every scroll limit, including the far edges.
            contentSize = max(double(availablePosition(3:4)), ...
                frameSize + 2 * obj.PreviewMargin);
            content = uipanel(parent, "BorderType", "none", ...
                "AutoResizeChildren", "off", ...
                "BackgroundColor", [0.35 0.36 0.38], ...
                "Position", [1 1 contentSize], ...
                "Tag", "macd-preview-scroll-content");
            frameOrigin = floor((contentSize - frameSize) ./ 2) + 1;
            frame = uipanel(content, "BorderType", "none", ...
                "AutoResizeChildren", "off", ...
                "BackgroundColor", [0.53 0.54 0.55], ...
                "Position", [frameOrigin frameSize], ...
                "Tag", "macd-preview-frame");
            obj.PreviewSurface = uipanel(frame, "BorderType", "none", ...
                "AutoResizeChildren", "off", ...
                "BackgroundColor", [0.94 0.94 0.94], ...
                "Position", [2 2 double(sourceSize)], ...
                "Tag", "macd-preview-canvas");
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
