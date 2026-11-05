classdef (TestTags = {'generation', 'parser', 'lifecycle', 'ui'}) HandleAppMigrationTest < matlab.unittest.TestCase
    % HandleAppMigrationTest Verify the handle app contract and actual owner lifetime.
    %   Generated test apps execute only in explicit runtime tests. Parser tests
    %   preserve source without constructing the app or invoking its callbacks.

    methods (Test)
        function cleanupRethrowPreservesCertainInitialization(testCase)
            % cleanupRethrowPreservesCertainInitialization Trace the successful constructor path only when proven.
            registry = macd.model.ComponentRegistry.createDefault();
            original = macd.model.NewAppFactory.createEmpty("GuardedApp", registry);
            source = macd.source.NewAppGenerator(registry).generate(original);
            [document, diagnostics] = macd.source.AppSourceParser.parseText(source, registry);
            testCase.verifyEmpty(diagnostics);
            testCase.verifyTrue(document.getComponent(document.RootComponentId).getProperty("Name").IsEditable);
            testCase.verifyFalse(document.getComponent(document.RootComponentId).getProperty("CloseRequestFcn").IsEditable);
            testCase.verifyFalse(any(string({diagnostics.Code}) == "unresolved-initialization-call"));

            % Swallowing an exception does not prove that initialization completed.
            source = replace(source, "                rethrow(exception);", "");
            document = macd.source.AppSourceParser.parseText(source, registry);
            testCase.verifyFalse(document.getComponent(document.RootComponentId).getProperty("Name").IsEditable);
        end

        function rejectsOtherBasesAndMissingOrMultipleFigures(testCase)
            % rejectsOtherBasesAndMissingOrMultipleFigures Enforce the supported class and root count.
            registry = macd.model.ComponentRegistry.createDefault();
            for base = ["matlab.apps.AppBase", "OtherBase"]
                text = "classdef UnsupportedApp < " + base + newline + "end";
                [~, diagnostics] = macd.source.AppSourceParser.parseText(text, registry);
                testCase.verifyTrue(macd.validation.ModelValidator.hasErrors(diagnostics));
            end
            for count = [0 2]
                lines = ["classdef RootApp < handle"; "properties"; ...
                    "UIFigure matlab.ui.Figure"; "OtherFigure matlab.ui.Figure"; ...
                    "end"; "methods"; "function app = RootApp"];
                if count > 0
                    lines = [lines; "app.UIFigure = uifigure();"; "app.OtherFigure = uifigure();"]; %#ok<AGROW>
                end
                [document, diagnostics] = macd.source.AppSourceParser.parseText( ...
                    strjoin([lines; "end"; "end"; "end"], newline), registry);
                testCase.verifyEqual(nnz(string({document.Components.Factory}) == "uifigure"), count);
                testCase.verifyTrue(any(string({diagnostics.Code}) == "invalid-root-count"));
                testCase.verifyTrue(macd.validation.ModelValidator.hasErrors(diagnostics));
            end
        end

        function defaultCloseCanBeEditedDeletedAndUndone(testCase)
            % defaultCloseCanBeEditedDeletedAndUndone Preserve the shutdown fallback across source edits.
            registry = macd.model.ComponentRegistry.createDefault();
            original = macd.model.NewAppFactory.createEmpty("CloseApp", registry);
            generator = macd.source.RoundTripGenerator(registry);
            source = generator.generate(original);
            document = macd.source.AppSourceParser.parseText(source, registry);
            states = macd.source.CallbackSourceAnalyzer.analyze(document, document.RootComponentId, registry);
            testCase.verifyEqual(states(string({states.Name}) == "CloseRequestFcn").State, "absent");
            document.applyCallbackAction(document.RootComponentId, "CloseRequestFcn", "Add", registry);
            added = generator.generate(document);
            testCase.verifySubstring(added, "CloseRequestFcn = @app.");
            reopened = macd.source.AppSourceParser.parseText(added, registry);
            reopened.applyCallbackAction(reopened.RootComponentId, "CloseRequestFcn", "Delete", registry);
            restored = generator.generate(reopened);
            testCase.verifySubstring(restored, macd.source.CallbackSourceEdits.defaultClose("UIFigure"));
            testCase.verifyEqual(count(restored, ".CloseRequestFcn ="), 1);
            reopened.undo();
            testCase.verifyEqual(generator.generate(reopened), added);
            document.undo();
            testCase.verifyEqual(generator.generate(document), source);
        end

        function generatedCallbacksReceiveSourceAndEvent(testCase)
            % generatedCallbacksReceiveSourceAndEvent Exercise the documented bound-method calling convention.
            [document, registry] = testCase.runtimeDocument();
            button = document.insertComponent(registry, "uibutton", document.RootComponentId);
            tag = document.ClassName + "-button";
            button.setProperty("Tag", tag);
            document.applyCallbackAction(button.Id, "ButtonPushedFcn", "Add", registry);
            source = macd.source.NewAppGenerator(registry).generate(document);
            source = replace(source, "% Add callback behavior here.", ...
                "source.UserData = event; app." + button.Name + ".Text = source.Text + "" changed"";");
            app = testCase.instantiate(document, source);
            cleanup = onCleanup(@() delete(app));
            control = findall(0, "Tag", tag);
            testCase.assertNumElements(control, 1);
            before = string(control.Text);
            callback = control.ButtonPushedFcn;
            event = matlab.ui.eventdata.ButtonPushedData();
            callback(control, event);
            testCase.verifyEqual(string(control.Text), before + " changed");
            testCase.verifyEqual(control.UserData, event);
            clear cleanup
        end

        function closeAndExplicitDeleteDestroyOwnerAndFigure(testCase)
            % closeAndExplicitDeleteDestroyOwnerAndFigure Cover normal close and programmatic owner deletion.
            for action = ["close", "delete"]
                [document, registry] = testCase.runtimeDocument();
                app = testCase.instantiate(document, macd.source.NewAppGenerator(registry).generate(document));
                figure = findall(0, "Type", "figure", "Name", document.ClassName);
                testCase.assertNumElements(figure, 1);
                cleanup = onCleanup(@() delete(app));
                if action == "close", close(figure); else, delete(app); end
                testCase.verifyFalse(isvalid(app));
                testCase.verifyFalse(isvalid(figure));
                delete(app);
                clear cleanup
            end
        end

        function figureDeletionPreservesUserDeleteCallback(testCase)
            % figureDeletionPreservesUserDeleteCallback Keep user callbacks while releasing the owner.
            [document, registry] = testCase.runtimeDocument();
            app = testCase.instantiate(document, macd.source.NewAppGenerator(registry).generate(document));
            figure = findall(0, "Type", "figure", "Name", document.ClassName);
            testCase.assertNumElements(figure, 1);
            cleanup = onCleanup(@() delete(app));
            observer = uifigure("Visible", "off", "UserData", false);
            observerCleanup = onCleanup(@() delete(observer));
            figure.DeleteFcn = @(~, ~) set(observer, "UserData", true);
            delete(figure);
            testCase.verifyFalse(isvalid(app));
            testCase.verifyTrue(observer.UserData);
            clear cleanup observerCleanup
        end

        function outputlessStartupRetainsOwnerUntilClose(testCase)
            % outputlessStartupRetainsOwnerUntilClose Retain an app through its figure without a caller variable.
            [document, registry] = testCase.runtimeDocument();
            testCase.installSource(document, macd.source.NewAppGenerator(registry).generate(document));
            feval(document.ClassName);
            figure = findall(0, "Type", "figure", "Name", document.ClassName);
            testCase.assertNumElements(figure, 1);
            details = functions(figure.CloseRequestFcn);
            owner = details.workspace{1}.app;
            cleanup = onCleanup(@() delete(owner));
            testCase.verifyTrue(isvalid(owner));
            close(figure);
            testCase.verifyFalse(isvalid(owner));
            testCase.verifyFalse(isvalid(figure));
            clear cleanup
        end

        function canceledCloseKeepsOwnerUntilExplicitDelete(testCase)
            % canceledCloseKeepsOwnerUntilExplicitDelete Keep the shutdown decision outside the destructor.
            [document, registry] = testCase.runtimeDocument();
            document.applyCallbackAction(document.RootComponentId, "CloseRequestFcn", "Add", registry);
            source = macd.source.NewAppGenerator(registry).generate(document);
            source = replace(source, "            delete(app);", "            return");
            app = testCase.instantiate(document, source);
            cleanup = onCleanup(@() delete(app));
            figure = findall(0, "Type", "figure", "Name", document.ClassName);
            testCase.assertNumElements(figure, 1);
            close(figure);
            testCase.verifyTrue(isvalid(app));
            testCase.verifyTrue(isvalid(figure));
            delete(app);
            testCase.verifyFalse(isvalid(figure));
            clear cleanup
        end

        function constructionFailureReleasesPartialFigure(testCase)
            % constructionFailureReleasesPartialFigure Run cleanup before listener registration is reached.
            for stage = ["before-figure", "after-figure"]
                [document, registry] = testCase.runtimeDocument();
                button = document.insertComponent(registry, "uibutton", document.RootComponentId);
                source = macd.source.NewAppGenerator(registry).generate(document);
                anchor = "app." + button.Name + " = uibutton(app.UIFigure);";
                if stage == "before-figure"
                    anchor = "app.UIFigure = uifigure(""Visible"", ""off"");";
                end
                source = replace(source, anchor, "error(""test:HandleConstruction"", ""Construction failed"");");
                testCase.installSource(document, source);
                testCase.verifyError(@() feval(document.ClassName), "test:HandleConstruction");
                testCase.verifyEmpty(findall(0, "Type", "figure", "Name", document.ClassName));
            end
        end

        function editorFigureDeletionReleasesOwner(testCase)
            % editorFigureDeletionReleasesOwner Dispose editor state when its figure is directly deleted.
            app = yamada();
            cleanup = onCleanup(@() delete(app));
            figure = findall(0, "Tag", "macd-yamada-editor");
            testCase.assertNumElements(figure, 1);
            delete(figure);
            testCase.verifyFalse(isvalid(app));
            clear cleanup
        end

        function outputlessEditorRetainsOwnerUntilClose(testCase)
            % outputlessEditorRetainsOwnerUntilClose Preserve ans and retain an outputless editor until close.
            if evalin("base", "exist('ans','var') == 1")
                original = evalin("base", "ans");
                testCase.addTeardown(@() assignin("base", "ans", original));
            else
                testCase.addTeardown(@() evalin("base", "clear ans"));
            end
            sentinel = struct("Value", [17 29], "Tag", "preserved-ans");
            for hasAns = [false true]
                if hasAns
                    assignin("base", "ans", sentinel);
                else
                    evalin("base", "clear ans");
                end

                % Exercise the exact command without an assignment or semicolon.
                evalin("base", "yamada");
                figure = findall(0, "Tag", "macd-yamada-editor");
                testCase.assertNumElements(figure, 1);
                details = functions(figure.CloseRequestFcn);
                owner = details.workspace{1}.app;
                cleanup = onCleanup(@() delete(owner));
                if hasAns
                    testCase.verifyEqual(evalin("base", "ans"), sentinel);
                else
                    testCase.verifyEqual(evalin("base", "exist('ans','var')"), 0);
                end
                testCase.verifyTrue(isvalid(owner));
                close(figure);
                testCase.verifyFalse(isvalid(owner));
                testCase.verifyFalse(isvalid(figure));
                clear cleanup
            end
        end
    end

    methods (Access = private)
        function [document, registry] = runtimeDocument(~)
            % runtimeDocument Create an isolated hidden app model with a unique class identity.
            arguments (Input)
                ~
            end
            arguments (Output)
                document (1, 1) macd.model.DocumentModel
                registry (1, 1) macd.model.ComponentRegistry
            end
            registry = macd.model.ComponentRegistry.createDefault();
            name = "HandleApp" + erase(string(java.util.UUID.randomUUID()), "-");
            document = macd.model.NewAppFactory.createEmpty(name, registry);
            document.getComponent(document.RootComponentId).setProperty("Visible", "off");
        end

        function app = instantiate(testCase, document, source)
            % instantiate Install and run only source generated by the runtime test itself.
            arguments (Input)
                testCase (1, 1) HandleAppMigrationTest
                document (1, 1) macd.model.DocumentModel
                source (1, 1) string
            end
            arguments (Output)
                app handle
            end
            testCase.installSource(document, source);
            app = feval(document.ClassName);
        end

        function installSource(testCase, document, source)
            % installSource Scope generated runtime code to temporary fixtures and a temporary path.
            arguments (Input)
                testCase (1, 1) HandleAppMigrationTest
                document (1, 1) macd.model.DocumentModel
                source (1, 1) string
            end
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            macd.source.SourceWriter.write(fullfile(folder.Folder, document.ClassName + ".m"), source, "CRLF");
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(folder.Folder));
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
