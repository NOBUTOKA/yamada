classdef (TestTags = {'fast', 'model', 'generation'}) ComponentClipboardTest < matlab.unittest.TestCase
    % ComponentClipboardTest Verify independent copy, atomic cut and repeatable paste.
    %   These tests exercise model and source contracts without UI entry points.

    methods (Test)
        function pendingCallbacksStayOnOriginalSubtree(testCase)
            % pendingCallbacksStayOnOriginalSubtree Omit root and child bindings without changing pending edits or history.
            [document, registry, left, right] = ComponentClipboardTest.fixture();
            button = document.insertComponent(registry, "uibutton", left.Id);
            button.setProperty("Text", "Copy this text");
            document.applyCallbackAction(left.Id, "SizeChangedFcn", "Add", registry);
            document.applyCallbackAction(button.Id, "ButtonPushedFcn", "Add", registry);
            document.markSaved();
            original = macd.source.RoundTripGenerator(registry).generate(document);
            edits = document.CallbackEdits;
            history = document.HistoryIndex;
            clipboard = macd.model.ComponentClipboard();
            testCase.verifyTrue(clipboard.availability("Copy", document, left.Id, registry).Enabled);
            testCase.verifyFalse(clipboard.availability("Cut", document, left.Id, registry).Enabled);
            clipboard.copy(document, left.Id, registry);
            testCase.verifyFalse(document.IsDirty);
            testCase.verifyEqual(document.HistoryIndex, history);
            testCase.verifyEqual(document.CallbackEdits, edits);
            testCase.verifyError(@() clipboard.cut(document, left.Id, registry), "macd:DocumentModel:UnsafeSubtreeEdit");
            testCase.verifyEqual(document.HistoryIndex, history);
            pasted = clipboard.paste(document, right.Id, registry);
            copiedButton = document.getComponentByName(button.Name + "Copy");
            testCase.verifyEqual(copiedButton.getProperty("Text").LiteralValue, "Copy this text");
            for component = [pasted copiedButton]
                states = macd.source.CallbackSourceAnalyzer.analyze(document, component.Id, registry);
                testCase.verifyTrue(all(string({states.State}) == "absent"));
            end
            testCase.verifyEqual(document.CallbackEdits, edits);
            testCase.verifyEqual(document.HistoryIndex, history + 1);
            document.undo();
            testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(document), original);
            document.redo();
            clipboard.paste(document, right.Id, registry);
            testCase.verifyEqual(document.CallbackEdits, edits);
            testCase.verifyEqual(count(document.GeneratedText, ".ButtonPushedFcn ="), 1);
            testCase.verifyEqual(count(document.GeneratedText, ".SizeChangedFcn ="), 1);
        end

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

        function cutReusesNamesAndNumbersRepeatedPastes(testCase)
            % cutReusesNamesAndNumbersRepeatedPastes Preserve subtree names while avoiding later collisions.
            [document, registry, left, right, leaf] = ComponentClipboardTest.fixture();
            clipboard = macd.model.ComponentClipboard();
            clipboard.cut(document, left.Id, registry);
            first = clipboard.paste(document, right.Id, registry);
            testCase.verifyEqual(first.Name, left.Name);
            testCase.verifyEqual(document.getComponent(first.Children(1)).Name, leaf.Name);
            second = clipboard.paste(document, right.Id, registry);
            testCase.verifyEqual(second.Name, left.Name + "3");
            testCase.verifyEqual(document.getComponent(second.Children(1)).Name, leaf.Name + "2");
        end

        function parsedCutReusesNamesAfterSourceDeletion(testCase)
            % parsedCutReusesNamesAfterSourceDeletion Save and reopen original identifiers under a different parent.
            [original, registry, left, right, leaf] = ComponentClipboardTest.fixture();
            source = macd.source.NewAppGenerator(registry).generate(original);
            document = macd.source.AppSourceParser.parseText(source, registry);
            clipboard = macd.model.ComponentClipboard();
            clipboard.cut(document, document.getComponentByName(left.Name).Id, registry);
            target = document.getComponentByName(right.Name);
            testCase.verifyTrue(clipboard.availability("Paste", document, target.Id, registry).Enabled);
            pasted = clipboard.paste(document, target.Id, registry);
            testCase.verifyEqual(pasted.Name, left.Name);
            reopened = macd.source.AppSourceParser.parseText(document.GeneratedText, registry);
            testCase.verifyEqual(reopened.getComponentByName(left.Name).ParentId, reopened.getComponentByName(right.Name).Id);
            testCase.verifyEqual(reopened.getComponentByName(leaf.Name).ParentId, reopened.getComponentByName(left.Name).Id);
            document.undo();
            document.undo();
            testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(document), source);
        end

        function renamedParsedCutKeepsCurrentName(testCase)
            % renamedParsedCutKeepsCurrentName Reuse the current name despite a pending source rename.
            [original, registry, left, right] = ComponentClipboardTest.fixture();
            source = macd.source.NewAppGenerator(registry).generate(original);
            document = macd.source.AppSourceParser.parseText(source, registry);
            component = document.getComponentByName(left.Name);
            document.renameComponent(component.Id, "MovedPanel", registry);
            clipboard = macd.model.ComponentClipboard();
            clipboard.cut(document, component.Id, registry);
            pasted = clipboard.paste(document, document.getComponentByName(right.Name).Id, registry);
            testCase.verifyEqual(pasted.Name, "MovedPanel");
            reopened = macd.source.AppSourceParser.parseText(document.GeneratedText, registry);
            testCase.verifyNotEmpty(reopened.getComponentByName("MovedPanel"));
            testCase.verifyEmpty(reopened.getComponentByName(left.Name));
        end

        function undoCutDoesNotAllowDuplicateOriginalNames(testCase)
            % undoCutDoesNotAllowDuplicateOriginalNames Keep clipboard usable when Undo restores the source subtree.
            [document, registry, left, right] = ComponentClipboardTest.fixture();
            clipboard = macd.model.ComponentClipboard();
            clipboard.cut(document, left.Id, registry);
            document.undo();
            pasted = clipboard.paste(document, right.Id, registry);
            testCase.verifyEqual(pasted.Name, left.Name + "3");
            testCase.verifyEqual(document.getComponent(left.Id), left);
            clipboard.copy(document, left.Id, registry);
            copied = clipboard.paste(document, right.Id, registry);
            testCase.verifyEqual(copied.Name, left.Name + "Copy");
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
