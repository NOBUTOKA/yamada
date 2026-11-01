classdef (TestTags = {'fast', 'model', 'generation'}) ComponentRenameTest < matlab.unittest.TestCase
    % ComponentRenameTest Verify atomic component renaming and source preservation.
    %   These tests cover callback naming policy, member help, history, lexical
    %   references, and rejection of unresolved or conflicting names.

    methods (Test)
        function generatedCallbacksAndHistoryFollowTheName(testCase)
            % generatedCallbacksAndHistoryFollowTheName Rename the property and default handler atomically.
            [document, button, registry] = ComponentRenameTest.newButton();
            document.applyCallbackAction(button.Id, "ButtonPushedFcn", "Add", registry);
            document.markSaved();
            checkpoint = document.HistoryIndex;
            id = button.Id;
            document.renameComponent(id, "RunButton", registry);
            testCase.verifyEqual(document.HistoryIndex, checkpoint + 1);
            testCase.verifyEqual(button.Id, id);
            testCase.verifySubstring(document.GeneratedText, "app.RunButton = uibutton(app.UIFigure)");
            testCase.verifySubstring(document.GeneratedText, "@app.RunButtonButtonPushed");
            testCase.verifySubstring(document.GeneratedText, "% RunButtonButtonPushed Handle");
            states = macd.source.CallbackSourceAnalyzer.analyze(document, id, registry);
            testCase.verifyEqual(states(string({states.Name}) == "ButtonPushedFcn").HandlerName, "RunButtonButtonPushed");
            document.undo();
            testCase.verifyEqual(button.Name, "Button");
            testCase.verifyFalse(document.IsDirty);
            document.redo();
            testCase.verifyEqual(button.Name, "RunButton");
        end

        function parsedReferencesAndMemberHelpFollowWithoutChangingLiterals(testCase)
            % parsedReferencesAndMemberHelpFollowWithoutChangingLiterals Rewrite static uses and preserve literal text.
            [document, button, registry] = ComponentRenameTest.newButton();
            document.applyCallbackAction(button.Id, "ButtonPushedFcn", "Add", registry);
            source = macd.source.NewAppGenerator(registry).generate(document);
            source = replace(source, "        Button matlab.ui.control.Button", ...
                "        % Button - UI component handle." + newline + "        Button matlab.ui.control.Button");
            source = replace(source, "% ButtonButtonPushed Handle the ButtonPushedFcn callback.", ...
                "% ButtonButtonPushed Handle the ButtonPushedFcn callback." + newline + ...
                "            %   Example: ButtonButtonPushed(app, event); app.Button.Text = 'Run';");
            body = ["            x = app.Button.Position';"; ...
                "            y = app . Button.Text;"; ...
                "            a = 'app.Button'; b = ""app.Button"";"; ...
                "            % app.Button and ButtonButtonPushed remain prose."; ...
                "            %{ "; "            app.Button is a block comment"; "            %}"; ...
                "            value = ""app.Button""'; after = app.Button.Text;"; ...
                "            continued = app. ..."; "                Button.Text;"; ...
                "            properties(app); Button = app.Button;"; ...
                "            Button.Text = 'Local alias';"; ...
                "            other.ButtonButtonPushed = @(~, ~) [];"; ...
                "            other.ButtonButtonPushed(app, event);"; ...
                "            z = app.Button.Text;"];
            source = replace(source, "            % Add callback behavior here.", strjoin(body, newline));
            parsed = macd.source.AppSourceParser.parseText(source, registry);
            button = parsed.getComponentByName("Button");
            parsed.renameComponent(button.Id, "GoButton", registry);
            result = parsed.GeneratedText;
            testCase.verifyEqual(parsed.OriginalText, source);
            testCase.verifySubstring(result, "% GoButton - UI component handle.");
            testCase.verifySubstring(result, "GoButton matlab.ui.control.Button");
            testCase.verifySubstring(result, "x = app.GoButton.Position'");
            testCase.verifySubstring(result, "y = app . GoButton.Text");
            testCase.verifySubstring(result, "z = app.GoButton.Text");
            testCase.verifySubstring(result, "a = 'app.Button'; b = ""app.Button""");
            testCase.verifySubstring(result, "% app.Button and ButtonButtonPushed remain prose.");
            testCase.verifySubstring(result, "app.Button is a block comment");
            testCase.verifySubstring(result, "after = app.GoButton.Text");
            testCase.verifySubstring(result, "                GoButton.Text;");
            testCase.verifySubstring(result, "properties(app); Button = app.GoButton;");
            testCase.verifySubstring(result, "Button.Text = 'Local alias';");
            testCase.verifySubstring(result, "other.ButtonButtonPushed = @(~, ~) [];");
            testCase.verifySubstring(result, "other.ButtonButtonPushed(app, event);");
            testCase.verifySubstring(result, "% GoButtonButtonPushed Handle");
            testCase.verifySubstring(result, "%   Example: GoButtonButtonPushed(app, event); app.GoButton.Text = 'Run';");
            parsed.undo();
            testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(parsed), source);
        end

        function customAndSharedCallbackNamesRemainUnchanged(testCase)
            % customAndSharedCallbackNamesRemainUnchanged Preserve intentional handler identities.
            [document, button, registry] = ComponentRenameTest.newButton();
            document.applyCallbackAction(button.Id, "ButtonPushedFcn", "Add", registry);
            source = macd.source.NewAppGenerator(registry).generate(document);
            custom = replace(source, "ButtonButtonPushed", "performAction");
            parsed = macd.source.AppSourceParser.parseText(custom, registry);
            button = parsed.getComponentByName("Button");
            parsed.renameComponent(button.Id, "GoButton", registry);
            testCase.verifySubstring(parsed.GeneratedText, "@app.performAction");
            testCase.verifySubstring(parsed.GeneratedText, "% performAction Handle");
            shared = replace(source, "app.UIFigure.Position =", ...
                "app.UIFigure.CloseRequestFcn = @app.ButtonButtonPushed;" + newline + "            app.UIFigure.Position =");
            parsed = macd.source.AppSourceParser.parseText(shared, registry);
            button = parsed.getComponentByName("Button");
            parsed.renameComponent(button.Id, "GoButton", registry);
            testCase.verifySubstring(parsed.GeneratedText, "@app.ButtonButtonPushed");
            testCase.verifySubstring(parsed.GeneratedText, "function ButtonButtonPushed");
            shadowed = replace(source, "            % Add callback behavior here.", ...
                "            ButtonButtonPushed = 1; data = who('ButtonButtonPushed');");
            parsed = macd.source.AppSourceParser.parseText(shadowed, registry);
            button = parsed.getComponentByName("Button");
            parsed.renameComponent(button.Id, "GoButton", registry);
            testCase.verifySubstring(parsed.GeneratedText, "@app.ButtonButtonPushed");
            testCase.verifySubstring(parsed.GeneratedText, "ButtonButtonPushed = 1; data = who('ButtonButtonPushed');");
        end

        function rejectionLeavesAllStateUnchanged(testCase)
            % rejectionLeavesAllStateUnchanged Reject invalid, inherited and duplicate member names atomically.
            [document, button, registry] = ComponentRenameTest.newButton();
            before = document.History;
            for name = ["bad name", "1Button", "end", "UIFigure", document.ClassName, "delete", "createComponents"]
                try
                    document.renameComponent(button.Id, name, registry);
                    testCase.verifyFail("Accepted invalid or conflicting name: " + name);
                catch exception
                    testCase.verifyTrue(startsWith(string(exception.identifier), "macd:DocumentModel:"));
                end
                testCase.verifyEqual(button.Name, "Button");
                testCase.verifyEqual(document.History, before);
                testCase.verifyEmpty(document.RenameEdits);
            end
            document.renameComponent(button.Id, "Button", registry);
            testCase.verifyEqual(document.History, before);
        end

        function dynamicDispatchAndAliasesAreRejected(testCase)
            % dynamicDispatchAndAliasesAreRejected Preserve sources whose references cannot be resolved statically.
            [document, ~, registry] = ComponentRenameTest.newButton();
            source = macd.source.NewAppGenerator(registry).generate(document);
            for statement = ["app.('Button').Text = 'x';", "alias = app;", "eval('app.Button.Text');"]
                unsafe = replace(source, "            app.Button.Position", statement + newline + "            app.Button.Position");
                parsed = macd.source.AppSourceParser.parseText(unsafe, registry);
                button = parsed.getComponentByName("Button");
                testCase.verifyError(@() parsed.renameComponent(button.Id, "GoButton", registry), "macd:DocumentModel:UnsafeComponentRename");
                testCase.verifyEqual(button.Name, "Button");
                testCase.verifyEqual(parsed.OriginalText, unsafe);
                testCase.verifyEmpty(parsed.History);
            end
        end

        function repeatedRenamesAndCallbackEditsKeepTheirOriginalAnchors(testCase)
            % repeatedRenamesAndCallbackEditsKeepTheirOriginalAnchors Compose renames with parsed callback deletion and replacement.
            [document, button, registry] = ComponentRenameTest.newButton();
            document.applyCallbackAction(button.Id, "ButtonPushedFcn", "Add", registry);
            source = macd.source.NewAppGenerator(registry).generate(document);
            parsed = macd.source.AppSourceParser.parseText(source, registry);
            button = parsed.getComponentByName("Button");
            parsed.renameComponent(button.Id, "GoButton", registry);
            parsed.renameComponent(button.Id, "RunButton", registry);
            testCase.verifySubstring(parsed.GeneratedText, "% RunButtonButtonPushed Handle");
            parsed.applyCallbackAction(button.Id, "ButtonPushedFcn", "Delete", registry);
            testCase.verifyFalse(contains(parsed.GeneratedText, "function RunButtonButtonPushed"));
            parsed.undo();
            testCase.verifySubstring(macd.source.RoundTripGenerator(registry).generate(parsed), "@app.RunButtonButtonPushed");
            parsed.applyCallbackAction(button.Id, "ButtonPushedFcn", "Delete", registry);
            parsed.applyCallbackAction(button.Id, "ButtonPushedFcn", "Add", registry);
            testCase.verifySubstring(parsed.GeneratedText, "@app.RunButtonButtonPushed_2");
            parsed.renameComponent(button.Id, "ExecuteButton", registry);
            testCase.verifySubstring(parsed.GeneratedText, "% ExecuteButtonButtonPushed_2 Handle");
        end

        function parentReferencesAndLaterPropertyEditsUseCurrentNames(testCase)
            % parentReferencesAndLaterPropertyEditsUseCurrentNames Preserve parent links and combine literal edits with source renaming.
            [document, ~, registry] = ComponentRenameTest.newButton();
            source = macd.source.NewAppGenerator(registry).generate(document);
            parsed = macd.source.AppSourceParser.parseText(source, registry);
            root = parsed.getComponent(parsed.RootComponentId);
            parsed.renameComponent(root.Id, "MainWindow", registry);
            testCase.verifySubstring(parsed.GeneratedText, "uibutton(app.MainWindow)");
            testCase.verifySubstring(parsed.GeneratedText, "addlistener(app.MainWindow, ""ObjectBeingDestroyed"", @app.figureDeleted)");
            testCase.verifySubstring(parsed.GeneratedText, "delete(app.MainWindow)");
            button = parsed.getComponentByName("Button");
            parsed.renameComponent(button.Id, "RunButton", registry);
            parsed.setProperty(button.Id, "Text", "Run");
            result = macd.source.RoundTripGenerator(registry).generate(parsed);
            testCase.verifySubstring(result, "app.RunButton.Text = ""Run""");
            testCase.verifyEqual(button.ParentId, root.Id);
        end

        function existingUserMembersAndHandlerCollisionsAreRespected(testCase)
            % existingUserMembersAndHandlerCollisionsAreRespected Reserve other class members and suffix generated handlers.
            [document, button, registry] = ComponentRenameTest.newButton();
            document.applyCallbackAction(button.Id, "ButtonPushedFcn", "Add", registry);
            source = macd.source.NewAppGenerator(registry).generate(document);
            canonicalSource = source;
            source = replace(source, "    properties (Access = private)", ...
                "    properties (Access = private)" + newline + "        UserData double" + newline + "        RunButtonButtonPushed double");
            parsed = macd.source.AppSourceParser.parseText(source, registry);
            button = parsed.getComponentByName("Button");
            testCase.verifyError(@() parsed.renameComponent(button.Id, "UserData", registry), "macd:DocumentModel:ComponentNameCollision");
            parsed.renameComponent(button.Id, "RunButton", registry);
            testCase.verifySubstring(parsed.GeneratedText, "@app.RunButtonButtonPushed_2");
            testCase.verifySubstring(parsed.GeneratedText, "% RunButtonButtonPushed_2 Handle");
            % A Save As identity can differ from the preserved source snapshot.
            parsed = macd.source.AppSourceParser.parseText(canonicalSource, registry);
            parsed.ClassName = "RunButtonButtonPushed";
            button = parsed.getComponentByName("Button");
            parsed.renameComponent(button.Id, "RunButton", registry);
            testCase.verifySubstring(parsed.GeneratedText, "@app.RunButtonButtonPushed_2");
        end

        function insertionCannotReuseHistoricalSourceNames(testCase)
            % insertionCannotReuseHistoricalSourceNames Keep new components outside existing rename mappings.
            [document, button, registry] = ComponentRenameTest.newButton();
            document.renameComponent(button.Id, "RunButton", registry);
            second = document.insertComponent(registry, "uibutton", document.RootComponentId);
            testCase.verifyEqual(second.Name, "Button2");
            source = macd.source.RoundTripGenerator(registry).generate(document);
            parsed = macd.source.AppSourceParser.parseText(source, registry);
            testCase.verifyNotEmpty(parsed.getComponentByName("RunButton"));
            testCase.verifyNotEmpty(parsed.getComponentByName("Button2"));
        end

        function defaultHandlerCallsAndHelpExamplesFollowTheRename(testCase)
            % defaultHandlerCallsAndHelpExamplesFollowTheRename Rename static method calls alongside an exclusive default binding.
            [document, button, registry] = ComponentRenameTest.newButton();
            document.applyCallbackAction(button.Id, "ButtonPushedFcn", "Add", registry);
            source = macd.source.NewAppGenerator(registry).generate(document);
            source = replace(source, "            % Add callback behavior here.", ...
                "            ButtonButtonPushed(app, event);");
            parsed = macd.source.AppSourceParser.parseText(source, registry);
            button = parsed.getComponentByName("Button");
            parsed.renameComponent(button.Id, "RunButton", registry);
            testCase.verifySubstring(parsed.GeneratedText, "RunButtonButtonPushed(app, event);");
            testCase.verifySubstring(parsed.GeneratedText, "% RunButtonButtonPushed Handle");
        end
    end

    methods (Static, Access = private)
        function [document, button, registry] = newButton()
            % newButton Create a small new document with one editable button.
            arguments (Output)
                document (1, 1) macd.model.DocumentModel
                button (1, 1) macd.model.ComponentRecord
                registry (1, 1) macd.model.ComponentRegistry
            end

            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("RenameApp", registry);
            button = document.insertComponent(registry, "uibutton", document.RootComponentId);
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
