classdef (TestTags = {'fast', 'model', 'generation'}) LocalTextPropertyTest < matlab.unittest.TestCase
    % LocalTextPropertyTest Verify proven text replacements without whole-document preflight.
    %   Text edits retain literal syntax, source ownership, ordered setters,
    %   validation provenance, history, and independent public source plans.
    properties (Access = private)
        Registry macd.model.ComponentRegistry
    end

    methods (TestClassSetup)
        function loadRegistry(testCase)
            % loadRegistry Use the production catalog for both full and local preflight.
            testCase.Registry = macd.model.ComponentRegistry.createDefault();
        end
    end

    methods (Test)
        function repeatedTextAvoidsWholeDocumentWork(testCase)
            % repeatedTextAvoidsWholeDocumentWork Reuse a fully checked insertion across all layouts.
            for layout = ["absolute", "flat", "nested"]
                [document, first] = testCase.fixture(layout);
                document.setProperty(first.Id, "Text", "First edit", testCase.Registry);
                document.validatePropertyCommit(testCase.Registry);
                profile clear; profile on;
                stopProfile = onCleanup(@() profile("off"));
                requested = "quoted ""text""; % end app.Second.Text = 'unchanged'";
                document.setPropertyBatch(first.Id, ...
                    macd.model.PropertyTransaction.singleChange("Text", requested), testCase.Registry);
                document.validatePropertyCommit(testCase.Registry);
                profile off; functions = profile("info").FunctionTable; clear stopProfile
                testCase.verifyEqual(testCase.fullWorkCalls(functions), 0, layout);
                testCase.verifyEqual(first.getProperty("Text").LiteralValue, requested);
                testCase.verifyEqual(document.HistoryIndex, 2);
                source = macd.source.RoundTripGenerator(testCase.Registry).generate(document);
                parsed = macd.source.AppSourceParser.parseText(source, testCase.Registry);
                testCase.verifyEqual(parsed.getComponentByName("First").getProperty("Text").LiteralValue, requested);
                testCase.verifySubstring(source, "% untouched source");
            end
        end

        function textRepresentationsRetainExactLiteralValues(testCase)
            % textRepresentationsRetainExactLiteralValues Preserve quotes, arrays, char matrices, and row cells.
            [document, first] = testCase.fixture("absolute");
            document.setProperty(first.Id, "Text", "Warm", testCase.Registry);
            document.validatePropertyCommit(testCase.Registry);
            values = {"", "日本語 ""quoted"" % ; ...", 'char''s literal', ...
                ["line one"; "line two"], {'first', 'second'}, ['ab'; 'cd'], cell(0, 0)};
            for index = 1:numel(values)
                requested = values{index};
                profile clear; profile on;
                stopProfile = onCleanup(@() profile("off"));
                document.setProperty(first.Id, "Text", requested, testCase.Registry);
                document.validatePropertyCommit(testCase.Registry);
                profile off; functions = profile("info").FunctionTable; clear stopProfile
                testCase.verifyEqual(testCase.fullWorkCalls(functions), 0, "Representation " + index);
                source = macd.source.RoundTripGenerator(testCase.Registry).generate(document);
                parsed = macd.source.AppSourceParser.parseText(source, testCase.Registry);
                testCase.verifyEqual(parsed.getComponentByName("First").getProperty("Text").LiteralValue, requested);
            end
        end

        function preservesConstructorAndRepeatedSetterOwnership(testCase)
            % preservesConstructorAndRepeatedSetterOwnership Replace only the effective original occurrence.
            for constructor = [false true]
                lines = "app.First = uilabel(PARENT,'Text','constructor'); % creation";
                if ~constructor
                    lines = [lines, "app.First.Text = 'earlier'; % earlier", ...
                        "app.First.Text = 'latest'; % latest"]; %#ok<AGROW>
                end
                [document, first] = testCase.fixture("absolute", lines);
                document.setProperty(first.Id, "Text", "First replacement", testCase.Registry);
                document.validatePropertyCommit(testCase.Registry);
                settings = first.getSettings("Text");
                ids = string({settings.Id});
                document.setProperty(first.Id, "Text", "A longer final replacement", testCase.Registry);
                document.validatePropertyCommit(testCase.Registry);
                after = first.getSettings("Text");
                testCase.verifyEqual(string({after.Id}), ids);
                source = macd.source.RoundTripGenerator(testCase.Registry).generate(document);
                testCase.verifySubstring(source, "% creation");
                if ~constructor
                    testCase.verifySubstring(source, "app.First.Text = 'earlier'; % earlier");
                    testCase.verifySubstring(source, "'Text','constructor'");
                    testCase.verifySubstring(source, "% latest");
                end
                parsed = macd.source.AppSourceParser.parseText(source, testCase.Registry);
                testCase.verifyEqual(parsed.getComponentByName("First").getProperty("Text").LiteralValue, ...
                    "A longer final replacement");
            end
        end

        function changedInputsReturnToFullPreflight(testCase)
            % changedInputsReturnToFullPreflight Reuse validated owner changes but discard stale metadata, catalog, or source proofs.
            for kind = ["other-owner", "metadata", "registry", "source"]
                [document, first] = testCase.fixture("flat");
                registry = macd.model.ComponentRegistry.createDefault();
                document.setProperty(first.Id, "Text", "Warm", registry);
                document.validatePropertyCommit(registry);
                switch kind
                    case "other-owner"
                        second = document.getComponentByName("Second");
                        document.setProperty(second.Id, "Text", "Different owner", registry);
                    case "metadata"
                        document.Metadata.RecheckText = true;
                    case "registry"
                        registry.register(registry.get("uilabel"));
                    case "source"
                        document.OriginalText = document.OriginalText + string(newline) + "% changed source";
                end
                profile clear; profile on;
                stopProfile = onCleanup(@() profile("off"));
                if kind == "source"
                    identifier = testCase.attempt(document, first.Id, "After invalidation", registry);
                else
                    document.setProperty(first.Id, "Text", "After invalidation", registry);
                end
                profile off; functions = profile("info").FunctionTable; clear stopProfile
                if kind == "other-owner"
                    % The second owned edit established a complete configuration for both owners.
                    testCase.verifyEqual(testCase.fullWorkCalls(functions), 0, kind);
                else
                    testCase.verifyGreaterThan(testCase.fullWorkCalls(functions), 0, kind);
                end
                if kind == "source"
                    testCase.verifyEqual(identifier, "macd:DocumentModel:UnsafePropertyEdit");
                    testCase.verifyEqual(first.getProperty("Text").LiteralValue, "Warm");
                else
                    testCase.verifyEqual(first.getProperty("Text").LiteralValue, "After invalidation");
                end
            end
        end

        function oldPlansAndHistoryRemainIndependent(testCase)
            % oldPlansAndHistoryRemainIndependent Keep previous versions and public copies stable after text edits.
            [document, first] = testCase.fixture("nested");
            document.setProperty(first.Id, "Text", "One", testCase.Registry);
            document.validatePropertyCommit(testCase.Registry);
            previous = document.evaluationContext(testCase.Registry);
            [old, found] = previous.configuration("combined", first.Name);
            testCase.assertTrue(found);
            document.setPropertyBatch(first.Id, ...
                macd.model.PropertyTransaction.singleChange("Text", "Two"), testCase.Registry);
            document.validatePropertyCommit(testCase.Registry);
            testCase.verifyEqual(old.Component.getProperty("Text").LiteralValue, "One");
            [again, found] = previous.configuration("combined", first.Name);
            testCase.assertTrue(found);
            testCase.verifyEqual(again.Component.getProperty("Text").LiteralValue, "One");
            context = document.evaluationContext(testCase.Registry);
            [copy, found] = context.configuration("combined", first.Name);
            testCase.assertTrue(found);
            copy.Component.setProperty("Text", "External mutation");
            [copy, found] = context.configuration("combined", first.Name);
            testCase.assertTrue(found);
            testCase.verifyEqual(copy.Component.getProperty("Text").LiteralValue, "Two");
            document.undo();
            testCase.verifyEqual(first.getProperty("Text").LiteralValue, "One");
            document.redo();
            testCase.verifyEqual(first.getProperty("Text").LiteralValue, "Two");
            source = macd.source.RoundTripGenerator(testCase.Registry).generate(document);
            checkpoint = macd.model.SavedSourceCheckpoint(document, source, ...
                fullfile(tempdir, "LocalTextFixture.m"), testCase.Registry);
            testCase.verifyEqual(checkpoint.SourceText, source);
            testCase.verifyEqual(document.HistoryIndex, 2);
        end

        function unprovenSyntaxKeepsTheFullPath(testCase)
            % unprovenSyntaxKeepsTheFullPath Match full-preflight acceptance and retain fallback for unrepresentable syntax.
            values = {"first" + string(newline) + "second", string(missing), categorical("one"), {{'nested'}}};
            cases = ["physical-newline", "missing-string", "categorical", "exact-nested-cell"];
            for index = 1:numel(values)
                [document, first] = testCase.fixture("absolute");
                [reference, referenceFirst] = testCase.fixture("absolute");
                document.setProperty(first.Id, "Text", "Warm", testCase.Registry);
                document.validatePropertyCommit(testCase.Registry);
                reference.setProperty(referenceFirst.Id, "Text", "Warm", testCase.Registry);
                reference.validatePropertyCommit(testCase.Registry);
                reference.Metadata.ForceFullPreflight = true;
                expected = testCase.attempt(reference, referenceFirst.Id, values{index}, testCase.Registry);
                profile clear; profile on;
                stopProfile = onCleanup(@() profile("off"));
                actual = testCase.attempt(document, first.Id, values{index}, testCase.Registry);
                profile off; functions = profile("info").FunctionTable; clear stopProfile
                testCase.verifyEqual(actual, expected, cases(index));
                if cases(index) == "exact-nested-cell"
                    % Exact literal decoding permits local schema acceptance or rejection without a source trial.
                    [decoded, literal] = macd.source.MatlabLiteralParser.parse(macd.source.LiteralEncoder.encode(values{index}));
                    testCase.verifyTrue(literal);
                    testCase.verifyEqual(decoded, values{index});
                    testCase.verifyEqual(testCase.fullWorkCalls(functions), 0, cases(index));
                else
                    testCase.verifyGreaterThan(testCase.fullWorkCalls(functions), 0, cases(index));
                end
                testCase.verifyEqual(first.getProperty("Text").LiteralValue, ...
                    referenceFirst.getProperty("Text").LiteralValue);
                testCase.verifyEqual(document.HistoryIndex, reference.HistoryIndex);
            end
        end

        function modelValidationRequiresActualPreviousProof(testCase)
            % modelValidationRequiresActualPreviousProof Retain full validation until actual diagnostics were obtained.
            [document, first] = testCase.fixture("absolute");
            document.setProperty(first.Id, "Text", "One", testCase.Registry);
            document.setProperty(first.Id, "Text", "Two", testCase.Registry);
            profile clear; profile on;
            stopProfile = onCleanup(@() profile("off"));
            document.validatePropertyCommit(testCase.Registry);
            profile off; functions = profile("info").FunctionTable; clear stopProfile
            testCase.verifyGreaterThan(testCase.fullWorkCalls(functions), 0);
            profile clear; profile on;
            stopProfile = onCleanup(@() profile("off"));
            document.setProperty(first.Id, "Text", "Three", testCase.Registry);
            document.validatePropertyCommit(testCase.Registry);
            profile off; functions = profile("info").FunctionTable; clear stopProfile
            testCase.verifyEqual(testCase.fullWorkCalls(functions), 0);
        end

        function otherIndependentTextPropertiesReuseTheirProof(testCase)
            % otherIndependentTextPropertiesReuseTheirProof Share the literal path for plain and multiline text contracts.
            for path = ["Title", "Tooltip"]
                registry = testCase.Registry;
                document = macd.model.NewAppFactory.createEmpty("TextDomainsFixture", registry);
                panel = document.insertComponent(registry, "uipanel", document.RootComponentId);
                name = panel.Name;
                source = macd.source.NewAppGenerator(registry).generate(document);
                document = macd.source.AppSourceParser.parseText(source, registry);
                panel = document.getComponentByName(name);
                document.setProperty(panel.Id, path, "First edit", registry);
                document.validatePropertyCommit(registry);
                profile clear; profile on;
                stopProfile = onCleanup(@() profile("off"));
                document.setProperty(panel.Id, path, "Second edit", registry);
                document.validatePropertyCommit(registry);
                profile off; functions = profile("info").FunctionTable; clear stopProfile
                testCase.verifyEqual(testCase.fullWorkCalls(functions), 0, path);
                source = macd.source.RoundTripGenerator(registry).generate(document);
                parsed = macd.source.AppSourceParser.parseText(source, registry);
                testCase.verifyEqual(parsed.getComponentByName(name).getProperty(path).LiteralValue, "Second edit");
            end
        end

        function modeledTextRetainsConstraintPreflight(testCase)
            % modeledTextRetainsConstraintPreflight Preserve coupled text Value and CharacterLimits validation.
            registry = testCase.Registry;
            document = macd.model.NewAppFactory.createEmpty("ModeledTextFixture", registry);
            field = document.insertComponent(registry, "uieditfield", document.RootComponentId, {"text"});
            name = field.Name;
            source = macd.source.NewAppGenerator(registry).generate(document);
            document = macd.source.AppSourceParser.parseText(source, registry);
            field = document.getComponentByName(name);
            document.setProperty(field.Id, "Value", "One", registry);
            document.validatePropertyCommit(registry);
            profile clear; profile on;
            stopProfile = onCleanup(@() profile("off"));
            document.setProperty(field.Id, "Value", "Two", registry);
            profile off; functions = profile("info").FunctionTable; clear stopProfile
            testCase.verifyGreaterThan(testCase.fullWorkCalls(functions), 0);
        end
    end

    methods (Access = private)
        function [document, first] = fixture(testCase, layout, firstLines)
            % fixture Parse label settings in absolute, fit-grid, or nested fit-grid source.
            arguments (Input)
                testCase (1, 1) LocalTextPropertyTest
                layout (1, 1) string
                firstLines string = "app.First = uilabel(PARENT);"
            end
            arguments (Output)
                document (1, 1) macd.model.DocumentModel
                first (1, 1) macd.model.ComponentRecord
            end
            declarations = ["UIFigure matlab.ui.Figure", "First matlab.ui.control.Label", "Second matlab.ui.control.Label"];
            body = "app.UIFigure = uifigure(Visible='off');";
            parent = "app.UIFigure";
            if layout == "nested"
                declarations(end + 1) = "Outer matlab.ui.container.GridLayout";
                body = [body, "app.Outer = uigridlayout(" + parent + ",[1 1]);"];
                parent = "app.Outer";
            end
            if layout ~= "absolute"
                declarations(end + 1) = "Grid matlab.ui.container.GridLayout";
                body = [body, "app.Grid = uigridlayout(" + parent + ",[2 1]);", ...
                    "app.Grid.RowHeight = {'fit','1x'};"];
                parent = "app.Grid";
            end
            body = [body, replace(firstLines, "PARENT", parent), ...
                "app.Second = uilabel(" + parent + ");", "% untouched source"];
            if layout ~= "absolute"
                body = [body, "app.First.Layout.Row = 1;", "app.Second.Layout.Row = 2;"];
            end
            source = strjoin(["classdef LocalTextFixture < handle", "properties", declarations, ...
                "end", "methods", "function app = LocalTextFixture", "createComponents(app);", ...
                "end", "function createComponents(app)", body, "end", "end", "end"], sprintf("\r\n"));
            document = macd.source.AppSourceParser.parseText(source, testCase.Registry);
            first = document.getComponentByName("First");
        end
    end

    methods (Static, Access = private)
        function count = fullWorkCalls(functions)
            % fullWorkCalls Count complete generation, parsing, and model validation calls.
            arguments (Input)
                functions struct
            end
            arguments (Output)
                count (1, 1) double
            end
            names = string({functions.FunctionName});
            full = contains(names, "AppSourceParser.parseText") | ...
                contains(names, "RoundTripGenerator.generate") | contains(names, "ModelValidator.validate");
            count = sum([functions(full).NumCalls]);
        end

        function identifier = attempt(document, id, value, registry)
            % attempt Capture a failed preflight without changing its transactional behavior.
            arguments (Input)
                document (1, 1) macd.model.DocumentModel
                id (1, 1) string
                value
                registry (1, 1) macd.model.ComponentRegistry
            end
            arguments (Output)
                identifier (1, 1) string
            end
            identifier = "";
            try
                document.setProperty(id, "Text", value, registry);
            catch exception
                identifier = string(exception.identifier);
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
