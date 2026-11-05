classdef (TestTags = {'fast', 'parser'}) CallbackSourceAnalyzerTest < matlab.unittest.TestCase
    % CallbackSourceAnalyzerTest Verify nonexecuting callback source ownership checks.
    %   Fixtures exercise whole method spans, ambiguous binding scopes and sharing
    %   while ensuring analysis does not change document source or history.

    methods (Test)
        function sharesCandidateScansAcrossParsedOwners(testCase)
            % sharesCandidateScansAcrossParsedOwners Scan the source once per callback name across many component queries.
            registry = yamada.model.ComponentRegistry.createDefault();
            source = CallbackSourceAnalyzerTest.fixture("", "");
            declarations = strings(1, 24);
            creations = strings(1, 24);
            for index = 1:24
                name = "Other" + index;
                declarations(index) = name + " matlab.ui.control.Button";
                creations(index) = "app." + name + " = uibutton(app.UIFigure);";
            end
            source = replace(source, "Button matlab.ui.control.Button", ...
                strjoin(["Button matlab.ui.control.Button", declarations], newline));
            source = replace(source, "app.Button = uibutton(app.UIFigure);", ...
                strjoin(["app.Button = uibutton(app.UIFigure);", creations], newline));
            document = yamada.source.AppSourceParser.parseText(source, registry);
            buttons = document.Components(string({document.Components.Factory}) == "uibutton");
            for repeat = 1:2
                for button = buttons
                    states = yamada.source.CallbackSourceAnalyzer.analyze(document, button.Id, registry);
                    testCase.verifyTrue(all(string({states.State}) == "absent"));
                end
            end
        end

        function candidateFilteringPreservesFirstBlockingReason(testCase)
            % candidateFilteringPreservesFirstBlockingReason Keep source-order precedence for dynamic and indirect references.
            indirect = "alias.ButtonPushedFcn = @app.Pressed;";
            dynamic = "feval('unknown');";
            for order = 1:2
                lines = [indirect; dynamic];
                expected = "Indirect callback access prevents proving assignment ownership.";
                if order == 2
                    lines = flip(lines);
                    expected = "Dynamic source references prevent safe callback editing.";
                end
                [state, ~] = CallbackSourceAnalyzerTest.inspect(CallbackSourceAnalyzerTest.fixture(lines, ""));
                testCase.verifyEqual(state.State, "unsupported");
                testCase.verifyEqual(state.Reason, expected);
            end
            [state, ~] = CallbackSourceAnalyzerTest.inspect(CallbackSourceAnalyzerTest.fixture( ...
                "app.Other.ButtonPushedFcn = [];", ""));
            testCase.verifyEqual(state.State, "absent");
            [state, ~] = CallbackSourceAnalyzerTest.inspect(CallbackSourceAnalyzerTest.fixture( ...
                "text = ""app.Button.ButtonPushedFcn"";", ""));
            testCase.verifyEqual(state.State, "unsupported");
        end

        function changedSourceReplacesCandidateIndicesIndependently(testCase)
            % changedSourceReplacesCandidateIndicesIndependently Recompile changed text without poisoning another source owner.
            source = CallbackSourceAnalyzerTest.fixture("", "");
            [state, document] = CallbackSourceAnalyzerTest.inspect(source);
            testCase.assertEqual(state.State, "absent");
            copy = document.structuralCandidate();
            document.OriginalText = replace(source, "app.Button = uibutton(app.UIFigure);", ...
                "app.Button = uibutton(app.UIFigure);" + newline + "app.Button.ButtonPushedFcn = @app.Pressed;");
            registry = yamada.model.ComponentRegistry.createDefault();
            button = document.getComponentByName("Button");
            states = yamada.source.CallbackSourceAnalyzer.analyze(document, button.Id, registry);
            testCase.verifyEqual(states(string({states.Name}) == "ButtonPushedFcn").State, "editable");
            button = copy.getComponentByName("Button");
            states = yamada.source.CallbackSourceAnalyzer.analyze(copy, button.Id, registry);
            testCase.verifyEqual(states(string({states.Name}) == "ButtonPushedFcn").State, "absent");
            button.SourceSpans.Creation = yamada.model.SourceSpan(1, 1);
            states = yamada.source.CallbackSourceAnalyzer.analyze(copy, button.Id, registry);
            testCase.verifyTrue(all(string({states.State}) == "unsupported"));
        end

        function recognizesOwnedMethodIncludingNestedBlocks(testCase)
            % recognizesOwnedMethodIncludingNestedBlocks Locate complete method help and body.
            evalin("base", "clear yamadaCallbackAnalyzerSentinel");
            source = CallbackSourceAnalyzerTest.fixture( ...
                "app.Button.ButtonPushedFcn = @app.Pressed;", ...
                ["if true"; "assignin('base','yamadaCallbackAnalyzerSentinel',true);"; "end"]);
            [state, document] = CallbackSourceAnalyzerTest.inspect(source);
            testCase.verifyEqual(state.State, "editable");
            testCase.verifyEqual(state.HandlerName, "Pressed");
            method = extractBetween(source, state.MethodSpan.StartOffset, state.MethodSpan.EndOffset);
            testCase.verifySubstring(method, "% Pressed Keep the test callback inert.");
            testCase.verifySubstring(method, "assignin('base','yamadaCallbackAnalyzerSentinel',true);");
            testCase.verifyTrue(endsWith(strtrim(method), "end"));
            testCase.verifyEqual(document.OriginalText, source);
            testCase.verifyEmpty(document.History);
            testCase.verifyFalse(document.IsDirty);
            generated = yamada.source.RoundTripGenerator().generate(document);
            testCase.verifyEqual(generated, source);
            testCase.verifyEqual(evalin("base", "exist('yamadaCallbackAnalyzerSentinel','var')"), 0);
        end

        function recognizesAbsentAndExplicitlyEmptyBindings(testCase)
            % recognizesAbsentAndExplicitlyEmptyBindings Retain replacement spans for empty assignments.
            [absent, ~] = CallbackSourceAnalyzerTest.inspect(CallbackSourceAnalyzerTest.fixture("", ""));
            testCase.verifyEqual(absent.State, "absent");
            testCase.verifyEmpty(absent.BindingSpan);
            testCase.verifyGreaterThan(absent.BindingAnchor, 0);
            testCase.verifyGreaterThan(absent.MethodAnchor, 0);
            [empty, ~] = CallbackSourceAnalyzerTest.inspect( ...
                CallbackSourceAnalyzerTest.fixture("app.Button.ButtonPushedFcn = [];", ""));
            testCase.verifyEqual(empty.State, "absent");
            testCase.verifyTrue(empty.BindingSpan.isKnown());
        end

        function rejectsAmbiguousAssignmentsAndReferences(testCase)
            % rejectsAmbiguousAssignmentsAndReferences Block both actions when source ownership is uncertain.
            binding = "app.Button.ButtonPushedFcn = @app.Pressed;";
            sources = [ ...
                CallbackSourceAnalyzerTest.fixture(["if true"; binding; "end"], ""); ...
                CallbackSourceAnalyzerTest.fixture([binding; binding], ""); ...
                CallbackSourceAnalyzerTest.fixture("app.Button.ButtonPushedFcn = @(src,event) disp(event);", ""); ...
                CallbackSourceAnalyzerTest.fixture(binding, "app.Pressed([]);"); ...
                CallbackSourceAnalyzerTest.fixture(binding, "feval('unknown');"); ...
                CallbackSourceAnalyzerTest.fixture("set(app.Button, 'ButtonPushedFcn', @app.Pressed);", ""); ...
                CallbackSourceAnalyzerTest.fixture("alias.ButtonPushedFcn = @app.Pressed;", ""); ...
                CallbackSourceAnalyzerTest.fixture([binding; "app.Other.ButtonPushedFcn = @app.Pressed;"], "")];
            for source = sources(:)'
                [state, document] = CallbackSourceAnalyzerTest.inspect(source);
                testCase.verifyEqual(state.State, "unsupported");
                testCase.verifyNotEmpty(state.Reason);
                testCase.verifyEqual(document.OriginalText, source);
            end
        end

        function recognizesDirectMethodHandlesAndMultilineBindings(testCase)
            % recognizesDirectMethodHandlesAndMultilineBindings Cover direct handles and continuation syntax.
            bindings = {"app.Button.ButtonPushedFcn = @app.Pressed;", ...
                ["app.Button.ButtonPushedFcn = ..."; "@app.Pressed;"]};
            for index = 1:numel(bindings)
                [state, ~] = CallbackSourceAnalyzerTest.inspect( ...
                    CallbackSourceAnalyzerTest.fixture(bindings{index}, ""));
                testCase.verifyEqual(state.State, "editable");
            end
        end

        function recognizesAnonymousMethodForwarding(testCase)
            % recognizesAnonymousMethodForwarding Preserve inert wrappers with omitted or forwarded inputs.
            expressions = ["@(~, event) app.Pressed(event)", "@(~,~) app.Pressed()", ...
                "@(source,event) app.Pressed(source,event)", "@(source,~) app.Pressed(source)", ...
                "@(source,event) app.Pressed(event)", "@(source,event) app.Pressed()", ...
                "@ ( ~ , data ) app . Pressed ( data )"];
            for expression = expressions
                source = CallbackSourceAnalyzerTest.fixture( ...
                    "app.Button.ButtonPushedFcn = " + expression + ";", "");
                [state, document] = CallbackSourceAnalyzerTest.inspect(source);
                testCase.verifyEqual(state.State, "editable", expression);
                testCase.verifyEqual(state.HandlerName, "Pressed", expression);
                testCase.verifyTrue(state.MethodSpan.isKnown(), expression);
                testCase.verifyEqual(yamada.source.RoundTripGenerator().generate(document), source);
                testCase.verifyEmpty(document.History);
            end
        end

        function handlerNamesMayContainCallbackPropertyNames(testCase)
            % handlerNamesMayContainCallbackPropertyNames Match callback identifiers without confusing handler suffixes.
            registry = yamada.model.ComponentRegistry.createDefault();
            for name = ["ButtonPushedFcn", "CellEditCallback"]
                handler = "SampleTable" + name;
                source = CallbackSourceAnalyzerTest.fixture( ...
                    "app.Button." + name + " = @(~,event) app.Pressed(event);", "");
                source = replace(source, "Pressed", handler);
                if name == "CellEditCallback"
                    source = replace(source, "Button matlab.ui.control.Button", "Button matlab.ui.control.Table");
                    source = replace(source, "uibutton(app.UIFigure)", "uitable(app.UIFigure)");
                end
                document = yamada.source.AppSourceParser.parseText(source, registry);
                component = document.getComponentByName("Button");
                states = yamada.source.CallbackSourceAnalyzer.analyze(document, component.Id, registry);
                state = states(string({states.Name}) == name);
                testCase.verifyEqual(state.State, "editable", name);
                testCase.verifyEqual(state.HandlerName, handler);
                document.applyCallbackAction(component.Id, name, "Delete", registry);
                removed = yamada.source.RoundTripGenerator(registry).generate(document);
                testCase.verifyFalse(contains(removed, handler));
                document.undo();
                testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), source);
            end
        end

        function rejectsNonForwardingAnonymousBodies(testCase)
            % rejectsNonForwardingAnonymousBodies Reject captures, computed arguments, shadowing and compound calls.
            expressions = ["@(~,event) app.Pressed(other)", "@(~,event) app.Pressed(event.Value)", ...
                "@(~,event) app.Pressed(transform(event))", "@(~,event) app.Pressed(event) + 1", ...
                "@(app,event) app.Pressed(event)", "@(source,app) app.Pressed(source)", ...
                "@(event,event) app.Pressed(event)", "@(~,~) app.Pressed(~)", ...
                "@(source,event) app.Pressed(event,source)", "@(source,event) app.Pressed(event,event)", ...
                "@(event) app.Pressed(event)", "@(~,event) other.Pressed(event)"];
            for expression = expressions
                source = CallbackSourceAnalyzerTest.fixture( ...
                    "app.Button.ButtonPushedFcn = " + expression + ";", "");
                [state, document] = CallbackSourceAnalyzerTest.inspect(source);
                testCase.verifyEqual(state.State, "unsupported", expression);
                testCase.verifyNotEmpty(state.Reason, expression);
                testCase.verifyEqual(document.OriginalText, source);
            end
        end

        function forwardedHandlersStillRequireExclusiveOwnership(testCase)
            % forwardedHandlersStillRequireExclusiveOwnership Retain sharing and conditional-scope rejection.
            binding = "app.Button.ButtonPushedFcn = @(~,event) app.Pressed(event);";
            sources = [CallbackSourceAnalyzerTest.fixture([binding; ...
                "app.Other.ButtonPushedFcn = @(~,~) app.Pressed();"], ""); ...
                CallbackSourceAnalyzerTest.fixture(binding, "app.Pressed([]);"); ...
                CallbackSourceAnalyzerTest.fixture(["if true"; binding; "end"], "")];
            for source = sources'
                [state, ~] = CallbackSourceAnalyzerTest.inspect(source);
                testCase.verifyEqual(state.State, "unsupported");
            end
        end

        function rejectsConstructorBindingsAndUnbalancedScopes(testCase)
            % rejectsConstructorBindingsAndUnbalancedScopes Avoid unsafe edits of embedded or incomplete source.
            source = CallbackSourceAnalyzerTest.fixture("", "");
            source = replace(source, "app.Button = uibutton(app.UIFigure);", ...
                "app.Button = uibutton(app.UIFigure, ""ButtonPushedFcn"", @app.Pressed);");
            [state, ~] = CallbackSourceAnalyzerTest.inspect(source);
            testCase.verifyEqual(state.State, "unsupported");
            source = CallbackSourceAnalyzerTest.fixture("", "if true");
            [state, ~] = CallbackSourceAnalyzerTest.inspect(source);
            testCase.verifyEqual(state.State, "unsupported");
        end

        function generatedInsertionRechecksChangedParsedAnchors(testCase)
            % generatedInsertionRechecksChangedParsedAnchors Share source analysis without sharing mutable eligibility.
            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.source.AppSourceParser.parseText( ...
                CallbackSourceAnalyzerTest.fixture("", ""), registry);
            generated = yamada.model.ComponentRecord("new-button", "NewButton", "uibutton", ...
                "matlab.ui.control.Button", "generated");
            document.addComponent(generated, document.RootComponentId);
            shared = document.sourceAnalysis();
            states = yamada.source.CallbackSourceAnalyzer.analyze(document, generated.Id, registry);
            testCase.verifyTrue(all(string({states.State}) == "absent"));
            candidate = document.structuralCandidate();
            button = candidate.getComponentByName("Button");
            original = button.SourceSpans;
            for creation = {[], yamada.model.SourceSpan(1, 1), yamada.model.SourceSpan()}
                changed = original;
                changed.Creation = creation{1};
                button.SourceSpans = changed;
                rejected = yamada.source.CallbackSourceAnalyzer.analyze(candidate, generated.Id, registry);
                testCase.verifyTrue(all(string({rejected.State}) == "unsupported"));
                testCase.verifyEqual(candidate.sourceAnalysis(), shared);
                retained = yamada.source.CallbackSourceAnalyzer.analyze(document, generated.Id, registry);
                testCase.verifyEqual(retained, states);
            end
            button.SourceSpans = original;
            testCase.verifyEqual(yamada.source.CallbackSourceAnalyzer.analyze(candidate, generated.Id, registry), states);
            reloaded = yamada.source.AppSourceParser.parseText( ...
                replace(document.OriginalText, "app.Button = uibutton(app.UIFigure);", ...
                "if true" + newline + "app.Button = uibutton(app.UIFigure);" + newline + "end"), registry);
            replacement = yamada.model.ComponentRecord("new-button", "NewButton", "uibutton", ...
                "matlab.ui.control.Button", "generated");
            reloaded.addComponent(replacement, reloaded.RootComponentId);
            rejected = yamada.source.CallbackSourceAnalyzer.analyze(reloaded, replacement.Id, registry);
            testCase.verifyTrue(all(string({rejected.State}) == "unsupported"));
            testCase.verifyNotEqual(reloaded.sourceAnalysis(), shared);
        end

        function newComponentCallbacksAreAbsentAndMissingHandlersAreUnsupported(testCase)
            % newComponentCallbacksAreAbsentAndMissingHandlersAreUnsupported Cover generated and unresolved records.
            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.DocumentModel("NewCallbackApp");
            component = yamada.model.ComponentRecord("button", "Button", "uibutton", ...
                "matlab.ui.control.Button", "generated");
            document.addComponent(component);
            states = yamada.source.CallbackSourceAnalyzer.analyze(document, component.Id, registry);
            testCase.verifyTrue(all(string({states.State}) == "absent"));
            source = CallbackSourceAnalyzerTest.fixture( ...
                "app.Button.ButtonPushedFcn = @app.Missing;", "");
            [state, ~] = CallbackSourceAnalyzerTest.inspect(source);
            testCase.verifyEqual(state.State, "unsupported");
        end
    end

    methods (Static, Access = private)
        function source = fixture(binding, body)
            % fixture Build preserved handle-based text with a complete callback method.
            arguments (Input)
                binding string
                body string
            end
            arguments (Output)
                source (1, 1) string
            end
            lines = ["classdef CallbackFixture < handle"; ...
                "properties (Access = public)"; ...
                "UIFigure matlab.ui.Figure"; "Button matlab.ui.control.Button"; "end"; ...
                "methods (Access = private)"; "function createComponents(app)"; ...
                "app.UIFigure = uifigure('Visible', 'off');"; ...
                "app.Button = uibutton(app.UIFigure);"; binding(:); "end"; ...
                "function Pressed(app, source, event)"; "% Pressed Keep the test callback inert."; ...
                body(:); "end"; "end"; "end"];
            source = strjoin(lines, string(newline)) + newline;
        end

        function [state, document] = inspect(source)
            % inspect Parse fixture source and select its ButtonPushedFcn ownership result.
            arguments (Input)
                source (1, 1) string
            end
            arguments (Output)
                state (1, 1) yamada.model.CallbackState
                document (1, 1) yamada.model.DocumentModel
            end
            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.source.AppSourceParser.parseText(source, registry);
            component = document.getComponentByName("Button");
            states = yamada.source.CallbackSourceAnalyzer.analyze(document, component.Id, registry);
            state = states(string({states.Name}) == "ButtonPushedFcn");
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
