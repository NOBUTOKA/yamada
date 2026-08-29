classdef ComponentCatalogLoaderTest < matlab.unittest.TestCase
    % ComponentCatalogLoaderTest Verify strict JSON catalog loading and rejection.
    %   These tests create isolated temporary catalogs so loader validation proves
    %   its manifest-relative I/O, ordered group expansion, symbolic behavior
    %   checks, and fail-closed diagnostics without depending on the standard
    %   versioned runtime catalog and its strict validation boundary.

    methods (Test)
        function loadsOrderedGroupsAndStyleOverrides(testCase)
            % loadsOrderedGroupsAndStyleOverrides Build typed definitions from a valid fixture catalog.

            % Load one component whose property sequence mixes group and local entries.
            root = testCase.createCatalog();
            registry = macd.catalog.ComponentCatalogLoader.load(root);
            definition = registry.get("uilabel");
            testCase.verifyEqual(definition.Factory, "uilabel");
            testCase.verifyEqual(string({definition.Properties.Path}), ...
                ["Position", "Visible", "Text", "Layout.Row", "Layout.Column"]);
            testCase.verifyEqual(definition.SupportedStyles, "standard");
            testCase.verifyTrue(isfield(definition.Metadata, "StyleOverrides"));
            testCase.verifyTrue(isfield(definition.Metadata.StyleOverrides, "standard"));
            effective = registry.getEffectiveProperties("uilabel", "uigridlayout");
            testCase.verifyFalse(any(string({effective.Path}) == "Position"));
        end

        function rejectsUnknownFieldsWithCatalogContext(testCase)
            % rejectsUnknownFieldsWithCatalogContext Reject a manifest typo with its file path.

            % Mutate only the manifest after creating a known-valid temporary catalog.
            root = testCase.createCatalog();
            manifest = testCase.readJson(root, "catalog.json");
            manifest.unexpected = true;
            testCase.writeJson(root, "catalog.json", manifest);
            exception = testCase.verifyCatalogFailure(root);
            testCase.verifySubstring(string(exception.message), "catalog.json.unexpected");
        end

        function rejectsPropertyGroupCycles(testCase)
            % rejectsPropertyGroupCycles Reject recursive group expansion before registry creation.

            % Add a self-referential group and make the component depend on it.
            root = testCase.createCatalog();
            manifest = testCase.readJson(root, "catalog.json");
            manifest.propertyGroupFiles{end + 1} = "property-groups/cycle.json";
            testCase.writeJson(root, "catalog.json", manifest);
            testCase.writeJson(root, "property-groups/cycle.json", struct( ...
                "name", "cycle", "entries", {{struct("group", "cycle")} }));
            component = testCase.readJson(root, "components/uilabel.json");
            component.properties{1} = struct("group", "cycle");
            testCase.writeJson(root, "components/uilabel.json", component);
            exception = testCase.verifyCatalogFailure(root);
            testCase.verifySubstring(string(exception.message), "Property group cycle");
        end

        function rejectsUnknownBehaviorIdentifiers(testCase)
            % rejectsUnknownBehaviorIdentifiers Reject symbolic names outside the MATLAB allowlist.

            % Preserve valid shape while replacing one property editor token.
            root = testCase.createCatalog();
            component = testCase.readJson(root, "components/uilabel.json");
            component.properties{2}.metadata.editor = "arbitraryCode";
            testCase.writeJson(root, "components/uilabel.json", component);
            exception = testCase.verifyCatalogFailure(root);
            testCase.verifySubstring(string(exception.message), ".editor");
        end

        function loadsTypedInspectorPresentationMetadata(testCase)
            % loadsTypedInspectorPresentationMetadata Project JSON presentation metadata into definitions.

            % Annotate one fixture property with the metadata consumed by native rows.
            root = testCase.createCatalog();
            component = testCase.readJson(root, "components/uilabel.json");
            component.properties{2}.metadata.displayName = "Caption";
            component.properties{2}.metadata.category = "Content";
            component.properties{2}.metadata.order = 30;
            component.properties{2}.metadata.valueSchema = struct("kind", "string");
            component.properties{2}.metadata.applicableStyles = "standard";
            component.properties{2}.metadata.auditDisposition = "readOnly";
            testCase.writeJson(root, "components/uilabel.json", component);
            definition = macd.catalog.ComponentCatalogLoader.load(root).get("uilabel").Properties(3);
            testCase.verifyEqual(definition.DisplayName, "Caption");
            testCase.verifyEqual(definition.Category, "Content");
            testCase.verifyEqual(definition.Order, 30);
            testCase.verifyEqual(string(definition.ValueSchema.kind), "string");
            testCase.verifyEqual(definition.ApplicableStyles, "standard");
            testCase.verifyEqual(definition.AuditDisposition, "readOnly");
        end

        function rejectsInvalidInspectorPresentationMetadata(testCase)
            % rejectsInvalidInspectorPresentationMetadata Fail closed for invalid presentation shapes.

            % A display order must remain a scalar finite number in catalog JSON.
            root = testCase.createCatalog();
            component = testCase.readJson(root, "components/uilabel.json");
            component.properties{2}.metadata.order = [10, 20];
            testCase.writeJson(root, "components/uilabel.json", component);
            exception = testCase.verifyCatalogFailure(root);
            testCase.verifySubstring(string(exception.message), ".order");
        end

        function rejectsDuplicateExpandedProperties(testCase)
            % rejectsDuplicateExpandedProperties Reject duplicate paths after group expansion.

            % Repeat a common property locally so validation sees the effective sequence.
            root = testCase.createCatalog();
            component = testCase.readJson(root, "components/uilabel.json");
            component.properties{end + 1} = struct("path", "Position");
            testCase.writeJson(root, "components/uilabel.json", component);
            exception = testCase.verifyCatalogFailure(root);
            testCase.verifySubstring(string(exception.message), "Expanded property paths must be unique");
        end
    end

    methods (Access = private)
        function root = createCatalog(testCase)
            % createCatalog Create and schedule cleanup for one minimal valid catalog root.
            arguments (Input)
                testCase (1, 1) ComponentCatalogLoaderTest
            end
            arguments (Output)
                root (1, 1) string
            end

            % Keep every mutation inside a unique temporary test directory.
            root = string(tempname);
            mkdir(root);
            mkdir(fullfile(root, "property-groups"));
            mkdir(fullfile(root, "components"));
            testCase.addTeardown(@() rmdir(root, "s"));
            manifest = struct("schemaVersion", 1, "matlabRelease", "R2024a", ...
                "propertyGroupFiles", {{"property-groups/common.json", ...
                "property-groups/layout.json"}}, "parentContextRules", ...
                {{struct("parentFactories", {{"uigridlayout"}}, "kind", "grid")}}, "componentFiles", ...
                {{"components/uilabel.json"}});
            testCase.writeJson(root, "catalog.json", manifest);
            testCase.writeJson(root, "property-groups/common.json", struct( ...
                "name", "common", "entries", {{struct("path", "Position"), ...
                struct("path", "Visible")}}));
            testCase.writeJson(root, "property-groups/layout.json", struct( ...
                "name", "layout", "entries", {{struct("path", "Layout.Row"), ...
                struct("path", "Layout.Column")}}));
            component = struct("factory", "uilabel", ...
                "declaredType", "matlab.ui.control.Label", ...
                "allowedParentFactories", {{"uifigure"}}, "isRoot", false, ...
                "creationArguments", [], "properties", {{struct("group", "common"), ...
                struct("path", "Text", "metadata", struct("editor", "text", ...
                "validator", "none", "previewPolicy", "apply", "resetPolicy", "remove")), ...
                struct("group", "layout")}}, "capabilities", struct( ...
                "displayName", "Label", "category", "Common", ...
                "supportedStyles", {{"standard"}}, "defaultStyle", "standard", ...
                "declaredTypesByStyle", struct("standard", "matlab.ui.control.Label")), ...
                "styleOverrides", struct("standard", struct("addProperties", {{}}, ...
                "excludeProperties", {{}}, "overrides", struct())));
            testCase.writeJson(root, "components/uilabel.json", component);
        end

        function exception = verifyCatalogFailure(testCase, root)
            % verifyCatalogFailure Assert the common fail-closed catalog error identifier.
            arguments (Input)
                testCase (1, 1) ComponentCatalogLoaderTest
                root (1, 1) string
            end
            arguments (Output)
                exception (1, 1) MException
            end

            % Capture the exception so each test can verify its actionable context.
            try
                macd.catalog.ComponentCatalogLoader.load(root);
                testCase.assertFail("Expected catalog loading to fail.");
            catch exception
                testCase.verifyEqual(string(exception.identifier), ...
                    "macd:ComponentCatalogLoader:InvalidCatalog");
            end
        end

        function value = readJson(~, root, relativePath)
            % readJson Read one temporary test catalog document.
            arguments (Input)
                ~
                root (1, 1) string
                relativePath (1, 1) string
            end
            arguments (Output)
                value (1, 1) struct
            end

            % Test documents are generated by writeJson and therefore must decode cleanly.
            value = jsondecode(fileread(fullfile(root, relativePath)));
        end

        function writeJson(~, root, relativePath, value)
            % writeJson Write one temporary catalog document as UTF-8 JSON.
            arguments (Input)
                ~
                root (1, 1) string
                relativePath (1, 1) string
                value
            end

            % Keep test-only I/O local to the temporary fixture root.
            filePath = fullfile(root, relativePath);
            fileId = fopen(filePath, "w", "n", "UTF-8");
            cleanup = onCleanup(@() fclose(fileId));
            fprintf(fileId, "%s", jsonencode(value, PrettyPrint=true));
            clear cleanup
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
