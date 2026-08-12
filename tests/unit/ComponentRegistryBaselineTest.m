classdef ComponentRegistryBaselineTest < matlab.unittest.TestCase
    % ComponentRegistryBaselineTest Freeze and verify the Phase 4.5 registry contract.
    %   This class projects the runtime registry into a deterministic JSON document
    %   and compares it with the reviewed Phase 4.5 baseline. The projection is
    %   intentionally independent of containers.Map and structure field ordering.

    methods (Test)
        function defaultRegistryMatchesFrozenPhase45Baseline(testCase)
            % defaultRegistryMatchesFrozenPhase45Baseline Compare the runtime registry with the baseline.

            % Build the public registry and compare its canonical projection.
            registry = macd.model.ComponentRegistry.createDefault();
            actual = ComponentRegistryBaselineTest.canonicalJson(registry);
            expected = ComponentRegistryBaselineTest.readBaseline();
            testCase.verifyEqual(actual, expected);
        end

        function frozenBaselineIsValidJson(testCase)
            % frozenBaselineIsValidJson Verify that the reviewed fixture remains parseable JSON.

            % Parse the fixture independently so textual comparison cannot mask damage.
            baseline = jsondecode(ComponentRegistryBaselineTest.readBaseline());
            testCase.verifyEqual(baseline.SchemaVersion, 1);
            testCase.verifyNotEmpty(baseline.Definitions);
        end

        function effectivePropertiesMatchFrozenPhase45Baseline(testCase)
            % effectivePropertiesMatchFrozenPhase45Baseline Compare every allowed direct-parent surface.

            % Verify context composition independently from intrinsic definitions.
            registry = macd.model.ComponentRegistry.createDefault();
            actual = ComponentRegistryBaselineTest.canonicalEffectiveJson(registry);
            expected = ComponentRegistryBaselineTest.readEffectiveBaseline();
            testCase.verifyEqual(actual, expected);
        end
    end

    methods (Static, Access = private)
        function text = canonicalJson(registry)
            % canonicalJson Return a deterministic JSON projection of one registry.
            arguments (Input)
                registry (1, 1) macd.model.ComponentRegistry
            end
            arguments (Output)
                text (1, 1) string
            end

            % Project sorted definitions into a fixed field order before encoding.
            factories = registry.listFactories();
            definitions = repmat(ComponentRegistryBaselineTest.emptyDefinition(), ...
                numel(factories), 1);
            for index = 1:numel(factories)
                definitions(index) = ComponentRegistryBaselineTest.definitionProjection( ...
                    registry.get(factories(index)));
            end
            document = struct();
            document.SchemaVersion = 1;
            document.Definitions = definitions;
            text = string(jsonencode(document, PrettyPrint=true));
            text = ComponentRegistryBaselineTest.normalizedLineEndings(text);
        end

        function text = readBaseline()
            % readBaseline Read the Phase 4.5 baseline using normalized line endings.
            arguments (Output)
                text (1, 1) string
            end

            % Resolve the fixture relative to this test rather than the current folder.
            testPath = mfilename("fullpath");
            projectRoot = fileparts(fileparts(fileparts(testPath)));
            fixturePath = fullfile(projectRoot, "tests", "fixtures", ...
                "componentCatalog", "phase45-registry-baseline.json");
            text = ComponentRegistryBaselineTest.normalizedLineEndings( ...
                string(fileread(fixturePath)));
        end

        function result = definitionProjection(definition)
            % definitionProjection Convert one typed definition into fixed JSON fields.
            arguments (Input)
                definition (1, 1) macd.model.ComponentDefinition
            end
            arguments (Output)
                result (1, 1) struct
            end

            % Preserve all Phase 4.5 catalog data while normalizing container order.
            result = ComponentRegistryBaselineTest.emptyDefinition();
            result.Factory = char(definition.Factory);
            result.DeclaredType = char(definition.DeclaredType);
            result.AllowedParentFactories = cellstr(definition.AllowedParentFactories(:));
            result.IsRoot = definition.IsRoot;
            result.CreationArguments = ComponentRegistryBaselineTest.canonicalValue( ...
                definition.CreationArguments);
            result.Properties = ComponentRegistryBaselineTest.propertyProjection( ...
                definition.Properties);
            result.DisplayName = char(definition.DisplayName);
            result.Category = char(definition.Category);
            result.IsProgrammaticOnly = definition.IsProgrammaticOnly;
            result.RequiresParentComponent = definition.RequiresParentComponent;
            result.SupportedStyles = cellstr(definition.SupportedStyles(:));
            result.DefaultStyle = char(definition.DefaultStyle);
            result.DeclaredTypesByStyle = ComponentRegistryBaselineTest.canonicalValue( ...
                definition.DeclaredTypesByStyle);
            result.OverlayShape = char(definition.OverlayShape);
            result.OverlayShapesByStyle = ComponentRegistryBaselineTest.canonicalValue( ...
                definition.OverlayShapesByStyle);
            result.ResizeConstraint = char(definition.ResizeConstraint);
            result.ResizeConstraintsByStyle = ComponentRegistryBaselineTest.canonicalValue( ...
                definition.ResizeConstraintsByStyle);
            result.Metadata = ComponentRegistryBaselineTest.canonicalValue( ...
                definition.Metadata);
        end

        function result = propertyProjection(properties)
            % propertyProjection Convert ordered property capabilities into fixed JSON fields.
            arguments (Input)
                properties macd.model.PropertyDefinition
            end
            arguments (Output)
                result (:, 1) struct
            end

            % Keep definition order because it is part of the registry contract.
            result = repmat(ComponentRegistryBaselineTest.emptyProperty(), ...
                numel(properties), 1);
            for index = 1:numel(properties)
                property = properties(index);
                result(index).Path = char(property.Path);
                result(index).DefaultValue = ComponentRegistryBaselineTest.canonicalValue( ...
                    property.DefaultValue);
                result(index).HasDefault = property.HasDefault;
                result(index).IsEditable = property.IsEditable;
                % Inspector metadata is a Phase 6 extension, not Phase 4.5 behavior.
                result(index).Metadata = struct();
            end
        end

        function result = canonicalValue(value)
            % canonicalValue Normalize cells and structures without changing scalar values.
            arguments (Input)
                value
            end
            arguments (Output)
                result
            end

            % Sort all structure fields recursively to remove incidental field order.
            if isstruct(value)
                fieldNames = sort(string(fieldnames(value)));
                result = orderfields(value, cellstr(fieldNames));
                for elementIndex = 1:numel(result)
                    for fieldIndex = 1:numel(fieldNames)
                        fieldName = char(fieldNames(fieldIndex));
                        result(elementIndex).(fieldName) = ...
                            ComponentRegistryBaselineTest.canonicalValue( ...
                            result(elementIndex).(fieldName));
                    end
                end
            elseif iscell(value)
                result = cell(size(value));
                for index = 1:numel(value)
                    result{index} = ComponentRegistryBaselineTest.canonicalValue(value{index});
                end
            else
                result = value;
            end
        end

        function result = emptyDefinition()
            % emptyDefinition Return the fixed field layout for a projected definition.
            arguments (Output)
                result (1, 1) struct
            end

            % Construct fields in the reviewed JSON order.
            result = struct("Factory", "", "DeclaredType", "", ...
                "AllowedParentFactories", {{}}, "IsRoot", false, ...
                "CreationArguments", {{}}, "Properties", ...
                ComponentRegistryBaselineTest.emptyProperty(), ...
                "DisplayName", "", "Category", "", ...
                "IsProgrammaticOnly", false, "RequiresParentComponent", false, ...
                "SupportedStyles", {{}}, "DefaultStyle", "", ...
                "DeclaredTypesByStyle", struct(), "OverlayShape", "", ...
                "OverlayShapesByStyle", struct(), "ResizeConstraint", "", ...
                "ResizeConstraintsByStyle", struct(), "Metadata", struct());
        end

        function result = emptyProperty()
            % emptyProperty Return the fixed field layout for a projected property.
            arguments (Output)
                result (1, 1) struct
            end

            % Construct fields in the reviewed JSON order.
            result = struct("Path", "", "DefaultValue", [], "HasDefault", false, ...
                "IsEditable", true, "Metadata", struct());
        end

        function text = canonicalEffectiveJson(registry)
            % canonicalEffectiveJson Return direct-parent property projections in fixed JSON order.
            arguments (Input)
                registry (1, 1) macd.model.ComponentRegistry
            end
            arguments (Output)
                text (1, 1) string
            end

            % Project every supported direct parent so parent rules cannot drift silently.
            factories = registry.listFactories();
            projections = repmat(ComponentRegistryBaselineTest.emptyEffectiveProjection(), 0, 1);
            for factoryIndex = 1:numel(factories)
                definition = registry.get(factories(factoryIndex));
                parents = definition.AllowedParentFactories;
                if definition.IsRoot
                    parents = "";
                end
                for parentIndex = 1:numel(parents)
                    projection = ComponentRegistryBaselineTest.emptyEffectiveProjection();
                    projection.Factory = char(definition.Factory);
                    projection.ParentFactory = char(parents(parentIndex));
                    projection.Properties = ComponentRegistryBaselineTest.propertyProjection( ...
                        registry.getEffectiveProperties(definition.Factory, parents(parentIndex)));
                    projections(end + 1, 1) = projection; %#ok<AGROW>
                end
            end
            document = struct("SchemaVersion", 1, "Projections", projections);
            text = string(jsonencode(document, PrettyPrint=true));
            text = ComponentRegistryBaselineTest.normalizedLineEndings(text);
        end

        function text = readEffectiveBaseline()
            % readEffectiveBaseline Read the frozen direct-parent property projection fixture.
            arguments (Output)
                text (1, 1) string
            end

            % Resolve the companion fixture relative to this unit test class.
            testPath = mfilename("fullpath");
            projectRoot = fileparts(fileparts(fileparts(testPath)));
            fixturePath = fullfile(projectRoot, "tests", "fixtures", ...
                "componentCatalog", "phase45-effective-properties-baseline.json");
            text = ComponentRegistryBaselineTest.normalizedLineEndings( ...
                string(fileread(fixturePath)));
        end

        function result = emptyEffectiveProjection()
            % emptyEffectiveProjection Return the fixed layout for one parent projection.
            arguments (Output)
                result (1, 1) struct
            end

            % Construct fields in the reviewed JSON order.
            result = struct("Factory", "", "ParentFactory", "", ...
                "Properties", ComponentRegistryBaselineTest.emptyProperty());
        end
        function text = normalizedLineEndings(text)
            % normalizedLineEndings Compare fixture text independently of checkout line endings.
            arguments (Input)
                text (1, 1) string
            end
            arguments (Output)
                text (1, 1) string
            end

            % JSON encoding uses LF while fixtures retain project CRLF conventions.
            text = replace(text, "\r\n", newline);
            text = replace(text, "\r", newline);
        end
    end
end

%{
MatlabAppClassDesigner - Frozen Phase 4.5 component registry baseline tests.
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
