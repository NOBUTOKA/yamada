classdef (TestTags = {'fast', 'model', 'generation'}) SettingIndexTest < matlab.unittest.TestCase
    % SettingIndexTest Verify canonical value ownership, maintained indexes and primary-only property history.
    methods (Test)
        function sourceViewsAreIndependentAndRemainOrdered(testCase)
            % sourceViewsAreIndependentAndRemainOrdered Keep source order distinct from component membership and caller copies.
            [document, registry] = fixture();
            [values, owners] = document.settingsInSourceOrder();
            before = values;
            testCase.verifyFalse(isa(values, "handle"));
            testCase.verifyEqual(numel(values), sum(arrayfun(@(item) numel(item.Settings), document.Components)));
            starts = arrayfun(@(item) item.SourceSpan.StartOffset, values);
            testCase.verifyGreaterThanOrEqual(diff(starts), zeros(1, numel(starts) - 1));
            for owner = document.Components
                selected = values(owners == owner.Id);
                testCase.verifyEqual(sort(string({selected.Id})), sort(string({owner.Settings.Id})));
            end
            owner = document.getComponentByName("TopLeftLabel");
            document.setProperty(owner.Id, "Text", "A longer value", registry);
            testCase.verifyEqual(values, before);
            current = owner.Settings;
            record = current(1).toStruct();
            independent = macd.model.PropertySetting(record.Path, record.Value, record.Location);
            independent = independent.withLocations(struct("SourceSpan", macd.model.SourceSpan(1, 2)));
            testCase.verifyNotEqual(owner.Settings(1).SourceSpan, independent.SourceSpan);
            verifyIndexes(testCase, document, registry);
        end

        function historyRetainsPrimaryPatchesAndOnlyNewOccurrenceIdentities(testCase)
            % historyRetainsPrimaryPatchesAndOnlyNewOccurrenceIdentities Exclude derived positions and whole setting snapshots.
            [document, registry] = fixture();
            initial = document.CurrentText;
            owner = document.getComponentByName("TopLeftLabel");
            originalIds = string({owner.Settings.Id});
            document.setProperty(owner.Id, "Text", "Longer text", registry);
            replaced = document.History{end};
            testCase.verifyEqual(replaced.Kind, "source-property");
            testCase.verifyFalse(isfield(replaced, "BeforeSettings"));
            testCase.verifyFalse(isfield(replaced, "AfterSettings"));
            testCase.verifyFalse(isfield(replaced, "BeforeArguments"));
            testCase.verifyEmpty(replaced.SettingIdentities.Added);
            testCase.verifyEmpty(replaced.SettingIdentities.Removed);
            document.setProperty(owner.Id, "Tooltip", "New setting", registry);
            inserted = document.History{end};
            testCase.verifyEqual(numel(inserted.SettingIdentities.Added), 1);
            testCase.verifyFalse(any(isfield(inserted.SettingIdentities.Added, ...
                ["SourceSpan", "ValueSpan", "ScopeSpan", "Sequence", "Location", "Value"])));
            saved = document.CurrentText;
            ids = string({owner.Settings.Id});
            document.undo(); document.undo();
            testCase.verifyEqual(document.CurrentText, initial);
            testCase.verifyEqual(string({owner.Settings.Id}), originalIds);
            verifyIndexes(testCase, document, registry);
            document.redo(); document.redo();
            testCase.verifyEqual(document.CurrentText, saved);
            testCase.verifyEqual(string({owner.Settings.Id}), ids);
            verifyIndexes(testCase, document, registry);
        end

        function distinctEditsAndHistoryMatchFullParse(testCase)
            % distinctEditsAndHistoryMatchFullParse Preserve current values and every range after different owner edits.
            [document, registry] = fixture();
            operations = {"TopLeftLabel", "Text", "Long replacement"; "CenterLabel", "Tooltip", "New tooltip"; ...
                "BottomRightButton", "FontSize", 23; "TopLeftLabel", "FontColor", [0.1 0.2 0.3]};
            for index = 1:size(operations, 1)
                owner = document.getComponentByName(operations{index, 1});
                document.setProperty(owner.Id, operations{index, 2}, operations{index, 3}, registry);
                verifyIndexes(testCase, document, registry);
            end
            for index = 1:4, document.undo(); verifyIndexes(testCase, document, registry); end
            for index = 1:4, document.redo(); verifyIndexes(testCase, document, registry); end
        end

        function constructorOrderDoesNotFollowRecycledSlotNumbers(testCase)
            % constructorOrderDoesNotFollowRecycledSlotNumbers Derive constructor ordinals from physical pair order.
            store = macd.model.SourceSettingStore();
            dummy = macd.model.PropertySetting("Text", "temporary", struct("SourceSpan", macd.model.SourceSpan(1, 9)));
            released = store.replace("removed", zeros(1, 0), dummy);
            location = struct("Method", "nameValue", "Syntax", "quotedPair", "StatementId", "factory", ...
                "SourceSpan", macd.model.SourceSpan(20, 80), "SourceSnapshotId", "epoch");
            location.Id = 1; location.ValueSpan = macd.model.SourceSpan(40, 43);
            first = macd.model.PropertySetting("Text", "first", location);
            location.Id = 3; location.ValueSpan = macd.model.SourceSpan(60, 63);
            last = macd.model.PropertySetting("Tooltip", "last", location);
            slots = store.replace("owner", zeros(1, 0), [first last]);
            store.replace("removed", released, macd.model.PropertySetting.empty);
            location.Id = 2; location.ValueSpan = macd.model.SourceSpan(50, 53);
            middle = macd.model.PropertySetting("Tag", "middle", location);
            slots = store.replace("owner", slots, [first middle last]);
            testCase.verifyEqual(slots, [store.get(slots).Id]);
            batch = macd.source.SourcePatchBatch(string(repmat('x', 1, 100)));
            execution = struct("RangeStarts", 20, "RangeEnds", 80, "Visits", 1, "Assignment", 0, "Creation", 10);
            projection = store.prepare(batch, execution, "unrelated");
            store.publish(projection);
            current = store.get(slots);
            testCase.verifyEqual([current.Sequence], [11 12 13]);
        end

        function storesReleaseRemovedSlotsWithoutSharingValues(testCase)
            % storesReleaseRemovedSlotsWithoutSharingValues Reuse storage slots without exposing deleted settings or stale order.
            store = macd.model.SourceSettingStore();
            first = macd.model.PropertySetting("Text", "first", struct("SourceSpan", macd.model.SourceSpan(10, 30)));
            second = macd.model.PropertySetting("Text", "second", struct("SourceSpan", macd.model.SourceSpan(2, 8)));
            a = store.replace("a", zeros(1, 0), first);
            b = store.replace("b", zeros(1, 0), second);
            [values, owners] = store.inSourceOrder();
            testCase.verifyEqual(owners, ["b", "a"]);
            store.replace("a", a, macd.model.PropertySetting.empty);
            c = store.replace("c", zeros(1, 0), first);
            testCase.verifyGreaterThan(c, max([a b]));
            testCase.verifyEqual(store.get(b).LiteralValue, second.LiteralValue);
            testCase.verifyEqual([values.LiteralValue], [second.LiteralValue first.LiteralValue]);
            [~, owners] = store.inSourceOrder();
            testCase.verifyEqual(owners, ["b", "c"]);
        end
    end
