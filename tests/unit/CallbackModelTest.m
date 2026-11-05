classdef (TestTags = {'fast', 'model'}) CallbackModelTest < matlab.unittest.TestCase
    % CallbackModelTest Verify atomic callback intentions, history and safety rejection.
    %   These tests inspect authoritative model snapshots independently of the UI
    %   and preserve original method text for later localized source generation.

    methods (Test)
        function additionDeletionAndHistoryAreAtomic(testCase)
            % additionDeletionAndHistoryAreAtomic Restore pending methods and saved checkpoints exactly.
            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("CallbackApp", registry);
            button = document.insertComponent(registry, "uibutton", document.RootComponentId);
            document.markSaved();
            checkpoint = document.HistoryIndex;
            document.applyCallbackAction(button.Id, "ButtonPushedFcn", "Add", registry);
            testCase.verifyEqual(document.HistoryIndex, checkpoint + 1);
            added = document.History{end}.After;
            addedText = document.CurrentText;
            testCase.verifyEqual(numel(added), 1);
            testCase.verifySubstring(added.MethodText, "function " + added.HandlerName + "(app, source, event)");
            testCase.verifySubstring(added.MethodText, "% " + added.HandlerName);
            document.undo();
            testCase.verifyEmpty(document.CallbackEdits);
            testCase.verifyFalse(document.IsDirty);
            document.redo();
            testCase.verifyEqual(document.CurrentText, addedText);
            document.applyCallbackAction(button.Id, "ButtonPushedFcn", "Delete", registry);
            testCase.verifyEmpty(document.CallbackEdits);
            document.undo();
            testCase.verifyEqual(document.CurrentText, addedText);
            document.redo();
            testCase.verifyEmpty(document.CallbackEdits);
        end

        function rejectsRepeatedAndInvalidRequestsWithoutChangingState(testCase)
            % rejectsRepeatedAndInvalidRequestsWithoutChangingState Reject stale and unknown action targets before mutation.
            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("CallbackApp", registry);
            button = document.insertComponent(registry, "uibutton", document.RootComponentId);
            document.applyCallbackAction(button.Id, "ButtonPushedFcn", "Add", registry);
            before = document.CallbackEdits;
            history = document.History;
            testCase.verifyError(@() document.applyCallbackAction(button.Id, "ButtonPushedFcn", "Add", registry), ...
                "yamada:DocumentModel:UnsafeCallbackEdit");
            testCase.verifyError(@() document.applyCallbackAction("missing", "ButtonPushedFcn", "Delete", registry), ...
                "yamada:DocumentModel:UnsafeCallbackEdit");
            testCase.verifyError(@() document.applyCallbackAction(button.Id, "UnknownFcn", "Add", registry), ...
                "yamada:DocumentModel:UnsafeCallbackEdit");
            testCase.verifyEqual(document.CallbackEdits, before);
            testCase.verifyEqual(document.History, history);
        end

        function rejectsSharedMethodsAndGeneratesPendingCallbacks(testCase)
            % rejectsSharedMethodsAndGeneratesPendingCallbacks Protect unsafe source while generating validated operations.
            registry = yamada.model.ComponentRegistry.createDefault();
            path = fullfile(fileparts(fileparts(mfilename("fullpath"))), "fixtures", "SimpleCalculatorApp.m");
            source = string(fileread(path));
            source = replace(source, "app.CalculateButton = uibutton(app.GridLayout, 'push');", ...
                "app.CalculateButton = uibutton(app.GridLayout, 'push');" + newline + ...
                "app.UIFigure.CloseRequestFcn = @app.CalculateButtonPushed;");
            document = yamada.source.AppSourceParser.parseText(source, registry);
            component = document.getComponentByName("CalculateButton");
            testCase.verifyError(@() document.applyCallbackAction(component.Id, "ButtonPushedFcn", "Delete", registry), ...
                "yamada:DocumentModel:UnsafeCallbackEdit");
            testCase.verifyError(@() document.applyCallbackAction(component.Id, "ButtonPushedFcn", "Add", registry), ...
                "yamada:DocumentModel:UnsafeCallbackEdit");
            testCase.verifyFalse(document.IsDirty);
            testCase.verifyEmpty(document.History);
            fresh = yamada.model.NewAppFactory.createEmpty("CallbackApp", registry);
            fresh.applyCallbackAction(fresh.RootComponentId, "SizeChangedFcn", "Add", registry);
            [~, diagnostics] = yamada.source.NewAppGenerator(registry).generate(fresh);
            testCase.verifyFalse(yamada.validation.ModelValidator.hasErrors(diagnostics));
        end

        function generatedNamesAvoidSourceAndPendingCollisions(testCase)
            % generatedNamesAvoidSourceAndPendingCollisions Generate distinct valid names for multiple callback additions.
            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("UIFigureSizeChanged", registry);
            root = document.RootComponentId;
            document.applyCallbackAction(root, "SizeChangedFcn", "Add", registry);
            first = document.History{end}.After(1);
            testCase.verifyNotEqual(first.HandlerName, document.ClassName);
            testCase.verifyTrue(isvarname(first.HandlerName));
            document.applyCallbackAction(root, "CloseRequestFcn", "Add", registry);
            testCase.verifyNotEqual(document.History{end}.After(1).HandlerName, first.HandlerName);
        end

        function parsedDeletionPreservesOriginalBodyAndCanBeReplaced(testCase)
            % parsedDeletionPreservesOriginalBodyAndCanBeReplaced Retain original spans through delete/add and history.
            registry = yamada.model.ComponentRegistry.createDefault();
            path = fullfile(fileparts(fileparts(mfilename("fullpath"))), "fixtures", "SimpleCalculatorApp.m");
            document = yamada.source.AppSourceParser.parseFile(path, registry);
            component = document.getComponentByName("CalculateButton");
            original = document.OriginalText;
            document.applyCallbackAction(component.Id, "ButtonPushedFcn", "Delete", registry);
            removed = document.History{end}.After;
            deletedText = document.CurrentText;
            testCase.verifyTrue(removed.MethodSpan.isKnown());
            testCase.verifyTrue(removed.BindingSpan.isKnown());
            testCase.verifyEqual(document.OriginalText, original);
            document.applyCallbackAction(component.Id, "ButtonPushedFcn", "Add", registry);
            testCase.verifySubstring(document.CurrentText, document.History{end}.After.HandlerName + "(app");
            testCase.verifyNotEqual(document.History{end}.After.HandlerName, "CalculateButtonPushed");
            stale = document.structuralCandidate();
            stale.OriginalText = original + newline;
            testCase.verifyError(@() stale.applyCallbackAction(component.Id, "ButtonPushedFcn", "Delete", registry), ...
                "yamada:DocumentModel:UnsafeCallbackEdit");
            document.undo();
            testCase.verifyEqual(document.CurrentText, deletedText);
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
