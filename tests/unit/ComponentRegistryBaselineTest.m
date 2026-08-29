classdef ComponentRegistryBaselineTest < matlab.unittest.TestCase
    % ComponentRegistryBaselineTest Verify promotion of the R2024a grouping catalog.
    %   This class compares every runtime concrete variant with the audited
    %   development ledger and checks that direct-parent projections remain
    %   deterministic across the complete audited R2024a catalog.

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
            testCase.verifyEqual(numel(groups.groups), 314);
            testCase.verifyEqual(sort(string(manifest.orderProfileFiles)), "order-profiles.json");
            testCase.verifyEqual(sort(string({profiles.profiles.id})), ...
                ["axes", "contextMenu", "menuToolbar", "standardControl", "uifigure"]);
        end

        function runtimeCatalogLoadsInitialCompositeInspectorRows(testCase)
            % runtimeCatalogLoadsInitialCompositeInspectorRows Keep presentation overlays separate from properties.

            registry = macd.model.ComponentRegistry.createDefault();
            rows = registry.inspectorRows();
            testCase.verifyEqual(string({rows.Id}), ...
                ["tableDataAndNames", "tableColumns", "itemsAndData", "fontStyle"]);
            tableColumns = rows([rows.Id] == "tableColumns");
            testCase.verifyEqual(tableColumns.MemberPaths, ["ColumnWidth", "ColumnEditable", ...
                "ColumnRearrangeable", "ColumnSortable", "ColumnFormat"]);
            testCase.verifyEqual(tableColumns.CategoryId, "table");
            items = rows([rows.Id] == "itemsAndData");
            testCase.verifyEqual(items.ComponentIds, ...
                ["uidropdown", "uilistbox", "uiknob-discrete"]);
        end

        function editablePropertiesProjectToSupportedInspectorEditors(testCase)
            % editablePropertiesProjectToSupportedInspectorEditors Verify every editable capability has a row adapter.

            registry = macd.model.ComponentRegistry.createDefault();
            templates = registry.inspectorRows();
            for id = registry.listVariantIds()
                definition = registry.getById(id);
                states = repmat(struct("Definition", macd.model.PropertyDefinition()), ...
                    1, numel(definition.Properties));
                for propertyIndex = 1:numel(definition.Properties)
                    states(propertyIndex).Definition = definition.Properties(propertyIndex);
                end
                rows = macd.ui.inspector.InspectorSurfaceBuilder.build( ...
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
                            macd.ui.inspector.PropertyEditorFactory.supportsEditing(members), ...
                            id + ":" + members.Path);
                    end
                end
            end
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

        function figureRuntimeInteractionStateRemainsOmitted(testCase)
            % figureRuntimeInteractionStateRemainsOmitted Exclude mouse and keyboard event state from design editing.

            % These properties report the most recent user interaction rather than design intent.
            definition = macd.model.ComponentRegistry.createDefault().getById("uifigure");
            for path = ["CurrentCharacter", "CurrentPoint", "SelectionType"]
                property = definition.Properties([definition.Properties.Path] == path);
                testCase.verifyEqual(property.AuditDisposition, "omitted");
                testCase.verifyEqual(property.PreviewPolicy, "skip");
            end
        end

        function editableEnumContractsRetainCompleteFiniteChoices(testCase)
            % editableEnumContractsRetainCompleteFiniteChoices Require dropdown choices for every editable enum.

            % Prevent incomplete documentation from silently producing disabled enum editors.
            registry = macd.model.ComponentRegistry.createDefault();
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

        function editFieldPublicPropertiesAreNotLeftUnresolved(testCase)
            % editFieldPublicPropertiesAreNotLeftUnresolved Preserve audited editable field surfaces.

            registry = macd.model.ComponentRegistry.createDefault();
            ids = ["uieditfield-text", "uieditfield-numeric"];
            expected = {["Value", "CharacterLimits", "InputType", ...
                "Placeholder", "HorizontalAlignment", "FontName", "FontSize", ...
                "FontWeight", "FontAngle", "FontColor", "BackgroundColor", "Visible", ...
                "Editable", "Enable", "Tooltip", "Position", "Interruptible", "BusyAction"], ...
                ["Value", "Limits", "RoundFractionalValues", ...
                "ValueDisplayFormat", "AllowEmpty", "Placeholder", "HorizontalAlignment", ...
                "LowerLimitInclusive", "UpperLimitInclusive", "FontName", "FontSize", ...
                "FontWeight", "FontAngle", "FontColor", "BackgroundColor", "Visible", ...
                "Editable", "Enable", "Tooltip", "Position", "Interruptible", "BusyAction"]};
            for index = 1:numel(ids)
                id = ids(index);
                definition = registry.getById(id);
                for path = expected{index}
                    property = definition.Properties([definition.Properties.Path] == path);
                    testCase.verifyTrue(property.IsEditable, id + "." + path);
                end
            end
        end

        function switchItemsRetainTheirTwoStateContract(testCase)
            % switchItemsRetainTheirTwoStateContract Keep switches out of the generic Items dialog.

            registry = macd.model.ComponentRegistry.createDefault();
            for id = ["uiswitch-rocker", "uiswitch-slider", "uiswitch-toggle"]
                definition = registry.getById(id);
                items = definition.Properties([definition.Properties.Path] == "Items");
                testCase.verifyEqual(string(items.ValueSchema.shape), "fixedLengthVector");
                testCase.verifyEqual(items.ValueSchema.fixedLength, 2);
                testCase.verifyFalse(items.ValueSchema.allowsEmpty);
            end
        end

        function multilineTextSurfacesRemainDistinguishedFromStringLists(testCase)
            % multilineTextSurfacesRemainDistinguishedFromStringLists Preserve the audited text-editor scope.

            % Count only the prose surfaces that map arrays to display lines.
            registry = macd.model.ComponentRegistry.createDefault();
            textCount = 0;
            tooltipCount = 0;
            valueCount = 0;
            for id = registry.listVariantIds()
                definition = registry.getById(id);
                for property = definition.Properties
                    if property.Editor ~= "multilineText"
                        continue
                    end
                    if property.Path == "Text"
                        textCount = textCount + 1;
                    elseif property.Path == "Tooltip"
                        tooltipCount = tooltipCount + 1;
                    elseif id == "uitextarea" && property.Path == "Value"
                        valueCount = valueCount + 1;
                    else
                        testCase.assertFail("Unexpected multilineText surface: " + id + "." + property.Path);
                    end
                end
            end
            testCase.verifyEqual([textCount, tooltipCount, valueCount], [7, 37, 1]);
        end

        function specializedEditorContractsAreClassified(testCase)
            % specializedEditorContractsAreClassified Guard audited specialized-editor decisions.

            % Keep arbitrary HTML data visible but non-editable in the inspector.
            registry = macd.model.ComponentRegistry.createDefault();
            html = registry.getById("uihtml");
            data = html.Properties([html.Properties.Path] == "Data");
            testCase.verifyEqual(data.Editor, "readOnly");
            testCase.verifyEqual(data.AuditDisposition, "readOnly");

            % Route table data and headings through one related-data editor, while
            % reserving one column-settings editor for all column-oriented settings.
            table = registry.getById("uitable");
            for path = ["Data", "ColumnName", "RowName"]
                property = table.Properties([table.Properties.Path] == path);
                testCase.verifyEqual(property.Editor, "tableData");
            end
            for path = ["ColumnWidth", "ColumnEditable", "ColumnSortable", "ColumnFormat"]
                property = table.Properties([table.Properties.Path] == path);
                testCase.verifyEqual(property.Editor, "columnSettings");
            end
            rearrangeable = table.Properties([table.Properties.Path] == "ColumnRearrangeable");
            testCase.verifyEqual(rearrangeable.Editor, "onOff");
            for path = ["Selection", "SelectionType"]
                property = table.Properties([table.Properties.Path] == path);
                testCase.verifyEqual(property.AuditDisposition, "omitted");
                testCase.verifyEqual(property.Editor, "readOnly");
            end
        end

        function auditedValueContractsReachRuntimeCatalog(testCase)
            % auditedValueContractsReachRuntimeCatalog Verify exact pending-editor schemas.

            % Check the three documented date-picker modes independently.
            registry = macd.model.ComponentRegistry.createDefault();
            datePicker = registry.getById("uidatepicker");
            value = datePicker.Properties([datePicker.Properties.Path] == "Value").ValueSchema;
            testCase.verifyEqual(string(value.kind), "dateTime");
            testCase.verifyEqual(string(value.matlabClasses), "datetime");
            testCase.verifyEqual(string(value.shape), "scalar");
            testCase.verifyFalse(value.allowsEmpty);
            testCase.verifyTrue(value.allowsNaT);
            testCase.verifyEqual(string(value.normalization), "dateOnly");
            testCase.verifyEqual(string(value.constraints.kind), "withinLimitsOf");
            testCase.verifyEqual(string(value.constraints.property), "Limits");

            limits = datePicker.Properties([datePicker.Properties.Path] == "Limits").ValueSchema;
            testCase.verifyEqual(string(limits.matlabClasses), "datetime");
            testCase.verifyEqual(string(limits.shape), "fixedLengthVector");
            testCase.verifyEqual(limits.fixedLength, 2);
            testCase.verifyEqual(string(limits.orientation), "row");
            testCase.verifyFalse(limits.allowsEmpty);
            testCase.verifyFalse(limits.allowsNaT);
            testCase.verifyEqual(string(limits.constraints.kind), "strictlyIncreasing");

            disabled = datePicker.Properties( ...
                [datePicker.Properties.Path] == "DisabledDates").ValueSchema;
            testCase.verifyEqual(string(disabled.matlabClasses), "datetime");
            testCase.verifyEqual(string(disabled.shape), "vector");
            testCase.verifyEqual(string(disabled.orientation), "column");
            testCase.verifyTrue(disabled.allowsEmpty);
            testCase.verifyFalse(disabled.allowsNaT);
            testCase.verifyEqual(string(disabled.constraints.kind), "sortedAscending");

            % Check table data, headings, and each property-specific column contract.
            table = registry.getById("uitable");
            data = table.Properties([table.Properties.Path] == "Data").ValueSchema;
            testCase.verifyEqual(string(data.kind), "tabularData");
            testCase.verifyEqual(string(data.matlabClasses(:))', ...
                ["cell", "logical", "numeric", "string", "table"]);
            testCase.verifyEqual(string(data.shape), "matrix");
            testCase.verifyTrue(data.allowsEmpty);

            for path = ["ColumnName", "RowName"]
                heading = table.Properties([table.Properties.Path] == path).ValueSchema;
                testCase.verifyEqual(string(heading.kind), "stringList");
                testCase.verifyEqual(string(heading.shape), "propertyDependent");
                testCase.verifyEqual(string(heading.normalization), "columnVector");
            end

            width = table.Properties([table.Properties.Path] == "ColumnWidth").ValueSchema;
            testCase.verifyEqual(string(width.kind), "columnWidth");
            testCase.verifyEqual(string(width.matlabClasses(:))', ["cell", "char", "string"]);
            testCase.verifyFalse(width.allowsEmpty);
            testCase.verifyEqual(string(width.normalization), "charOrRowCell");

            for path = ["ColumnEditable", "ColumnSortable"]
                logicalColumns = table.Properties([table.Properties.Path] == path).ValueSchema;
                testCase.verifyEqual(string(logicalColumns.kind), "logical");
                testCase.verifyEqual(string(logicalColumns.matlabClasses(:))', ...
                    ["double", "logical"]);
                testCase.verifyTrue(logicalColumns.allowsEmpty);
                testCase.verifyEqual(string(logicalColumns.normalization), "logical");
            end

            format = table.Properties([table.Properties.Path] == "ColumnFormat").ValueSchema;
            testCase.verifyEqual(string(format.kind), "columnFormat");
            testCase.verifyEqual(string(format.matlabClasses(:))', ["cell", "double"]);
            testCase.verifyTrue(format.allowsEmpty);
            testCase.verifyEqual(string(format.normalization), "rowCell");
        end

        function reauditedContractsReachRuntimeCatalog(testCase)
            % reauditedContractsReachRuntimeCatalog Preserve the post-audit contract corrections.

            registry = macd.model.ComponentRegistry.createDefault();

            % Text-valued fields must not surface through a numeric-vector editor.
            textTargets = {"uidatepicker", "Placeholder"; "uidatepicker", "DisplayFormat"; ...
                    "uidropdown", "Placeholder"; "uieditfield-text", "Value"; ...
                    "uiimage", "AltText"; "uispinner", "ValueDisplayFormat"; ...
                    "uipanel", "Title"; "uitab", "Title"};
            for targetIndex = 1:size(textTargets, 1)
                definition = registry.getById(textTargets{targetIndex, 1});
                property = definition.Properties([definition.Properties.Path] == textTargets{targetIndex, 2});
                testCase.verifyEqual(property.Editor, "text");
                testCase.verifyEqual(string(property.ValueSchema.kind), "text");
                testCase.verifyTrue(property.ValueSchema.allowsEmpty);
            end

            % Record heterogeneous day choices and defer grid-track editing safely.
            datePicker = registry.getById("uidatepicker");
            disabledDays = datePicker.Properties( ...
                [datePicker.Properties.Path] == "DisabledDaysOfWeek");
            testCase.verifyEqual(disabledDays.Editor, "structuredData");
            testCase.verifyEqual(string(disabledDays.ValueSchema.kind), "dayOfWeekList");
            testCase.verifyEqual(string(disabledDays.ValueSchema.matlabClasses(:))', ...
                ["cell", "numeric", "string"]);

            grid = registry.getById("uigridlayout");
            for path = ["ColumnWidth", "RowHeight"]
                property = grid.Properties([grid.Properties.Path] == path);
                testCase.verifyEqual(property.Editor, "readOnly");
                testCase.verifyEqual(property.AuditDisposition, "readOnly");
                testCase.verifyEqual(string(property.ValueSchema.kind), "gridTrackList");
                testCase.verifyEqual(string(property.ValueSchema.matlabClasses(:))', ...
                    ["cell", "char", "numeric", "string"]);
            end

            % Item-backed selections use Items labels and optionally map to ItemsData.
            for id = ["uidropdown", "uiknob-discrete", "uilistbox", ...
                    "uiswitch-rocker", "uiswitch-slider", "uiswitch-toggle"]
                definition = registry.getById(id);
                property = definition.Properties([definition.Properties.Path] == "Value");
                testCase.verifyEqual(property.Editor, "itemSelection");
                testCase.verifyEqual(property.AuditDisposition, "editable");
                testCase.verifyEqual(string(property.ValueSchema.kind), "itemSelection");
                testCase.verifyEqual(string(property.ValueSchema.matlabClasses), "any");
            end
            listBox = registry.getById("uilistbox");
            listValue = listBox.Properties([listBox.Properties.Path] == "Value");
            testCase.verifyEqual(string(listValue.ValueSchema.multiselectProperty), "Multiselect");

            % Fixed vectors and explicit numeric bounds must reach the runtime schema.
            numeric = registry.getById("uieditfield-numeric");
            limits = numeric.Properties([numeric.Properties.Path] == "Limits").ValueSchema;
            testCase.verifyEqual(limits.fixedLength, 2);
            testCase.verifyTrue(limits.allowsInfinity);
            panel = registry.getById("uipanel");
            border = panel.Properties([panel.Properties.Path] == "BorderWidth").ValueSchema;
            testCase.verifyEqual(string(border.kind), "number");
            testCase.verifyEqual(border.minimum, 0);
            testCase.verifyTrue(border.exclusiveMinimum);
            testCase.verifyTrue(border.integer);
            font = panel.Properties([panel.Properties.Path] == "FontSize").ValueSchema;
            testCase.verifyEqual(font.minimum, 0);
            testCase.verifyTrue(font.exclusiveMinimum);

            % CurrentPoint is interaction state even where runtime metadata exposes it.
            axes = registry.getById("uiaxes");
            currentPoint = axes.Properties([axes.Properties.Path] == "CurrentPoint");
            testCase.verifyEqual(currentPoint.AuditDisposition, "omitted");
            testCase.verifyEqual(currentPoint.Editor, "readOnly");
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
