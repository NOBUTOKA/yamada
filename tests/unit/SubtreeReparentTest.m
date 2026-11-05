classdef (TestTags = {'fast', 'model', 'generation', 'gridOverlay'}) SubtreeReparentTest < matlab.unittest.TestCase
    % SubtreeReparentTest Verify identity-preserving atomic subtree parent changes.
    %   Tests cover layout conversion, source relocation and history restoration.

    methods (Test)
        function movesNestedSubtreeAndRestoresExactOrder(testCase)
            % movesNestedSubtreeAndRestoresExactOrder Keep handles and identities across one undoable move.
            [document, registry, left, right, nested, leaf] = SubtreeReparentTest.fixture();
            before = document.Components;
            leftChildren = left.Children;
            beforePosition = nested.getProperty("Position").LiteralValue;
            document.markSaved();
            history = document.HistoryIndex;
            document.reparentSubtree(nested.Id, right.Id, registry);
            testCase.verifyEqual(nested.ParentId, right.Id);
            testCase.verifyEqual(leaf.ParentId, nested.Id);
            testCase.verifyEqual(nested.getProperty("Position").LiteralValue, beforePosition);
            testCase.verifyEqual(document.HistoryIndex, history + 1);
            testCase.verifyEqual(document.getComponent(nested.Id), nested);
            testCase.verifyLessThan(find(document.Components == right), find(document.Components == nested));
            document.undo();
            testCase.verifyEqual(document.Components, before);
            testCase.verifyEqual(left.Children, leftChildren);
            testCase.verifyEmpty(right.Children);
            testCase.verifyEqual(nested.ParentId, left.Id);
            testCase.verifyFalse(document.IsDirty);
            document.redo();
            testCase.verifyEqual(nested.ParentId, right.Id);
        end

        function movesAcrossAbsoluteAndGridBoundaries(testCase)
            % movesAcrossAbsoluteAndGridBoundaries Restore both parent and placement fields on undo.
            [document, registry, left, right, ~, leaf] = SubtreeReparentTest.fixture();
            grid = document.insertComponent(registry, "uigridlayout", right.Id);
            original = leaf.getProperty("Position").LiteralValue;
            document.reparentSubtree(leaf.Id, grid.Id, registry);
            testCase.verifyEmpty(leaf.getProperty("Position"));
            testCase.verifyEqual(leaf.getProperty("Layout.Row").LiteralValue, 1);
            document.undo();
            testCase.verifyEqual(leaf.getProperty("Position").LiteralValue, original);
            document.redo();
            document.reparentSubtree(leaf.Id, left.Id, registry, [10 20 90 25]);
            testCase.verifyEmpty(leaf.getProperty("Layout.Row"));
            testCase.verifyEqual(leaf.getProperty("Position").LiteralValue, [10 20 90 25]);
            document.undo();
            testCase.verifyEqual(leaf.ParentId, grid.Id);
            testCase.verifyEmpty(leaf.getProperty("Position"));
        end

        function parsedMoveUnderLaterParentRoundTrips(testCase)
            % parsedMoveUnderLaterParentRoundTrips Relocate initialization after a later destination safely.
            [original, registry, ~, right, nested, leaf] = SubtreeReparentTest.fixture();
            source = yamada.source.NewAppGenerator(registry).generate(original);
            document = yamada.source.AppSourceParser.parseText(source, registry);
            nested = document.getComponentByName(nested.Name);
            right = document.getComponentByName(right.Name);
            document.reparentSubtree(nested.Id, right.Id, registry);
            after = document.GeneratedText;
            reopened = yamada.source.AppSourceParser.parseText(after, registry);
            testCase.verifyEqual(reopened.getComponentByName(nested.Name).ParentId, reopened.getComponentByName(right.Name).Id);
            testCase.verifyEqual(reopened.getComponentByName(leaf.Name).ParentId, reopened.getComponentByName(nested.Name).Id);
            document.undo();
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), source);
            document.redo();
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), after);
        end

        function preservesCallbackMethodsAndBindings(testCase)
            % preservesCallbackMethodsAndBindings Keep existing handler text while moving initialization.
            [original, registry, left, right] = SubtreeReparentTest.fixture();
            button = original.insertComponent(registry, "uibutton", left.Id);
            original.applyCallbackAction(button.Id, "ButtonPushedFcn", "Add", registry);
            source = yamada.source.NewAppGenerator(registry).generate(original);
            source = replace(source, "% Add callback behavior here.", "error('callback-must-not-run');");
            document = yamada.source.AppSourceParser.parseText(source, registry);
            button = document.getComponentByName(button.Name);
            right = document.getComponentByName(right.Name);
            document.reparentSubtree(button.Id, right.Id, registry);
            testCase.verifySubstring(document.GeneratedText, "error('callback-must-not-run');");
            testCase.verifySubstring(document.GeneratedText, ".ButtonPushedFcn = @app.");
        end

        function dependentInitializationRejectsWithoutMutation(testCase)
            % dependentInitializationRejectsWithoutMutation Keep all live state intact when relocation changes dependencies.
            [original, registry, ~, right, nested] = SubtreeReparentTest.fixture();
            source = yamada.source.NewAppGenerator(registry).generate(original);
            marker = "app." + right.Name + " = uipanel(app.UIFigure);";
            source = replace(source, marker, "disp(app." + nested.Name + ");" + newline + "            " + marker);
            document = yamada.source.AppSourceParser.parseText(source, registry);
            nested = document.getComponentByName(nested.Name);
            right = document.getComponentByName(right.Name);
            parent = nested.ParentId;
            before = document.Components;
            history = document.HistoryIndex;
            testCase.verifyError(@() document.reparentSubtree(nested.Id, right.Id, registry), ...
                "yamada:DocumentModel:UnsafeSubtreeEdit");
            testCase.verifyEqual(nested.ParentId, parent);
            testCase.verifyEqual(document.Components, before);
            testCase.verifyEqual(document.HistoryIndex, history);
        end

        function gridTransferPreservesSpanAndIsAtomic(testCase)
            % gridTransferPreservesSpanAndIsAtomic Move explicit spans between independent grid parents.
            [document, registry, left, right] = SubtreeReparentTest.fixture();
            first = document.insertComponent(registry, "uigridlayout", left.Id);
            second = document.insertComponent(registry, "uigridlayout", right.Id);
            leaf = document.insertComponent(registry, "uilabel", first.Id);
            document.setProperty(leaf.Id, "Layout.Column", [1 2], registry);
            history = document.HistoryIndex;
            document.reparentSubtree(leaf.Id, second.Id, registry);
            testCase.verifyEqual(document.HistoryIndex, history + 1);
            testCase.verifyEqual(leaf.ParentId, second.Id);
            testCase.verifyEqual(leaf.getProperty("Layout.Column").LiteralValue, [1 2]);
            document.undo();
            testCase.verifyEqual(leaf.ParentId, first.Id);
            testCase.verifyEqual(leaf.getProperty("Layout.Column").LiteralValue, [1 2]);
        end

        function parsedLayoutConversionRemovesOwnedPosition(testCase)
            % parsedLayoutConversionRemovesOwnedPosition Remove obsolete source assignments and reopen new placement.
            [original, registry, ~, right, ~, leaf] = SubtreeReparentTest.fixture();
            grid = original.insertComponent(registry, "uigridlayout", right.Id);
            source = yamada.source.NewAppGenerator(registry).generate(original);
            document = yamada.source.AppSourceParser.parseText(source, registry);
            leaf = document.getComponentByName(leaf.Name);
            grid = document.getComponentByName(grid.Name);
            document.reparentSubtree(leaf.Id, grid.Id, registry);
            after = document.GeneratedText;
            testCase.verifyFalse(contains(after, "app." + leaf.Name + ".Position ="));
            reopened = yamada.source.AppSourceParser.parseText(after, registry);
            testCase.verifyEqual(reopened.getComponentByName(leaf.Name).ParentId, reopened.getComponentByName(grid.Name).Id);
            testCase.verifyEqual(reopened.getComponentByName(leaf.Name).getProperty("Layout.Row").LiteralValue, 1);
            document.undo();
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), source);
        end

        function conditionalInitializationIsRejected(testCase)
            % conditionalInitializationIsRejected Do not relocate statements out of conditional scope.
            [original, registry, ~, right, nested] = SubtreeReparentTest.fixture();
            source = yamada.source.NewAppGenerator(registry).generate(original);
            marker = "app." + nested.Name + " = uipanel(app.Panel);";
            testCase.assertTrue(contains(source, marker));
            source = replace(source, marker, "if true" + newline + "            " + marker + newline + "            end");
            document = yamada.source.AppSourceParser.parseText(source, registry);
            nested = document.getComponentByName(nested.Name);
            right = document.getComponentByName(right.Name);
            parent = nested.ParentId;
            testCase.verifyError(@() document.reparentSubtree(nested.Id, right.Id, registry), ...
                "yamada:DocumentModel:UnsafeSubtreeEdit");
            testCase.verifyEqual(nested.ParentId, parent);
        end

        function repeatedMovesRemainUndoable(testCase)
            % repeatedMovesRemainUndoable Retain original source ownership through repeated parent changes.
            [original, registry, left, right, nested] = SubtreeReparentTest.fixture();
            source = yamada.source.NewAppGenerator(registry).generate(original);
            document = yamada.source.AppSourceParser.parseText(source, registry);
            nested = document.getComponentByName(nested.Name);
            left = document.getComponentByName(left.Name);
            right = document.getComponentByName(right.Name);
            document.reparentSubtree(nested.Id, right.Id, registry);
            first = document.GeneratedText;
            document.reparentSubtree(nested.Id, left.Id, registry);
            reopened = yamada.source.AppSourceParser.parseText(document.GeneratedText, registry);
            testCase.verifyEqual(reopened.getComponentByName(nested.Name).ParentId, reopened.getComponentByName(left.Name).Id);
            document.undo();
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), first);
        end
    end

    methods (Static, Access = private)
        function [document, registry, left, right, nested, leaf] = fixture()
            % fixture Create a subtree before its eventual destination in generation order.
            arguments (Output)
                document (1, 1) yamada.model.DocumentModel
                registry (1, 1) yamada.model.ComponentRegistry
                left (1, 1) yamada.model.ComponentRecord
                right (1, 1) yamada.model.ComponentRecord
                nested (1, 1) yamada.model.ComponentRecord
                leaf (1, 1) yamada.model.ComponentRecord
            end
            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("ReparentApp", registry);
            left = document.insertComponent(registry, "uipanel", document.RootComponentId);
            nested = document.insertComponent(registry, "uipanel", left.Id);
            leaf = document.insertComponent(registry, "uilabel", nested.Id);
            right = document.insertComponent(registry, "uipanel", document.RootComponentId);
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
