classdef ComponentRegistryBaselineTest < matlab.unittest.TestCase
    % ComponentRegistryBaselineTest Verify promotion of the R2024a grouping catalog.
    %   This class compares every runtime concrete variant with the audited
    %   development ledger and checks that direct-parent projections remain
    %   deterministic. It replaces the obsolete Phase 4.5 subset baseline.

    methods (Test)
        function runtimeRegistryMatchesAuditedR2024aLedger(testCase)
            % runtimeRegistryMatchesAuditedR2024aLedger Compare every variant with the audited ledger.

            % Resolve the generated catalog through the production loader.
            registry = macd.model.ComponentRegistry.createDefault();
            documents = ComponentRegistryBaselineTest.ledgerDocuments();
            expectedIds = sort(string(cellfun(@(document) document.id, documents, "UniformOutput", false)));
            testCase.verifyEqual(registry.listVariantIds(), expectedIds);
            testCase.verifyEqual(numel(registry.listFactories()), 38);
            for documentIndex = 1:numel(documents)
                document = documents{documentIndex};
                definition = registry.getById(string(document.id));
                testCase.verifyEqual(definition.Factory, string(document.factory));
                testCase.verifyEqual(definition.DeclaredType, string(document.declaredType));
                testCase.verifyEqual(definition.CreationArguments, ...
                    ComponentRegistryBaselineTest.cellArguments(document.creationArguments));
                properties = ComponentRegistryBaselineTest.objectList(document.properties);
                expectedPaths = string(cellfun(@(property) property.path, properties, ...
                    "UniformOutput", false));
                testCase.verifyEqual(string({definition.Properties.Path}), expectedPaths);
                for propertyIndex = 1:numel(properties)
                    expected = properties{propertyIndex};
                    actual = definition.Properties(propertyIndex);
                    expectedEditor = string(expected.requiredEditor);
                    if expectedEditor == "none", expectedEditor = "readOnly"; end
                    testCase.verifyEqual(actual.Editor, expectedEditor);
                    testCase.verifyEqual(actual.AuditDisposition, string(expected.disposition.kind));
                    testCase.verifyEqual(string(actual.ValueSchema.kind), ...
                        string(expected.valueContract.kind));
                    if isfield(expected.valueContract, "values")
                        testCase.verifyTrue(isfield(actual.ValueSchema, "values"));
                        testCase.verifyEqual(string(actual.ValueSchema.values), ...
                            string(expected.valueContract.values));
                    else
                        testCase.verifyFalse(isfield(actual.ValueSchema, "values"));
                    end
                end
            end
        end

        function runtimeCatalogRetainsGroupingProvenance(testCase)
            % runtimeCatalogRetainsGroupingProvenance Verify runtime data names the reviewed grouping input.

            % Read raw JSON so the provenance check does not depend on registry details.
            root = macd.catalog.ComponentCatalogLoader.defaultCatalogRoot();
            manifest = jsondecode(fileread(fullfile(root, "catalog.json")));
            groups = jsondecode(fileread(fullfile(root, "property-groups", "groups.json")));
            profiles = jsondecode(fileread(fullfile(root, "order-profiles.json")));
            testCase.verifyEqual(manifest.schemaVersion, 2);
            testCase.verifyEqual(string(manifest.matlabRelease), "R2024a");
            testCase.verifyEqual(string(manifest.sourceGroupingSha256), string(groups.inputSha256));
            testCase.verifyEqual(numel(groups.groups), 313);
            testCase.verifyEqual(sort(string(manifest.orderProfileFiles)), "order-profiles.json");
            testCase.verifyEqual(sort(string({profiles.profiles.id})), ...
                ["axes", "contextMenu", "menuToolbar", "standardControl", "uifigure"]);
        end

        function figureCustomPointerShapesRemainOmitted(testCase)
            % figureCustomPointerShapesRemainOmitted Keep bitmap-pointer data outside the inspector catalog.

            % Retain the standard pointer choice while omitting its custom bitmap and hotspot.
            definition = macd.model.ComponentRegistry.createDefault().getById("uifigure");
            pointer = definition.Properties([definition.Properties.Path] == "Pointer");
            customShape = definition.Properties([definition.Properties.Path] == "PointerShapeCData");
            hotSpot = definition.Properties([definition.Properties.Path] == "PointerShapeHotSpot");
            testCase.verifyEqual(pointer.AuditDisposition, "editable");
            testCase.verifyEqual(pointer.Editor, "enum");
            testCase.verifyEqual(customShape.AuditDisposition, "omitted");
            testCase.verifyEqual(hotSpot.AuditDisposition, "omitted");
        end

        function innerPositionRemainsOmittedAcrossTheCatalog(testCase)
            % innerPositionRemainsOmittedAcrossTheCatalog Keep derived geometry out of the inspector.

            % Position is the editable design-time geometry surface for every variant.
            registry = macd.model.ComponentRegistry.createDefault();
            count = 0;
            for id = registry.listVariantIds()
                definition = registry.getById(id);
                matches = definition.Properties([definition.Properties.Path] == "InnerPosition");
                if isempty(matches)
                    continue
                end
                count = count + 1;
                testCase.verifyEqual(matches.AuditDisposition, "omitted");
            end
            testCase.verifyGreaterThan(count, 0);
        end

        function effectivePropertiesRemainUniqueForEveryConcreteVariant(testCase)
            % effectivePropertiesRemainUniqueForEveryConcreteVariant Check all direct-parent projections.

            % Resolve every allowed parent using the concrete variant's constructor arguments.
            registry = macd.model.ComponentRegistry.createDefault();
            for id = registry.listVariantIds()
                definition = registry.getById(id);
                parents = definition.AllowedParentFactories;
                if definition.IsRoot, parents = ""; end
                for parent = parents
                    effective = registry.getEffectiveProperties(definition.Factory, parent, ...
                        definition.CreationArguments);
                    paths = string({effective.Path});
                    testCase.verifyEqual(numel(paths), numel(unique(paths)));
                    if parent == "uigridlayout"
                        testCase.verifyFalse(any(paths == "Position"));
                        testCase.verifyTrue(all(ismember(["Layout.Row", "Layout.Column"], paths)));
                    end
                end
            end
        end
    end

    methods (Static, Access = private)
        function documents = ledgerDocuments()
            % ledgerDocuments Read the audited R2024a concrete component transcript.
            arguments (Output)
                documents cell
            end

            testPath = mfilename("fullpath");
            projectRoot = fileparts(fileparts(fileparts(testPath)));
            directory = fullfile(projectRoot, "dev", "component-data", "R2024a", "components");
            files = dir(fullfile(directory, "*.json"));
            documents = cell(1, numel(files));
            for index = 1:numel(files)
                documents{index} = jsondecode(fileread(fullfile(directory, files(index).name)));
            end
        end

        function result = cellArguments(value)
            % cellArguments Normalize JSON array values to catalog constructor cells.
            arguments (Input)
                value
            end
            arguments (Output)
                result cell
            end

            if isempty(value)
                result = {};
            elseif iscell(value)
                result = reshape(value, 1, []);
            else
                result = {value};
            end
        end

        function result = objectList(value)
            % objectList Normalize decoded JSON arrays whose members have optional fields.
            arguments (Input)
                value
            end
            arguments (Output)
                result cell
            end

            if iscell(value)
                result = reshape(value, 1, []);
            elseif isstruct(value)
                result = num2cell(reshape(value, 1, []));
            else
                error("ComponentRegistryBaselineTest:InvalidJsonArray", ...
                    "Expected a JSON object array.");
            end
        end

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
