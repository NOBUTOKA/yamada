classdef (TestTags = {'fast', 'parser', 'model', 'generation'}) CallbackCopyTest < matlab.unittest.TestCase
    % CallbackCopyTest Copy configuration while retaining callback source only on original components.
    %   Inert source fixtures cover parsed bindings, constructor arguments,
    %   callback bodies, independent clipboard data and source safety failures.

    methods (Test)
        function parsedBindingsAreOmittedRegardlessOfEditableOwnership(testCase)
            % parsedBindingsAreOmittedRegardlessOfEditableOwnership Preserve opaque bindings and bodies without copying or executing them.
            for binding = ["@app.OnPushed", "@(~, event) app.OnPushed(event)", ...
                    "@(src, event) error('callback-must-not-run')", "{@app.OnPushed, 42}", ...
                    "'error(''callback-must-not-run'')'", "[]"]
                body = ["app.Button = uibutton(app.Panel);", ...
                    "app.Button.ButtonPushedFcn = " + binding + ";"];
                [document, registry, panel, button] = CallbackCopyTest.fixture(body);
                original = document.OriginalText;
                settings = button.settingSnapshot();
                clipboard = yamada.model.ComponentClipboard();
                testCase.verifyTrue(clipboard.availability("Copy", document, panel.Id, registry).Enabled);
                clipboard.copy(document, panel.Id, registry);
                testCase.verifyFalse(document.IsDirty);
                testCase.verifyEqual(document.HistoryIndex, 0);
                pasted = clipboard.paste(document, document.RootComponentId, registry);
                source = document.GeneratedText;
                copiedButton = document.getComponent(pasted.Children(1));
                testCase.verifyEqual(copiedButton.getProperty("Text").LiteralValue, 'Keep this text');
                testCase.verifyEqual(copiedButton.ParentId, pasted.Id);
                testCase.verifyEmpty(copiedButton.getProperty("ButtonPushedFcn"));
                testCase.verifyEmpty(pasted.getProperty("SizeChangedFcn"));
                testCase.verifyEqual(SourceAssertions.retained(button.settingSnapshot(), settings), SourceAssertions.semantics(settings));
                testCase.verifySubstring(source, body(2));
                testCase.verifySubstring(source, "error('handler-must-not-run');");
                testCase.verifyEqual(count(source, "function OnPushed(app, event)"), 1);
                testCase.verifyEqual(count(source, ".ButtonPushedFcn ="), 1);
                testCase.verifyEqual(count(source, ".SizeChangedFcn ="), 1);

                % Reopening and Undo/Redo retain one binding and one body per original.
                reopened = yamada.source.AppSourceParser.parseText(source, registry);
                copied = reopened.getComponentByName(copiedButton.Name);
                states = yamada.source.CallbackSourceAnalyzer.analyze(reopened, copied.Id, registry);
                testCase.verifyTrue(all(string({states.State}) == "absent"));
                testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(reopened), source);
                document.undo();
                testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), original);
                document.redo();
                testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), source);
            end
        end

        function constructorCallbacksAreRemovedWithBothNamedSpellings(testCase)
            % constructorCallbacksAreRemovedWithBothNamedSpellings Retain literal settings while excluding callback arguments from output.
            for creation = ["app.Button = uibutton(app.Panel, ButtonPushedFcn=@app.OnPushed, Text='Constructor');", ...
                    "app.Button = uibutton(app.Panel, 'ButtonPushedFcn', @app.OnPushed, 'Text', 'Constructor');", ...
                    "app.Button = uibutton(app.Panel, ButtonPushedFcn=[], Text='Constructor');", ...
                    "app.Button = uibutton(app.Panel, CreateFcn=[], Text='Constructor');", ...
                    "app.Button = uibutton(app.Panel, DeleteFcn=@app.OnPushed, Text='Constructor');"]
                [document, registry, ~, button] = CallbackCopyTest.fixture(creation);
                clipboard = yamada.model.ComponentClipboard();
                testCase.verifyTrue(clipboard.availability("Copy", document, button.Id, registry).Enabled);
                clipboard.copy(document, button.Id, registry);
                pasted = clipboard.paste(document, document.RootComponentId, registry);
                testCase.verifyEmpty(pasted.CreationArguments);
                testCase.verifyEmpty(pasted.getProperty("ButtonPushedFcn"));
                testCase.verifyEmpty(pasted.getProperty("CreateFcn"));
                testCase.verifyEmpty(pasted.getProperty("DeleteFcn"));
                testCase.verifyEqual(pasted.getProperty("Text").LiteralValue, 'Constructor');
                testCase.verifySubstring(document.GeneratedText, creation);
                testCase.verifySubstring(document.GeneratedText, "app." + pasted.Name + " = uibutton(app.UIFigure);");
                document.undo();
                testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), document.OriginalText);
            end
        end

        function otherUnsupportedValuesStillRejectCopy(testCase)
            % otherUnsupportedValuesStillRejectCopy Limit omission to catalog callbacks and leave rejected documents unchanged.
            for body = { ...
                    ["app.Button = uibutton(app.Panel);", "app.Button.Text = computeText(app);"], ...
                    "app.Button = uibutton(app.Panel, ButtonPushedFcn=@app.OnPushed, Text=computeText(app));", ...
                    "app.Button = uibutton(app.Panel, ButtonPushedFcn=@app.OnPushed, UnknownFcn=[]);"}
                [document, registry, ~, button] = CallbackCopyTest.fixture(body{1});
                clipboard = yamada.model.ComponentClipboard();
                testCase.verifyFalse(clipboard.availability("Copy", document, button.Id, registry).Enabled);
                testCase.verifyError(@() clipboard.copy(document, button.Id, registry), "yamada:DocumentModel:UnsafeSubtreeCopy");
                testCase.verifyEqual(document.HistoryIndex, 0);
                testCase.verifyFalse(document.IsDirty);
                testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), document.OriginalText);
            end
        end

        function constructionEffectsStillPreventUnknownConfigurationCopy(testCase)
            % constructionEffectsStillPreventUnknownConfigurationCopy Do not infer effective settings after an executable CreateFcn.
            [document, registry, ~, button] = CallbackCopyTest.fixture( ...
                "app.Button = uibutton(app.Panel, CreateFcn=@app.OnPushed);");
            clipboard = yamada.model.ComponentClipboard();
            testCase.verifyFalse(clipboard.availability("Copy", document, button.Id, registry).Enabled);
            testCase.verifyError(@() document.copySubtree(button.Id, registry), "yamada:DocumentModel:UnsafeSubtreeCopy");
            testCase.verifyEqual(document.HistoryIndex, 0);
            testCase.verifyFalse(document.IsDirty);
        end

        function parsedPendingCallbackEditsRemainIndependentOfCopy(testCase)
            % parsedPendingCallbackEditsRemainIndependentOfCopy Retain original Add and Delete intentions across paste and undo.
            [document, registry, panel, button] = CallbackCopyTest.fixture("app.Button = uibutton(app.Panel);");
            document.applyCallbackAction(button.Id, "ButtonPushedFcn", "Add", registry);
            document.applyCallbackAction(panel.Id, "SizeChangedFcn", "Delete", registry);
            edits = document.CallbackEdits;
            source = yamada.source.RoundTripGenerator(registry).generate(document);
            clipboard = yamada.model.ComponentClipboard();
            clipboard.copy(document, panel.Id, registry);
            pasted = clipboard.paste(document, document.RootComponentId, registry);
            copied = document.getComponent(pasted.Children(1));
            testCase.verifyEmpty(copied.getProperty("ButtonPushedFcn"));
            testCase.verifyEmpty(pasted.getProperty("SizeChangedFcn"));
            testCase.verifyEqual(document.CallbackEdits, edits);
            testCase.verifyEqual(count(document.GeneratedText, ".ButtonPushedFcn ="), 1);
            testCase.verifyEqual(count(document.GeneratedText, ".SizeChangedFcn ="), 0);
            document.undo();
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), source);
            testCase.verifyEqual(document.CallbackEdits, edits);
        end
    end

    methods (Static, Access = private)
        function [document, registry, panel, button] = fixture(body)
            % fixture Parse a complete handle app with callback-bearing root and child components without executing it.
            arguments (Input)
                body (1, :) string
            end
            arguments (Output)
                document (1, 1) yamada.model.DocumentModel
                registry (1, 1) yamada.model.ComponentRegistry
                panel (1, 1) yamada.model.ComponentRecord
                button (1, 1) yamada.model.ComponentRecord
            end
            registry = yamada.model.ComponentRegistry.createDefault();
            textAssignment = "app.Button.Text = 'Keep this text';";
            if any(contains(body, "Text")), textAssignment = strings(1, 0); end
            source = strjoin(["classdef CallbackCopyApp < handle", "properties", ...
                "UIFigure matlab.ui.Figure", "Panel matlab.ui.container.Panel", ...
                "Button matlab.ui.control.Button", "end", "methods", ...
                "function app = CallbackCopyApp", "createComponents(app);", "end", ...
                "function createComponents(app)", "app.UIFigure = uifigure(Visible='off');", ...
                "app.Panel = uipanel(app.UIFigure);", "app.Panel.Position = [10 10 200 150];", ...
                "app.Panel.SizeChangedFcn = @app.OnResized;", body, ...
                "app.Button.Position = [20 20 100 30];", textAssignment, "end", ...
                "function OnPushed(app, event)", "error('handler-must-not-run');", "end", ...
                "function OnResized(app, event)", "error('resize-must-not-run');", "end", ...
                "end", "end"], sprintf("\r\n"));
            document = yamada.source.AppSourceParser.parseText(source, registry);
            panel = document.getComponentByName("Panel");
            button = document.getComponentByName("Button");
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
