classdef (TestTags = {'fast', 'parser', 'model', 'generation'}) SourcePatchBatchTest < matlab.unittest.TestCase
    % SourcePatchBatchTest Verify reversible source edits and position transforms.
    %   These cases protect transaction boundaries before model integration.

    methods (Test)
        function changedLengthsAndUnicodeRoundTrip(testCase)
            % changedLengthsAndUnicodeRoundTrip Preserve Unicode and exact line endings through reversal.
            source = "app.A.Value = 9;" + string(sprintf("\r\n")) + "app.B.Text = '日本語';";
            first = strfind(source, "9");
            second = strfind(source, "'日本語'");
            edits = [change(first, first, "1000"), change(second, second + 4, "'Long text'")];
            batch = macd.source.SourcePatchBatch(source, edits);
            testCase.verifySubstring(batch.AfterText, "app.A.Value = 1000;");
            testCase.verifySubstring(batch.AfterText, "app.B.Text = 'Long text';");
            testCase.verifyEqual(batch.inverse().AfterText, source);
            testCase.verifyEqual(batch.apply(source), batch.AfterText);
        end

        function insertionsAndAdjacentDeletionsReverseExactly(testCase)
            % insertionsAndAdjacentDeletionsReverseExactly Retain order at shared inverse boundaries.
            batch = macd.source.SourcePatchBatch("AB", [change(2, 1, "one"), change(2, 1, "two")]);
            testCase.verifyEqual(batch.AfterText, "AonetwoB");
            testCase.verifyEqual(batch.inverse().AfterText, "AB");
            batch = macd.source.SourcePatchBatch("abcdef", [change(1, 2, ""), change(3, 4, "")]);
            testCase.verifyEqual(batch.AfterText, "ef");
            testCase.verifyEqual(batch.inverse().AfterText, "abcdef");
        end

        function staleAndOverlappingBatchesAreRejected(testCase)
            % staleAndOverlappingBatchesAreRejected Refuse outdated fragments and noncanonical ranges.
            edit = change(2, 3, "X");
            edit.ExpectedText = "wrong";
            testCase.verifyError(@() macd.source.SourcePatchBatch("abcdef", edit), "macd:SourcePatchBatch:StaleEdit");
            testCase.verifyError(@() macd.source.SourcePatchBatch("abcdef", ...
                [change(2, 4, "X"), change(4, 5, "Y")]), "macd:SourcePatchBatch:OverlappingEdits");
            batch = macd.source.SourcePatchBatch("abc", change(2, 2, "long"));
            testCase.verifyError(@() batch.apply("axc"), "macd:SourcePatchBatch:StaleSource");
        end

        function rangesAndInsertionAffinityStayConsistent(testCase)
            % rangesAndInsertionAffinityStayConsistent Expand owners without absorbing neighboring statements.
            batch = macd.source.SourcePatchBatch("0123456789", change(4, 5, "LONGER"));
            [span, valid] = batch.mapSpan(macd.model.SourceSpan(2, 9));
            testCase.verifyTrue(valid);
            testCase.verifyEqual([span.StartOffset span.EndOffset], [2 13]);
            [span, valid] = batch.mapSpan(macd.model.SourceSpan(7, 10));
            testCase.verifyTrue(valid);
            testCase.verifyEqual([span.StartOffset span.EndOffset], [11 14]);
            batch = macd.source.SourcePatchBatch("abcdef", change(4, 3, "NEW"));
            [span, valid] = batch.mapSpan(macd.model.SourceSpan(1, 3));
            testCase.verifyTrue(valid);
            testCase.verifyEqual([span.StartOffset span.EndOffset], [1 3]);
            [span, valid] = batch.mapSpan(macd.model.SourceSpan(4, 6));
            testCase.verifyTrue(valid);
            testCase.verifyEqual([span.StartOffset span.EndOffset], [7 9]);
            testCase.verifyEqual(batch.mapBoundary(3, "left"), 3);
            testCase.verifyEqual(batch.mapBoundary(3, "right"), 6);
        end

        function translatedStatementsMatchAnIndependentScan(testCase)
            % translatedStatementsMatchAnIndependentScan Keep code-unit projections correct across earlier length changes.
            source = "app.A.Value = 9;" + string(sprintf("\r\n")) + ...
                "app.B.Text = ['a' ..." + string(sprintf("\r\n")) + " 'b'];";
            statements = macd.source.MatlabLexicalScanner.splitStatements(source);
            offset = strfind(source, "9");
            batch = macd.source.SourcePatchBatch(source, change(offset, offset, "10000"));
            parsed = macd.source.MatlabLexicalScanner.splitStatements(batch.AfterText);
            before = statements(2);
            [span, valid] = batch.mapSpan(before.Span);
            testCase.verifyTrue(valid);
            after = before.withSpan(span);
            testCase.verifyEqual(after.Text, parsed(2).Text);
            testCase.verifyEqual(after.CodeOffsets, parsed(2).CodeOffsets);
            testCase.verifyEqual(before.CodeOffsets, statements(2).CodeOffsets);
        end

        function settingIdentitySurvivesLocationAndValueChanges(testCase)
            % settingIdentitySurvivesLocationAndValueChanges Separate occurrence identity from movable source ranges.
            original = macd.model.PropertySetting("Text", "Old", struct("Method", "assignment", ...
                "Syntax", "dot", "SourceSnapshotId", "epoch", "SourceSpan", macd.model.SourceSpan(10, 30), ...
                "ValueSpan", macd.model.SourceSpan(20, 24)));
            original = original.withScope("createComponents", macd.model.SourceSpan(1, 100));
            current = original.withLocations(struct("SourceSpan", macd.model.SourceSpan(15, 40), ...
                "ValueSpan", macd.model.SourceSpan(25, 34), "ScopeSpan", macd.model.SourceSpan(1, 110)));
            current = current.withLiteral("New longer value");
            testCase.verifyEqual(current.Id, original.Id);
            testCase.verifyEqual(current.StatementId, original.StatementId);
            testCase.verifyEqual(current.InitializationScopeId, original.InitializationScopeId);
            testCase.verifyEqual(original.LiteralValue, "Old");
            testCase.verifyEqual(original.ValueSpan.StartOffset, 20);
            testCase.verifyEqual(current.ValueSpan.StartOffset, 25);
            record = current.toStruct();
            restored = macd.model.PropertySetting(record.Path, record.Value, record.Location);
            testCase.verifyEqual(restored.Id, original.Id);
            testCase.verifyEqual(restored, current);
        end

        function workingStateSeparatesRevisionAndHistoryIdentity(testCase)
            % workingStateSeparatesRevisionAndHistoryIdentity Restore history without reviving old source revisions.
            original = macd.model.CurrentSourceState("app.A.Value = 9;");
            batch = macd.source.SourcePatchBatch(original.Text, change(15, 15, "1000"));
            current = original.withBatch(batch);
            testCase.verifyEqual(original.Text, "app.A.Value = 9;");
            testCase.verifyEqual(current.Revision, original.Revision + uint64(1));
            testCase.verifyNotEqual(current.StateId, original.StateId);
            restored = current.withBatch(batch.inverse(), original.StateId);
            testCase.verifyEqual(restored.Text, original.Text);
            testCase.verifyEqual(restored.StateId, original.StateId);
            testCase.verifyGreaterThan(restored.Revision, current.Revision);
            testCase.verifyTrue(restored.Analysis.matches(original.Text));
            testCase.verifyError(@() restored.assertRevision(original.Revision, original.StateId), ...
                "macd:CurrentSourceState:StaleCandidate");
            testCase.verifyError(@() current.withBatch(batch), "macd:SourcePatchBatch:StaleSource");
        end

        function liveLocationsAndBindingsKeepTheirHandles(testCase)
            % liveLocationsAndBindingsKeepTheirHandles Match an independent parser while retaining live identities.
            registry = macd.model.ComponentRegistry.createDefault();
            root = fileparts(fileparts(mfilename("fullpath")));
            source = string(fileread(fullfile(root, "fixtures", "handle", "SmallPreviewFixtureApp.m")));
            document = macd.source.AppSourceParser.parseText(source, registry);
            owner = document.getComponentByName("TopLeftLabel");
            entry = owner.getProperty("Text");
            setting = owner.getSettings("Text");
            span = entry.Metadata.ValueSpan;
            replacement = "A longer source string";
            batch = macd.source.SourcePatchBatch(source, change(span.StartOffset, span.EndOffset, ...
                macd.source.LiteralEncoder.encode(replacement)));
            updates = macd.model.SourceLocationUpdate.empty;
            for component = document.Components
                changes = struct("SettingId", {}, "Value", {});
                if component.Id == owner.Id
                    changes = struct("SettingId", setting(end).Id, "Value", replacement);
                end
                updates(end + 1) = macd.model.SourceLocationUpdate(component, batch, changes); %#ok<AGROW>
            end
            for index = 1:numel(updates), updates(index).apply(document.Components(index)); end
            expected = macd.source.AppSourceParser.parseText(batch.AfterText, registry);
            testCase.verifyEqual(owner.getProperty("Text"), entry);
            testCase.verifyEqual(entry.LiteralValue, replacement);
            testCase.verifyEqual(owner.getSettings("Text").Id, setting.Id);
            for component = document.Components
                parsed = expected.getComponentByName(component.Name);
                testCase.verifyEqual(component.SourceSpans, parsed.SourceSpans);
                for actual = component.Settings
                    candidates = parsed.getSettings(actual.Path);
                    ordinal = find(string({component.getSettings(actual.Path).Id}) == actual.Id, 1);
                    other = candidates(ordinal);
                    testCase.verifyEqual(actual.SourceSpan, other.SourceSpan);
                    testCase.verifyEqual(actual.ValueSpan, other.ValueSpan);
                end
            end
        end

        function liveValueChangesRejectPreparedLocationUpdates(testCase)
            % liveValueChangesRejectPreparedLocationUpdates Preserve edits made after source-location preparation.
            registry = macd.model.ComponentRegistry.createDefault();
            root = fileparts(fileparts(mfilename("fullpath")));
            source = string(fileread(fullfile(root, "fixtures", "handle", "SmallPreviewFixtureApp.m")));
            document = macd.source.AppSourceParser.parseText(source, registry);
            owner = document.getComponentByName("TopLeftLabel");
            span = owner.getProperty("Text").Metadata.ValueSpan;
            batch = macd.source.SourcePatchBatch(source, change(span.StartOffset, span.EndOffset, "'Changed'"));
            update = macd.model.SourceLocationUpdate(owner, batch);
            owner.setProperty("Text", "A different later value");
            testCase.verifyError(@() update.apply(owner), "macd:SourceLocationUpdate:StaleComponent");
            testCase.verifyEqual(owner.getProperty("Text").LiteralValue, "A different later value");
        end

        function componentRebindingMatchesActualInsertedOrder(testCase)
            % componentRebindingMatchesActualInsertedOrder Rebind only the owner while preserving existing setting IDs.
            registry = macd.model.ComponentRegistry.createDefault();
            root = fileparts(fileparts(mfilename("fullpath")));
            source = string(fileread(fullfile(root, "fixtures", "handle", "SmallPreviewFixtureApp.m")));
            document = macd.source.AppSourceParser.parseText(source, registry);
            owner = document.getComponentByName("TopLeftLabel");
            previous = owner.Settings;
            spans = [previous.SourceSpan];
            last = max([spans.EndOffset]);
            batch = macd.source.SourcePatchBatch(source, change(last + 1, last, ...
                string(sprintf("\r\n")) + "            app.TopLeftLabel.FontSize = 19;"));
            before = macd.model.CurrentSourceState(source, document.sourceAnalysis());
            after = before.withBatch(batch);
            [actual, ~, factoryArguments] = macd.model.SourceSettingRebinder.rebind(document, owner, after, batch, registry);
            parsed = macd.source.AppSourceParser.parseText(batch.AfterText, registry);
            expected = parsed.getComponentByName(owner.Name).Settings;
            testCase.verifyEqual(string({actual.Path}), string({expected.Path}));
            for index = 1:numel(actual)
                testCase.verifyEqual(actual(index).LiteralValue, expected(index).LiteralValue);
                testCase.verifyEqual(actual(index).ValueSpan, expected(index).ValueSpan);
                testCase.verifyEqual(actual(index).Sequence, expected(index).Sequence);
            end
            for old = previous
                testCase.verifyTrue(any(string({actual.Id}) == old.Id));
            end
            entry = owner.getProperty("Text");
            owner.synchronizeSourceSettings(actual, factoryArguments);
            testCase.verifyEqual(owner.getProperty("Text"), entry);
            testCase.verifyEqual(owner.getProperty("FontSize").LiteralValue, 19);
            testCase.verifyEqual(owner.getProperty("FontSize").Metadata.SourceSettingId, actual(end).Id);
        end

        function literalCandidatePublishesInsertedAndExistingValues(testCase)
            % literalCandidatePublishesInsertedAndExistingValues Prepare exact current syntax before changing live handles.
            registry = macd.model.ComponentRegistry.createDefault();
            root = fileparts(fileparts(mfilename("fullpath")));
            source = string(fileread(fullfile(root, "fixtures", "handle", "SmallPreviewFixtureApp.m")));
            document = macd.source.AppSourceParser.parseText(source, registry);
            owner = document.getComponentByName("TopLeftLabel");
            entry = owner.getProperty("Text");
            state = macd.model.CurrentSourceState(source, document.sourceAnalysis());
            changes = struct("Path", {"Text", "FontSize"}, "Value", {"Longer changed text", 23});
            candidate = macd.model.SourceLiteralTransaction(document, state, owner.Id, changes, registry);
            testCase.verifyNotEqual(entry.LiteralValue, "Longer changed text");
            testCase.verifyEmpty(owner.getProperty("FontSize"));
            parsed = macd.source.AppSourceParser.parseText(candidate.AfterSource.Text, registry);
            expected = parsed.getComponentByName(owner.Name);
            candidate.applyModel(document, state, registry);
            testCase.verifyEqual(owner.getProperty("Text"), entry);
            testCase.verifyEqual(entry.LiteralValue, "Longer changed text");
            testCase.verifyEqual(owner.getProperty("FontSize").LiteralValue, 23);
            testCase.verifyEqual(string({owner.Settings.Path}), string({expected.Settings.Path}));
            testCase.verifyEqual([owner.Settings.Sequence], [expected.Settings.Sequence]);
            testCase.verifyError(@() candidate.applyModel(document, state, registry), ...
                "macd:SourceLocationUpdate:StaleComponent");
        end

        function documentPublishesCurrentTextAndExactHistory(testCase)
            % documentPublishesCurrentTextAndExactHistory Exercise distinct insertions and replacements without deferred source.
            registry = macd.model.ComponentRegistry.createDefault();
            root = fileparts(fileparts(mfilename("fullpath")));
            original = string(fileread(fullfile(root, "fixtures", "handle", "SmallPreviewFixtureApp.m")));
            document = macd.source.AppSourceParser.parseText(original, registry);
            owner = document.getComponentByName("TopLeftLabel");
            entry = owner.getProperty("Text");
            document.setProperty(owner.Id, "Text", "Longer changed text", registry);
            first = document.CurrentText;
            document.setProperty(owner.Id, "FontSize", 23, registry);
            second = document.CurrentText;
            testCase.verifyNotEqual(first, second);
            testCase.verifyEqual(document.OriginalText, original);
            testCase.verifyEqual(owner.getProperty("Text"), entry);
            testCase.verifyEmpty(document.PendingEdits);
            testCase.verifyTrue(document.sourceAnalysis().matches(second));
            generated = macd.source.RoundTripGenerator(registry).generate(document);
            testCase.verifyEqual(generated, second);
            document.undo();
            testCase.verifyEqual(document.CurrentText, first);
            testCase.verifyEmpty(owner.getProperty("FontSize"));
            document.undo();
            testCase.verifyEqual(document.CurrentText, original);
            document.redo();
            document.redo();
            testCase.verifyEqual(document.CurrentText, second);
            testCase.verifyEqual(owner.getProperty("FontSize").LiteralValue, 23);
        end

        function detachedCandidatesNeverMasqueradeAsPublishedSource(testCase)
            % detachedCandidatesNeverMasqueradeAsPublishedSource Prevent zero input revisions from enabling recursive source-plan snapshots.
            registry = macd.model.ComponentRegistry.createDefault();
            root = fileparts(fileparts(mfilename("fullpath")));
            source = string(fileread(fullfile(root, "fixtures", "handle", "SmallPreviewFixtureApp.m")));
            document = macd.source.AppSourceParser.parseText(source, registry);
            testCase.verifyTrue(document.hasPublishedModel());
            candidate = document.structuralCandidate();
            testCase.verifyFalse(candidate.hasPublishedModel());
            candidate.evaluationContext(registry);
            testCase.verifyFalse(candidate.hasPublishedModel());
            owner = candidate.getComponentByName("TopLeftLabel");
            owner.setProperty("FontSize", 23);
            plan = macd.source.PropertySourcePlan.plan(candidate, owner, registry);
            testCase.verifyEqual(plan.Component.getProperty("FontSize").LiteralValue, 23);
            testCase.verifyEmpty(document.getComponentByName(owner.Name).getProperty("FontSize"));
        end

        function deletedAndInteriorRangesNeedRebinding(testCase)
            % deletedAndInteriorRangesNeedRebinding Avoid inventing source ownership inside replaced syntax.
            batch = macd.source.SourcePatchBatch("abcdef", change(2, 4, "X"));
            [span, valid] = batch.mapSpan(macd.model.SourceSpan(3, 6));
            testCase.verifyFalse(valid);
            testCase.verifyEmpty(span);
            batch = macd.source.SourcePatchBatch("abcdef", change(2, 4, ""));
            [span, valid] = batch.mapSpan(macd.model.SourceSpan(2, 4));
            testCase.verifyFalse(valid);
            testCase.verifyEmpty(span);
        end
    end
end

function edit = change(first, last, text)
% change Create one inclusive source edit, including an empty insertion range.
arguments (Input)
    first (1, 1) double
    last (1, 1) double
    text (1, 1) string
end
arguments (Output)
    edit (1, 1) struct
end
edit = struct("Start", first, "End", last, "Text", text);
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
