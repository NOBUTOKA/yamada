classdef (TestTags = {'fast', 'parser'}) CallbackSourceAnalyzerTest < matlab.unittest.TestCase
    % CallbackSourceAnalyzerTest Verify nonexecuting callback source ownership checks.
    %   Fixtures exercise whole method spans, ambiguous binding scopes and sharing
    %   while ensuring analysis does not change document source or history.

    methods (Test)
        function recognizesOwnedMethodIncludingNestedBlocks(testCase)
            % recognizesOwnedMethodIncludingNestedBlocks Locate complete method help and body.
            evalin("base", "clear macdCallbackAnalyzerSentinel");
            source = CallbackSourceAnalyzerTest.fixture( ...
                "app.Button.ButtonPushedFcn = createCallbackFcn(app, @Pressed, true);", ...
                ["if true"; "assignin('base','macdCallbackAnalyzerSentinel',true);"; "end"]);
            [state, document] = CallbackSourceAnalyzerTest.inspect(source);
            testCase.verifyEqual(state.State, "editable");
            testCase.verifyEqual(state.HandlerName, "Pressed");
            method = extractBetween(source, state.MethodSpan.StartOffset, state.MethodSpan.EndOffset);
            testCase.verifySubstring(method, "% Pressed Keep the test callback inert.");
            testCase.verifySubstring(method, "assignin('base','macdCallbackAnalyzerSentinel',true);");
            testCase.verifyTrue(endsWith(strtrim(method), "end"));
            testCase.verifyEqual(document.OriginalText, source);
            testCase.verifyEmpty(document.History);
            testCase.verifyFalse(document.IsDirty);
            generated = macd.source.RoundTripGenerator().generate(document);
            testCase.verifyEqual(generated, source);
            testCase.verifyEqual(evalin("base", "exist('macdCallbackAnalyzerSentinel','var')"), 0);
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
            binding = "app.Button.ButtonPushedFcn = createCallbackFcn(app, @Pressed, true);";
            sources = [ ...
                CallbackSourceAnalyzerTest.fixture(["if true"; binding; "end"], ""); ...
                CallbackSourceAnalyzerTest.fixture([binding; binding], ""); ...
                CallbackSourceAnalyzerTest.fixture("app.Button.ButtonPushedFcn = @(src,event) disp(event);", ""); ...
                CallbackSourceAnalyzerTest.fixture(binding, "app.Pressed([]);"); ...
                CallbackSourceAnalyzerTest.fixture(binding, "feval('unknown');"); ...
                CallbackSourceAnalyzerTest.fixture("set(app.Button, 'ButtonPushedFcn', @app.Pressed);", ""); ...
                CallbackSourceAnalyzerTest.fixture("alias.ButtonPushedFcn = @app.Pressed;", ""); ...
                CallbackSourceAnalyzerTest.fixture([binding; "app.Other.ButtonPushedFcn = createCallbackFcn(app, @Pressed, true);"], "")];
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
                ["app.Button.ButtonPushedFcn = createCallbackFcn( ..."; "app, @Pressed, true);"]};
            for index = 1:numel(bindings)
                [state, ~] = CallbackSourceAnalyzerTest.inspect( ...
                    CallbackSourceAnalyzerTest.fixture(bindings{index}, ""));
                testCase.verifyEqual(state.State, "editable");
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

        function newComponentCallbacksAreAbsentAndMissingHandlersAreUnsupported(testCase)
            % newComponentCallbacksAreAbsentAndMissingHandlersAreUnsupported Cover generated and unresolved records.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.DocumentModel("NewCallbackApp");
            component = macd.model.ComponentRecord("button", "Button", "uibutton", ...
                "matlab.ui.control.Button", "generated");
            document.addComponent(component);
            states = macd.source.CallbackSourceAnalyzer.analyze(document, component.Id, registry);
            testCase.verifyTrue(all(string({states.State}) == "absent"));
            source = CallbackSourceAnalyzerTest.fixture( ...
                "app.Button.ButtonPushedFcn = createCallbackFcn(app, @Missing, true);", "");
            [state, ~] = CallbackSourceAnalyzerTest.inspect(source);
            testCase.verifyEqual(state.State, "unsupported");
        end
    end

    methods (Static, Access = private)
        function source = fixture(binding, body)
            % fixture Build preserved AppBase text with a complete callback method.
            arguments (Input)
                binding string
                body string
            end
            arguments (Output)
                source (1, 1) string
            end
            lines = ["classdef CallbackFixture < matlab.apps.AppBase"; ...
                "properties (Access = public)"; ...
                "UIFigure matlab.ui.Figure"; "Button matlab.ui.control.Button"; "end"; ...
                "methods (Access = private)"; "function createComponents(app)"; ...
                "app.UIFigure = uifigure('Visible', 'off');"; ...
                "app.Button = uibutton(app.UIFigure);"; binding(:); "end"; ...
                "function Pressed(app, event)"; "% Pressed Keep the test callback inert."; ...
                body(:); "end"; "end"; "end"];
            source = strjoin(lines, string(newline)) + newline;
        end

        function [state, document] = inspect(source)
            % inspect Parse fixture source and select its ButtonPushedFcn ownership result.
            arguments (Input)
                source (1, 1) string
            end
            arguments (Output)
                state (1, 1) macd.model.CallbackState
                document (1, 1) macd.model.DocumentModel
            end
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.source.AppSourceParser.parseText(source, registry);
            component = document.getComponentByName("Button");
            states = macd.source.CallbackSourceAnalyzer.analyze(document, component.Id, registry);
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
