classdef (TestTags = {'fast', 'generation'}) CallbackGenerationTest < matlab.unittest.TestCase
    % CallbackGenerationTest Verify complete callback source changes and reparsing.
    %   These tests cover new and opened documents, multiple insertion anchors,
    %   binding removal that retains handler methods, and atomic preflight failure.

    methods (Test)
        % Guarantee: empty Items are encoded correctly and survive unrelated callback edits.
        % Failure mode: the first callback command on a New document regenerates the whole document, and an empty Items value is rewritten as a different empty form.
        function generatesNewAndEditedEmptyItems(testCase)
            % generatesNewAndEditedEmptyItems Encode empty list contents for new and parsed documents.
            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("EmptyItemsApp", registry);
            list = document.insertComponent(registry, "uilistbox", document.RootComponentId);
            list.setProperty("Items", {});
            generator = yamada.source.RoundTripGenerator(registry);
            [emptySource, diagnostics] = generator.generate(document);
            testCase.verifyFalse(yamada.validation.ModelValidator.hasErrors(diagnostics));
            testCase.verifySubstring(emptySource, "app." + list.Name + ".Items = {};");
            list.setProperty("Items", {'first'});
            parsed = yamada.source.AppSourceParser.parseText(generator.generate(document), registry);
            parsed.getComponentByName(list.Name).setProperty("Items", {});
            [edited, diagnostics] = generator.generate(parsed);
            testCase.verifyFalse(yamada.validation.ModelValidator.hasErrors(diagnostics));
            testCase.verifyEqual(edited, emptySource);
        end

        function unchangedEmptyItemsSurviveCallbackNewDisconnectAndUndo(testCase)
            % unchangedEmptyItemsSurviveCallbackNewDisconnectAndUndo Preserve unrelated empty cells during callback preflight.
            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("EmptyItemsApp", registry);
            document.insertComponent(registry, "uibutton", document.RootComponentId);
            document.insertComponent(registry, "uibutton", document.RootComponentId);
            list = document.insertComponent(registry, "uilistbox", document.RootComponentId);
            generator = yamada.source.RoundTripGenerator(registry);
            source = generator.generate(document);
            creation = "app." + list.Name + " = uilistbox(app.UIFigure);";
            assignment = "app." + list.Name + ".Items = {};";
            source = replace(source, creation, creation + newline + "            " + assignment);
            parsed = yamada.source.AppSourceParser.parseText(source, registry);
            testCase.verifyEqual(generator.generate(parsed), source);

            % Both buttons must generate handlers without rewriting the list assignment.
            for name = ["Button", "Button2"]
                button = parsed.getComponentByName(name);
                parsed.applyCallbackAction(button.Id, "ButtonPushedFcn", "New", registry, yamada.source.CallbackMethodTargets.defaultName(parsed, button.Id, "ButtonPushedFcn", registry));
            end
            [added, diagnostics] = generator.generate(parsed);
            testCase.verifyFalse(yamada.validation.ModelValidator.hasErrors(diagnostics));
            testCase.verifySubstring(added, assignment);
            reopened = yamada.source.AppSourceParser.parseText(added, registry);
            for name = ["Button", "Button2"]
                button = reopened.getComponentByName(name);
                states = yamada.source.CallbackSourceAnalyzer.analyze(reopened, button.Id, registry);
                testCase.verifyEqual(states(string({states.Name}) == "ButtonPushedFcn").State, "editable");
                reopened.applyCallbackAction(button.Id, "ButtonPushedFcn", "Disconnect", registry);
            end
            testCase.verifySubstring(generator.generate(reopened), assignment);
            reopened.undo();
            reopened.undo();
            testCase.verifyEqual(generator.generate(reopened), added);
            parsed.undo();
            parsed.undo();
            testCase.verifyEqual(generator.generate(parsed), source);
        end

        % Guarantee: New inserts exactly a binding and its method, Disconnect removes exactly the binding and keeps the method, and the result reopens with the same ownership.
        % Failure mode: Disconnect removes method or unrelated text, or an inserted binding or method is not recognized as owned after reopening.
        function newCallbacksRoundTripAndDisconnectKeepsMethod(testCase)
            % newCallbacksRoundTripAndDisconnectKeepsMethod Keep generated bindings and bodies consistent after reopening.
            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("CallbackApp", registry);
            button = document.insertComponent(registry, "uibutton", document.RootComponentId);
            document.applyCallbackAction(button.Id, "ButtonPushedFcn", "New", registry, yamada.source.CallbackMethodTargets.defaultName(document, button.Id, "ButtonPushedFcn", registry));
            document.applyCallbackAction(document.RootComponentId, "SizeChangedFcn", "New", registry, yamada.source.CallbackMethodTargets.defaultName(document, document.RootComponentId, "SizeChangedFcn", registry));
            generator = yamada.source.RoundTripGenerator(registry);
            [source, diagnostics] = generator.generate(document);
            testCase.verifyFalse(yamada.validation.ModelValidator.hasErrors(diagnostics));
            testCase.verifyEqual(generator.generate(document), source);
            reopened = yamada.source.AppSourceParser.parseText(source, registry);
            component = reopened.getComponentByName(button.Name);
            states = yamada.source.CallbackSourceAnalyzer.analyze(reopened, component.Id, registry);
            state = states(string({states.Name}) == "ButtonPushedFcn");
            testCase.verifyEqual(state.State, "editable");
            reopened.applyCallbackAction(component.Id, "ButtonPushedFcn", "Disconnect", registry);
            removed = generator.generate(reopened);
            testCase.verifyFalse(contains(removed, ".ButtonPushedFcn = @app." + state.HandlerName));
            testCase.verifySubstring(removed, "function " + state.HandlerName + "(app, source, event)");
            testCase.verifyTrue(contains(removed, "SizeChangedFcn = @app."));
            reopened.undo();
            testCase.verifyEqual(generator.generate(reopened), source);
        end

        function openedCallbacksPreserveUnrelatedTextAndCombineInsertions(testCase)
            % openedCallbacksPreserveUnrelatedTextAndCombineInsertions Remove owned bindings and preserve surrounding source.
            registry = yamada.model.ComponentRegistry.createDefault();
            path = fullfile(fileparts(fileparts(mfilename("fullpath"))), "fixtures", "SimpleCalculatorApp.m");
            document = yamada.source.AppSourceParser.parseFile(path, registry);
            original = document.OriginalText;
            button = document.getComponentByName("CalculateButton");
            document.applyCallbackAction(button.Id, "ButtonPushedFcn", "Disconnect", registry);
            document.applyCallbackAction(document.RootComponentId, "SizeChangedFcn", "New", registry, yamada.source.CallbackMethodTargets.defaultName(document, document.RootComponentId, "SizeChangedFcn", registry));
            document.applyCallbackAction(document.RootComponentId, "CloseRequestFcn", "New", registry, yamada.source.CallbackMethodTargets.defaultName(document, document.RootComponentId, "CloseRequestFcn", registry));
            generator = yamada.source.RoundTripGenerator(registry);
            source = generator.generate(document);
            testCase.verifyFalse(contains(source, "CalculateButton.ButtonPushedFcn"));
            testCase.verifySubstring(source, "function CalculateButtonPushed");
            testCase.verifySubstring(source, "leftValue = app.LeftValueField.Value");
            testCase.verifySubstring(source, "app.ResultLabel.Text = 'Result';");
            parsed = yamada.source.AppSourceParser.parseText(source, registry);
            states = yamada.source.CallbackSourceAnalyzer.analyze(parsed, parsed.RootComponentId, registry);
            testCase.verifyEqual(states(string({states.Name}) == "SizeChangedFcn").State, "editable");
            testCase.verifyEqual(states(string({states.Name}) == "CloseRequestFcn").State, "editable");
            document.undo(); document.undo(); document.undo();
            testCase.verifyEqual(generator.generate(document), original);
        end

        function generatedComponentsInOpenedAppsReceiveCallbacks(testCase)
            % generatedComponentsInOpenedAppsReceiveCallbacks Insert bindings beside newly generated initialization.
            registry = yamada.model.ComponentRegistry.createDefault();
            path = fullfile(fileparts(fileparts(mfilename("fullpath"))), "fixtures", "SimpleCalculatorApp.m");
            document = yamada.source.AppSourceParser.parseFile(path, registry);
            button = document.insertComponent(registry, "uibutton", document.RootComponentId);
            document.applyCallbackAction(button.Id, "ButtonPushedFcn", "New", registry, yamada.source.CallbackMethodTargets.defaultName(document, button.Id, "ButtonPushedFcn", registry));
            source = yamada.source.RoundTripGenerator(registry).generate(document);
            parsed = yamada.source.AppSourceParser.parseText(source, registry);
            component = parsed.getComponentByName(button.Name);
            states = yamada.source.CallbackSourceAnalyzer.analyze(parsed, component.Id, registry);
            testCase.verifyEqual(states(string({states.Name}) == "ButtonPushedFcn").State, "editable");
        end

        function anonymousForwardersPreserveSourceAndSupportDisconnectUndo(testCase)
            % anonymousForwardersPreserveSourceAndSupportDisconnectUndo Keep wrapper syntax and inert handler bodies intact.
            registry = yamada.model.ComponentRegistry.createDefault();
            generator = yamada.source.RoundTripGenerator(registry);
            evalin("base", "clear yamadaForwardedCallbackSentinel");
            for mode = ["event", "none", "both"]
                document = yamada.model.NewAppFactory.createEmpty("ForwardedCallbackApp", registry);
                button = document.insertComponent(registry, "uibutton", document.RootComponentId);
                document.applyCallbackAction(button.Id, "ButtonPushedFcn", "New", registry, yamada.source.CallbackMethodTargets.defaultName(document, button.Id, "ButtonPushedFcn", registry));
                states = yamada.source.CallbackSourceAnalyzer.analyze(document, button.Id, registry);
                handler = states(string({states.Name}) == "ButtonPushedFcn").HandlerName;
                source = generator.generate(document);
                ending = string(newline);
                if document.LineEnding == "CRLF", ending = string(sprintf("\r\n")); end
                expression = "@(~, event) app." + handler + "(event)";
                inputs = "app, event";
                if mode == "none"
                    expression = "@(~,~) app." + handler + "()";
                    inputs = "app";
                elseif mode == "both"
                    expression = "@(source,event) app." + handler + "(source,event)";
                    inputs = "app, source, event";
                end
                source = replace(source, "@app." + handler + ";", expression + ";");
                definitions = registry.getEffectiveCallbacks("uibutton");
                definition = definitions(string({definitions.Path}) == "ButtonPushedFcn");
                originalMethod = yamada.source.CallbackSourceEdits.handlerText( ...
                    handler, "ButtonPushedFcn", document.ClassName, ending, false, definition.CallbackSignature);
                testCase.assertSubstring(source, originalMethod);
                method = strjoin(["        function " + handler + "(" + inputs + ")"; ...
                    "            % " + handler + " Keep forwarded callback behavior inert."; ...
                    "            assignin('base','yamadaForwardedCallbackSentinel',true);"; ...
                    "        end"], ending);
                source = replace(source, originalMethod, method);
                testCase.assertSubstring(source, method);

                % Parsing and unrelated property edits retain the original registration and signature.
                parsed = yamada.source.AppSourceParser.parseText(source, registry);
                target = parsed.getComponentByName(button.Name);
                states = yamada.source.CallbackSourceAnalyzer.analyze(parsed, target.Id, registry);
                testCase.assertEqual(states(string({states.Name}) == "ButtonPushedFcn").State, "editable");
                testCase.verifyEqual(generator.generate(parsed), source);
                parsed.setProperty(target.Id, "Text", "Changed", registry);
                changed = generator.generate(parsed);
                testCase.verifySubstring(changed, expression + ";");
                testCase.verifySubstring(changed, method);
                parsed.undo();
                testCase.verifyEqual(generator.generate(parsed), source);

                % Default handler renames preserve the wrapper's inputs and forwarding convention.
                parsed.renameComponent(target.Id, "ForwardedButton", registry);
                renamedHandler = yamada.source.ComponentNameRewriter.defaultHandler("ForwardedButton", "ButtonPushedFcn", definition.HandlerSuffix);
                renamed = generator.generate(parsed);
                testCase.verifySubstring(renamed, replace(expression, "app." + handler, "app." + renamedHandler));
                testCase.verifySubstring(renamed, "function " + renamedHandler + "(" + inputs + ")");
                renamedDocument = yamada.source.AppSourceParser.parseText(renamed, registry);
                renamedTarget = renamedDocument.getComponentByName("ForwardedButton");
                renamedStates = yamada.source.CallbackSourceAnalyzer.analyze(renamedDocument, renamedTarget.Id, registry);
                testCase.verifyEqual(renamedStates(string({renamedStates.Name}) == "ButtonPushedFcn").State, "editable");
                parsed.undo();
                testCase.verifyEqual(generator.generate(parsed), source);

                % Disconnect removes the wrapper binding but keeps the method, and Undo restores the exact original bytes.
                parsed.applyCallbackAction(target.Id, "ButtonPushedFcn", "Disconnect", registry);
                removed = generator.generate(parsed);
                testCase.verifyFalse(contains(removed, expression));
                testCase.verifySubstring(removed, method);
                reopened = yamada.source.AppSourceParser.parseText(removed, registry);
                states = yamada.source.CallbackSourceAnalyzer.analyze( ...
                    reopened, reopened.getComponentByName(button.Name).Id, registry);
                testCase.verifyEqual(states(string({states.Name}) == "ButtonPushedFcn").State, "absent");
                parsed.undo();
                testCase.verifyEqual(generator.generate(parsed), source);
                parsed.redo();
                testCase.verifyEqual(generator.generate(parsed), removed);
                testCase.verifyEqual(evalin("base", "exist('yamadaForwardedCallbackSentinel','var')"), 0);
            end
        end

        function failedGenerationRollsBackEveryTemporaryModelChange(testCase)
            % failedGenerationRollsBackEveryTemporaryModelChange Reject an invalid sibling value without recording history.
            % Guarantee: failed callback generation leaves no temporary model change or history.
            % Failure mode: an invalid sibling value aborts generation after partial mutation.
            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("CallbackApp", registry);
            root = document.getComponent(document.RootComponentId);
            entry = root.setProperty("Name", []);
            entry.setSourceExpression("unsafeName()");
            document.GeneratedText = "previous preview";
            before = document.History;
            beforeDiagnostics = document.Diagnostics;
            testCase.verifyError(@() document.applyCallbackAction(root.Id, "SizeChangedFcn", "New", registry, yamada.source.CallbackMethodTargets.defaultName(document, root.Id, "SizeChangedFcn", registry)), ...
                "yamada:DocumentModel:UnsafeCallbackSource");
            testCase.verifyEmpty(document.CallbackEdits);
            testCase.verifyEqual(document.GeneratedText, "previous preview");
            testCase.verifyEqual(document.History, before);
            testCase.verifyEqual(document.Diagnostics, beforeDiagnostics);
            testCase.verifyFalse(document.IsDirty);
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
