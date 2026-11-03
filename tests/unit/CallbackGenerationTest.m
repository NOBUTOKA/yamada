classdef (TestTags = {'fast', 'generation'}) CallbackGenerationTest < matlab.unittest.TestCase
    % CallbackGenerationTest Verify complete callback source changes and reparsing.
    %   These tests cover new and opened documents, multiple insertion anchors,
    %   method-body deletion and atomic preflight failure without running apps.

    methods (Test)
        function generatesNewAndEditedEmptyItems(testCase)
            % generatesNewAndEditedEmptyItems Encode empty list contents for new and parsed documents.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("EmptyItemsApp", registry);
            list = document.insertComponent(registry, "uilistbox", document.RootComponentId);
            list.setProperty("Items", {});
            generator = macd.source.RoundTripGenerator(registry);
            [emptySource, diagnostics] = generator.generate(document);
            testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
            testCase.verifySubstring(emptySource, "app." + list.Name + ".Items = {};");
            list.setProperty("Items", {'first'});
            parsed = macd.source.AppSourceParser.parseText(generator.generate(document), registry);
            parsed.getComponentByName(list.Name).setProperty("Items", {});
            [edited, diagnostics] = generator.generate(parsed);
            testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
            testCase.verifyEqual(edited, emptySource);
        end

        function unchangedEmptyItemsSurviveCallbackAddDeleteAndUndo(testCase)
            % unchangedEmptyItemsSurviveCallbackAddDeleteAndUndo Preserve unrelated empty cells during callback preflight.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("EmptyItemsApp", registry);
            document.insertComponent(registry, "uibutton", document.RootComponentId);
            document.insertComponent(registry, "uibutton", document.RootComponentId);
            list = document.insertComponent(registry, "uilistbox", document.RootComponentId);
            generator = macd.source.RoundTripGenerator(registry);
            source = generator.generate(document);
            creation = "app." + list.Name + " = uilistbox(app.UIFigure);";
            assignment = "app." + list.Name + ".Items = {};";
            source = replace(source, creation, creation + newline + "            " + assignment);
            parsed = macd.source.AppSourceParser.parseText(source, registry);
            testCase.verifyEqual(generator.generate(parsed), source);

            % Both buttons must generate handlers without rewriting the list assignment.
            for name = ["Button", "Button2"]
                button = parsed.getComponentByName(name);
                parsed.applyCallbackAction(button.Id, "ButtonPushedFcn", "Add", registry);
            end
            [added, diagnostics] = generator.generate(parsed);
            testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
            testCase.verifySubstring(added, assignment);
            reopened = macd.source.AppSourceParser.parseText(added, registry);
            for name = ["Button", "Button2"]
                button = reopened.getComponentByName(name);
                states = macd.source.CallbackSourceAnalyzer.analyze(reopened, button.Id, registry);
                testCase.verifyEqual(states(string({states.Name}) == "ButtonPushedFcn").State, "editable");
                reopened.applyCallbackAction(button.Id, "ButtonPushedFcn", "Delete", registry);
            end
            testCase.verifySubstring(generator.generate(reopened), assignment);
            reopened.undo();
            reopened.undo();
            testCase.verifyEqual(generator.generate(reopened), added);
            parsed.undo();
            parsed.undo();
            testCase.verifyEqual(generator.generate(parsed), source);
        end

        function newCallbacksRoundTripAndDeleteEntireMethod(testCase)
            % newCallbacksRoundTripAndDeleteEntireMethod Keep generated bindings and bodies consistent after reopening.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("CallbackApp", registry);
            button = document.insertComponent(registry, "uibutton", document.RootComponentId);
            document.applyCallbackAction(button.Id, "ButtonPushedFcn", "Add", registry);
            document.applyCallbackAction(document.RootComponentId, "SizeChangedFcn", "Add", registry);
            generator = macd.source.RoundTripGenerator(registry);
            [source, diagnostics] = generator.generate(document);
            testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
            testCase.verifyEqual(generator.generate(document), source);
            reopened = macd.source.AppSourceParser.parseText(source, registry);
            component = reopened.getComponentByName(button.Name);
            states = macd.source.CallbackSourceAnalyzer.analyze(reopened, component.Id, registry);
            state = states(string({states.Name}) == "ButtonPushedFcn");
            testCase.verifyEqual(state.State, "editable");
            reopened.applyCallbackAction(component.Id, "ButtonPushedFcn", "Delete", registry);
            removed = generator.generate(reopened);
            testCase.verifyFalse(contains(removed, state.HandlerName));
            testCase.verifyTrue(contains(removed, "SizeChangedFcn = @app."));
            reopened.undo();
            testCase.verifyEqual(generator.generate(reopened), source);
        end

        function openedCallbacksPreserveUnrelatedTextAndCombineInsertions(testCase)
            % openedCallbacksPreserveUnrelatedTextAndCombineInsertions Remove owned bodies and preserve surrounding source.
            registry = macd.model.ComponentRegistry.createDefault();
            path = fullfile(fileparts(fileparts(mfilename("fullpath"))), "fixtures", "SimpleCalculatorApp.m");
            document = macd.source.AppSourceParser.parseFile(path, registry);
            original = document.OriginalText;
            button = document.getComponentByName("CalculateButton");
            document.applyCallbackAction(button.Id, "ButtonPushedFcn", "Delete", registry);
            document.applyCallbackAction(document.RootComponentId, "SizeChangedFcn", "Add", registry);
            document.applyCallbackAction(document.RootComponentId, "CloseRequestFcn", "Add", registry);
            generator = macd.source.RoundTripGenerator(registry);
            source = generator.generate(document);
            testCase.verifyFalse(contains(source, "function CalculateButtonPushed"));
            testCase.verifyFalse(contains(source, "leftValue = app.LeftValueField.Value"));
            testCase.verifySubstring(source, "app.ResultLabel.Text = 'Result';");
            parsed = macd.source.AppSourceParser.parseText(source, registry);
            states = macd.source.CallbackSourceAnalyzer.analyze(parsed, parsed.RootComponentId, registry);
            testCase.verifyEqual(states(string({states.Name}) == "SizeChangedFcn").State, "editable");
            testCase.verifyEqual(states(string({states.Name}) == "CloseRequestFcn").State, "editable");
            document.undo(); document.undo(); document.undo();
            testCase.verifyEqual(generator.generate(document), original);
        end

        function generatedComponentsInOpenedAppsReceiveCallbacks(testCase)
            % generatedComponentsInOpenedAppsReceiveCallbacks Insert bindings beside newly generated initialization.
            registry = macd.model.ComponentRegistry.createDefault();
            path = fullfile(fileparts(fileparts(mfilename("fullpath"))), "fixtures", "SimpleCalculatorApp.m");
            document = macd.source.AppSourceParser.parseFile(path, registry);
            button = document.insertComponent(registry, "uibutton", document.RootComponentId);
            document.applyCallbackAction(button.Id, "ButtonPushedFcn", "Add", registry);
            source = macd.source.RoundTripGenerator(registry).generate(document);
            parsed = macd.source.AppSourceParser.parseText(source, registry);
            component = parsed.getComponentByName(button.Name);
            states = macd.source.CallbackSourceAnalyzer.analyze(parsed, component.Id, registry);
            testCase.verifyEqual(states(string({states.Name}) == "ButtonPushedFcn").State, "editable");
        end

        function savedEditedBodiesAreRemovedWithoutExecutingThem(testCase)
            % savedEditedBodiesAreRemovedWithoutExecutingThem Reparse a saved externally edited method before deletion.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("SavedCallbackApp", registry);
            document.applyCallbackAction(document.RootComponentId, "SizeChangedFcn", "Add", registry);
            generator = macd.source.RoundTripGenerator(registry);
            source = generator.generate(document);
            source = replace(source, "% Add callback behavior here.", ...
                "assignin('base','macdCallbackSaveSentinel',true);");
            evalin("base", "clear macdCallbackSaveSentinel");
            path = string(tempname) + ".m";
            cleanup = onCleanup(@() delete(path));
            macd.source.SourceWriter.write(path, source, "CRLF");
            loaded = macd.source.AppSourceParser.parseFile(path, registry);
            loaded.applyCallbackAction(loaded.RootComponentId, "SizeChangedFcn", "Delete", registry);
            removed = generator.generate(loaded);
            testCase.verifyFalse(contains(removed, "macdCallbackSaveSentinel"));
            testCase.verifyEqual(evalin("base", "exist('macdCallbackSaveSentinel','var')"), 0);
            loaded.undo();
            testCase.verifyEqual(generator.generate(loaded), source);
        end

        function anonymousForwardersPreserveSourceAndSupportDeleteUndo(testCase)
            % anonymousForwardersPreserveSourceAndSupportDeleteUndo Keep wrapper syntax and inert handler bodies intact.
            registry = macd.model.ComponentRegistry.createDefault();
            generator = macd.source.RoundTripGenerator(registry);
            evalin("base", "clear macdForwardedCallbackSentinel");
            for mode = ["event", "none", "both"]
                document = macd.model.NewAppFactory.createEmpty("ForwardedCallbackApp", registry);
                button = document.insertComponent(registry, "uibutton", document.RootComponentId);
                document.applyCallbackAction(button.Id, "ButtonPushedFcn", "Add", registry);
                states = macd.source.CallbackSourceAnalyzer.analyze(document, button.Id, registry);
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
                originalMethod = macd.source.CallbackSourceEdits.handlerText( ...
                    handler, "ButtonPushedFcn", document.ClassName, ending);
                method = strjoin(["        function " + handler + "(" + inputs + ")"; ...
                    "            % " + handler + " Keep forwarded callback behavior inert."; ...
                    "            assignin('base','macdForwardedCallbackSentinel',true);"; ...
                    "        end"], ending);
                source = replace(source, originalMethod, method);
                testCase.assertSubstring(source, method);

                % Parsing and unrelated property edits retain the original registration and signature.
                parsed = macd.source.AppSourceParser.parseText(source, registry);
                target = parsed.getComponentByName(button.Name);
                states = macd.source.CallbackSourceAnalyzer.analyze(parsed, target.Id, registry);
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
                renamedHandler = macd.source.ComponentNameRewriter.defaultHandler("ForwardedButton", "ButtonPushedFcn");
                renamed = generator.generate(parsed);
                testCase.verifySubstring(renamed, replace(expression, "app." + handler, "app." + renamedHandler));
                testCase.verifySubstring(renamed, "function " + renamedHandler + "(" + inputs + ")");
                renamedDocument = macd.source.AppSourceParser.parseText(renamed, registry);
                renamedTarget = renamedDocument.getComponentByName("ForwardedButton");
                renamedStates = macd.source.CallbackSourceAnalyzer.analyze(renamedDocument, renamedTarget.Id, registry);
                testCase.verifyEqual(renamedStates(string({renamedStates.Name}) == "ButtonPushedFcn").State, "editable");
                parsed.undo();
                testCase.verifyEqual(generator.generate(parsed), source);

                % One Delete removes both owned ranges, and Undo restores their exact original bytes.
                parsed.applyCallbackAction(target.Id, "ButtonPushedFcn", "Delete", registry);
                removed = generator.generate(parsed);
                testCase.verifyFalse(contains(removed, handler));
                reopened = macd.source.AppSourceParser.parseText(removed, registry);
                states = macd.source.CallbackSourceAnalyzer.analyze( ...
                    reopened, reopened.getComponentByName(button.Name).Id, registry);
                testCase.verifyEqual(states(string({states.Name}) == "ButtonPushedFcn").State, "absent");
                parsed.undo();
                testCase.verifyEqual(generator.generate(parsed), source);
                parsed.redo();
                testCase.verifyEqual(generator.generate(parsed), removed);
                testCase.verifyEqual(evalin("base", "exist('macdForwardedCallbackSentinel','var')"), 0);
            end
        end

        function failedGenerationRollsBackEveryTemporaryModelChange(testCase)
            % failedGenerationRollsBackEveryTemporaryModelChange Reject an invalid sibling value without recording history.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("CallbackApp", registry);
            root = document.getComponent(document.RootComponentId);
            entry = root.setProperty("Name", []);
            entry.setSourceExpression("unsafeName()");
            document.GeneratedText = "previous preview";
            before = document.History;
            beforeDiagnostics = document.Diagnostics;
            testCase.verifyError(@() document.applyCallbackAction(root.Id, "SizeChangedFcn", "Add", registry), ...
                "macd:DocumentModel:UnsafeCallbackSource");
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
