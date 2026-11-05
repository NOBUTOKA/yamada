classdef (TestTags = {'fast', 'parser', 'generation'}) InitializationScopeTest < matlab.unittest.TestCase
    % InitializationScopeTest Separate initial properties from runtime callback writes.
    %   These tests preserve callback source without executing it and verify
    %   that constructor-reachable assignments own editable initial values.

    methods (Test)
        function aConditionalCallDoesNotMakeItsDefiniteReturnFallThrough(testCase)
            % aConditionalCallDoesNotMakeItsDefiniteReturnFallThrough Distinguish call certainty from local control flow.
            source = testCase.returnFixture(["if app.UIFigure.Visible == ""on""", "configure(app);", ...
                "end", "finalize(app);"], ["app.Options.Value = ""Second"";", "return;", ...
                "app.Options.Value = ""Third"";"]);
            document = yamada.source.AppSourceParser.parseText(source, yamada.model.ComponentRegistry.createDefault());
            component = document.getComponentByName("Options");
            testCase.verifyNumElements(component.getSettings("Value"), 2);
            testCase.verifyFalse(component.getProperty("Value").IsEditable);
            testCase.verifyEqual(component.getProperty("Tooltip").LiteralValue, "Final");
        end

        function helperReturnStopsItsTailButNotItsCaller(testCase)
            % helperReturnStopsItsTailButNotItsCaller Keep the enclosing constructor's later calls reachable.
            source = testCase.returnFixture(["configure(app);", "finalize(app);"], ...
                ["app.Options.Value = ""Second"";", "return;", "app.Options.Value = ""Third"";"]);
            document = yamada.source.AppSourceParser.parseText(source, yamada.model.ComponentRegistry.createDefault());
            component = document.getComponentByName("Options");
            testCase.verifyEqual(component.getProperty("Value").LiteralValue, "Second");
            testCase.verifyEqual(component.getProperty("Tooltip").LiteralValue, "Final");
            testCase.verifyNumElements(component.getSettings("Value"), 2);
        end

        function constructorReturnDoesNotVisitLaterHelpers(testCase)
            % constructorReturnDoesNotVisitLaterHelpers Do not own settings in unreachable initializer calls.
            source = testCase.returnFixture(["return;", "configure(app);", "finalize(app);"], ...
                "app.Options.Value = ""Second"";");
            document = yamada.source.AppSourceParser.parseText(source, yamada.model.ComponentRegistry.createDefault());
            component = document.getComponentByName("Options");
            testCase.verifyEqual(component.getProperty("Value").LiteralValue, "First");
            testCase.verifyEmpty(component.getProperty("Tooltip"));
            testCase.verifyNumElements(component.getSettings("Value"), 1);
        end

        function guardedReturnMakesOnlyTheCurrentMethodTailUncertain(testCase)
            % guardedReturnMakesOnlyTheCurrentMethodTailUncertain Preserve conditional ownership without contaminating caller certainty.
            source = testCase.returnFixture(["configure(app);", "finalize(app);"], ...
                ["if app.UIFigure.Visible == ""on""", "return;", "end", "app.Options.Value = ""Second"";"]);
            document = yamada.source.AppSourceParser.parseText(source, yamada.model.ComponentRegistry.createDefault());
            component = document.getComponentByName("Options");
            testCase.verifyFalse(component.getProperty("Value").IsEditable);
            testCase.verifyTrue(component.getProperty("Tooltip").IsEditable);
            testCase.verifyEqual(component.getProperty("Tooltip").LiteralValue, "Final");
        end

        function callbackExpressionsDoNotLockInitialValues(testCase)
            % callbackExpressionsDoNotLockInitialValues Ignore runtime writes in either method order and nested functions.
            registry = yamada.model.ComponentRegistry.createDefault();
            for placement = ["before", "after", "nested"]
                [source, callback] = InitializationScopeTest.fixture(placement, false);
                [document, diagnostics] = yamada.source.AppSourceParser.parseText(source, registry);
                options = document.getComponentByName("Options");
                testCase.assertNotEmpty(options, placement);
                for path = ["Value", "Items"]
                    entry = options.getProperty(path);
                    testCase.verifyTrue(entry.IsEditable, placement + ": " + path);
                    testCase.verifyEqual(entry.ValueKind, "literal");
                    owned = extractBetween(source, entry.SourceSpan.StartOffset, entry.SourceSpan.EndOffset);
                    testCase.verifyFalse(contains(owned, "event."));
                end
                testCase.verifyEqual(options.getProperty("Value").LiteralValue, "First");
                testCase.verifyEqual(options.getProperty("Items").LiteralValue, ["First", "Second"]);
                testCase.verifyFalse(any(ismember(string({diagnostics.Code}), ...
                    ["source-expression", "assignment-before-creation", "unknown-assignment-component"])));
                testCase.verifyEqual(document.OriginalText, source);

                % Edit only the initialized value while preserving the entire callback body.
                document.setProperty(options.Id, "Value", "Second");
                [generated, generatedDiagnostics] = yamada.source.RoundTripGenerator(registry).generate(document);
                testCase.verifyFalse(yamada.validation.ModelValidator.hasErrors(generatedDiagnostics));
                testCase.verifySubstring(generated, callback);
                testCase.verifySubstring(generated, "app.Options.Value = ""Second"";");
            end
        end

        function callbackLiteralsDoNotReplaceInitialValuesOrSpans(testCase)
            % callbackLiteralsDoNotReplaceInitialValuesOrSpans Keep later literal runtime values out of the model.
            registry = yamada.model.ComponentRegistry.createDefault();
            [source, callback] = InitializationScopeTest.fixture("after", true);
            document = yamada.source.AppSourceParser.parseText(source, registry);
            options = document.getComponentByName("Options");
            testCase.verifyEqual(options.getProperty("Value").LiteralValue, "First");
            testCase.verifyEqual(options.getProperty("Items").LiteralValue, ["First", "Second"]);
            document.setProperty(options.Id, "Items", ["First", "Second", "Third"]);
            generated = yamada.source.RoundTripGenerator(registry).generate(document);
            testCase.verifySubstring(generated, callback);
            testCase.verifySubstring(generated, 'app.Options.Items = ["First" "Second" "Third"];');
        end

        function initializationExpressionsRemainReadOnly(testCase)
            % initializationExpressionsRemainReadOnly Preserve unsafe initialization even when a callback writes literals.
            registry = yamada.model.ComponentRegistry.createDefault();
            [source, ~] = InitializationScopeTest.fixture("after", true);
            source = replace(source, 'app.Options.Value = "First";', 'app.Options.Value = initialValue(app);');
            [document, diagnostics] = yamada.source.AppSourceParser.parseText(source, registry);
            options = document.getComponentByName("Options");
            entry = options.getProperty("Value");
            testCase.verifyFalse(entry.IsEditable);
            testCase.verifyEqual(entry.SourceExpression, "initialValue(app)");
            testCase.verifyTrue(any(string({diagnostics.Code}) == "source-expression"));
            testCase.verifyFalse(any(string({diagnostics.Code}) == "conflicting-property-assignment"));
        end

        function constructorInitializationRemainsSupported(testCase)
            % constructorInitializationRemainsSupported Preserve direct constructor values while excluding callbacks.
            registry = yamada.model.ComponentRegistry.createDefault();
            [source, ~] = InitializationScopeTest.fixture("after", false);
            source = replace(source, "function createComponents(app)", "function app = ScopeApp");
            document = yamada.source.AppSourceParser.parseText(source, registry);
            options = document.getComponentByName("Options");
            testCase.verifyEqual(options.getProperty("Value").LiteralValue, "First");
            testCase.verifyTrue(options.getProperty("Value").IsEditable);
            testCase.verifyEqual(options.getProperty("Items").LiteralValue, ["First", "Second"]);
        end

        function followsRenamedHelpersInCallOrderAndPreservesCallbacks(testCase)
            % followsRenamedHelpersInCallOrderAndPreservesCallbacks Trace multiple levels independently of file order.
            registry = yamada.model.ComponentRegistry.createDefault();
            [source, callback] = InitializationScopeTest.fixture("after", false);
            source = replace(source, "createComponents", "buildWidgets");
            helpers = strjoin(["        function app = ScopeApp"; ...
                "            app.bootstrap();"; ...
                "            app.Options.Value = ""First"";"; "        end"; ...
                "        function bootstrap(app)"; ...
                "            buildWidgets(app);"; "            app.chooseInitial();"; "        end"; ...
                "        function chooseInitial(app)"; ...
                "            app.Options.Value = ""Second"";"; "        end"], newline);
            source = replace(source, "    methods (Access = private)", "    methods (Access = private)" + newline + helpers);
            [document, diagnostics] = yamada.source.AppSourceParser.parseText(source, registry);
            options = document.getComponentByName("Options");
            testCase.verifyEqual(options.getProperty("Value").LiteralValue, "First");
            testCase.verifyTrue(options.getProperty("Items").IsEditable);
            testCase.verifyFalse(any(string({diagnostics.Code}) == "assignment-before-creation"));
            owned = extractBetween(source, options.getProperty("Value").SourceSpan.StartOffset, options.getProperty("Value").SourceSpan.EndOffset);
            testCase.verifyEqual(strtrim(owned), "app.Options.Value = ""First"";");
            document.setProperty(options.Id, "Value", "Second");
            generated = yamada.source.RoundTripGenerator(registry).generate(document);
            testCase.verifySubstring(generated, callback);
        end

        function unreachableConventionalNameIsNotAnInitializer(testCase)
            % unreachableConventionalNameIsNotAnInitializer Do not privilege the createComponents spelling.
            registry = yamada.model.ComponentRegistry.createDefault();
            [source, ~] = InitializationScopeTest.fixture("after", false);
            source = replace(source, "createComponents", "buildWidgets");
            helpers = strjoin(["        function app = ScopeApp"; "            buildWidgets(app);"; ...
                "            listener = @(~, event) changed(app, event);"; "        end"; ...
                "        function createComponents(app)"; ...
                "            app.Options.Value = shouldNotRun(app);"; "        end"], newline);
            source = replace(source, "    methods (Access = private)", "    methods (Access = private)" + newline + helpers);
            document = yamada.source.AppSourceParser.parseText(source, registry);
            options = document.getComponentByName("Options");
            testCase.verifyTrue(options.getProperty("Value").IsEditable);
            testCase.verifyEqual(options.getProperty("Value").LiteralValue, "First");
        end

        function calledCallbacksAndHelpersAreInitialization(testCase)
            % calledCallbacksAndHelpersAreInitialization Include ordinary same-class function and method calls.
            registry = yamada.model.ComponentRegistry.createDefault();
            for call = ["changed(app, []);", "app.changed([]);"]
                [source, ~] = InitializationScopeTest.fixture("after", false);
                helpers = strjoin(["        function app = ScopeApp"; ...
                    "            createComponents(app);"; "            " + call; "        end"], newline);
                source = replace(source, "    methods (Access = private)", "    methods (Access = private)" + newline + helpers);
                document = yamada.source.AppSourceParser.parseText(source, registry);
                options = document.getComponentByName("Options");
                testCase.verifyFalse(options.getProperty("Value").IsEditable, call);
                testCase.verifyEqual(options.getProperty("Items").SourceExpression, "event.Source.UserData");
            end
        end

        function repeatedCallsAndRecursionAreBounded(testCase)
            % repeatedCallsAndRecursionAreBounded Preserve repeated visits and diagnose cycles without executing code.
            registry = yamada.model.ComponentRegistry.createDefault();
            [source, ~] = InitializationScopeTest.fixture("after", false);
            helpers = strjoin(["        function app = ScopeApp"; ...
                "            createComponents(app);"; "            second(app);"; ...
                "            first(app);"; "            second(app);"; "        end"; ...
                "        function second(app)"; "            app.Options.Value = ""Second"";"; "        end"; ...
                "        function first(app)"; "            app.Options.Value = ""First"";"; "        end"], newline);
            source = replace(source, "    methods (Access = private)", "    methods (Access = private)" + newline + helpers);
            document = yamada.source.AppSourceParser.parseText(source, registry);
            testCase.verifyEqual(document.getComponentByName("Options").getProperty("Value").LiteralValue, "Second");
            recursive = replace(source, "function first(app)", "function first(app)" + newline + "            first(app);");
            [~, diagnostics] = yamada.source.AppSourceParser.parseText(recursive, registry);
            testCase.verifyTrue(any(string({diagnostics.Code}) == "unresolved-initialization-call"));
        end

        function dynamicCallsAreDiagnosedButDeferredBodiesAreNot(testCase)
            % dynamicCallsAreDiagnosedButDeferredBodiesAreNot Report unresolved execution without treating registration as execution.
            registry = yamada.model.ComponentRegistry.createDefault();
            [source, ~] = InitializationScopeTest.fixture("after", false);
            helpers = strjoin(["        function app = ScopeApp"; ...
                "            createComponents(app);"; ...
                "            handler = @(~, ~) eval('unsafe');"; ...
                "            feval(@changed, app, []);"; "        end"], newline);
            source = replace(source, "    methods (Access = private)", "    methods (Access = private)" + newline + helpers);
            [~, diagnostics] = yamada.source.AppSourceParser.parseText(source, registry);
            unresolved = diagnostics(string({diagnostics.Code}) == "unresolved-initialization-call");
            testCase.verifyEqual(numel(unresolved), 1);
            testCase.verifySubstring(extractBetween(source, unresolved.SourceSpan.StartOffset, unresolved.SourceSpan.EndOffset), "feval");
        end

        function directCallsMayReceiveHandlesWithoutInvokingThem(testCase)
            % directCallsMayReceiveHandlesWithoutInvokingThem Execute the outer initializer, not its callback argument.
            registry = yamada.model.ComponentRegistry.createDefault();
            [source, ~] = InitializationScopeTest.fixture("after", false);
            source = replace(source, "function createComponents(app)", "function buildWidgets(app, varargin)");
            helpers = strjoin(["        function app = ScopeApp"; ...
                "            buildWidgets(app, @(~, event)changed(app, event));"; ...
                "            callback = @app.changed;"; ...
                "            buildWidgets(app, callback);"; "        end"], newline);
            source = replace(source, "    methods (Access = private)", "    methods (Access = private)" + newline + helpers);
            [document, diagnostics] = yamada.source.AppSourceParser.parseText(source, registry);
            options = document.getComponentByName("Options");
            testCase.verifyTrue(options.getProperty("Value").IsEditable);
            testCase.verifyEqual(options.getProperty("Value").LiteralValue, "First");
            testCase.verifyFalse(any(string({diagnostics.Code}) == "unresolved-initialization-call"));
        end
    end

    methods (Static, Access = private)
        function source = returnFixture(tail, configure)
            % returnFixture Build owned control-flow text without evaluating constructor conditions.
            arguments (Input)
                tail (1, :) string
                configure (1, :) string
            end
            arguments (Output)
                source (1, 1) string
            end
            source = strjoin(["classdef ReturnScopeApp < handle", "properties", ...
                "UIFigure matlab.ui.Figure", "Options matlab.ui.control.DropDown", "end", "methods", ...
                "function app = ReturnScopeApp", "createComponents(app);", tail, "end", ...
                "function createComponents(app)", "app.UIFigure = uifigure(Visible='off');", ...
                "app.Options = uidropdown(app.UIFigure);", "app.Options.Items = [""First"" ""Second""];", ...
                "app.Options.Value = ""First"";", "end", "function configure(app)", configure, "end", ...
                "function finalize(app)", "app.Options.Tooltip = ""Final"";", "end", "end", "end"], sprintf("\r\n"));
        end

        function [source, callback] = fixture(placement, literalWrites)
            % fixture Create an unexecuted handle-based source with runtime property mutations.
            arguments (Input)
                placement (1, 1) string {mustBeMember(placement, ["before", "after", "nested"])}
                literalWrites (1, 1) logical
            end
            arguments (Output)
                source (1, 1) string
                callback (1, 1) string
            end

            writes = ["            app.Options.Items = event.Source.UserData;"; ...
                "            app.Options.Value = chooseValue(app.Options);"];
            if literalWrites
                writes = ["            app.Options.Items = [""Runtime""];"; ...
                    "            app.Options.Value = ""Runtime"";"];
            end
            callback = strjoin(["        function changed(app, event)"; ...
                writes; "        end"], newline);
            initialization = ["        function createComponents(app)"; ...
                "            app.UIFigure = uifigure();"; ...
                "            app.Options = uidropdown(app.UIFigure);"; ...
                "            app.Options.Items = [""First"", ""Second""];"; ...
                "            app.Options.Value = ""First"";"];
            if placement == "nested", initialization(end + 1) = callback; end
            initialization(end + 1) = "        end";
            methods = strjoin(initialization, newline);
            if placement == "before"
                methods = callback + newline + methods;
            elseif placement == "after"
                methods = methods + newline + callback;
            end
            source = strjoin(["classdef ScopeApp < handle"; ...
                "    properties"; "        UIFigure matlab.ui.Figure"; ...
                "        Options matlab.ui.control.DropDown"; ...
                "    end"; ...
                "    methods (Access = private)"; methods; "    end"; "end"], newline) + newline;
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
