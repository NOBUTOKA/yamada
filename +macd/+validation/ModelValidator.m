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
                definition = registry.get(component.Factory);
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

                % Report unknown paths without discarding their source data.
                supportedPaths = [definition.Properties.Path];
                for propertyIndex = 1:numel(component.Properties)
                    entry = component.Properties(propertyIndex);
                    if ~any(supportedPaths == entry.Path)
                        diagnostics(end + 1) = macd.model.Diagnostic( ...
                            "unsupported-property", "warning", ...
                            sprintf("Property ""%s"" is not editable for factory ""%s"".", ...
                            entry.Path, component.Factory), component.Id, entry.SourceSpan); %#ok<AGROW>
                    elseif entry.ValueKind == "expression" && entry.IsEditable
                        diagnostics(end + 1) = macd.validation.ModelValidator.error( ...
                            "editable-expression", ...
                            "Source expressions cannot be marked editable.", component.Id); %#ok<AGROW>
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
MatlabAppClassDesigner - Validation for shared document and component models.
Copyright (C) 2026 MatlabAppClassDesigner contributors

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
