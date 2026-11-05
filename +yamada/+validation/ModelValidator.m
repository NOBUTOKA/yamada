classdef ModelValidator
    % ModelValidator Validate shared handle-based document and component models.
    %   This static utility checks identifiers, hierarchy, registry support, and
    %   property edit safety. It reports structured diagnostics without mutating
    %   component values or generating source.

    methods (Static)
        function [diagnostics, validatedIds] = validate(document, registry, propertyNames)
            % validate Check names, hierarchy, registry support, and edit safety.
            %   Optional property names bound state checks; structural checks remain document-wide.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                registry (1, 1) yamada.model.ComponentRegistry
                propertyNames (1, :) string = strings(1, 0)
            end
            arguments (Output)
                diagnostics yamada.model.Diagnostic
                validatedIds (1, :) string
            end

            % Validate the class identity before traversing component records.
            evaluationScope = document.evaluationContext(registry).readScope(); %#ok<NASGU>
            diagnostics = yamada.model.Diagnostic.empty;
            if ~isvarname(document.ClassName) || iskeyword(document.ClassName)
                diagnostics(end + 1) = yamada.model.Diagnostic( ...
                    "invalid-class-name", "error", ...
                    sprintf("Class name ""%s"" is not a valid MATLAB identifier.", ...
                    document.ClassName));
            end

            % Track identities, names, and roots while validating each component.
            propertyNames = yamada.validation.ModelValidator.propertyScope(document, propertyNames);
            selected = document.Components;
            if ~isempty(propertyNames), selected = selected(ismember(string({selected.Name}), propertyNames)); end
            validatedIds = reshape(string({selected.Id}), 1, []);
            names = strings(1, 0);
            ids = strings(1, 0);
            roots = 0;
            for index = 1:numel(document.Components)
                component = document.Components(index);
                % Component identifiers and MATLAB property names must be unique.
                if any(ids == component.Id)
                    diagnostics(end + 1) = yamada.validation.ModelValidator.error( ...
                        "duplicate-component-id", "Component IDs must be unique.", component.Id); %#ok<AGROW>
                end
                ids(end + 1) = component.Id; %#ok<AGROW>
                if ~isvarname(component.Name) || iskeyword(component.Name)
                    diagnostics(end + 1) = yamada.validation.ModelValidator.error( ...
                        "invalid-component-name", ...
                        sprintf("Component name ""%s"" is not a valid MATLAB identifier.", ...
                        component.Name), component.Id); %#ok<AGROW>
                elseif any(names == component.Name)
                    diagnostics(end + 1) = yamada.validation.ModelValidator.error( ...
                        "duplicate-component-name", ...
                        sprintf("Component name ""%s"" is duplicated.", component.Name), ...
                        component.Id); %#ok<AGROW>
                end
                names(end + 1) = component.Name; %#ok<AGROW>

                % Native groups accept one mutually exclusive child family at a time.
                if component.Factory == "uibuttongroup"
                    children = document.Components(string({document.Components.ParentId}) == component.Id & ...
                        ismember(string({document.Components.Factory}), ["uiradiobutton", "uitogglebutton"]));
                    if numel(unique(string({children.Factory}))) > 1
                        diagnostics(end + 1) = yamada.validation.ModelValidator.error( ...
                            "mixed-button-group", "RadioButton and ToggleButton cannot share one ButtonGroup.", component.Id); %#ok<AGROW>
                    end
                end
                % Registry membership controls component-specific behavior.
                if ~registry.contains(component.Factory)
                    diagnostics(end + 1) = yamada.validation.ModelValidator.error( ...
                        "unsupported-factory", ...
                        sprintf("Factory ""%s"" is not registered.", component.Factory), ...
                        component.Id); %#ok<AGROW>
                    continue
                end
                definition = registry.get(component.Factory, component.CreationArguments);
                % Resolve and validate the component's hierarchy location.
                if strlength(component.ParentId) == 0
                    roots = roots + 1;
                    if ~definition.IsRoot
                        diagnostics(end + 1) = yamada.validation.ModelValidator.error( ...
                            "invalid-root", "This component cannot be a root.", component.Id); %#ok<AGROW>
                    end
                else
                    parent = document.getComponent(component.ParentId);
                    if isempty(parent)
                        diagnostics(end + 1) = yamada.validation.ModelValidator.error( ...
                            "missing-parent", "The parent component does not exist.", component.Id); %#ok<AGROW>
                    elseif ~any(definition.AllowedParentFactories == parent.Factory)
                        diagnostics(end + 1) = yamada.validation.ModelValidator.error( ...
                            "invalid-parent", ...
                            sprintf("Factory ""%s"" cannot be parented by ""%s"".", ...
                            component.Factory, parent.Factory), component.Id); %#ok<AGROW>
                    end
                end

                % Retain global structural checks while bounding property-state evaluation.
                if ~isempty(propertyNames) && ~any(propertyNames == component.Name), continue, end
                % Resolve direct-parent applicability before reporting unknown paths.
                parentFactory = "";
                if strlength(component.ParentId) > 0 && ~isempty(parent)
                    parentFactory = parent.Factory;
                end
                effectiveProperties = registry.getEffectiveProperties(component.Factory, parentFactory, ...
                    component.CreationArguments);
                supportedPaths = [effectiveProperties.Path];
                [transaction, resolved, stateDiagnostics] = yamada.validation.ModelValidator.propertyTransaction( ...
                    component, effectiveProperties, document, registry);
                diagnostics = [diagnostics stateDiagnostics]; %#ok<AGROW>
                for propertyIndex = 1:numel(component.Properties)
                    entry = component.Properties(propertyIndex);
                    if ~any(supportedPaths == entry.Path)
                        if yamada.validation.ModelValidator.isNotRenderedFigureTool(component.Factory)
                            continue
                        end
                        diagnostics(end + 1) = yamada.model.Diagnostic( ...
                            "unsupported-property", "warning", ...
                            sprintf("Property ""%s"" is not editable for factory ""%s"".", ...
                            entry.Path, component.Factory), component.Id, entry.SourceSpan); %#ok<AGROW>
                    elseif entry.ValueKind == "expression" && entry.IsEditable
                        diagnostics(end + 1) = yamada.validation.ModelValidator.error( ...
                            "editable-expression", ...
                            "Source expressions cannot be marked editable.", component.Id); %#ok<AGROW>
                    elseif entry.ValueKind == "literal"
                        definition = effectiveProperties( ...
                            find(supportedPaths == entry.Path, 1));
                        state = resolved(find(supportedPaths == entry.Path, 1));
                        if definition.IsEditable && definition.AuditDisposition == "editable" && state.IsKnown
                            transaction.stage(entry.Path, state.EffectiveValue);
                            message = yamada.validation.PropertyBatchValidator.validate( ...
                                effectiveProperties, transaction);
                            if strlength(message) > 0
                                diagnostics(end + 1) = yamada.validation.ModelValidator.error( ...
                                    "invalid-catalog-property", message, component.Id); %#ok<AGROW>
                            end
                        end
                        geometryDiagnostic = yamada.validation.ModelValidator.validateGeometry( ...
                            entry, component.Id, component.Factory, definition);
                        if ~isempty(geometryDiagnostic)
                            diagnostics(end + 1) = geometryDiagnostic; %#ok<AGROW>
                        end
                    end
                end
            end

            % Require one resolvable registered root for every app document.
            if roots ~= 1 || strlength(document.RootComponentId) == 0 || ...
                    isempty(document.getComponent(document.RootComponentId))
                diagnostics(end + 1) = yamada.model.Diagnostic( ...
                    "invalid-root-count", "error", ...
                    "A document must have exactly one registered root component.");
            end
            % Publish diagnostics for editor and generator consumers.
            document.Diagnostics = diagnostics;
        end

        function result = hasErrors(diagnostics)
            % hasErrors Return true when any diagnostic has error severity.
            arguments (Input)
                diagnostics yamada.model.Diagnostic
            end
            arguments (Output)
                result (1, 1) logical
            end

            % Stop at the first blocking diagnostic.
            result = false;
            for index = 1:numel(diagnostics)
                if diagnostics(index).isError()
                    result = true;
                    return
                end
            end
        end
    end

    methods (Static, Access = ?yamada.model.DocumentModel)
        function result = prepareIndependentProperties(component, definitions, states, previous, paths, diagnostics, batch)
            % prepareIndependentProperties Complete unaffected effective states and validate only the proven changed closure.
            arguments (Input)
                component (1, 1) yamada.model.ComponentRecord
                definitions yamada.model.PropertyDefinition
                states yamada.model.PropertyState
                previous yamada.model.PropertyState
                paths (1, :) string
                diagnostics yamada.model.Diagnostic
                batch (1, 1) yamada.source.SourcePatchBatch
            end
            arguments (Output)
                result (1, 1) struct
            end
            result = struct("Ready", false);
            if numel(states) ~= numel(previous) || ...
                    ~isequal(string({states.Path}), string({previous.Path})) || ...
                    any(string({diagnostics.ComponentId}) == component.Id)
                return
            end
            affected = paths;
            for path = paths
                definition = definitions([definitions.Path] == path);
                affected = union(affected, definition.Application.AffectedPaths, "stable");
            end
            % A finite owner-local setter can change followers without adding explicit source settings.
            % Compare already-resolved local results; retain document-dependent states from the proven baseline.
            localPaths = yamada.model.PropertyStateResolver.ownerLocalPaths(definitions);
            for index = find(ismember(string({states.Path}), localPaths))
                current = states(index); old = previous(index);
                if current.IsKnown ~= old.IsKnown || current.IsEditable ~= old.IsEditable || ...
                        ~isequaln(current.EffectiveValue, old.EffectiveValue) || current.EffectKey ~= old.EffectKey || ...
                        current.ReadOnlyReason ~= old.ReadOnlyReason
                    affected = union(affected, current.Path, "stable");
                end
            end
            dependent = [yamada.model.GridLayoutStatePolicy.inputPropertyPaths(), ...
                yamada.model.AncestorGeometryPolicy.inputPropertyPaths()];
            if any(ismember(affected, dependent)), return, end
            for index = 1:numel(states)
                if any(affected == states(index).Path), continue, end
                old = previous(index);
                states(index) = states(index).withEffective(old.EffectiveValue, old.IsKnown, ...
                    old.EffectKey, old.Reason, old.ReasonCode);
                if ~old.IsEditable, states(index) = states(index).withReadOnly(old.ReadOnlyReason); end
            end
            % The baseline validated every other property and document structure already.
            transaction = yamada.model.PropertyStateResolver.transaction(states);
            for entry = component.Properties
                if ~any(affected == entry.Path), continue, end
                index = find([definitions.Path] == entry.Path, 1);
                if isempty(index) || entry.ValueKind ~= "literal", return, end
                state = states(index);
                requested = any(paths == entry.Path);
                if requested && (~state.IsKnown || ~state.IsEditable), return, end
                if state.IsKnown && definitions(index).IsEditable && definitions(index).AuditDisposition == "editable"
                    value = state.EffectiveValue;
                    if requested, value = entry.LiteralValue; end
                    transaction.stage(entry.Path, value);
                end
                diagnostic = yamada.validation.ModelValidator.validateGeometry(entry, component.Id, component.Factory, definitions(index));
                assert(isempty(diagnostic), "yamada:SourceLiteralTransaction:InvalidValue", ...
                    "The prepared geometry must satisfy the existing model contract.");
            end
            message = yamada.validation.PropertyBatchValidator.validate(definitions, transaction);
            assert(strlength(message) == 0, "yamada:SourceLiteralTransaction:InvalidValue", "%s", message);
            diagnostics = yamada.model.SourceLocationUpdate.relocateDiagnostics(diagnostics, batch);
            result = struct("Ready", true, "States", states, "Definitions", definitions, ...
                "StateDiagnostics", yamada.model.Diagnostic.empty, "Diagnostics", diagnostics);
        end
    end

    methods (Static, Access = private)
        function names = propertyScope(document, requested)
            % propertyScope Include target descendants and ancestors without expanding unrelated sibling branches.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                requested (1, :) string
            end
            arguments (Output)
                names (1, :) string
            end
            names = strings(1, 0);
            if isempty(requested), return, end
            records = document.Components;
            if ~all(ismember(requested, string({records.Name}))), return, end
            targets = records(ismember(string({records.Name}), requested));
            pending = string({targets.Id});
            visited = strings(1, 0);
            while ~isempty(pending)
                id = pending(1); pending(1) = [];
                if any(visited == id), continue, end
                visited(end + 1) = id; %#ok<AGROW>
                record = document.getComponent(id);
                if isempty(record), continue, end
                names(end + 1) = record.Name; %#ok<AGROW>
                pending = [pending reshape(record.Children, 1, [])]; %#ok<AGROW>
            end
            pending = string({targets.ParentId});
            while ~isempty(pending)
                id = pending(1); pending(1) = [];
                if strlength(id) == 0 || any(visited == id), continue, end
                visited(end + 1) = id; %#ok<AGROW>
                record = document.getComponent(id);
                if isempty(record), continue, end
                names(end + 1) = record.Name; %#ok<AGROW>
                pending(end + 1) = record.ParentId; %#ok<AGROW>
            end
            names = unique(names, "stable");
        end

        function [transaction, states, diagnostics] = propertyTransaction(component, definitions, document, registry)
            % propertyTransaction Resolve audited state before validating the current values.
            arguments (Input)
                component (1, 1) yamada.model.ComponentRecord
                definitions yamada.model.PropertyDefinition
                document (1, 1) yamada.model.DocumentModel
                registry (1, 1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                transaction (1, 1) yamada.model.PropertyTransaction
                states yamada.model.PropertyState
                diagnostics yamada.model.Diagnostic
            end

            [states, diagnostics] = yamada.model.PropertyStateResolver.resolve(component, definitions, document, registry);
            transaction = yamada.model.PropertyStateResolver.transaction(states);
        end

        function result = isNotRenderedFigureTool(factory)
            % isNotRenderedFigureTool Identify Figure Tools intentionally outside preview scope.
            arguments (Input)
                factory (1, 1) string
            end
            arguments (Output)
                result (1, 1) logical
            end

            result = any(factory == ["uicontextmenu", "uimenu", "uitoolbar", ...
                "uipushtool", "uitoggletool"]);
        end

        function diagnostic = validateGeometry(entry, componentId, factory, definition)
            % validateGeometry Check literal Position and grid coordinates.
            arguments (Input)
                entry (1, 1) yamada.model.PropertyEntry
                componentId string
                factory (1, 1) string
                definition (1, 1) yamada.model.PropertyDefinition
            end
            arguments (Output)
                diagnostic yamada.model.Diagnostic
            end

            diagnostic = yamada.model.Diagnostic.empty;
            value = entry.LiteralValue;
            if entry.Path == "Position"
                % Reviewed aliases have native support for zero-sized controls.
                zeroAllowed = yamada.model.PositionAliasPolicy.applies(definition);
                sizeRequirement = "positive";
                if zeroAllowed, sizeRequirement = "nonnegative"; end
                if ~isnumeric(value) || ~isreal(value) || ~isequal(size(value), [1 4]) || ...
                        any(~isfinite(value)) || any(value(3:4) < 0) || (~zeroAllowed && any(value(3:4) == 0))
                    diagnostic = yamada.validation.ModelValidator.error( ...
                        "invalid-position", ...
                        "Position must be a finite real numeric 1-by-4 value with " + sizeRequirement + " size.", ...
                        componentId);
                end
            elseif any(entry.Path == ["Layout.Row", "Layout.Column"])
                if ~isnumeric(value) || ~isvector(value) || isempty(value) || ...
                    numel(value) > 2 || any(~isfinite(value)) || ...
                        any(value < 1) || any(value ~= floor(value))
                    diagnostic = yamada.validation.ModelValidator.error( ...
                        "invalid-grid-coordinate", ...
                        "Grid row and column values must be positive integer scalars or spans.", ...
                        componentId);
                end
            elseif factory == "uigridlayout" && any(entry.Path == ["RowHeight", "ColumnWidth"])
                message = yamada.model.GridTrackList.validate(value);
                if strlength(message) > 0
                    diagnostic = yamada.validation.ModelValidator.error( ...
                        "invalid-grid-track-list", message, componentId);
                end
            end
        end

        function diagnostic = error(code, message, componentId)
            % error Create a component-scoped blocking diagnostic.
            arguments (Input)
                code string
                message string
                componentId string
            end
            arguments (Output)
                diagnostic (1, 1) yamada.model.Diagnostic
            end

            diagnostic = yamada.model.Diagnostic( ...
                code, "error", message, componentId);
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
