classdef (TestTags = {'fast', 'model', 'generation'}) ComponentClipboardTest < matlab.unittest.TestCase
    % ComponentClipboardTest Verify independent copy, atomic cut and repeatable paste.
    %   These tests exercise model and source contracts without UI entry points.

    methods (Test)
        function copyDoesNotDirtyAndPasteUsesIndependentData(testCase)
            % copyDoesNotDirtyAndPasteUsesIndependentData Freeze values and assign fresh subtree identities.
            [document, registry, left, right, leaf] = ComponentClipboardTest.fixture();
            leaf.setProperty("Text", "Copied");
            document.markSaved();
            clipboard = macd.model.ComponentClipboard();
            history = document.HistoryIndex;
            clipboard.copy(document, left.Id, registry);
            testCase.verifyFalse(document.IsDirty);
            testCase.verifyEqual(document.HistoryIndex, history);
            leaf.setProperty("Text", "Edited");
            pasted = clipboard.paste(document, right.Id, registry);
            testCase.verifyNotEqual(pasted.Id, left.Id);
            testCase.verifyNotEqual(pasted.Name, left.Name);
            testCase.verifyEqual(pasted.ParentId, right.Id);
            copiedLeaf = document.getComponent(pasted.Children(1));
            testCase.verifyEqual(copiedLeaf.getProperty("Text").LiteralValue, "Copied");
            testCase.verifyNotEqual(copiedLeaf.Id, leaf.Id);
            testCase.verifyEqual(document.HistoryIndex, history + 1);
            document.undo();
            testCase.verifyEmpty(document.getComponent(pasted.Id));
            document.redo();
            testCase.verifyEqual(document.getComponent(pasted.Id), pasted);
        end

        function repeatedPastesAvoidNameAndIdCollisions(testCase)
            % repeatedPastesAvoidNameAndIdCollisions Retain clipboard contents and vary absolute offsets.
            [document, registry, left, right] = ComponentClipboardTest.fixture();
            clipboard = macd.model.ComponentClipboard();
            clipboard.copy(document, left.Id, registry);
            first = clipboard.paste(document, right.Id, registry);
            second = clipboard.paste(document, right.Id, registry);
            testCase.verifyNotEqual(first.Id, second.Id);
            testCase.verifyNotEqual(first.Name, second.Name);
            testCase.verifyEqual(second.getProperty("Position").LiteralValue(1:2), ...
                first.getProperty("Position").LiteralValue(1:2) + [10 10]);
            testCase.verifyTrue(clipboard.hasContents(document));
        end

        function longNamesRemainValidAcrossRepeatedPastes(testCase)
            % longNamesRemainValidAcrossRepeatedPastes Bound generated identifiers to MATLAB name length.
            [document, registry, left, right] = ComponentClipboardTest.fixture();
            left.Name = string(repmat('A', 1, namelengthmax));
            clipboard = macd.model.ComponentClipboard();
            clipboard.copy(document, left.Id, registry);
            first = clipboard.paste(document, right.Id, registry);
            second = clipboard.paste(document, right.Id, registry);
            testCase.verifyTrue(isvarname(first.Name));
            testCase.verifyTrue(isvarname(second.Name));
            testCase.verifyLessThanOrEqual(strlength(first.Name), namelengthmax);
            testCase.verifyNotEqual(first.Name, second.Name);
        end

        function cutAndPasteEachHaveOneUndoStep(testCase)
            % cutAndPasteEachHaveOneUndoStep Restore deleted subtree and pasted clone independently.
            [document, registry, left, right] = ComponentClipboardTest.fixture();
            before = document.Components;
            history = document.HistoryIndex;
            clipboard = macd.model.ComponentClipboard();
            clipboard.cut(document, left.Id, registry);
            testCase.verifyEmpty(document.getComponent(left.Id));
            testCase.verifyEqual(document.HistoryIndex, history + 1);
            pasted = clipboard.paste(document, right.Id, registry);
            testCase.verifyEqual(document.HistoryIndex, history + 2);
            document.undo();
            testCase.verifyEmpty(document.getComponent(pasted.Id));
            document.undo();
            testCase.verifyEqual(document.Components, before);
            testCase.verifyTrue(clipboard.hasContents(document));
        end

        function rejectedCutPreservesPreviousClipboard(testCase)
            % rejectedCutPreservesPreviousClipboard Keep prior copied data on read-only cut failure.
            [document, registry, left, right, leaf] = ComponentClipboardTest.fixture();
            clipboard = macd.model.ComponentClipboard();
            clipboard.copy(document, leaf.Id, registry);
            right.IsEditable = false;
            history = document.HistoryIndex;
            testCase.verifyError(@() clipboard.cut(document, right.Id, registry), "macd:DocumentModel:UnsafeSubtreeCopy");
            right.IsEditable = true;
            pasted = clipboard.paste(document, left.Id, registry);
            testCase.verifyEqual(pasted.Factory, "uilabel");
            testCase.verifyEqual(document.HistoryIndex, history + 1);
        end

        function differentDocumentAndClearInvalidateClipboard(testCase)
            % differentDocumentAndClearInvalidateClipboard Restrict clipboard to its owning document.
            [document, registry, left] = ComponentClipboardTest.fixture();
            other = macd.model.NewAppFactory.createEmpty("OtherApp", registry);
            clipboard = macd.model.ComponentClipboard();
            clipboard.copy(document, left.Id, registry);
            testCase.verifyFalse(clipboard.hasContents(other));
            testCase.verifyError(@() clipboard.paste(other, other.RootComponentId, registry), "macd:ComponentClipboard:Empty");
            clipboard.clear();
            testCase.verifyFalse(clipboard.hasContents(document));
        end

        function sourceInsertionIncludesGeneratedDescendants(testCase)
            % sourceInsertionIncludesGeneratedDescendants Reopen a copied parsed subtree under another parent.
            [original, registry, left, right] = ComponentClipboardTest.fixture();
            source = macd.source.NewAppGenerator(registry).generate(original);
            document = macd.source.AppSourceParser.parseText(source, registry);
            left = document.getComponentByName(left.Name);
            right = document.getComponentByName(right.Name);
            clipboard = macd.model.ComponentClipboard();
            clipboard.copy(document, left.Id, registry);
            pasted = clipboard.paste(document, right.Id, registry);
            reopened = macd.source.AppSourceParser.parseText(document.GeneratedText, registry);
            copied = reopened.getComponentByName(pasted.Name);
            testCase.verifyEqual(copied.ParentId, reopened.getComponentByName(right.Name).Id);
            testCase.verifyEqual(numel(copied.Children), 1);
            document.undo();
            testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(document), source);
        end

        function expressionCopyFailsWithoutDiscardingContents(testCase)
            % expressionCopyFailsWithoutDiscardingContents Refuse expressions instead of silently dropping behavior.
            [document, registry, left, right, leaf] = ComponentClipboardTest.fixture();
            clipboard = macd.model.ComponentClipboard();
            clipboard.copy(document, leaf.Id, registry);
            left.getProperty("Position").setSourceExpression("computePosition(app)");
            testCase.verifyError(@() clipboard.copy(document, left.Id, registry), "macd:DocumentModel:UnsafeSubtreeCopy");
            left.getProperty("Position").setLiteral([20 20 100 30]);
            copied = clipboard.paste(document, right.Id, registry);
            testCase.verifyEqual(copied.Factory, "uilabel");
        end

        function leafTargetResolvesParentAndGridFailurePreservesHistory(testCase)
            % leafTargetResolvesParentAndGridFailurePreservesHistory Resolve nearest parent and keep rejected paste atomic.
            [document, registry, ~, right, leaf] = ComponentClipboardTest.fixture();
            clipboard = macd.model.ComponentClipboard();
            clipboard.copy(document, leaf.Id, registry);
            testCase.verifyEqual(clipboard.destination(document, leaf.Id, registry), leaf.ParentId);
            grid = document.insertComponent(registry, "uigridlayout", right.Id);
            grid.setProperty("RowHeight", {"1x"});
            grid.setProperty("ColumnWidth", {"1x"});
            document.insertComponent(registry, "uilabel", grid.Id);
            before = document.Components;
            history = document.HistoryIndex;
            testCase.verifyError(@() clipboard.paste(document, grid.Id, registry), "macd:SubtreePlacementPlanner:NoSpace");
            testCase.verifyEqual(document.Components, before);
            testCase.verifyEqual(document.HistoryIndex, history);
            testCase.verifyTrue(clipboard.hasContents(document));
        end
    end

    methods (Static, Access = private)
        function [document, registry, left, right, leaf] = fixture()
            % fixture Build a copyable panel subtree and a different compatible destination.
            arguments (Output)
                document (1, 1) macd.model.DocumentModel
                registry (1, 1) macd.model.ComponentRegistry
                left (1, 1) macd.model.ComponentRecord
                right (1, 1) macd.model.ComponentRecord
                leaf (1, 1) macd.model.ComponentRecord
            end
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("ClipboardApp", registry);
            left = document.insertComponent(registry, "uipanel", document.RootComponentId);
            leaf = document.insertComponent(registry, "uilabel", left.Id);
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
