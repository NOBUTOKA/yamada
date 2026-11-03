classdef (TestTags = {'fast', 'model', 'parser', 'generation'}) ValidationPublicationTest < matlab.unittest.TestCase
    % ValidationPublicationTest Preserve current semantic values and live identities across source publication and history.
    %   Independent parsing checks observable values and diagnostic locations;
    %   no parser, cache or validation-call strategy is prescribed by these tests.
    methods (Test)
        function structuralAndCallbackEditsRetainIndependentBindings(testCase)
            % structuralAndCallbackEditsRetainIndependentBindings Follow each source transition with a distinct ordinary setting edit.
            registry = macd.model.ComponentRegistry.createDefault();
            for operation = ["insert", "rename", "callback-add", "callback-delete", "grid", "reparent", "delete", "paste", "position"]
                document = fixture(registry); label = document.getComponentByName("TopLeftLabel");
                grid = document.getComponentByName("CenterGrid"); child = document.getComponentByName("CenterLabel");
                button = document.getComponentByName("BottomRightButton");
                switch operation
                    case "insert", document.insertComponent(registry, "uilabel", document.RootComponentId);
                    case "rename", document.renameComponent(label.Id, "RenamedLabel", registry);
                    case "callback-add", document.applyCallbackAction(button.Id, "ButtonPushedFcn", "Add", registry);
                    case "callback-delete"
                        document.applyCallbackAction(button.Id, "ButtonPushedFcn", "Add", registry);
                        document.applyCallbackAction(button.Id, "ButtonPushedFcn", "Delete", registry);
                    case "grid"
                        document.applyGridLayoutEdit(grid.Id, [struct("ComponentId", grid.Id, "Path", "RowHeight", "Value", {{20,30}}), ...
                            struct("ComponentId", child.Id, "Path", "Layout.Row", "Value", 2)], registry);
                    case "reparent"
                        panel = document.getComponentByName("CenterPanel");
                        document.reparentSubtree(label.Id, panel.Id, registry, [10 205 110 22], [], [5 5 110 22]);
                    case "delete", document.removeSubtree(child.Id, registry);
                    case "paste", document.pasteSubtree(document.copySubtree(label.Id, registry), document.RootComponentId, registry);
                    case "position", document.setProperty(label.Id, "Position", [11 202 120 23], registry);
                end
                verifyStateBindings(testCase, document, registry);
                document.setProperty(button.Id, "Tooltip", "A different setting after " + operation, registry);
                document.validatePropertyCommit(registry);
                verifyStateBindings(testCase, document, registry);
            end
        end

        function literalAndGridHistoryRetainCurrentSemanticStates(testCase)
            % literalAndGridHistoryRetainCurrentSemanticStates Keep implicit placement and source identities through both history directions.
            registry = macd.model.ComponentRegistry.createDefault();
            for operation = ["existing", "new", "position", "grid"]
                document = fixture(registry); label = document.getComponentByName("TopLeftLabel");
                before = document.CurrentText;
                switch operation
                    case "existing", document.setProperty(label.Id, "Text", "Longer text", registry);
                    case "new", document.setProperty(label.Id, "Tooltip", "New setting", registry);
                    case "position", document.setProperty(label.Id, "Position", [12 200 111 24], registry);
                    case "grid"
                        grid = document.getComponentByName("CenterGrid"); child = document.getComponentByName("CenterLabel");
                        document.applyGridLayoutEdit(grid.Id, [struct("ComponentId", grid.Id, "Path", "RowHeight", "Value", {{25,35}}), ...
                            struct("ComponentId", child.Id, "Path", "Layout.Row", "Value", 2)], registry);
                end
                document.validatePropertyCommit(registry); after = document.CurrentText;
                document.undo(); testCase.verifyEqual(document.CurrentText, before); verifyStateBindings(testCase, document, registry);
                document.redo(); testCase.verifyEqual(document.CurrentText, after); verifyStateBindings(testCase, document, registry);
                button = document.getComponentByName("BottomRightButton");
                document.setProperty(button.Id, "Tooltip", "Another property after history", registry); document.validatePropertyCommit(registry);
                verifyStateBindings(testCase, document, registry);
            end
        end

        function saveAndSaveAsDoNotChangeLiveValueOwnership(testCase)
            % saveAndSaveAsDoNotChangeLiveValueOwnership Keep independently saved output and later edits bound to current records.
            registry = macd.model.ComponentRegistry.createDefault();
            for rename = [false true]
                document = fixture(registry); added = document.insertComponent(registry, "uilabel", document.RootComponentId);
                document.setProperty(added.Id, "Text", "Added value before saving", registry); document.validatePropertyCommit(registry);
                source = document.CurrentText; className = document.ClassName;
                if rename, className = "LongerPublicationFixture"; source = macd.source.AppClassIdentityRewriter.rewrite(source, className); end
                checkpoint = macd.model.SavedSourceCheckpoint(document, source, fullfile(tempdir, className + ".m"), registry);
                document.confirmSavedSource(checkpoint, registry); verifyStateBindings(testCase, document, registry);
                document.setProperty(added.Id, "Tooltip", "New value after saving", registry); document.validatePropertyCommit(registry);
                verifyStateBindings(testCase, document, registry);
                testCase.verifyEqual(checkpoint.SourceText, macd.source.SourceWriter.normalize(source, document.LineEnding));
            end
        end

        function changedCatalogAndLiveInputsCannotReuseStaleValues(testCase)
            % changedCatalogAndLiveInputsCannotReuseStaleValues Keep independently parsed semantics after external low-level or catalog changes.
            registry = macd.model.ComponentRegistry.createDefault(); document = fixture(registry);
            label = document.getComponentByName("TopLeftLabel");
            document.setProperty(label.Id, "Text", "First replacement", registry); document.validatePropertyCommit(registry);
            registry.register(registry.get("uilabel"));
            document.undo(); document.validatePropertyCommit(registry); verifyStateBindings(testCase, document, registry);
            document.redo(); document.validatePropertyCommit(registry); verifyStateBindings(testCase, document, registry);
            label.getProperty("Text").setSourceExpression("userOwnedValue");
            testCase.verifyError(@() document.setProperty(label.Id, "Text", "Rejected", registry), "macd:DocumentModel:ReadOnlyProperty");
            testCase.verifyEqual(label.getProperty("Text").SourceExpression, "userOwnedValue");
        end
    end
