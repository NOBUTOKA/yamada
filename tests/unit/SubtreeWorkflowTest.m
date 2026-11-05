classdef (TestTags = {'fast', 'model', 'generation'}) SubtreeWorkflowTest < matlab.unittest.TestCase
    % SubtreeWorkflowTest Verify composed subtree edits and their source ownership.
    %   Tests combine parsed and generated nodes without executing opened apps.

    methods (Test)
        function moveThenCutRestoresEachSourceState(testCase)
            % moveThenCutRestoresEachSourceState Preserve old property ownership after grid conversion.
            [document, registry, left, right, leaf] = SubtreeWorkflowTest.fixture();
            original = document.OriginalText;
            grid = document.insertComponent(registry, "uigridlayout", right.Id);
            document.reparentSubtree(leaf.Id, grid.Id, registry);
            moved = document.GeneratedText;
            clipboard = yamada.model.ComponentClipboard();
            clipboard.cut(document, leaf.Id, registry);
            reopened = yamada.source.AppSourceParser.parseText(document.GeneratedText, registry);
            testCase.verifyEmpty(reopened.getComponentByName(leaf.Name));
            document.undo();
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), moved);
            document.undo();
            document.undo();
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), original);
            testCase.verifyEqual(leaf.ParentId, left.Id);
        end

        function detachedChildSurvivesDeletionOfOriginalParent(testCase)
            % detachedChildSurvivesDeletionOfOriginalParent Ignore only the rewritten constructor parent reference.
            [document, registry, left, right, leaf] = SubtreeWorkflowTest.fixture();
            document.reparentSubtree(leaf.Id, right.Id, registry);
            moved = document.GeneratedText;
            document.removeSubtree(left.Id, registry);
            reopened = yamada.source.AppSourceParser.parseText(document.GeneratedText, registry);
            testCase.verifyEmpty(reopened.getComponentByName(left.Name));
            testCase.verifyEqual(reopened.getComponentByName(leaf.Name).ParentId, reopened.getComponentByName(right.Name).Id);
            document.undo();
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), moved);
            document.redo();
            testCase.verifyEmpty(document.getComponent(left.Id));
        end

        function copiedTreeCanMoveThenCutAndUndoAllSteps(testCase)
            % copiedTreeCanMoveThenCutAndUndoAllSteps Keep independent clipboard data and one history step per edit.
            [document, registry, left, right] = SubtreeWorkflowTest.fixture();
            original = document.OriginalText;
            clipboard = yamada.model.ComponentClipboard();
            clipboard.copy(document, left.Id, registry);
            pasted = clipboard.paste(document, document.RootComponentId, registry);
            document.reparentSubtree(pasted.Id, right.Id, registry);
            moved = document.GeneratedText;
            clipboard.cut(document, pasted.Id, registry);
            document.undo();
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), moved);
            document.undo();
            document.undo();
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), original);
            testCase.verifyTrue(clipboard.hasContents(document));
        end

        function parsedChildCanMoveUnderGeneratedParent(testCase)
            % parsedChildCanMoveUnderGeneratedParent Generate the new parent before relocated parsed initialization.
            [document, registry, ~, right, leaf] = SubtreeWorkflowTest.fixture();
            generated = document.insertComponent(registry, "uipanel", right.Id);
            document.reparentSubtree(leaf.Id, generated.Id, registry);
            reopened = yamada.source.AppSourceParser.parseText(document.GeneratedText, registry);
            testCase.verifyNotEmpty(reopened.getComponentByName(generated.Name));
            testCase.verifyNotEmpty(reopened.getComponentByName(leaf.Name));
            testCase.verifyEqual(reopened.getComponentByName(leaf.Name).ParentId, reopened.getComponentByName(generated.Name).Id);
        end

        function pasteUnderMovedParsedParentKeepsGenerationOrder(testCase)
            % pasteUnderMovedParsedParentKeepsGenerationOrder Insert generated descendants after their relocated parent.
            [document, registry, left, right, leaf] = SubtreeWorkflowTest.fixture();
            clipboard = yamada.model.ComponentClipboard();
            clipboard.copy(document, leaf.Id, registry);
            document.reparentSubtree(left.Id, right.Id, registry);
            pasted = clipboard.paste(document, left.Id, registry);
            reopened = yamada.source.AppSourceParser.parseText(document.GeneratedText, registry);
            testCase.verifyNotEmpty(reopened.getComponentByName(pasted.Name));
            testCase.verifyEqual(reopened.getComponentByName(pasted.Name).ParentId, reopened.getComponentByName(left.Name).Id);
            testCase.verifyEqual(numel(reopened.Components), numel(document.Components));
        end

        function nonParentReferenceStillBlocksDeletion(testCase)
            % nonParentReferenceStillBlocksDeletion Do not ignore a property reference outside the rewritten parent token.
            [original, registry, left, right, leaf] = SubtreeWorkflowTest.fixture();
            source = replace(original.OriginalText, "app." + leaf.Name + " = uilabel(app." + left.Name + ");", ...
                "app." + leaf.Name + " = uilabel(app." + left.Name + ");" + newline + ...
                "            app." + leaf.Name + ".UserData = app." + left.Name + ";");
            document = yamada.source.AppSourceParser.parseText(source, registry);
            left = document.getComponentByName(left.Name);
            right = document.getComponentByName(right.Name);
            leaf = document.getComponentByName(leaf.Name);
            document.reparentSubtree(leaf.Id, right.Id, registry);
            history = document.HistoryIndex;
            testCase.verifySubstring(document.GeneratedText, "app." + leaf.Name + ".UserData = app." + left.Name + ";");
            testCase.verifyError(@() document.removeSubtree(left.Id, registry), "yamada:SubtreeSourceEdits:UnsafeDeletion");
            testCase.verifyEqual(document.HistoryIndex, history);
            testCase.verifyNotEmpty(document.getComponent(left.Id));
        end
    end

    methods (Static, Access = private)
        function [document, registry, left, right, leaf] = fixture()
            % fixture Parse a trusted generated source without constructing its application.
            arguments (Output)
                document (1, 1) yamada.model.DocumentModel
                registry (1, 1) yamada.model.ComponentRegistry
                left (1, 1) yamada.model.ComponentRecord
                right (1, 1) yamada.model.ComponentRecord
                leaf (1, 1) yamada.model.ComponentRecord
            end
            registry = yamada.model.ComponentRegistry.createDefault();
            original = yamada.model.NewAppFactory.createEmpty("WorkflowApp", registry);
            left = original.insertComponent(registry, "uipanel", original.RootComponentId);
            leaf = original.insertComponent(registry, "uilabel", left.Id);
            right = original.insertComponent(registry, "uipanel", original.RootComponentId);
            source = yamada.source.NewAppGenerator(registry).generate(original);
            document = yamada.source.AppSourceParser.parseText(source, registry);
            left = document.getComponentByName(left.Name);
            right = document.getComponentByName(right.Name);
            leaf = document.getComponentByName(leaf.Name);
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
