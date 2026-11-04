classdef (TestTags = {'fast', 'model', 'generation'}) StructuralSourceEditTest < matlab.unittest.TestCase
    % StructuralSourceEditTest Verify source ownership across component insertion and naming history.
    %   Public edits must preserve literal values, unrelated source, occurrence
    %   identities and subsequent edits after Undo, Redo and Save As.

    properties (TestParameter)
        Operation = {"insert", "delete", "callbackAdd", "callbackDelete", "reparent"}
    end

    methods (Test)
        function editorCommandsRetainBindingsAcrossSaveAndHistory(testCase, Operation)
            % editorCommandsRetainBindingsAcrossSaveAndHistory Compare every structural command with independent source loading.
            [document, registry] = fixture();
            source = replace(document.CurrentText, "uibutton(app.UIFigure, ""push"")", ...
                "uibutton(app.UIFigure, ""push"", FontSize=13)");
            document = macd.source.AppSourceParser.parseText(source, registry);
            button = document.getComponentByName("BottomRightButton");
            if Operation == "callbackDelete", document.applyCallbackAction(button.Id, "ButtonPushedFcn", "Add", registry); end
            switch Operation
                case "insert", document.insertComponent(registry, "uilabel", document.RootComponentId);
                case "delete", document.removeSubtree(button.Id, registry);
                case "callbackAdd", document.applyCallbackAction(button.Id, "ButtonPushedFcn", "Add", registry);
                case "callbackDelete", document.applyCallbackAction(button.Id, "ButtonPushedFcn", "Delete", registry);
                case "reparent", document.reparentSubtree(button.Id, document.getComponentByName("CenterPanel").Id, registry);
            end
            verifyBindings(testCase, document, registry);
            document.ClassName = "SavedCommandHistory";
            source = macd.source.AppClassIdentityRewriter.rewrite(document.CurrentText, document.ClassName);
            checkpoint = macd.model.SavedSourceCheckpoint(document, source, document.ClassName + ".m", registry);
            document.confirmSavedSource(checkpoint, registry); saved = document.CurrentText;
            document.undo(); verifyBindings(testCase, document, registry);
            document.redo(); verifyBindings(testCase, document, registry);
            testCase.verifyEqual(document.CurrentText, saved);
        end

        function deletionRefreshesExecutionEffectFlags(testCase)
            % deletionRefreshesExecutionEffectFlags Remove a source-only setter without leaving stale document restrictions.
            [document, registry] = fixture();
            source = replace(document.CurrentText, "app.TopLeftLabel.Text = ""Top left"";", ...
                "app.TopLeftLabel.Text = ""Top left"";" + newline + "app.TopLeftLabel.UnrecognizedSetting = 1;");
            document = macd.source.AppSourceParser.parseText(source, registry);
            testCase.verifyTrue(document.Metadata.HasUnrecognizedSetter);
            label = document.getComponentByName("TopLeftLabel");
            document.removeSubtree(label.Id, registry);
            testCase.verifyFalse(document.Metadata.HasUnrecognizedSetter);
            document.undo(); testCase.verifyTrue(document.Metadata.HasUnrecognizedSetter);
            document.redo(); testCase.verifyFalse(document.Metadata.HasUnrecognizedSetter);
        end

        function pastedSubtreeAndDistinctEditsRetainSourceBindings(testCase)
            % pastedSubtreeAndDistinctEditsRetainSourceBindings Compare nested copies and their later edits with independent parsing.
            [document, registry] = fixture();
            parent = document.getComponentByName("CenterPanel");
            before = document.CurrentText;
            pasted = document.pasteSubtree(document.copySubtree(parent.Id, registry), document.RootComponentId, registry);
            copied = document.getComponentByName("CenterLabelCopy");
            ids = [copied.Settings.Id]; afterPaste = document.CurrentText;
            verifyBindings(testCase, document, registry);
            document.renameComponent(pasted.Id, "LongerPanelName", registry);
            verifyBindings(testCase, document, registry);
            document.setProperty(copied.Id, "Tooltip", "A different, longer property", registry);
            document.setProperty(copied.Id, "FontSize", 23, registry);
            verifyBindings(testCase, document, registry);
            testCase.verifyTrue(all(ismember(ids, [copied.Settings.Id])));
            for index = 1:3, document.undo(); verifyBindings(testCase, document, registry); end
            testCase.verifyEqual(document.CurrentText, afterPaste);
            document.undo(); testCase.verifyEqual(document.CurrentText, before);
            verifyBindings(testCase, document, registry);
            document.redo(); testCase.verifyEqual(document.getComponent(pasted.Id), pasted);
            testCase.verifyEqual([document.getComponentByName("CenterLabelCopy").Settings.Id], ids);
            verifyBindings(testCase, document, registry);
            for index = 1:3, document.redo(); verifyBindings(testCase, document, registry); end
        end

        function renameReservationsFollowHistoryAndKeepLiteralText(testCase)
            % renameReservationsFollowHistoryAndKeepLiteralText Reserve user members and pasted slots while leaving strings untouched.
            [document, registry] = fixture();
            source = replace(document.CurrentText, "    properties (Access = public)", ...
                "    properties (Access = public)" + newline + "        UserData double");
            document = macd.source.AppSourceParser.parseText(source, registry);
            owner = document.getComponentByName("TopLeftLabel");
            document.setProperty(owner.Id, "Tooltip", "app.TopLeftLabel and UserData", registry);
            before = document.CurrentText; history = document.HistoryIndex;
            testCase.verifyError(@() document.renameComponent(owner.Id, "UserData", registry), ...
                "macd:DocumentModel:ComponentNameCollision");
            testCase.verifyEqual(document.CurrentText, before); testCase.verifyEqual(document.HistoryIndex, history);
            document.renameComponent(owner.Id, "LongerLabel", registry);
            testCase.verifyEqual(owner.getProperty("Tooltip").LiteralValue, "app.TopLeftLabel and UserData");
            pasted = document.pasteSubtree(document.copySubtree(owner.Id, registry), document.RootComponentId, registry);
            testCase.verifyError(@() document.renameComponent(owner.Id, pasted.Name, registry), ...
                "macd:DocumentModel:ComponentNameCollision");
            verifyBindings(testCase, document, registry);
            document.undo(); document.undo(); verifyBindings(testCase, document, registry);
            document.redo(); document.redo(); verifyBindings(testCase, document, registry);
        end

        function savedClassIdentityPreservesPasteAndRenameHistory(testCase)
            % savedClassIdentityPreservesPasteAndRenameHistory Rebase primary patches without changing restored values or component handles.
            [document, registry] = fixture();
            owner = document.getComponentByName("BottomRightButton");
            document.applyCallbackAction(owner.Id, "ButtonPushedFcn", "Add", registry);
            document.renameComponent(owner.Id, "ANameLongEnoughToMovePositions", registry);
            pasted = document.pasteSubtree(document.copySubtree(owner.Id, registry), document.RootComponentId, registry);
            document.ClassName = "SavedWithADifferentClassName";
            source = macd.source.RoundTripGenerator(registry).generate(document);
            source = macd.source.AppClassIdentityRewriter.rewrite(source, document.ClassName);
            checkpoint = macd.model.SavedSourceCheckpoint(document, source, document.ClassName + ".m", registry);
            document.confirmSavedSource(checkpoint, registry);
            saved = document.CurrentText; verifyBindings(testCase, document, registry);
            document.undo(); verifyBindings(testCase, document, registry);
            document.undo(); verifyBindings(testCase, document, registry);
            document.redo(); verifyBindings(testCase, document, registry);
            document.redo(); verifyBindings(testCase, document, registry);
            testCase.verifyEqual(document.CurrentText, saved);
            testCase.verifyEqual(document.getComponent(pasted.Id), pasted);
        end

        function directBuilderValuesRemainPresentWhenPasting(testCase)
            % directBuilderValuesRemainPresentWhenPasting Preserve staged literal configuration and independent copied values.
            [document, registry] = fixture();
            owner = document.getComponentByName("TopLeftLabel");
            owner.setProperty("Text", "Captured copy");
            snapshot = document.copySubtree(owner.Id, registry);
            owner.setProperty("Text", "Current original"); owner.setProperty("Tooltip", "New builder property");
            pasted = document.pasteSubtree(snapshot, document.RootComponentId, registry);
            testCase.verifyEqual(owner.getProperty("Text").LiteralValue, "Current original");
            testCase.verifyEqual(owner.getProperty("Tooltip").LiteralValue, "New builder property");
            testCase.verifyEqual(pasted.getProperty("Text").LiteralValue, "Captured copy");
            verifyBindings(testCase, document, registry);
            document.undo(); verifyBindings(testCase, document, registry);
            testCase.verifyEqual(owner.getProperty("Text").LiteralValue, "Top left");
            document.redo(); verifyBindings(testCase, document, registry);
        end
        function stagedRenameAndSaveRestoreEarlierHistory(testCase)
            % stagedRenameAndSaveRestoreEarlierHistory Keep direct builder writes in the command that publishes them.
            [document, registry] = fixture();
            owner = document.insertComponent(registry, "uilabel", document.RootComponentId);
            originalId = owner.Id; before = document.CurrentText;
            owner.setProperty("Text", "A direct builder value"); owner.setProperty("Tooltip", "Another direct value");
            document.renameComponent(owner.Id, "BuilderRenamedLabel", registry);
            verifyBindings(testCase, document, registry);
            document.ClassName = "SavedBuilderRename";
            source = macd.source.RoundTripGenerator(registry).generate(document);
            source = macd.source.AppClassIdentityRewriter.rewrite(source, document.ClassName);
            checkpoint = macd.model.SavedSourceCheckpoint(document, source, document.ClassName + ".m", registry);
            document.confirmSavedSource(checkpoint, registry); saved = document.CurrentText;
            document.undo(); verifyBindings(testCase, document, registry);
            testCase.verifyEmpty(owner.getProperty("Tooltip"));
            document.undo(); testCase.verifyEmpty(document.getComponent(originalId));
            document.redo(); document.redo(); verifyBindings(testCase, document, registry);
            testCase.verifyEqual(document.CurrentText, saved);
            testCase.verifyNotEqual(document.CurrentText, before);
        end

    end
