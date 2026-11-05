classdef (TestTags = {'fast', 'model', 'parser', 'generation'}) IndexedSettingEditTest < matlab.unittest.TestCase
    % IndexedSettingEditTest Verify numeric occurrence addresses and source-faithful indexed edits.
    %   Independent parsing checks semantic values, lexical positions and execution
    %   order without requiring any particular implementation or call count.
    methods (Test)
        function canonicalAddressesAreStableAcrossRemovalAndRestore(testCase)
            % canonicalAddressesAreStableAcrossRemovalAndRestore Reserve tombstones for the same historical occurrence.
            store = yamada.model.SourceSettingStore();
            first = yamada.model.PropertySetting("Text", "first");
            second = yamada.model.PropertySetting("Tooltip", "second");
            ids = store.replace("owner", zeros(1, 0), [first second]);
            records = store.get(ids);
            testCase.verifyEqual([records.Id], ids);
            testCase.verifyGreaterThan(ids, zeros(size(ids)));
            retained = store.replace("owner", ids, records(2));
            testCase.verifyEqual(retained, ids(2));
            testCase.verifyEqual(store.get(ids(1)).Id, 0);
            third = yamada.model.PropertySetting("FontSize", 19);
            another = store.replace("other", zeros(1, 0), third);
            testCase.verifyGreaterThan(another, max(ids));
            restored = store.replace("owner", retained, records);
            testCase.verifyEqual(restored, ids);
            testCase.verifyEqual(store.get(ids), records);
        end

        function distinctEditsAndHistoryMatchIndependentParsing(testCase)
            % distinctEditsAndHistoryMatchIndependentParsing Preserve comments, literal code and all derived positions.
            registry = yamada.model.ComponentRegistry.createDefault();
            root = fileparts(fileparts(mfilename("fullpath")));
            source = string(fileread(fullfile(root, "fixtures", "SmallPreviewFixtureApp.m")));
            document = yamada.source.AppSourceParser.parseText(source, registry);
            operations = {"TopLeftLabel", "Text", "Longer quoted ""text"" 日本語"; ...
                "CenterLabel", "Tooltip", "A new tooltip"; ...
                "BottomRightButton", "FontSize", 21; ...
                "TopLeftLabel", "FontColor", [0.1 0.2 0.3]};
            for index = 1:size(operations, 1)
                owner = document.getComponentByName(operations{index, 1});
                document.setProperty(owner.Id, operations{index, 2}, operations{index, 3}, registry);
                verifyIndependent(testCase, document, registry);
            end
            for index = 1:size(operations, 1), document.undo(); verifyIndependent(testCase, document, registry); end
            testCase.verifyEqual(document.CurrentText, source);
            for index = 1:size(operations, 1), document.redo(); verifyIndependent(testCase, document, registry); end
        end

        function editsAfterStructuralChangesMatchIndependentParsing(testCase)
            % editsAfterStructuralChangesMatchIndependentParsing Preserve source indexes when new components precede distinct edits.
            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("IndexedAfterInsert", registry);
            first = document.insertComponent(registry, "uilabel", document.RootComponentId);
            second = document.insertComponent(registry, "uibutton", document.RootComponentId);
            third = document.insertComponent(registry, "uilabel", document.RootComponentId);
            operations = {first.Id, "Tooltip", "First hint"; second.Id, "FontSize", 22; third.Id, "Text", "Longer third text"};
            for index = 1:size(operations, 1)
                document.setProperty(operations{index, 1}, operations{index, 2}, operations{index, 3}, registry);
                verifyIndependent(testCase, document, registry);
            end
            document.undo(); document.redo();
            verifyIndependent(testCase, document, registry);
        end

        function multiOwnerGridEditsPreserveTextPositionsAndIdentities(testCase)
            % multiOwnerGridEditsPreserveTextPositionsAndIdentities Replay mixed constructor, assignment and new child settings atomically.
            registry = yamada.model.ComponentRegistry.createDefault();
            source = gridSource(); document = yamada.source.AppSourceParser.parseText(source, registry);
            grid = document.getComponentByName("Grid"); first = document.getComponentByName("First");
            second = document.getComponentByName("Second");
            original = [grid.Settings first.Settings second.Settings];
            changes = [struct("ComponentId", grid.Id, "Path", "RowHeight", "Value", {{55}}), ...
                struct("ComponentId", first.Id, "Path", "Layout.Row", "Value", 1), ...
                struct("ComponentId", second.Id, "Path", "Layout.Row", "Value", 1), ...
                struct("ComponentId", second.Id, "Path", "Layout.Column", "Value", 2)];
            document.applyGridLayoutEdit(grid.Id, changes, registry);
            testCase.verifyEqual(document.HistoryIndex, 1);
            testCase.verifyEqual(first.getProperty("Layout.Row").LiteralValue, 1);
            testCase.verifyEqual(second.getProperty("Layout.Column").LiteralValue, 2);
            verifyIndependent(testCase, document, registry);
            after = document.CurrentText;
            ids = [grid.Settings.Id first.Settings.Id second.Settings.Id];
            testCase.verifyTrue(all(ismember([original.Id], ids)));
            document.undo();
            testCase.verifyEqual(document.CurrentText, source);
            testCase.verifyEqual([grid.Settings.Id first.Settings.Id second.Settings.Id], [original.Id]);
            verifyIndependent(testCase, document, registry);
            document.redo();
            testCase.verifyEqual(document.CurrentText, after);
            testCase.verifyEqual([grid.Settings.Id first.Settings.Id second.Settings.Id], ids);
            verifyIndependent(testCase, document, registry);
            % Save As changes class-name lengths without introducing a history node.
            renamed = yamada.source.AppClassIdentityRewriter.rewrite(after, "LongerIndexedGridFixture");
            checkpoint = yamada.model.SavedSourceCheckpoint(document, renamed, fullfile(tempdir, "LongerIndexedGridFixture.m"), registry);
            document.confirmSavedSource(checkpoint, registry);
            document.undo();
            testCase.verifyEqual(document.CurrentText, yamada.source.AppClassIdentityRewriter.rewrite(source, "LongerIndexedGridFixture"));
            verifyIndependent(testCase, document, registry);
            document.redo();
            testCase.verifyEqual(document.CurrentText, renamed);
            testCase.verifyEqual([grid.Settings.Id first.Settings.Id second.Settings.Id], ids);
            verifyIndependent(testCase, document, registry);
        end

        function rejectedMultiOwnerGridEditRetainsEveryOwner(testCase)
            % rejectedMultiOwnerGridEditRetainsEveryOwner Keep source, settings and history unchanged when any requested value cannot survive.
            registry = yamada.model.ComponentRegistry.createDefault();
            source = gridSource(); document = yamada.source.AppSourceParser.parseText(source, registry);
            grid = document.getComponentByName("Grid"); second = document.getComponentByName("Second");
            original = [grid.Settings second.Settings];
            changes = [struct("ComponentId", grid.Id, "Path", "RowHeight", "Value", {{55}}), ...
                struct("ComponentId", second.Id, "Path", "Layout.Column", "Value", 2)];
            testCase.verifyError(@() document.applyGridLayoutEdit(grid.Id, changes, registry), ...
                "yamada:DocumentModel:UnsafePropertyEdit");
            testCase.verifyEqual(document.CurrentText, source);
            testCase.verifyEqual(document.HistoryIndex, 0);
            testCase.verifyEqual([grid.Settings second.Settings], original);
            verifyIndependent(testCase, document, registry);
        end

        function historyBranchNeverReusesAnIssuedOccurrence(testCase)
            % historyBranchNeverReusesAnIssuedOccurrence Keep old identities distinct after an insertion is undone.
            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("IntegerBranch", registry);
            label = document.insertComponent(registry, "uilabel", document.RootComponentId);
            document.setProperty(label.Id, "Tooltip", "First branch", registry);
            first = label.getSettings("Tooltip");
            document.undo();
            document.setProperty(label.Id, "FontSize", 19, registry);
            second = label.getSettings("FontSize");
            testCase.verifyGreaterThan(second.Id, first.Id);
            testCase.verifyEmpty(label.getSettings("Tooltip"));
            verifyIndependent(testCase, document, registry);
        end
    end