end

function document = fixture(registry)
% fixture Parse the shared small preview source without executing its callbacks.
arguments (Input)
    registry (1, 1) macd.model.ComponentRegistry
end
arguments (Output)
    document (1, 1) macd.model.DocumentModel
end
root = fileparts(fileparts(mfilename("fullpath")));
document = macd.source.AppSourceParser.parseText(string(fileread(fullfile(root, "fixtures", "SmallPreviewFixtureApp.m"))), registry);
end

function verifyStateBindings(testCase, document, registry)
% verifyStateBindings Compare current values, source ownership and effect references against a fresh independent parse.
arguments (Input)
    testCase (1, 1) matlab.unittest.TestCase
    document (1, 1) macd.model.DocumentModel
    registry (1, 1) macd.model.ComponentRegistry
end
reference = macd.source.AppSourceParser.parseText(document.CurrentText, registry);
[actualSettings, ~] = document.settingsInSourceOrder(); [expectedSettings, ~] = reference.settingsInSourceOrder();
for owner = document.Components
    other = reference.getComponentByName(owner.Name);
    actual = document.getEffectivePropertyStates(registry, owner.Id); expected = reference.getEffectivePropertyStates(registry, other.Id);
    testCase.assertEqual(numel(actual), numel(expected));
    for index = 1:numel(actual)
        a = actual(index).Resolution; b = expected(index).Resolution;
        for field = ["IsKnown", "IsEditable", "EffectiveValue", "ExplicitKind", "ExplicitValue", "RequestedValue"]
            testCase.verifyEqual(a.(field), b.(field), owner.Name + "." + a.Path + "." + field);
        end
        owned = owner.getSettings(a.Path);
        if ~isempty(owned), testCase.verifyEqual(a.LastSettingId, owned(end).Id); end
        if b.EffectSettingId ~= 0
            source = expectedSettings([expectedSettings.Id] == b.EffectSettingId);
            target = actualSettings([actualSettings.Id] == a.EffectSettingId);
            testCase.assertNumElements(target, 1); testCase.verifyEqual(target.SourceSpan, source.SourceSpan);
        elseif startsWith(b.EffectKey, "creation:")
            origin = reference.getComponent(extractAfter(b.EffectKey, "creation:")); target = document.getComponentByName(origin.Name);
            testCase.verifyEqual(a.EffectKey, "creation:" + target.Id);
        end
    end
end
ids = string({document.Components.Id});
for diagnostic = document.Diagnostics
    testCase.verifyTrue(strlength(diagnostic.ComponentId) == 0 || any(ids == diagnostic.ComponentId));
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
