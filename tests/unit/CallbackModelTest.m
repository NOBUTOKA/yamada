classdef (TestTags = {'fast', 'model'}) CallbackModelTest < matlab.unittest.TestCase
    % CallbackModelTest Verify atomic callback intentions, history and safety rejection.
    %   These tests inspect authoritative model snapshots independently of the UI
    %   and preserve original method text for later localized source generation.

    methods (Test)
        function additionDeletionAndHistoryAreAtomic(testCase)
            % additionDeletionAndHistoryAreAtomic Restore pending methods and saved checkpoints exactly.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("CallbackApp", registry);
            button = document.insertComponent(registry, "uibutton", document.RootComponentId);
            document.markSaved();
            checkpoint = document.HistoryIndex;
            document.applyCallbackAction(button.Id, "ButtonPushedFcn", "Add", registry);
            testCase.verifyEqual(document.HistoryIndex, checkpoint + 1);
            added = document.CallbackEdits;
            testCase.verifyEqual(numel(added), 1);
            testCase.verifySubstring(added.MethodText, "function " + added.HandlerName + "(app, event)");
            testCase.verifySubstring(added.MethodText, "% " + added.HandlerName);
            document.undo();
            testCase.verifyEmpty(document.CallbackEdits);
            testCase.verifyFalse(document.IsDirty);
            document.redo();
            testCase.verifyEqual(document.CallbackEdits, added);
            document.applyCallbackAction(button.Id, "ButtonPushedFcn", "Delete", registry);
            testCase.verifyEmpty(document.CallbackEdits);
            document.undo();
            testCase.verifyEqual(document.CallbackEdits, added);
            document.redo();
            testCase.verifyEmpty(document.CallbackEdits);
        end

        function rejectsRepeatedAndInvalidRequestsWithoutChangingState(testCase)
            % rejectsRepeatedAndInvalidRequestsWithoutChangingState Reject stale and unknown action targets before mutation.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("CallbackApp", registry);
            button = document.insertComponent(registry, "uibutton", document.RootComponentId);
            document.applyCallbackAction(button.Id, "ButtonPushedFcn", "Add", registry);
            before = document.CallbackEdits;
            history = document.History;
            testCase.verifyError(@() document.applyCallbackAction(button.Id, "ButtonPushedFcn", "Add", registry), ...
                "macd:DocumentModel:UnsafeCallbackEdit");
            testCase.verifyError(@() document.applyCallbackAction("missing", "ButtonPushedFcn", "Delete", registry), ...
                "macd:DocumentModel:UnsafeCallbackEdit");
            testCase.verifyError(@() document.applyCallbackAction(button.Id, "UnknownFcn", "Add", registry), ...
                "macd:DocumentModel:UnsafeCallbackEdit");
            testCase.verifyEqual(document.CallbackEdits, before);
            testCase.verifyEqual(document.History, history);
        end

        function rejectsSharedMethodsAndBlocksPendingGeneration(testCase)
            % rejectsSharedMethodsAndBlocksPendingGeneration Protect both unsafe source and staged generation.
            registry = macd.model.ComponentRegistry.createDefault();
            path = fullfile(fileparts(fileparts(mfilename("fullpath"))), "fixtures", "SimpleCalculatorApp.m");
            source = string(fileread(path));
            source = replace(source, "app.CalculateButton = uibutton(app.GridLayout, 'push');", ...
                "app.CalculateButton = uibutton(app.GridLayout, 'push');" + newline + ...
                "app.UIFigure.CloseRequestFcn = createCallbackFcn(app, @CalculateButtonPushed, true);");
            document = macd.source.AppSourceParser.parseText(source, registry);
            component = document.getComponentByName("CalculateButton");
            testCase.verifyError(@() document.applyCallbackAction(component.Id, "ButtonPushedFcn", "Delete", registry), ...
                "macd:DocumentModel:UnsafeCallbackEdit");
            testCase.verifyError(@() document.applyCallbackAction(component.Id, "ButtonPushedFcn", "Add", registry), ...
                "macd:DocumentModel:UnsafeCallbackEdit");
            testCase.verifyFalse(document.IsDirty);
            testCase.verifyEmpty(document.History);
            fresh = macd.model.NewAppFactory.createEmpty("CallbackApp", registry);
            fresh.applyCallbackAction(fresh.RootComponentId, "SizeChangedFcn", "Add", registry);
            [~, diagnostics] = macd.source.NewAppGenerator(registry).generate(fresh);
            testCase.verifyTrue(macd.validation.ModelValidator.hasErrors(diagnostics));
        end

        function generatedNamesAvoidSourceAndPendingCollisions(testCase)
            % generatedNamesAvoidSourceAndPendingCollisions Generate distinct valid names for multiple callback additions.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("UIFigureSizeChanged", registry);
            root = document.RootComponentId;
            document.applyCallbackAction(root, "SizeChangedFcn", "Add", registry);
            first = document.CallbackEdits(1);
            testCase.verifyNotEqual(first.HandlerName, document.ClassName);
            testCase.verifyTrue(isvarname(first.HandlerName));
            document.applyCallbackAction(root, "CloseRequestFcn", "Add", registry);
            testCase.verifyNotEqual(document.CallbackEdits(2).HandlerName, first.HandlerName);
        end

        function parsedDeletionPreservesOriginalBodyAndCanBeReplaced(testCase)
            % parsedDeletionPreservesOriginalBodyAndCanBeReplaced Retain original spans through delete/add and history.
            registry = macd.model.ComponentRegistry.createDefault();
            path = fullfile(fileparts(fileparts(mfilename("fullpath"))), "fixtures", "SimpleCalculatorApp.m");
            document = macd.source.AppSourceParser.parseFile(path, registry);
            component = document.getComponentByName("CalculateButton");
            original = document.OriginalText;
            document.applyCallbackAction(component.Id, "ButtonPushedFcn", "Delete", registry);
            removed = document.CallbackEdits;
            testCase.verifyTrue(removed.MethodSpan.isKnown());
            testCase.verifyTrue(removed.BindingSpan.isKnown());
            testCase.verifyEqual(document.OriginalText, original);
            document.applyCallbackAction(component.Id, "ButtonPushedFcn", "Add", registry);
            testCase.verifyEqual(document.CallbackEdits.MethodSpan, removed.MethodSpan);
            testCase.verifyNotEqual(document.CallbackEdits.HandlerName, "CalculateButtonPushed");
            document.OriginalText = original + newline;
            testCase.verifyError(@() document.applyCallbackAction(component.Id, "ButtonPushedFcn", "Delete", registry), ...
                "macd:DocumentModel:UnsafeCallbackEdit");
            document.OriginalText = original;
            document.undo();
            testCase.verifyEqual(document.CallbackEdits, removed);
            document.undo();
            testCase.verifyEmpty(document.CallbackEdits);
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
