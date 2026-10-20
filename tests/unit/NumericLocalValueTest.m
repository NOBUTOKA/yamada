classdef (TestTags = {'fast', 'model', 'generation'}) NumericLocalValueTest < matlab.unittest.TestCase
    % NumericLocalValueTest Verify finite numeric Value edits against complete owned source checkpoints.
    %   Local validation must preserve source order, constraint behavior, atomic
    %   history, full save verification and the independence of public results.
    properties (Access = private)
        Registry macd.model.ComponentRegistry
    end

    methods (TestClassSetup)
        function loadRegistry(testCase)
            % loadRegistry Load the same catalog used by full property preflight.
            testCase.Registry = macd.model.ComponentRegistry.createDefault();
        end
    end

    methods (Test)
        function reusesACompleteCheckpointAcrossNumericOwners(testCase)
            % reusesACompleteCheckpointAcrossNumericOwners Avoid parsing for owned re-edits across grid layouts.
            for layout = ["absolute", "flat", "nested"]
                document = testCase.fixture(layout, "app.First = uieditfield(PARENT,'numeric');");
                first = document.getComponentByName("First");
                second = document.getComponentByName("Second");
                document.setProperty(first.Id, "Value", 2, testCase.Registry);
                document.validatePropertyCommit(testCase.Registry);
                document.setProperty(second.Id, "Value", 3, testCase.Registry);
                document.validatePropertyCommit(testCase.Registry);
                profile clear; profile on;
                cleanup = onCleanup(@() profile("off"));
                document.setPropertyBatch(first.Id, macd.model.PropertyTransaction.singleChange("Value", 4), testCase.Registry);
                document.validatePropertyCommit(testCase.Registry);
                document.setProperty(second.Id, "Value", 5, testCase.Registry);
                document.validatePropertyCommit(testCase.Registry);
                profile off; functions = profile("info").FunctionTable; clear cleanup
                names = string({functions.FunctionName});
                repeated = contains(names, "AppSourceParser.parseText") | ...
                    contains(names, "RoundTripGenerator.generate") | contains(names, "ModelValidator.validate");
                testCase.verifyEqual(sum([functions(repeated).NumCalls]), 0, layout);
                testCase.verifyEqual(first.getProperty("Value").LiteralValue, 4);
                testCase.verifyEqual(second.getProperty("Value").LiteralValue, 5);
                testCase.verifyEqual(document.HistoryIndex, 4);
                document.undo(); document.redo();
                source = macd.source.RoundTripGenerator(testCase.Registry).generate(document);
                parsed = macd.source.AppSourceParser.parseText(source, testCase.Registry);
                testCase.verifyEqual(parsed.getComponentByName("First").getProperty("Value").LiteralValue, 4);
                testCase.verifyEqual(parsed.getComponentByName("Second").getProperty("Value").LiteralValue, 5);
            end
        end

        function laterConstraintsDoNotHideAnEarlierInvalidAssignment(testCase)
            % laterConstraintsDoNotHideAnEarlierInvalidAssignment Validate every occurrence rather than final bounds alone.
            document = testCase.fixture("absolute", ...
                ["app.First = uieditfield(PARENT,'numeric');", "app.First.Limits = [0 10];", ...
                "app.First.Value = 1;", "app.First.Limits = [0 100];"]);
            first = document.getComponentByName("First");
            document.setProperty(first.Id, "Value", 2, testCase.Registry);
            document.validatePropertyCommit(testCase.Registry);
            history = document.History;
            source = macd.source.RoundTripGenerator(testCase.Registry).generate(document);
            testCase.verifyError(@() document.setProperty(first.Id, "Value", 50, testCase.Registry), ...
                "macd:DocumentModel:UnsafePropertyEdit");
            testCase.verifyEqual(document.History, history);
            testCase.verifyEqual(first.getProperty("Value").LiteralValue, 2);
            testCase.verifyEqual(macd.source.RoundTripGenerator(testCase.Registry).generate(document), source);
        end

        function preservesRoundingAndExclusiveBoundaryRejections(testCase)
            % preservesRoundingAndExclusiveBoundaryRejections Keep strict requested-value equality and native limits.
            for kind = ["rounding", "lower", "upper"]
                settings = ["app.First = uieditfield(PARENT,'numeric');", ...
                    "app.First.Limits = [0 10];", "app.First.Value = 1;"];
                if kind == "rounding"
                    settings(end + 1) = "app.First.RoundFractionalValues = 'on';"; %#ok<AGROW>
                    rejected = 2.5;
                elseif kind == "lower"
                    settings(end + 1) = "app.First.LowerLimitInclusive = 'off';"; %#ok<AGROW>
                    rejected = 0;
                else
                    settings(end + 1) = "app.First.UpperLimitInclusive = 'off';"; %#ok<AGROW>
                    rejected = 10;
                end
                document = testCase.fixture("absolute", settings);
                first = document.getComponentByName("First");
                document.setProperty(first.Id, "Value", 2, testCase.Registry);
                document.validatePropertyCommit(testCase.Registry);
                before = document.History;
                testCase.verifyError(@() document.setProperty(first.Id, "Value", rejected, testCase.Registry), ...
                    "macd:DocumentModel:UnsafePropertyEdit", kind);
                testCase.verifyEqual(first.getProperty("Value").LiteralValue, 2);
                testCase.verifyEqual(document.History, before);
            end
        end

        function changedConstraintsAndCatalogInvalidateTheCheckpoint(testCase)
            % changedConstraintsAndCatalogInvalidateTheCheckpoint Re-enter full source validation after semantic changes.
            for kind = ["limits", "registry"]
                document = testCase.fixture("absolute", ...
                    ["app.First = uieditfield(PARENT,'numeric');", "app.First.Limits = [0 10];", "app.First.Value = 1;"]);
                first = document.getComponentByName("First");
                document.setProperty(first.Id, "Value", 2, testCase.Registry);
                document.validatePropertyCommit(testCase.Registry);
                if kind == "limits"
                    first.setProperty("Limits", [0 5]);
                else
                    testCase.Registry.register(testCase.Registry.get("uieditfield", {"numeric"}));
                end
                profile clear; profile on;
                cleanup = onCleanup(@() profile("off"));
                document.setProperty(first.Id, "Value", 4, testCase.Registry);
                profile off; functions = profile("info").FunctionTable; clear cleanup
                parsing = contains(string({functions.FunctionName}), "AppSourceParser.parseText");
                testCase.verifyGreaterThan(sum([functions(parsing).NumCalls]), 0, kind);
                testCase.verifyEqual(first.getProperty("Value").LiteralValue, 4);
            end
        end

        function constructorAndRepeatedAssignmentsKeepTheirSourceForm(testCase)
            % constructorAndRepeatedAssignmentsKeepTheirSourceForm Rewrite only the latest original Value occurrence.
            cases = {"app.First = uieditfield(PARENT,'numeric',Limits=[0 10],Value=1);", ...
                ["app.First = uieditfield(PARENT,'numeric');", "app.First.Value = 1; % earlier", ...
                "app.First.Value = 2; % latest"]};
            for index = 1:numel(cases)
                document = testCase.fixture("absolute", cases{index});
                first = document.getComponentByName("First");
                document.setProperty(first.Id, "Value", 3, testCase.Registry);
                document.validatePropertyCommit(testCase.Registry);
                document.setProperty(first.Id, "Value", 4, testCase.Registry);
                source = macd.source.RoundTripGenerator(testCase.Registry).generate(document);
                parsed = macd.source.AppSourceParser.parseText(source, testCase.Registry);
                settings = parsed.getComponentByName("First").getSettings("Value");
                if index == 1
                    testCase.verifyEqual(settings.Method, "nameValue");
                else
                    testCase.verifyNumElements(settings, 2);
                    testCase.verifySubstring(source, "app.First.Value = 1; % earlier");
                    testCase.verifySubstring(source, "app.First.Value = 4; % latest");
                end
                testCase.verifyEqual(parsed.getComponentByName("First").getProperty("Value").LiteralValue, 4);
            end
        end

        function emptyValuesUseTheFullAllowedEmptyPath(testCase)
            % emptyValuesUseTheFullAllowedEmptyPath Keep non-scalar requests outside finite scalar local validation.
            document = testCase.fixture("absolute", ...
                ["app.First = uieditfield(PARENT,'numeric');", "app.First.AllowEmpty = 'on';", "app.First.Value = 1;"]);
            first = document.getComponentByName("First");
            document.setProperty(first.Id, "Value", 2, testCase.Registry);
            document.validatePropertyCommit(testCase.Registry);
            profile clear; profile on;
            cleanup = onCleanup(@() profile("off"));
            document.setProperty(first.Id, "Value", [], testCase.Registry);
            profile off; functions = profile("info").FunctionTable; clear cleanup
            parsing = contains(string({functions.FunctionName}), "AppSourceParser.parseText");
            testCase.verifyGreaterThan(sum([functions(parsing).NumCalls]), 0);
            testCase.verifyEmpty(first.getProperty("Value").LiteralValue);
        end

        function fullSaveValidationStillGeneratesAndReparses(testCase)
            % fullSaveValidationStillGeneratesAndReparses Retain source and checkpoint checks after a local commit.
            document = testCase.fixture("absolute", "app.First = uieditfield(PARENT,'numeric');");
            first = document.getComponentByName("First");
            document.setProperty(first.Id, "Value", 2, testCase.Registry);
            document.validatePropertyCommit(testCase.Registry);
            document.setProperty(first.Id, "Value", 3, testCase.Registry);
            document.validatePropertyCommit(testCase.Registry);
            profile clear; profile on;
            cleanup = onCleanup(@() profile("off"));
            source = macd.source.RoundTripGenerator(testCase.Registry).generate(document);
            checkpoint = macd.model.SavedSourceCheckpoint(document, source, ...
                fullfile(tempdir, "LocalNumericFixture.m"), testCase.Registry);
            profile off; functions = profile("info").FunctionTable; clear cleanup
            names = string({functions.FunctionName});
            testCase.verifyGreaterThan(sum([functions(contains(names, "AppSourceParser.parseText")).NumCalls]), 0);
            testCase.verifyGreaterThan(sum([functions(contains(names, "ModelValidator.validate")).NumCalls]), 0);
            testCase.verifyEqual(checkpoint.SourceText, source);
        end
    end

    methods (Access = private)
        function document = fixture(testCase, layout, firstBody)
            % fixture Parse synthetic numeric initialization without executing application code.
            arguments (Input)
                testCase (1, 1) NumericLocalValueTest
                layout (1, 1) string
                firstBody (1, :) string
            end
            arguments (Output)
                document (1, 1) macd.model.DocumentModel
            end
            declarations = ["UIFigure matlab.ui.Figure", "First matlab.ui.control.NumericEditField", ...
                "Second matlab.ui.control.NumericEditField"];
            body = "app.UIFigure = uifigure(Visible='off');";
            parent = "app.UIFigure";
            if layout == "nested"
                for depth = 1:2
                    name = "Outer" + depth;
                    declarations(end + 1) = name + " matlab.ui.container.GridLayout"; %#ok<AGROW>
                    body = [body, "app." + name + " = uigridlayout(" + parent + ",[1 1]);", ...
                        "app." + name + ".RowHeight = {'1x'};", "app." + name + ".ColumnWidth = {'1x'};"]; %#ok<AGROW>
                    parent = "app." + name;
                end
            end
            if layout ~= "absolute"
                declarations(end + 1) = "Grid matlab.ui.container.GridLayout";
                body = [body, "app.Grid = uigridlayout(" + parent + ",[2 1]);", ...
                    "app.Grid.RowHeight = {'fit','1x'};", "app.Grid.ColumnWidth = {'1x'};"];
                parent = "app.Grid";
            end
            body = [body, replace(firstBody, "PARENT", parent), ...
                "app.Second = uieditfield(" + parent + ",'numeric');"];
            if layout ~= "absolute"
                body = [body, "app.First.Layout.Row = 1;", "app.Second.Layout.Row = 2;"];
            end
            source = strjoin(["classdef LocalNumericFixture < matlab.apps.AppBase", "properties", ...
                declarations, "end", "methods", "function app = LocalNumericFixture", ...
                "createComponents(app);", "end", "function createComponents(app)", ...
                body, "end", "end", "end"], sprintf("\r\n"));
            document = macd.source.AppSourceParser.parseText(source, testCase.Registry);
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