end

function [document, registry] = fixture()
% fixture Parse an owned handle-app input with one document-owned setting store.
arguments (Output)
    document (1, 1) macd.model.DocumentModel
    registry (1, 1) macd.model.ComponentRegistry
end
registry = macd.model.ComponentRegistry.createDefault();
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
document = macd.source.AppSourceParser.parseText(string(fileread(fullfile(root, ...
    "tests", "fixtures", "SmallPreviewFixtureApp.m"))), registry);
end

function verifyIndexes(testCase, document, registry)
% verifyIndexes Compare canonical membership, settings and source spans with independent full parsing.
arguments (Input)
    testCase (1, 1) matlab.unittest.TestCase
    document (1, 1) macd.model.DocumentModel
    registry (1, 1) macd.model.ComponentRegistry
end
[settings, owners] = document.settingsInSourceOrder();
parsed = macd.source.AppSourceParser.parseText(document.CurrentText, registry);
for owner = document.Components
    other = parsed.getComponentByName(owner.Name);
    testCase.verifyEqual(owner.SourceSpans, other.SourceSpans);
    testCase.verifyEqual(numel(owner.Settings), numel(other.Settings));
    testCase.verifyEqual(sort(string({settings(owners == owner.Id).Id})), sort(string({owner.Settings.Id})));
    for index = 1:numel(owner.Settings)
        actual = owner.Settings(index); expected = other.Settings(index);
        for field = ["Path", "LiteralValue", "ValueKind", "SourceSpan", "ValueSpan", "NameSpan", "PairSpan", "ScopeSpan", "Sequence", "IsCertain"]
            testCase.verifyEqual(actual.(field), expected.(field));
        end
    end
end
testCase.verifyEqual(document.evaluationContext(registry).inputs(), macd.model.EvaluationContext(document, registry).inputs());
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
