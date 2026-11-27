classdef (TestTags = {'fast', 'model', 'generation'}) ComponentClipboardTest < matlab.unittest.TestCase
    % ComponentClipboardTest Verify independent copy, atomic cut and repeatable paste.
    %   These tests exercise model and source contracts without UI entry points.

    methods (Test)
        % Guarantee: Copy is read-only, and Paste creates independent components with their bindings and descendants.
        % Failure mode: Copy dirties the document, Paste shares data with the original, or generated descendants are lost.
        function cutCarriesBindingsAndRetainsHandlers(testCase)
            % cutCarriesBindingsAndRetainsHandlers Move the connections while leaving callback bodies in place.
            [document, registry, left, right] = ComponentClipboardTest.fixture();
            button = document.insertComponent(registry, "uibutton", left.Id);
            document.applyCallbackAction(left.Id, "SizeChangedFcn", "New", registry, yamada.source.CallbackMethodTargets.defaultName(document, left.Id, "SizeChangedFcn", registry));
            document.applyCallbackAction(button.Id, "ButtonPushedFcn", "New", registry, yamada.source.CallbackMethodTargets.defaultName(document, button.Id, "ButtonPushedFcn", registry));
            before = document.CurrentText;
            handler = regexp(before, 'function [^\r\n]*ButtonPushed[^\r\n]*', 'match', 'once');
            testCase.assertNotEmpty(handler);
            clipboard = yamada.model.ComponentClipboard();
            testCase.verifyTrue(clipboard.availability("Cut", document, left.Id, registry).Enabled);
            clipboard.cut(document, left.Id, registry);
            testCase.verifyEmpty(document.getComponent(button.Id));
            testCase.verifyFalse(contains(document.CurrentText, ".ButtonPushedFcn ="));
            testCase.verifyEqual(count(document.CurrentText, handler), 1);
            pasted = clipboard.paste(document, right.Id, registry);
            testCase.verifyEqual(count(document.CurrentText, ".ButtonPushedFcn ="), 1);
            testCase.verifyEqual(count(document.CurrentText, ".SizeChangedFcn ="), 1);
            testCase.verifyEqual(pasted.ParentId, right.Id);
            document.undo();
            document.undo();
            testCase.verifyEqual(document.CurrentText, before);
        end

        function copyDoesNotDirtyAndPasteUsesIndependentData(testCase)
            % copyDoesNotDirtyAndPasteUsesIndependentData Freeze values and assign fresh subtree identities.
            [document, registry, left, right, leaf] = ComponentClipboardTest.fixture();
            leaf.setProperty("Text", "Copied");
            document.markSaved();
            clipboard = yamada.model.ComponentClipboard();
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

        % Guarantee: pasted names and ids are valid, unique, and stable for Cut.
        % Failure mode: repeated Paste produces duplicate or too-long names, or Cut then Paste renames components unnecessarily.
        function repeatedPastesAvoidNameAndIdCollisions(testCase)
            % repeatedPastesAvoidNameAndIdCollisions Retain clipboard contents and vary absolute offsets.
            [document, registry, left, right] = ComponentClipboardTest.fixture();
            clipboard = yamada.model.ComponentClipboard();
            clipboard.copy(document, left.Id, registry);
            first = clipboard.paste(document, right.Id, registry);
            second = clipboard.paste(document, right.Id, registry);
            testCase.verifyNotEqual(first.Id, second.Id);
            testCase.verifyNotEqual(first.Name, second.Name);
            testCase.verifyEqual(second.getProperty("Position").LiteralValue(1:2), ...
                first.getProperty("Position").LiteralValue(1:2) + [10 10]);
            testCase.verifyTrue(clipboard.hasContents());
        end

        function longNamesRemainValidAcrossRepeatedPastes(testCase)
            % longNamesRemainValidAcrossRepeatedPastes Bound generated identifiers to MATLAB name length.
            [document, registry, left, right] = ComponentClipboardTest.fixture();
            document.renameComponent(left.Id, string(repmat('A', 1, namelengthmax)), registry);
            clipboard = yamada.model.ComponentClipboard();
            clipboard.copy(document, left.Id, registry);
            first = clipboard.paste(document, right.Id, registry);
            second = clipboard.paste(document, right.Id, registry);
            testCase.verifyTrue(isvarname(first.Name));
            testCase.verifyTrue(isvarname(second.Name));
            testCase.verifyLessThanOrEqual(strlength(first.Name), namelengthmax);
            testCase.verifyNotEqual(first.Name, second.Name);
        end

        % Guarantee: clipboard commands are atomic, and a rejection keeps both the document and the clipboard.
        % Failure mode: a rejected Cut clears the clipboard, or Copy silently drops expression-backed behavior.
        function cutAndPasteEachHaveOneUndoStep(testCase)
            % cutAndPasteEachHaveOneUndoStep Restore deleted subtree and pasted clone independently.
            [document, registry, left, right] = ComponentClipboardTest.fixture();
            before = document.Components;
            history = document.HistoryIndex;
            clipboard = yamada.model.ComponentClipboard();
            clipboard.cut(document, left.Id, registry);
            testCase.verifyEmpty(document.getComponent(left.Id));
            testCase.verifyEqual(document.HistoryIndex, history + 1);
            pasted = clipboard.paste(document, right.Id, registry);
            testCase.verifyEqual(document.HistoryIndex, history + 2);
            document.undo();
            testCase.verifyEmpty(document.getComponent(pasted.Id));
            document.undo();
            testCase.verifyEqual(document.Components, before);
            testCase.verifyTrue(clipboard.hasContents());
        end

        function cutReusesNamesAndNumbersRepeatedPastes(testCase)
            % cutReusesNamesAndNumbersRepeatedPastes Preserve subtree names while avoiding later collisions.
            % Guarantee and failure mode: shared with repeatedPastesAvoidNameAndIdCollisions.
            [document, registry, left, right, leaf] = ComponentClipboardTest.fixture();
            clipboard = yamada.model.ComponentClipboard();
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
            source = yamada.source.NewAppGenerator(registry).generate(original);
            document = yamada.source.AppSourceParser.parseText(source, registry);
            clipboard = yamada.model.ComponentClipboard();
            clipboard.cut(document, document.getComponentByName(left.Name).Id, registry);
            target = document.getComponentByName(right.Name);
            testCase.verifyTrue(clipboard.availability("Paste", document, target.Id, registry).Enabled);
            pasted = clipboard.paste(document, target.Id, registry);
            testCase.verifyEqual(pasted.Name, left.Name);
            reopened = yamada.source.AppSourceParser.parseText(document.GeneratedText, registry);
            testCase.verifyEqual(reopened.getComponentByName(left.Name).ParentId, reopened.getComponentByName(right.Name).Id);
            testCase.verifyEqual(reopened.getComponentByName(leaf.Name).ParentId, reopened.getComponentByName(left.Name).Id);
            document.undo();
            document.undo();
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), source);
        end

        function renamedParsedCutKeepsCurrentName(testCase)
            % renamedParsedCutKeepsCurrentName Reuse the current name despite a pending source rename.
            [original, registry, left, right] = ComponentClipboardTest.fixture();
            source = yamada.source.NewAppGenerator(registry).generate(original);
            document = yamada.source.AppSourceParser.parseText(source, registry);
            component = document.getComponentByName(left.Name);
            document.renameComponent(component.Id, "MovedPanel", registry);
            clipboard = yamada.model.ComponentClipboard();
            clipboard.cut(document, component.Id, registry);
            pasted = clipboard.paste(document, document.getComponentByName(right.Name).Id, registry);
            testCase.verifyEqual(pasted.Name, "MovedPanel");
            reopened = yamada.source.AppSourceParser.parseText(document.GeneratedText, registry);
            testCase.verifyNotEmpty(reopened.getComponentByName("MovedPanel"));
            testCase.verifyEmpty(reopened.getComponentByName(left.Name));
        end

        function undoCutDoesNotAllowDuplicateOriginalNames(testCase)
            % undoCutDoesNotAllowDuplicateOriginalNames Keep clipboard usable when Undo restores the source subtree.
            [document, registry, left, right] = ComponentClipboardTest.fixture();
            clipboard = yamada.model.ComponentClipboard();
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
            % rejectedCutPreservesPreviousClipboard Keep prior copied data when a root cut is rejected.
            % Guarantee and failure mode: shared with cutAndPasteEachHaveOneUndoStep.
            [document, registry, left, right, leaf] = ComponentClipboardTest.fixture();
            clipboard = yamada.model.ComponentClipboard();
            clipboard.copy(document, leaf.Id, registry);
            history = document.HistoryIndex;
            testCase.verifyError(@() clipboard.cut(document, document.RootComponentId, registry), "yamada:DocumentModel:UnsafeSubtreeCopy");
            pasted = clipboard.paste(document, left.Id, registry);
            testCase.verifyEqual(pasted.Factory, "uilabel");
            testCase.verifyEqual(document.HistoryIndex, history + 1);
        end

        % Guarantee: a subtree copied or cut from one document pastes into another, keeping external references and callback bindings as written and warning about the ones the destination does not define.
        % Failure mode: Paste into another document is refused, resolves an external reference through an identity of the first document, drops a binding, or blocks editing with an error for a missing target.
        function pasteIntoAnotherDocumentKeepsExternalReferences(testCase)
            % pasteIntoAnotherDocumentKeepsExternalReferences Paste a source-backed subtree across documents.
            registry = yamada.model.ComponentRegistry.createDefault();
            source = strjoin(["classdef SourceApp < handle", "properties", ...
                "UIFigure matlab.ui.Figure", "Menu matlab.ui.container.ContextMenu", ...
                "Panel matlab.ui.container.Panel", "Button matlab.ui.control.Button", "end", ...
                "methods", "function app = SourceApp", "createComponents(app);", "end", "end", ...
                "methods (Access = private)", "function createComponents(app)", ...
                "app.UIFigure = uifigure(Visible='off');", "app.Menu = uicontextmenu(app.UIFigure);", ...
                "app.Panel = uipanel(app.UIFigure);", "app.Button = uibutton(app.Panel);", ...
                "app.Button.ButtonPushedFcn = @app.ButtonPushed;", "app.Button.ContextMenu = app.Menu;", ...
                "app.Button.UserData = @app.helper;", "end", ...
                "function ButtonPushed(app, event)", "end", "end", "end"], sprintf("\r\n"));
            document = yamada.source.AppSourceParser.parseText(source, registry);
            empty = yamada.model.NewAppFactory.createEmpty("OtherApp", registry);
            for action = ["copy", "cut"]
                other = yamada.source.AppSourceParser.parseText(yamada.source.NewAppGenerator(registry).generate(empty), registry);
                clipboard = yamada.model.ComponentClipboard();
                clipboard.(action)(document, document.getComponentByName("Panel").Id, registry);
                testCase.verifyTrue(clipboard.availability("Paste", other, other.RootComponentId, registry).Enabled);
                pasted = clipboard.paste(other, other.RootComponentId, registry);
                if action == "cut", testCase.verifyEqual(pasted.Name, "Panel"); end
                button = other.getComponent(pasted.Children(1));
                testCase.verifyEqual(button.getProperty("ContextMenu").SourceExpression, "app.Menu");
                testCase.verifyEqual(button.getProperty("ButtonPushedFcn").SourceExpression, "@app.ButtonPushed");
                diagnostics = yamada.validation.ModelValidator.validate(other, registry);
                testCase.verifyFalse(yamada.validation.ModelValidator.hasErrors(diagnostics));
                testCase.verifyEqual(sort(string({diagnostics(string({diagnostics.ComponentId}) == button.Id).Code})), ...
                    ["missing-callback-method" "missing-reference-target"]);
                reopened = yamada.source.AppSourceParser.parseText(other.GeneratedText, registry);
                testCase.verifyNotEmpty(reopened.getComponentByName(button.Name));
            end
            % A renamed destination button keeps the parsed identity of the copied menu, but is no context menu.
            other = yamada.source.AppSourceParser.parseText(replace(source, "classdef SourceApp", "classdef OtherApp"), registry);
            other.removeSubtree(other.getComponentByName("Panel").Id, registry);
            other.removeSubtree(other.getComponentByName("Menu").Id, registry);
            button = other.insertComponent(registry, "uibutton", other.RootComponentId);
            other.renameComponent(button.Id, "Menu", registry);
            reopened = yamada.source.AppSourceParser.parseText(other.GeneratedText, registry);
            reopened.renameComponent(reopened.getComponentByName("Menu").Id, "OkButton", registry);
            clipboard = yamada.model.ComponentClipboard();
            original = yamada.source.AppSourceParser.parseText(source, registry);
            clipboard.copy(original, original.getComponentByName("Panel").Id, registry);
            pasted = clipboard.paste(reopened, reopened.RootComponentId, registry);
            testCase.verifyEqual(reopened.getComponent(pasted.Children(1)).getProperty("ContextMenu").SourceExpression, "app.Menu");
            % The source document defines both targets; a function handle outside a callback property never warns.
            diagnostics = yamada.validation.ModelValidator.validate(document, registry);
            testCase.verifyEmpty(diagnostics(ismember(string({diagnostics.Code}), ["missing-callback-method" "missing-reference-target"])));
        end

        function sourceInsertionIncludesGeneratedDescendants(testCase)
            % sourceInsertionIncludesGeneratedDescendants Reopen a copied parsed subtree under another parent.
            % Guarantee and failure mode: shared with cutCarriesBindingsAndRetainsHandlers.
            [original, registry, left, right] = ComponentClipboardTest.fixture();
            source = yamada.source.NewAppGenerator(registry).generate(original);
            document = yamada.source.AppSourceParser.parseText(source, registry);
            left = document.getComponentByName(left.Name);
            right = document.getComponentByName(right.Name);
            clipboard = yamada.model.ComponentClipboard();
            clipboard.copy(document, left.Id, registry);
            pasted = clipboard.paste(document, right.Id, registry);
            reopened = yamada.source.AppSourceParser.parseText(document.GeneratedText, registry);
            copied = reopened.getComponentByName(pasted.Name);
            testCase.verifyEqual(copied.ParentId, reopened.getComponentByName(right.Name).Id);
            testCase.verifyEqual(numel(copied.Children), 1);
            document.undo();
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), source);
        end

        function expressionCopyFailsWithoutDiscardingContents(testCase)
            % expressionCopyFailsWithoutDiscardingContents Refuse expressions instead of silently dropping behavior.
            % Guarantee and failure mode: shared with cutAndPasteEachHaveOneUndoStep.
            [document, registry, left, right, leaf] = ComponentClipboardTest.fixture();
            clipboard = yamada.model.ComponentClipboard();
            clipboard.copy(document, leaf.Id, registry);
            left.getProperty("Position").setSourceExpression("computePosition(app)");
            testCase.verifyError(@() clipboard.copy(document, left.Id, registry), "yamada:DocumentModel:UnsafeSubtreeCopy");
            left.getProperty("Position").setLiteral([20 20 100 30]);
            copied = clipboard.paste(document, right.Id, registry);
            testCase.verifyEqual(copied.Factory, "uilabel");
        end

        function leafTargetResolvesParentAndGridFailurePreservesHistory(testCase)
            % leafTargetResolvesParentAndGridFailurePreservesHistory Resolve nearest parent and keep rejected paste atomic.
            [document, registry, ~, right, leaf] = ComponentClipboardTest.fixture();
            clipboard = yamada.model.ComponentClipboard();
            clipboard.copy(document, leaf.Id, registry);
            testCase.verifyEqual(clipboard.destination(document, leaf.Id, registry), leaf.ParentId);
            grid = document.insertComponent(registry, "uigridlayout", right.Id);
            grid.setProperty("RowHeight", {"1x"});
            grid.setProperty("ColumnWidth", {"1x"});
            document.insertComponent(registry, "uilabel", grid.Id);
            before = document.Components;
            history = document.HistoryIndex;
            testCase.verifyError(@() clipboard.paste(document, grid.Id, registry), "yamada:SubtreePlacementPlanner:NoSpace");
            testCase.verifyEqual(document.Components, before);
            testCase.verifyEqual(document.HistoryIndex, history);
            testCase.verifyTrue(clipboard.hasContents());
        end
    end

    methods (Static, Access = private)
        function [document, registry, left, right, leaf] = fixture()
            % fixture Build a copyable panel subtree and a different compatible destination.
            arguments (Output)
                document (1, 1) yamada.model.DocumentModel
                registry (1, 1) yamada.model.ComponentRegistry
                left (1, 1) yamada.model.ComponentRecord
                right (1, 1) yamada.model.ComponentRecord
                leaf (1, 1) yamada.model.ComponentRecord
            end
            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("ClipboardApp", registry);
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