end

function [document, registry] = fixture()
% fixture Load a small app containing absolute and Grid-managed components.
arguments (Output)
    document (1, 1) macd.model.DocumentModel
    registry (1, 1) macd.model.ComponentRegistry
end
registry = macd.model.ComponentRegistry.createDefault();
root = fileparts(fileparts(mfilename("fullpath")));
document = macd.source.AppSourceParser.parseText(string(fileread(fullfile(root, "fixtures", "SmallPreviewFixtureApp.m"))), registry);
end

function verifyBindings(testCase, document, registry)
% verifyBindings Check public source, values and occurrence ownership against a fresh independent load.
arguments (Input)
    testCase (1, 1) matlab.unittest.TestCase
    document (1, 1) macd.model.DocumentModel
    registry (1, 1) macd.model.ComponentRegistry
end
reference = macd.source.AppSourceParser.parseText(document.CurrentText, registry);
actual = document.sourceAnalysis().Statements; expected = reference.sourceAnalysis().Statements;
testCase.assertNumElements(actual, numel(expected));
for index = 1:numel(actual)
    testCase.verifyEqual(actual(index).Text, expected(index).Text);
    testCase.verifyEqual(actual(index).Span, expected(index).Span);
    testCase.verifyEqual(actual(index).CodeOffsets, expected(index).CodeOffsets);
