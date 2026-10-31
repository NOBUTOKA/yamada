classdef SourcePatchBatchTest < matlab.unittest.TestCase
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