end

function source = gridSource()
% gridSource Provide mixed inline, constructor and assignment source with untouched comments.
arguments (Output)
    source (1, 1) string
end
source = strjoin(["classdef IndexedGridFixture < handle", "properties", ...
    "UIFigure matlab.ui.Figure", "Grid matlab.ui.container.GridLayout", ...
    "First matlab.ui.control.Button", "Second matlab.ui.control.Button", "end", ...
    "methods", "function app = IndexedGridFixture", "createComponents(app);", "end", ...
    "function createComponents(app)", "app.UIFigure = uifigure(Visible='off');", ...
    "app.Grid = uigridlayout(app.UIFigure, RowHeight={100,200}); % retained grid comment", ...
    "app.First = uibutton(app.Grid); app.First.Layout.Row = 2; % retained inline comment", ...
    "app.Second = uibutton(app.Grid, Text=""second"");", "end", "end", "end"], sprintf('\r\n'));
end

function verifyIndependent(testCase, document, registry)
% verifyIndependent Compare published text, token offsets and semantic source settings with a fresh parse.
arguments (Input)
    testCase (1, 1) matlab.unittest.TestCase
    document (1, 1) yamada.model.DocumentModel
    registry (1, 1) yamada.model.ComponentRegistry
end
reference = yamada.source.AppSourceParser.parseText(document.CurrentText, registry);
actual = document.sourceAnalysis().Statements;
expected = reference.sourceAnalysis().Statements;
testCase.assertEqual(numel(actual), numel(expected));
for index = 1:numel(actual)
    testCase.verifyEqual(actual(index).Text, expected(index).Text);
    testCase.verifyEqual(actual(index).Span, expected(index).Span);
    testCase.verifyEqual(actual(index).CodeOffsets, expected(index).CodeOffsets);
end
for owner = document.Components
    fresh = reference.getComponentByName(owner.Name);
    a = owner.settingSnapshot(); b = fresh.settingSnapshot();
    testCase.assertEqual(numel(a), numel(b));
    for index = 1:numel(a)
        testCase.verifyEqual(a(index).Path, b(index).Path);
        testCase.verifyEqual(a(index).Value, b(index).Value);
        for field = ["Sequence", "SourceSpan", "ValueSpan", "NameSpan", "PairSpan", "ScopeSpan", "Method", "Syntax", "FactoryArgumentIndex"]
            testCase.verifyEqual(a(index).Location.(field), b(index).Location.(field), owner.Name + "." + a(index).Path + "." + field);
        end
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
