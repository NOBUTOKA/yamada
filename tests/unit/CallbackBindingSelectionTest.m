classdef (TestTags = {'fast', 'parser', 'generation'}) CallbackBindingSelectionTest < matlab.unittest.TestCase
    % CallbackBindingSelectionTest Verify binding-only callback transactions and cached method selection.
    %   Tests cover binding replacement, retained method bodies and atomic history.

    methods (Test)
        function firstCallbackCreationPreservesRootAndHistory(testCase)
            % firstCallbackCreationPreservesRootAndHistory Preserve root values, identity and clean Undo on the first callback creation.
            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("FirstCallbackFixture", registry);
            root = document.getComponent(document.RootComponentId);
            document.applyCallbackAction(root.Id, "SizeChangedFcn", "New", registry, "RootSized");
            document.undo();
            testCase.verifyFalse(document.IsDirty);
            document.redo();
            testCase.verifyEqual(document.getComponent(root.Id), root);
            testCase.verifyEqual(root.getProperty("Visible").LiteralValue, "on");
            testCase.verifySubstring(document.CurrentText, "SizeChangedFcn = @app.RootSized;");
            testCase.verifyEqual(document.HistoryIndex, 1);
        end

        function candidatesUseCachedSignaturesAndFixedArity(testCase)
            % candidatesUseCachedSignaturesAndFixedArity Exclude optional fourth inputs and retain unknown constraints.
            [document, registry, button] = CallbackBindingSelectionTest.fixture();
            analysis = document.sourceAnalysis();
            targets = yamada.source.CallbackMethodTargets.list(document, button.Id, "ButtonPushedFcn", registry);
            names = string({targets.Name});
            testCase.verifyTrue(all(ismember(["run0", "run1", "run2", "unknown", "baseEvent", "ignoredSource", "ignoredEvent"], names)));
            testCase.verifyFalse(any(ismember(["four", "variadic", "wrongSource", "wrongEvent", "delete", "createComponents", document.ClassName], names)));
            testCase.verifyEqual(targets(names == "run0").Expression, "@(~, ~) app.run0()");
            testCase.verifyEqual(targets(names == "run1").Expression, "@(~, event) app.run1(event)");
            testCase.verifyEqual(targets(names == "run2").Expression, "@app.run2");
            testCase.verifyEqual(targets(names == "ignoredSource").Label, ...
                "ignoredSource(app, ~, event matlab.ui.eventdata.ButtonPushedData)");
            testCase.verifyEqual(targets(names == "ignoredEvent").Label, ...
                "ignoredEvent(app, src matlab.ui.control.Button, ~)");
            testCase.verifyEqual(targets(names == "ignoredSource").Expression, "@app.ignoredSource");
            testCase.verifyTrue(targets(names == "unknown").Unchecked);
            testCase.verifySubstring(targets(names == "unknown").Label, "[unchecked]");
            [accepted, known] = yamada.source.CallbackMethodTargets.compatible("matlab.ui.eventdata.ButtonPushedData", "event.EventData");
            testCase.verifyTrue(accepted && known);
            [accepted, known] = yamada.source.CallbackMethodTargets.compatible("double", "event.EventData");
            testCase.verifyTrue(~accepted && known);
            testCase.verifyError(@() document.applyCallbackAction(button.Id, "ButtonPushedFcn", "Connect", registry, "missing"), ...
                "yamada:DocumentModel:UnsafeCallbackTarget");
            for index = 1:3
                testCase.verifyEqual(yamada.source.CallbackMethodTargets.list(document, button.Id, "ButtonPushedFcn", registry), targets);
                testCase.verifyEqual(document.sourceAnalysis(), analysis);
            end
        end

        function preparedChoicesFollowSourceAndHistory(testCase)
            % preparedChoicesFollowSourceAndHistory Refresh listed methods and binding ownership after edits and replay.
            [document, registry, button] = CallbackBindingSelectionTest.fixture();
            before = document.callbackRevision(registry);
            targets = document.callbackTargets(button.Id, "ButtonPushedFcn", registry);
            testCase.verifyFalse(any(string({targets.Name}) == "CreatedByChoice"));
            document.applyCallbackAction(button.Id, "ButtonPushedFcn", "New", registry, "CreatedByChoice");
            testCase.verifyNotEqual(document.callbackRevision(registry), before);
            targets = document.callbackTargets(button.Id, "ButtonPushedFcn", registry);
            testCase.verifyTrue(any(string({targets.Name}) == "CreatedByChoice"));
            document.undo();
            targets = document.callbackTargets(button.Id, "ButtonPushedFcn", registry);
            testCase.verifyFalse(any(string({targets.Name}) == "CreatedByChoice"));
            document.redo();
            states = document.callbackStates(button.Id, registry);
            selected = states(string({states.Name}) == "ButtonPushedFcn");
            testCase.verifyEqual(selected.HandlerName, "CreatedByChoice");
        end

        function callbackThenLiteralEditSurvivesSaveAndHistory(testCase)
            % callbackThenLiteralEditSurvivesSaveAndHistory Preserve current callback and value bindings through Save As and replay.
            [document, registry, button] = CallbackBindingSelectionTest.fixture();
            initial = document.CurrentText;
            document.applyCallbackAction(button.Id, "ButtonPushedFcn", "New", registry, "CreatedThenEdited");
            connected = document.CurrentText;
            document.setProperty(button.Id, "Text", "Changed after callback", registry);
            source = document.CurrentText;
            savedClass = "SavedCallbackThenLiteral";
            source = yamada.source.AppClassIdentityRewriter.rewrite(source, savedClass);
            checkpoint = yamada.model.SavedSourceCheckpoint(document, source, savedClass + ".m", registry);
            document.confirmSavedSource(checkpoint, registry);
            saved = document.CurrentText;
            document.undo();
            testCase.verifyEqual(document.CurrentText, yamada.source.AppClassIdentityRewriter.rewrite(connected, document.ClassName));
            document.undo();
            testCase.verifyEqual(document.CurrentText, yamada.source.AppClassIdentityRewriter.rewrite(initial, document.ClassName));
            document.redo(); document.redo();
            testCase.verifyEqual(document.CurrentText, saved);
            testCase.verifyEqual(button.getProperty("Text").LiteralValue, "Changed after callback");
            testCase.verifyFalse(yamada.validation.ModelValidator.hasErrors(document.validatePropertyCommit(registry)));
        end

        function detachedBuilderComponentsBindBeforeFirstCallback(testCase)
            % detachedBuilderComponentsBindBeforeFirstCallback Retain nested records and distinct constructor and assignment occurrence identities.
            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("DetachedCallbackFixture", registry);
            definition = registry.get("uipanel");
            panel = yamada.model.ComponentRecord("panel", "Panel", definition.Factory, definition.DeclaredType, "generated");
            panel.setProperty("Position", [10 10 300 200]);
            document.addComponent(panel, document.RootComponentId);
            definition = registry.get("uibutton");
            button = yamada.model.ComponentRecord("button", "Button", definition.Factory, definition.DeclaredType, "generated");
            button.setProperty("Text", "Run");
            document.addComponent(button, panel.Id);
            document.applyCallbackAction(button.Id, "ButtonPushedFcn", "New", registry, "RunPushed");
            testCase.verifyEqual(document.getComponent(button.Id), button);
            testCase.verifyEqual(button.ParentId, panel.Id);
            testCase.verifyEqual(button.getProperty("Text").LiteralValue, "Run");
            root = document.getComponent(document.RootComponentId);
            settings = root.getSettings("Visible");
            testCase.verifyNumElements(settings, 2);
            testCase.verifyEqual(numel(unique([settings.Id])), numel(settings));
            testCase.verifySubstring(document.CurrentText, "app.Button = uibutton(app.Panel);");
        end

        function replaceAndDisconnectKeepEveryMethodBody(testCase)
            % replaceAndDisconnectKeepEveryMethodBody Edit only assignments even when another callback shares the target.
            [document, registry, button] = CallbackBindingSelectionTest.fixture();
            other = document.insertComponent(registry, "uibutton", document.RootComponentId);
            document.applyCallbackAction(button.Id, "ButtonPushedFcn", "Connect", registry, "run0");
            document.applyCallbackAction(other.Id, "ButtonPushedFcn", "Connect", registry, "run0");
            states = yamada.source.CallbackSourceAnalyzer.analyze(document, button.Id, registry, true);
            testCase.verifyEqual(states([states.Name] == "ButtonPushedFcn").State, "editable");
            before = document.CurrentText;
            document.applyCallbackAction(button.Id, "ButtonPushedFcn", "Connect", registry, "run1");
            replacement = document.CurrentText;
            testCase.verifySubstring(replacement, "app." + button.Name + ".ButtonPushedFcn = @(~, event) app.run1(event);");
            document.applyCallbackAction(button.Id, "ButtonPushedFcn", "Disconnect", registry);
            testCase.verifySubstring(document.CurrentText, "function run0(app)");
            testCase.verifySubstring(document.CurrentText, "function run1(app, event)");
            testCase.verifySubstring(document.CurrentText, "app." + other.Name + ".ButtonPushedFcn = @(~, ~) app.run0();");
            document.undo(); testCase.verifyEqual(document.CurrentText, replacement);
            document.undo(); testCase.verifyEqual(document.CurrentText, before);
            document.redo(); document.redo();
            count = document.HistoryIndex;
            document.applyCallbackAction(button.Id, "ButtonPushedFcn", "Disconnect", registry);
            testCase.verifyEqual(document.HistoryIndex, count);
        end

        function newIsAtomicAndDisconnectRetainsItsBody(testCase)
            % newIsAtomicAndDisconnectRetainsItsBody Preserve generated bodies independently of save state.
            [document, registry, button] = CallbackBindingSelectionTest.fixture();
            initial = document.CurrentText;
            count = document.HistoryIndex;
            for invalid = ["run0", "delete", "bad-name", "end", document.ClassName]
                testCase.verifyError(@() document.applyCallbackAction(button.Id, "ButtonPushedFcn", "New", registry, invalid), ...
                    "yamada:DocumentModel:CallbackNameCollision");
                testCase.verifyEqual(document.CurrentText, initial);
                testCase.verifyEqual(document.HistoryIndex, count);
            end
            document.applyCallbackAction(button.Id, "ButtonPushedFcn", "New", registry, "CustomPushed");
            created = document.CurrentText;
            testCase.verifySubstring(created, "function CustomPushed(app, source, event)");
            document.undo(); testCase.verifyEqual(document.CurrentText, initial);
            document.redo(); testCase.verifyEqual(document.CurrentText, created);
            document.applyCallbackAction(button.Id, "ButtonPushedFcn", "Disconnect", registry);
            testCase.verifySubstring(document.CurrentText, "function CustomPushed(app, source, event)");
            testCase.verifyFalse(contains(document.CurrentText, "ButtonPushedFcn = @app.CustomPushed"));
            reopened = yamada.source.AppSourceParser.parseText(document.CurrentText, registry);
            targets = yamada.source.CallbackMethodTargets.list(reopened, reopened.getComponentByName(button.Name).Id, "ButtonPushedFcn", registry);
            testCase.verifyTrue(any(string({targets.Name}) == "CustomPushed"));
        end

    end

    methods (Static, Access = private)
        function [document, registry, button] = fixture()
            % fixture Load owned app text containing fixed, optional and unknown method signatures.
            arguments (Output)
                document (1, 1) yamada.model.DocumentModel
                registry (1, 1) yamada.model.ComponentRegistry
                button (1, 1) yamada.model.ComponentRecord
            end
            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("CallbackSelectionFixture", registry);
            button = document.insertComponent(registry, "uibutton", document.RootComponentId);
            source = document.CurrentText;
            anchor = document.sourceAnalysis().Layout.MethodAnchor;
            methods = [""; "function run0(app)"; "disp('retained marker')"; "end"; ...
                "function run1(app, event)"; "end"; "function run2(app, src, event)"; "end"; ...
                "function ignoredSource(app, ~, event)"; "arguments"; "app CallbackSelectionFixture"; "~"; ...
                "event matlab.ui.eventdata.ButtonPushedData"; "end"; "end"; ...
                "function ignoredEvent(app, src, ~)"; "arguments"; "app CallbackSelectionFixture"; ...
                "src matlab.ui.control.Button"; "~"; "end"; "end"; ...
                "function wrongSource(app, src, event)"; "arguments"; "app"; "src matlab.ui.control.Label"; "event"; "end"; "end"; ...
                "function wrongEvent(app, event)"; "arguments"; "app"; "event matlab.ui.eventdata.ValueChangedData"; "end"; "end"; ...
                "function baseEvent(app, event)"; "arguments"; "app"; "event event.EventData"; "end"; "end"; ...
                "function unknown(app, event)"; "arguments"; "app"; "event project.CustomEvent"; "end"; "end"; ...
                "function four(app, src, event, optional)"; "arguments"; "app"; "src"; "event"; "optional = dangerous()"; "end"; "end"; ...
                "function variadic(app, varargin)"; "end"; ""];
            batch = yamada.source.SourcePatchBatch(source, struct("Start", anchor + 1, "End", anchor, "Text", strjoin(methods, newline)));
            buttonName = button.Name;
            document = yamada.source.AppSourceParser.parseText(batch.AfterText, registry);
            button = document.getComponentByName(buttonName);
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
