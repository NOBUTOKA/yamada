classdef (TestTags = {'fast', 'generation'}) CallbackGenerationTest < matlab.unittest.TestCase
    % CallbackGenerationTest Verify complete callback source changes and reparsing.
    %   These tests cover new and opened documents, multiple insertion anchors,
    %   method-body deletion and atomic preflight failure without running apps.

    methods (Test)
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
            testCase.verifyTrue(contains(removed, "SizeChangedFcn = createCallbackFcn"));
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