end
for owner = document.Components
    other = reference.getComponentByName(owner.Name); testCase.assertNotEmpty(other);
    testCase.verifyEqual(owner.SourceSpans, other.SourceSpans);
    testCase.assertNumElements(owner.Settings, numel(other.Settings));
    for index = 1:numel(owner.Settings)
        for field = ["Path", "LiteralValue", "ValueKind", "SourceExpression", "SourceSpan", ...
                "ValueSpan", "NameSpan", "PairSpan", "ScopeSpan", "Sequence", "OwnerMethod", "IsCertain"]
            testCase.verifyEqual(owner.Settings(index).(field), other.Settings(index).(field), owner.Name + "." + field);
        end
    end
    a = document.getEffectivePropertyStates(registry, owner.Id);
    b = reference.getEffectivePropertyStates(registry, other.Id);
    testCase.assertNumElements(a, numel(b));
    for index = 1:numel(a)
        for field = ["IsKnown", "IsEditable", "EffectiveValue", "ExplicitKind", "SourceExpression"]
            testCase.verifyEqual(a(index).Resolution.(field), b(index).Resolution.(field), owner.Name + "." + a(index).Definition.Path);
        end
    end
end
document.validatePropertyCommit(registry);
testCase.verifyFalse(macd.validation.ModelValidator.hasErrors(document.Diagnostics));
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
