classdef (TestTags = {'catalog'}) ComponentRegistryBaselineTest < matlab.unittest.TestCase
    % ComponentRegistryBaselineTest Verify promotion of the R2024a grouping catalog.
    %   This class compares every runtime concrete variant with the audited
    %   development ledger and checks that direct-parent projections remain
    %   deterministic across the complete audited R2024a catalog.

    methods (Test, TestTags = {'fast'})
        function cachedParentProjectionIsInvalidatedByRulesAndRegistration(testCase)
            % cachedParentProjectionIsInvalidatedByRulesAndRegistration Observe changes after a cache hit.
            registry = yamada.model.ComponentRegistry.createDefault();
            first = registry.getEffectiveProperties("uilabel", "uigridlayout");
            testCase.verifyTrue(any(string({first.Path}) == "Layout.Row"));
            testCase.verifyEqual(registry.getEffectiveProperties("uilabel", "uigridlayout"), first);
            registry.setParentContextRules(yamada.model.ParentContextRule.empty);
            plain = registry.getEffectiveProperties("uilabel", "uigridlayout");
            testCase.verifyFalse(any(string({plain.Path}) == "Layout.Row"));
            replacement = yamada.model.ComponentDefinition("uilabel", "matlab.ui.control.Label", ...
                "uifigure", false, {}, yamada.model.PropertyDefinition("Custom", 7, true, true));
            registry.register(replacement);
            replaced = registry.getEffectiveProperties("uilabel", "uigridlayout");
            testCase.verifyEqual(string({replaced.Path}), "Custom");
        end
    end

    methods (Test, TestTags = {'exhaustive'})
        function runtimeRegistryMatchesAuditedR2024aLedger(testCase)
            % runtimeRegistryMatchesAuditedR2024aLedger Compare every variant with the audited ledger.

            % Resolve the generated catalog through the production loader.
            registry = yamada.model.ComponentRegistry.createDefault();
            documents = ComponentRegistryBaselineTest.ledgerDocuments();
            expectedIds = sort(string(cellfun(@(document) document.id, documents, "UniformOutput", false)));
            testCase.verifyEqual(registry.listVariantIds(), expectedIds);
            expectedFactories = string(cellfun(@(document) document.factory, documents, "UniformOutput", false));
            testCase.verifyEqual(registry.listFactories(), sort(unique(expectedFactories)));
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
                    testCase.verifyEqual(string(actual.Metadata.description), string(expected.summary));
                    context = string(document.id) + "." + string(expected.path);
                    testCase.verifyEqual(actual.IsEditable, string(expected.runtimeSetAccess) == "public", context);
                    testCase.verifyEqual(actual.PreviewPolicy, string(expected.previewPolicy), context);
                    % Compare the complete contract, including optional bounds and constraints.
                    actualSchema = actual.ValueSchema;
                    expectedSchema = expected.valueContract;
                    actualSchema.matlabClasses = sort(reshape(string(actualSchema.matlabClasses), 1, []));
                    expectedSchema.matlabClasses = sort(reshape(string(expectedSchema.matlabClasses), 1, []));
                    testCase.verifyEqual(orderfields(actualSchema), orderfields(expectedSchema), context);
                    policy = yamada.model.PropertyApplicationPolicy();
                    if isfield(expected, "application")
                        policy = yamada.model.PropertyApplicationPolicy(expected.application);
                    end
                    testCase.verifyEqual(actual.Application.ApplyAfter, policy.ApplyAfter);
                    testCase.verifyEqual(actual.Application.EffectPolicy, policy.EffectPolicy);
                    testCase.verifyEqual(actual.Application.EffectStatus, policy.EffectStatus);
                    testCase.verifyEqual(actual.Application.AffectedPaths, policy.AffectedPaths);
                    testCase.verifyEqual(actual.Application.EffectReason, policy.EffectReason);
                    testCase.verifyEqual(actual.Application.DefaultLiteral, policy.DefaultLiteral);
                    testCase.verifyEqual(actual.Application.HasInitialValue, policy.HasInitialValue);
                    testCase.verifyTrue(isequaln(actual.Application.InitialValue, policy.InitialValue));
                    testCase.verifyFalse(isfield(actual.Metadata, "applicationEvidence"));
                    if string(expected.valueContract.kind) == "callback"
                        testCase.verifyEqual(actual.HandlerSuffix, string(expected.handlerSuffix));
                        contract = rmfield(expected.callbackSignature, "evidence");
                        testCase.verifyEqual(actual.CallbackSignature, yamada.model.CallbackSignature(contract));
                        testCase.verifyFalse(isfield(actual.Metadata.callbackSignature, "evidence"));
                    end
                end
            end

            % Presentation rows have their own reviewed ledger and ordered membership.
            ComponentRegistryBaselineTest.verifyInspectorRows(testCase, registry);
        end
    end

    methods (Test, TestTags = {'fast'})
        function editablePropertiesProjectToSupportedInspectorEditors(testCase)
            % editablePropertiesProjectToSupportedInspectorEditors Verify every editable capability has a row adapter.

            registry = yamada.model.ComponentRegistry.createDefault();
            templates = registry.inspectorRows();
            for id = registry.listVariantIds()
                definition = registry.getById(id);
                states = repmat(struct("Definition", yamada.model.PropertyDefinition()), ...
                    1, numel(definition.Properties));
                for propertyIndex = 1:numel(definition.Properties)
                    states(propertyIndex).Definition = definition.Properties(propertyIndex);
                end
                rows = yamada.ui.inspector.InspectorSurfaceBuilder.build( ...
                    id, "", states, templates);
                for rowIndex = 1:numel(rows)
                    members = definition.Properties(rows(rowIndex).MemberIndices);
                    editable = [members.IsEditable] & ...
                        [members.AuditDisposition] == "editable";
                    if ~any(editable)
                        continue
                    end
                    if rows(rowIndex).IsComposite
                        testCase.verifyTrue(any(rows(rowIndex).Editor == ...
                            ["tableData", "columnSettings", "items", "fontStyle"]), ...
                            id + ":" + rows(rowIndex).Id);
                    else
                        testCase.verifyTrue( ...
                            yamada.ui.inspector.PropertyEditorFactory.supportsEditing(members), ...
                            id + ":" + members.Path);
                    end
                end
            end
        end

        function editableEnumContractsRetainCompleteFiniteChoices(testCase)
            % editableEnumContractsRetainCompleteFiniteChoices Require dropdown choices for every editable enum.

            % Prevent incomplete documentation from silently producing disabled enum editors.
            registry = yamada.model.ComponentRegistry.createDefault();
            for id = registry.listVariantIds()
                definition = registry.getById(id);
                for property = definition.Properties
                    if property.Editor ~= "enum" || property.AuditDisposition ~= "editable"
                        continue
                    end
                    testCase.verifyTrue(isfield(property.ValueSchema, "values"));
                    testCase.verifyGreaterThanOrEqual(numel(property.ValueSchema.values), 2);
                end
            end
            definition = registry.getById("uiaxes");
            smoothing = definition.Properties([definition.Properties.Path] == "FontSmoothing");
            testCase.verifyEqual(smoothing.AuditDisposition, "omitted");
        end

        function checkboxTreeGeometryRetainsNativeAndProductAccessBoundaries(testCase)
            % checkboxTreeGeometryRetainsNativeAndProductAccessBoundaries Keep writable source aliases distinct from inspector capabilities.
            registry = yamada.model.ComponentRegistry.createDefault();
            definition = registry.getById("uitree-checkbox");
            position = definition.Properties([definition.Properties.Path] == "Position");
            inner = definition.Properties([definition.Properties.Path] == "InnerPosition");
            outer = definition.Properties([definition.Properties.Path] == "OuterPosition");
            testCase.verifyTrue(position.IsEditable);
            testCase.verifyEqual(position.AuditDisposition, "editable");
            testCase.verifyEqual(position.Editor, "position");
            testCase.verifyTrue(inner.IsEditable);
            testCase.verifyEqual(inner.AuditDisposition, "omitted");
            testCase.verifyEqual(inner.Editor, "readOnly");
            testCase.verifyFalse(outer.IsEditable);
            testCase.verifyEqual(outer.AuditDisposition, "omitted");
            testCase.verifyTrue(registry.isReadOnlyProperty("uitree", "OuterPosition", {"checkbox"}));
            for path = ["Position", "InnerPosition"]
                testCase.verifyFalse(registry.isReadOnlyProperty("uitree", path, {"checkbox"}));
                property = definition.Properties([definition.Properties.Path] == path);
                testCase.verifyFalse(isfield(property.Metadata, "runtimeObservations"));
            end
        end

        function effectivePropertiesRemainUniqueForEveryConcreteVariant(testCase)
            % effectivePropertiesRemainUniqueForEveryConcreteVariant Check all direct-parent projections.

            % Resolve every allowed parent using the concrete variant's constructor arguments.
            registry = yamada.model.ComponentRegistry.createDefault();
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
        function verifyInspectorRows(testCase, registry)
            % verifyInspectorRows Compare every runtime row field with the reviewed presentation ledger.
            arguments (Input)
                testCase (1, 1) ComponentRegistryBaselineTest
                registry (1, 1) yamada.model.ComponentRegistry
            end

            projectRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            ledger = jsondecode(fileread(fullfile(projectRoot, "dev", "component-data", ...
                "R2024a", "inspector-rows.json")));
            expectedRows = ComponentRegistryBaselineTest.objectList(ledger.rows);
            actualRows = registry.inspectorRows();
            testCase.assertNumElements(actualRows, numel(expectedRows));
            for index = 1:numel(expectedRows)
                expected = expectedRows{index};
                actual = actualRows(index);
                context = "Inspector row " + string(expected.id);
                testCase.verifyEqual(actual.Id, string(expected.id), context);
                testCase.verifyEqual(actual.DisplayName, string(expected.displayName), context);
                testCase.verifyEqual(actual.Editor, string(expected.editor), context);
                members = ComponentRegistryBaselineTest.objectList(expected.members);
                paths = string(cellfun(@(member) member.path, members, "UniformOutput", false));
                roles = string(cellfun(@(member) member.role, members, "UniformOutput", false));
                testCase.verifyEqual(actual.MemberPaths, paths, context);
                testCase.verifyEqual(actual.MemberRoles, roles, context);
                category = "";
                if isfield(expected, "categoryId"), category = string(expected.categoryId); end
                testCase.verifyEqual(actual.CategoryId, category, context);
                testCase.verifyEqual(actual.OrderAnchor, string(expected.orderAnchor), context);
                testCase.verifyEqual(actual.ComponentIds, ...
                    reshape(string(expected.match.componentIds), 1, []), context);
                testCase.verifyEqual(actual.ParentContextIds, ...
                    reshape(string(expected.match.parentContextIds), 1, []), context);
            end
        end

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
