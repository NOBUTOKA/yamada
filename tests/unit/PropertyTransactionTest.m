classdef (TestTags = {'fast', 'inspector', 'model'}) PropertyTransactionTest < matlab.unittest.TestCase
    % PropertyTransactionTest Verify staged property candidates and typed-cell parsing.
    %   These tests cover the nonvisual transaction primitives shared by modal
    %   editors. They do not construct a visible application window or mutate a
    %   document except through focused model coverage elsewhere.

    methods (Test)
        function optionalUnknownPathsHaveNoValue(testCase)
            % optionalUnknownPathsHaveNoValue Keep predicate queries safe for partial transaction surfaces.
            transaction = yamada.model.PropertyTransaction("Value", {20});
            testCase.verifyTrue(transaction.hasValue("Value"));
            testCase.verifyFalse(transaction.hasValue("Editable"));
            testCase.verifyError(@() transaction.stage("Editable", "on"), "yamada:PropertyTransaction:UnknownPath");
        end

        function stagesReplacementAndClearWithoutMutatingSnapshot(testCase)
            % stagesReplacementAndClearWithoutMutatingSnapshot Keep candidate values local to a transaction.

            transaction = yamada.model.PropertyTransaction(["Items", "ItemsData"], ...
                {"First", [1 2]}, [true true]);
            transaction.stage("Items", "Second");
            transaction.clear("ItemsData");

            testCase.verifyEqual(transaction.InitialValues{1}, "First");
            testCase.verifyEqual(transaction.value("Items"), "Second");
            testCase.verifyEmpty(transaction.value("ItemsData"));
            changes = transaction.changes();
            testCase.verifyEqual(string({changes.Path}), ["Items", "ItemsData"]);
            testCase.verifyEqual(changes(1).Value, "Second");
            testCase.verifyEmpty(changes(2).Value);
        end

        function singleChangeRetainsOneCellArrayValue(testCase)
            % singleChangeRetainsOneCellArrayValue Avoid expanding multiline text into multiple updates.

            lines = {"First", "Second", "Third"};
            changes = yamada.model.PropertyTransaction.singleChange("Value", lines);

            testCase.verifySize(changes, [1 1]);
            testCase.verifyEqual(changes.Path, "Value");
            testCase.verifyEqual(changes.Value, lines);
        end

        function validatesCrossPropertyConstraintsAgainstOneCandidate(testCase)
            % validatesCrossPropertyConstraintsAgainstOneCandidate Use staged references before document mutation.

            itemDefinition = yamada.model.PropertyDefinition("Items", [], false, true, ...
                struct("editor", "stringList", "auditDisposition", "editable"));
            dataDefinition = yamada.model.PropertyDefinition("ItemsData", [], false, true, ...
                struct("editor", "structuredData", "auditDisposition", "editable", ...
                "valueSchema", struct("constraints", struct( ...
                "kind", "sameLengthAs", "property", "Items"))));
            transaction = yamada.model.PropertyTransaction(["Items", "ItemsData"], ...
                {{"One", "Two"}, [1 2]}, [true true]);
            transaction.stage("Items", {"One", "Two", "Three"});
            transaction.stage("ItemsData", [1 2 3]);

            message = yamada.validation.PropertyBatchValidator.validate( ...
                [itemDefinition dataDefinition], transaction);
            testCase.verifyEqual(message, "");
            transaction.stage("ItemsData", [1 2]);
            message = yamada.validation.PropertyBatchValidator.validate( ...
                [itemDefinition dataDefinition], transaction);
            testCase.verifyEqual(message, ...
                "The value must have the same number of elements as Items.");
            dataDefinition = yamada.model.PropertyDefinition("ItemsData", [], false, true, ...
                struct("editor", "structuredData", "auditDisposition", "editable", ...
                "valueSchema", struct("allowsEmpty", true, "constraints", struct( ...
                "kind", "sameLengthAs", "property", "Items"))));
            transaction.clear("ItemsData");
            message = yamada.validation.PropertyBatchValidator.validate( ...
                [itemDefinition dataDefinition], transaction);
            testCase.verifyEqual(message, "");
        end

        function validatesFixedLengthStringLists(testCase)
            % validatesFixedLengthStringLists Reject a switch state list with the wrong cardinality.

            definition = yamada.model.PropertyDefinition("Items", [], false, true, ...
                struct("editor", "stringList", "auditDisposition", "editable", ...
                "valueSchema", struct("shape", "fixedLengthVector", "fixedLength", 2, ...
                "allowsEmpty", false, "constraints", [])));
            transaction = yamada.model.PropertyTransaction("Items", {{"Off", "On"}}, true);
            transaction.stage("Items", ["Low", "Medium", "High"]);

            message = yamada.validation.PropertyBatchValidator.validate(definition, transaction);
            testCase.verifyEqual(message, "Enter a vector with the required number of values.");
        end

        function validatesItemsBackedSelections(testCase)
            % validatesItemsBackedSelections Require Value to match ItemsData or Items.

            valueDefinition = yamada.model.PropertyDefinition("Value", [], false, true, ...
                struct("editor", "itemSelection", "auditDisposition", "editable", ...
                "valueSchema", struct("kind", "itemSelection", "allowsEmpty", false)));
            itemsDefinition = yamada.model.PropertyDefinition("Items", [], false, true, ...
                struct("editor", "stringList", "auditDisposition", "editable"));
            dataDefinition = yamada.model.PropertyDefinition("ItemsData", [], false, true, ...
                struct("editor", "structuredData", "auditDisposition", "editable"));
            transaction = yamada.model.PropertyTransaction(["Value", "Items", "ItemsData"], ...
                {10, ["One", "Two"], [10 20]}, [true true true]);

            message = yamada.validation.PropertyBatchValidator.validate( ...
                [valueDefinition itemsDefinition dataDefinition], transaction);
            testCase.verifyEqual(message, "");
            transaction.stage("Value", 30);
            message = yamada.validation.PropertyBatchValidator.validate( ...
                [valueDefinition itemsDefinition dataDefinition], transaction);
            testCase.verifyEqual(message, "Choose a value represented by Items.");

            multiDefinition = yamada.model.PropertyDefinition("Value", [], false, true, ...
                struct("editor", "itemSelection", "auditDisposition", "editable", ...
                "valueSchema", struct("kind", "itemSelection", "allowsEmpty", true, ...
                "multiselectProperty", "Multiselect")));
            multiDefinition = [multiDefinition itemsDefinition dataDefinition ...
                yamada.model.PropertyDefinition("Multiselect", [], false, true, ...
                struct("editor", "onOff", "auditDisposition", "editable"))];
            transaction = yamada.model.PropertyTransaction( ...
                ["Value", "Items", "ItemsData", "Multiselect"], ...
                {[10 20], ["One", "Two"], [10 20], "on"}, true(1, 4));
            message = yamada.validation.PropertyBatchValidator.validate(multiDefinition, transaction);
            testCase.verifyEqual(message, "");
        end

        function typedCellCodecPreservesSafeTypesAndReportsCoordinates(testCase)
            % typedCellCodecPreservesSafeTypesAndReportsCoordinates Keep literal cell failures local.

            [values, row, column, message] = yamada.ui.inspector.TypedCellCodec.parse( ...
                ["1"; "true"; """Text"""], true);
            testCase.verifyEqual(row, 0);
            testCase.verifyEqual(column, 0);
            testCase.verifyEqual(message, "");
            testCase.verifyEqual(values{1}, 1);
            testCase.verifyTrue(values{2});
            testCase.verifyEqual(values{3}, "Text");
            [~, row, column, message] = yamada.ui.inspector.TypedCellCodec.parse( ...
                ["1"; "[1"], true);
            testCase.verifyEqual([row column], [2 1]);
            testCase.verifyEqual(message, "This cell has an invalid MATLAB literal.");
        end

        function typedCellCodecPacksHomogeneousValues(testCase)
            % typedCellCodecPacksHomogeneousValues Retain compact homogeneous vector forms.

            testCase.verifyEqual(yamada.ui.inspector.TypedCellCodec.packVector( ...
                {1, 2, 3}), [1 2 3]);
            testCase.verifyEqual(yamada.ui.inspector.TypedCellCodec.packVector( ...
                {"One", "Two"}), ["One", "Two"]);
            result = yamada.ui.inspector.TypedCellCodec.packVector({1, "Two"});
            testCase.verifyClass(result, "cell");
            testCase.verifyEqual(result, {1, "Two"});
        end

        function typedCellCodecPacksExplicitTableDataKinds(testCase)
            % typedCellCodecPacksExplicitTableDataKinds Apply blank-cell rules for each documented UITable Data type.

            [numericData, row, column, message] = ...
                yamada.ui.inspector.TypedCellCodec.parseTableMatrix( ...
                ["1", ""; "NaN", "Inf"], "numeric");
            testCase.verifyEqual([row column], [0 0]);
            testCase.verifyEqual(message, "");
            testCase.verifyEqual(numericData(1, 1), 1);
            testCase.verifyTrue(isnan(numericData(1, 2)));
            testCase.verifyTrue(isnan(numericData(2, 1)));
            testCase.verifyEqual(numericData(2, 2), Inf);

            logicalData = yamada.ui.inspector.TypedCellCodec.parseTableMatrix( ...
                ["true", ""; "false", "true"], "logical");
            testCase.verifyEqual(logicalData, logical([1 0; 0 1]));

            stringData = yamada.ui.inspector.TypedCellCodec.parseTableMatrix( ...
                ["""One""", ""; "'Three'", "plain"], "string");
            testCase.verifyEqual(stringData, ["One", ""; "Three", "plain"]);

            cellData = yamada.ui.inspector.TypedCellCodec.parseTableMatrix( ...
                ["1", ""; "true", """Text"""], "cell");
            testCase.verifyEqual(cellData{1, 1}, 1);
            testCase.verifyEmpty(cellData{1, 2});
            testCase.verifyTrue(cellData{2, 1});
            testCase.verifyEqual(cellData{2, 2}, 'Text');

            charCellData = yamada.ui.inspector.TypedCellCodec.parseTableMatrix( ...
                ["123", ""; "NaN", """Four"""], "charCell");
            testCase.verifyEqual(charCellData, {'123', ''; 'NaN', 'Four'});
            testCase.verifyEqual(yamada.ui.inspector.TypedCellCodec.inferTableDataKind( ...
                {'one', 'two'}), "charCell");
            testCase.verifyEqual(yamada.ui.inspector.TypedCellCodec.inferTableDataKind( ...
                {1, 'two'}), "cell");
        end

        function validatesDateTimeShapesAndCrossPropertyRules(testCase)
            % validatesDateTimeShapesAndCrossPropertyRules Check the audited date picker contract.

            valueDefinition = yamada.model.PropertyDefinition("Value", [], false, true, ...
                struct("editor", "dateTime", "auditDisposition", "editable", ...
                "valueSchema", struct("kind", "dateTime", "shape", "scalar", ...
                "allowsEmpty", false, "allowsNaT", true, "constraints", struct( ...
                "kind", "withinLimitsOf", "property", "Limits"))));
            limitsDefinition = yamada.model.PropertyDefinition("Limits", [], false, true, ...
                struct("editor", "dateTime", "auditDisposition", "editable", ...
                "valueSchema", struct("kind", "dateTime", "shape", "fixedLengthVector", ...
                "fixedLength", 2, "orientation", "row", "allowsEmpty", false, ...
                "allowsNaT", false, "constraints", struct("kind", "strictlyIncreasing"))));
            transaction = yamada.model.PropertyTransaction(["Value", "Limits"], ...
                {datetime(2024, 1, 2), [datetime(2024, 1, 1) datetime(2024, 1, 3)]});

            transaction.stage("Value", datetime(2024, 1, 4));
            message = yamada.validation.PropertyBatchValidator.validate( ...
                [valueDefinition limitsDefinition], transaction);
            testCase.verifyEqual(message, "The selected date must be within Limits.");
            transaction.stage("Value", NaT);
            message = yamada.validation.PropertyBatchValidator.validate( ...
                [valueDefinition limitsDefinition], transaction);
            testCase.verifyEqual(message, "");
            transaction.stage("Limits", [datetime(2024, 1, 3) datetime(2024, 1, 1)]);
            message = yamada.validation.PropertyBatchValidator.validate( ...
                [valueDefinition limitsDefinition], transaction);
            testCase.verifyEqual(message, "The end date must be later than the start date.");
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
