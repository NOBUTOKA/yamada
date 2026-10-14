classdef (TestTags = {'fast', 'model', 'generation'}) SubtreeDeletionTest < matlab.unittest.TestCase
    % SubtreeDeletionTest Verify atomic subtree deletion and conservative source ownership.
    %   Tests exercise generated and opened documents without running application code.

    methods (Test)
        function deletesNestedTreeAsOneHistoryStep(testCase)
            % deletesNestedTreeAsOneHistoryStep Preserve exact collection and child ordering on undo.
            [document, registry, panel] = SubtreeDeletionTest.fixture();
            sibling = document.insertComponent(registry, "uilabel", document.RootComponentId);
            before = document.Components;
            children = document.getComponent(document.RootComponentId).Children;
            document.markSaved();
            history = document.HistoryIndex;
            document.removeSubtree(panel.Id, registry);
            testCase.verifyEqual(document.HistoryIndex, history + 1);
            testCase.verifyEqual(string({document.Components.Id}), [document.RootComponentId sibling.Id]);
            document.undo();
            testCase.verifyEqual(document.Components, before);
            testCase.verifyEqual(document.getComponent(document.RootComponentId).Children, children);
            testCase.verifyFalse(document.IsDirty);
            document.redo();
            testCase.verifyEmpty(document.getComponent(panel.Id));
        end

        function openedSourceAllowsInternalParentReferences(testCase)
            % openedSourceAllowsInternalParentReferences Remove all owned subtree spans together.
            [original, registry, panel] = SubtreeDeletionTest.fixture();
            source = macd.source.NewAppGenerator(registry).generate(original);
            document = macd.source.AppSourceParser.parseText(source, registry);
            panel = document.getComponentByName(panel.Name);
            before = document.OriginalText;
            document.removeSubtree(panel.Id, registry);
            [after, diagnostics] = macd.source.RoundTripGenerator(registry).generate(document);
            testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(diagnostics));
            testCase.verifyFalse(contains(after, "app." + panel.Name));
            reopened = macd.source.AppSourceParser.parseText(after, registry);
            testCase.verifyEqual(numel(reopened.Components), 1);
            document.undo();
            restored = macd.source.RoundTripGenerator(registry).generate(document);
            testCase.verifyEqual(restored, before);
            document.redo();
            testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(document), after);
        end

        function externalReferencesRejectWithoutMutation(testCase)
            % externalReferencesRejectWithoutMutation Keep source preview, history and hierarchy intact.
            [original, registry, panel] = SubtreeDeletionTest.fixture();
            source = macd.source.NewAppGenerator(registry).generate(original);
            source = replace(source, "delete(app.UIFigure);", "disp(app." + panel.Name + "); delete(app.UIFigure);");
            document = macd.source.AppSourceParser.parseText(source, registry);
            panel = document.getComponentByName(panel.Name);
            before = document.Components;
            history = document.HistoryIndex;
            text = document.GeneratedText;
            testCase.verifyError(@() document.removeSubtree(panel.Id, registry), ...
                "macd:SubtreeSourceEdits:UnsafeDeletion");
            testCase.verifyEqual(document.Components, before);
            testCase.verifyEqual(document.HistoryIndex, history);
            testCase.verifyEqual(document.GeneratedText, text);
        end

        function commentsAndStringsAreNotExternalReferences(testCase)
            % commentsAndStringsAreNotExternalReferences Ignore textual mentions while preserving their bytes.
            [original, registry, panel] = SubtreeDeletionTest.fixture();
            source = macd.source.NewAppGenerator(registry).generate(original);
            marker = "app." + panel.Name;
            source = replace(source, "delete(app.UIFigure);", ...
                "disp(""" + marker + """); % " + marker + newline + "            delete(app.UIFigure);");
            document = macd.source.AppSourceParser.parseText(source, registry);
            panel = document.getComponentByName(panel.Name);
            document.removeSubtree(panel.Id, registry);
            testCase.verifySubstring(document.GeneratedText, "disp(""" + marker + """); % " + marker);
        end

        function candidateDoesNotShareComponentOrPropertyHandles(testCase)
            % candidateDoesNotShareComponentOrPropertyHandles Isolate speculative changes from the real document.
            [document, ~, panel] = SubtreeDeletionTest.fixture();
            panel.setProperty("Title", "Before");
            candidate = document.structuralCandidate();
            copy = candidate.getComponent(panel.Id);
            copy.setProperty("Title", "After");
            copy.Name = "Changed";
            testCase.verifyEqual(panel.getProperty("Title").LiteralValue, "Before");
            testCase.verifyNotEqual(panel.Name, copy.Name);
        end

        function rootAndReadOnlyDescendantsAreRejected(testCase)
            % rootAndReadOnlyDescendantsAreRejected Check the complete subtree before mutation.
            [document, registry, panel] = SubtreeDeletionTest.fixture();
            testCase.verifyError(@() document.removeSubtree(document.RootComponentId, registry), ...
                "macd:DocumentModel:RootDeletion");
            document.getComponent(panel.Children(1)).IsEditable = false;
            history = document.HistoryIndex;
            testCase.verifyError(@() document.removeSubtree(panel.Id, registry), ...
                "macd:DocumentModel:UnsafeSubtreeEdit");
            testCase.verifyEqual(document.HistoryIndex, history);
        end
    end

    methods (Static, Access = private)
        function [document, registry, panel] = fixture()
            % fixture Build a complete nested panel subtree with one leaf.
            arguments (Output)
                document (1, 1) macd.model.DocumentModel
                registry (1, 1) macd.model.ComponentRegistry
                panel (1, 1) macd.model.ComponentRecord
            end
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("SubtreeApp", registry);
            panel = document.insertComponent(registry, "uipanel", document.RootComponentId);
            nested = document.insertComponent(registry, "uipanel", panel.Id);
            document.insertComponent(registry, "uilabel", nested.Id);
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
