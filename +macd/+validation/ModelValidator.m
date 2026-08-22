classdef ModelValidator
    % ModelValidator Validate shared AppBase document and component models.
    %   This static utility checks identifiers, hierarchy, registry support, and
    %   property edit safety. It reports structured diagnostics without mutating
    %   component values or generating source.

    methods (Static)
        function diagnostics = validate(document, registry)
            % validate Check names, hierarchy, registry support, and edit safety.
            arguments (Input)
                document (1, 1) macd.model.DocumentModel
                registry (1, 1) macd.model.ComponentRegistry
            end
            arguments (Output)
                diagnostics macd.model.Diagnostic
            end

            % Validate the class identity before traversing component records.
            diagnostics = macd.model.Diagnostic.empty;
            if ~isvarname(document.ClassName) || iskeyword(document.ClassName)
                diagnostics(end + 1) = macd.model.Diagnostic( ...
                    "invalid-class-name", "error", ...
                    sprintf("Class name ""%s"" is not a valid MATLAB identifier.", ...
                    document.ClassName));
            end

            % Track identities, names, and roots while validating each component.
            names = strings(1, 0);
            ids = strings(1, 0);
            roots = 0;
            for index = 1:numel(document.Components)
                component = document.Components(index);
                % Component identifiers and MATLAB property names must be unique.
                if any(ids == component.Id)
                    diagnostics(end + 1) = macd.validation.ModelValidator.error( ...
                        "duplicate-component-id", "Component IDs must be unique.", component.Id); %#ok<AGROW>
                end
                ids(end + 1) = component.Id; %#ok<AGROW>
                if ~isvarname(component.Name) || iskeyword(component.Name)
                    diagnostics(end + 1) = macd.validation.ModelValidator.error( ...
                        "invalid-component-name", ...
                        sprintf("Component name ""%s"" is not a valid MATLAB identifier.", ...
                        component.Name), component.Id); %#ok<AGROW>
                elseif any(names == component.Name)
                    diagnostics(end + 1) = macd.validation.ModelValidator.error( ...
                        "duplicate-component-name", ...
                        sprintf("Component name ""%s"" is duplicated.", component.Name), ...
                        component.Id); %#ok<AGROW>
                end
                names(end + 1) = component.Name; %#ok<AGROW>

                % Registry membership controls component-specific behavior.
                if ~registry.contains(component.Factory)
                    diagnostics(end + 1) = macd.validation.ModelValidator.error( ...
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
                        diagnostics(end + 1) = macd.validation.ModelValidator.error( ...
                            "invalid-root", "This component cannot be a root.", component.Id); %#ok<AGROW>
                    end
                else
                    parent = document.getComponent(component.ParentId);
                    if isempty(parent)
                        diagnostics(end + 1) = macd.validation.ModelValidator.error( ...
                            "missing-parent", "The parent component does not exist.", component.Id); %#ok<AGROW>
                    elseif ~any(definition.AllowedParentFactories == parent.Factory)
                        diagnostics(end + 1) = macd.validation.ModelValidator.error( ...
                            "invalid-parent", ...
                            sprintf("Factory ""%s"" cannot be parented by ""%s"".", ...
                            component.Factory, parent.Factory), component.Id); %#ok<AGROW>
                    end
                end

                % Resolve direct-parent applicability before reporting unknown paths.
                parentFactory = "";
                if strlength(component.ParentId) > 0 && ~isempty(parent)
                    parentFactory = parent.Factory;
                end
                effectiveProperties = registry.getEffectiveProperties(component.Factory, parentFactory, ...
                    component.CreationArguments);
                supportedPaths = [effectiveProperties.Path];
                transaction = macd.validation.ModelValidator.propertyTransaction( ...
                    component, effectiveProperties);
                for propertyIndex = 1:numel(component.Properties)
                    entry = component.Properties(propertyIndex);
                    if ~any(supportedPaths == entry.Path)
                        if macd.validation.ModelValidator.isNotRenderedFigureTool(component.Factory)
                            continue
                        end
                        diagnostics(end + 1) = macd.model.Diagnostic( ...
                            "unsupported-property", "warning", ...
                            sprintf("Property ""%s"" is not editable for factory ""%s"".", ...
                            entry.Path, component.Factory), component.Id, entry.SourceSpan); %#ok<AGROW>
                    elseif entry.ValueKind == "expression" && entry.IsEditable
                        diagnostics(end + 1) = macd.validation.ModelValidator.error( ...
                            "editable-expression", ...
                            "Source expressions cannot be marked editable.", component.Id); %#ok<AGROW>
                    elseif entry.ValueKind == "literal"
                        definition = effectiveProperties( ...
                            find(supportedPaths == entry.Path, 1));
                        if definition.IsEditable && definition.AuditDisposition == "editable"
                            transaction.stage(entry.Path, entry.LiteralValue);
                            message = macd.validation.PropertyBatchValidator.validate( ...
                                effectiveProperties, transaction);
                            if strlength(message) > 0
                                diagnostics(end + 1) = macd.validation.ModelValidator.error( ...
                                    "invalid-catalog-property", message, component.Id); %#ok<AGROW>
                            end
                        end
                        geometryDiagnostic = macd.validation.ModelValidator.validateGeometry( ...
                            entry, component.Id);
                        if ~isempty(geometryDiagnostic)
                            diagnostics(end + 1) = geometryDiagnostic; %#ok<AGROW>
                        end
                    end
                end
            end

            % Require one resolvable registered root for every app document.
            if roots ~= 1 || strlength(document.RootComponentId) == 0 || ...
                    isempty(document.getComponent(document.RootComponentId))
                diagnostics(end + 1) = macd.model.Diagnostic( ...
                    "invalid-root-count", "error", ...
                    "A document must have exactly one registered root component.");
            end
            % Publish diagnostics for editor and generator consumers.
            document.Diagnostics = diagnostics;
        end

        function result = hasErrors(diagnostics)
            % hasErrors Return true when any diagnostic has error severity.
            arguments (Input)
                diagnostics macd.model.Diagnostic
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

    methods (Static, Access = private)
        function transaction = propertyTransaction(component, definitions)
            % propertyTransaction Snapshot literal effective values for shared schema validation.
            arguments (Input)
                component (1, 1) macd.model.ComponentRecord
                definitions macd.model.PropertyDefinition
            end
            arguments (Output)
                transaction (1, 1) macd.model.PropertyTransaction
            end

            paths = string({definitions.Path});
            values = cell(1, numel(definitions));
            known = false(1, numel(definitions));
            for index = 1:numel(definitions)
                entry = component.getProperty(paths(index));
                if ~isempty(entry) && entry.ValueKind == "literal"
                    values{index} = entry.LiteralValue;
                    known(index) = true;
                end
            end
            transaction = macd.model.PropertyTransaction(paths, values, known);
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

        function diagnostic = validateGeometry(entry, componentId)
            % validateGeometry Check literal Position and grid coordinates.
            arguments (Input)
                entry (1, 1) macd.model.PropertyEntry
                componentId string
            end
            arguments (Output)
                diagnostic macd.model.Diagnostic
            end

            diagnostic = macd.model.Diagnostic.empty;
            value = entry.LiteralValue;
            if entry.Path == "Position"
                if ~isnumeric(value) || ~isequal(size(value), [1 4]) || ...
                        any(~isfinite(value)) || any(value(3:4) <= 0)
                    diagnostic = macd.validation.ModelValidator.error( ...
                        "invalid-position", ...
                        "Position must be a finite numeric 1-by-4 value with positive size.", ...
                        componentId);
                end
            elseif any(entry.Path == ["Layout.Row", "Layout.Column"])
                if ~isnumeric(value) || ~isvector(value) || isempty(value) || ...
                        numel(value) > 2 || any(~isfinite(value)) || ...
                        any(value < 1) || any(value ~= floor(value))
                    diagnostic = macd.validation.ModelValidator.error( ...
                        "invalid-grid-coordinate", ...
                        "Grid row and column values must be positive integer scalars or spans.", ...
                        componentId);
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
                diagnostic (1, 1) macd.model.Diagnostic
            end

            diagnostic = macd.model.Diagnostic( ...
                code, "error", message, componentId);
        end
    end
end

%{
Copyright (C) 2026 Nobuto Kaitoh

This file is part of MatlabAppClassDesigner.

MatlabAppClassDesigner is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

MatlabAppClassDesigner is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with MatlabAppClassDesigner. If not, see <https://www.gnu.org/licenses/>.
%}
