classdef (TestTags = {'fast', 'parser', 'model', 'generation', 'lifecycle'}) PropertySaveCheckpointTest < matlab.unittest.TestCase
    % PropertySaveCheckpointTest Verify saved positions without rebasing Undo intentions.
    %   Owned source fixtures cover constructor settings, repeated assignments,
    %   exact output bytes, class renaming, structural edits, and stale save plans.

    methods (Test)
        function savedPositionsAndHistoriesAreIndependent(testCase)
            % savedPositionsAndHistoriesAreIndependent Capture every occurrence and update only the final bound value.
            for creation = ["app.Control = uidropdown(app.Left, Items=[""A"" ""B""], Value='A');", ...
                    "app.Control = uidropdown(app.Left, 'Items', [""A"" ""B""], 'Value', 'A');"]
                [document, registry, control] = testCase.fixture([creation, "app.Control.Value = 'A';"]);
                baseline = document.OriginalText;
                document.setProperty(control.Id, "Value", 'B', registry);
                original = control.settingSnapshot();
                history = document.HistoryIndex;
                checkpoint = testCase.save(document, registry);
                testCase.verifyEqual(document.OriginalText, baseline);
                testCase.verifyEqual(control.settingSnapshot(), original);
                testCase.verifyEqual(document.HistoryIndex, history);
                testCase.verifyNotEqual(checkpoint.SourceSnapshotId, document.Metadata.SourceSnapshotId);
                record = checkpoint.Snapshot.Records(string({checkpoint.Snapshot.Records.Name}) == "Control");
                settings = record.Settings(string({record.Settings.Path}) == "Value");
                testCase.verifyEqual([settings.Value], 'AB');
                locations = [settings.Location];
                testCase.verifyEqual(string({locations.Method}), ["nameValue" "assignment"]);
                span = settings(end).Location.ValueSpan;
                testCase.verifyEqual(extractBetween(checkpoint.SourceText, span.StartOffset, span.EndOffset), "'B'");
                independent = checkpoint.Snapshot.materialize();
                independent(string({independent.Name}) == "Control").setProperty("Value", 'A');
                testCase.verifyEqual(control.getProperty("Value").LiteralValue, 'B');
                testCase.verifyEqual(checkpoint.Snapshot.Records(string({checkpoint.Snapshot.Records.Name}) == "Control").Settings, record.Settings);
            end
        end

        function repeatedSaveAndReopenRetainNewSettings(testCase)
            % repeatedSaveAndReopenRetainNewSettings Track inserted pairs and edit them after a fresh parse.
            [document, registry, control] = testCase.fixture("app.Control = uidropdown(app.Left, Items=[""A"" ""B""]); ");
            document.setProperty(control.Id, "Value", 'B', registry);
            first = testCase.save(document, registry);
            testCase.verifySubstring(first.SourceText, "Value='B'");
            document.setProperty(control.Id, "Tooltip", "日本語の長い説明", registry);
            second = testCase.save(document, registry);
            testCase.verifyNotEqual(first.SourceSnapshotId, second.SourceSnapshotId);
            testCase.verifySubstring(second.SourceText, "日本語の長い説明");
            reopened = yamada.source.AppSourceParser.parseText(second.SourceText, registry);
            other = reopened.getComponentByName("Control");
            reopened.setProperty(other.Id, "Value", 'A', registry);
            third = testCase.save(reopened, registry);
            testCase.verifySubstring(third.SourceText, "Value='A'");
            testCase.verifySubstring(third.SourceText, "日本語の長い説明");
            testCase.verifyNumElements(other.getSettings("Value"), 1);
        end

        function undoRedoCrossesMultipleSavesWithoutChangingSourceOwnership(testCase)
            % undoRedoCrossesMultipleSavesWithoutChangingSourceOwnership Keep original setting IDs and saved checkpoint values.
            [document, registry, control] = testCase.fixture([ ...
                "app.Control = uidropdown(app.Left, Items=[""A"" ""B""], Value='A');", ...
                "app.Control.Value = 'B';"]);
            original = document.OriginalText;
            settingIds = string({control.Settings.Id});
            document.setProperty(control.Id, "Value", 'A', registry);
            first = testCase.save(document, registry);
            document.setProperty(control.Id, "Tooltip", "Saved later", registry);
            second = testCase.save(document, registry);
            document.undo();
            testCase.verifyTrue(document.IsDirty);
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), first.SourceText);
            document.undo();
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), original);
            document.redo();
            document.redo();
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), second.SourceText);
            testCase.verifyTrue(document.IsDirty);
            testCase.verifyEqual(document.SavedSource.SourceText, second.SourceText);
            testCase.verifyEqual(string({control.Settings(ismember(string({control.Settings.Id}), settingIds)).Id}), settingIds);
            testCase.verifyEqual(document.OriginalText, original);
            testCase.save(document, registry);
            testCase.verifyFalse(document.IsDirty);
        end

        function exactSavedBytesOwnNormalizedUnicodePositions(testCase)
            % exactSavedBytesOwnNormalizedUnicodePositions Match saved offsets after mixed line endings and Save As renaming.
            [document, registry, control] = testCase.fixture("app.Control = uidropdown(app.Left, Items=[""A"" ""B""]); ");
            mixed = replace(document.OriginalText, "app.Left =", newline + "app.Left =");
            document = yamada.source.AppSourceParser.parseText(mixed, registry);
            document.LineEnding = "LF";
            control = document.getComponentByName(control.Name);
            document.setProperty(control.Id, "Tooltip", "保存値 日本語", registry);
            source = yamada.source.RoundTripGenerator(registry).generate(document);
            source = yamada.source.AppClassIdentityRewriter.rewrite(source, "RenamedSavedApp");
            path = string(tempname) + ".m";
            cleanup = onCleanup(@() delete(path));
            checkpoint = yamada.model.SavedSourceCheckpoint(document, source, path, registry);
            yamada.source.SourceWriter.write(path, checkpoint.SourceText, document.LineEnding);
            document.confirmSavedSource(checkpoint, registry);
            bytes = yamada.ui.DocumentLifecycleService().readSourceBytes(path);
            testCase.verifyFalse(numel(bytes) >= 3 && isequal(bytes(1:3), uint8([239 187 191])));
            testCase.verifyEqual(string(native2unicode(bytes, 'UTF-8')), checkpoint.SourceText);
            testCase.verifyFalse(contains(checkpoint.SourceText, sprintf('\r')));
            testCase.verifyEqual(document.ClassName, "RenamedSavedApp");
            record = checkpoint.Snapshot.Records(string({checkpoint.Snapshot.Records.Name}) == "Control");
            settings = record.Settings(string({record.Settings.Path}) == "Tooltip");
            span = settings.Location.ValueSpan;
            testCase.verifyEqual(extractBetween(checkpoint.SourceText, span.StartOffset, span.EndOffset), ...
                yamada.source.LiteralEncoder.encode("保存値 日本語"));
            document.setProperty(control.Id, "Value", 'B', registry);
            next = testCase.save(document, registry);
            testCase.verifySubstring(next.SourceText, "classdef RenamedSavedApp");
            testCase.verifySubstring(next.SourceText, "保存値 日本語");
        end

        function saveAsRebasesUndoAndRedoWithoutAnExtraEdit(testCase)
            % saveAsRebasesUndoAndRedoWithoutAnExtraEdit Keep the saved class identity through both history branches.
            [document, registry, control] = testCase.fixture("app.Control = uidropdown(app.Left, Items=[""A"" ""B""], Value='A');");
            document.setProperty(control.Id, "Tooltip", "Long changed length", registry);
            document.setProperty(control.Id, "Value", 'B', registry);
            document.undo();
            source = yamada.source.AppClassIdentityRewriter.rewrite(document.CurrentText, "RenamedHistoryApp");
            checkpoint = yamada.model.SavedSourceCheckpoint(document, source, "RenamedHistoryApp.m", registry);
            document.confirmSavedSource(checkpoint, registry);
            testCase.verifyEqual(document.HistoryIndex, 1);
            document.undo();
            testCase.verifySubstring(document.CurrentText, "classdef RenamedHistoryApp");
            testCase.verifyEmpty(control.getProperty("Tooltip"));
            document.redo();
            document.redo();
            testCase.verifySubstring(document.CurrentText, "classdef RenamedHistoryApp");
            testCase.verifyEqual(control.getProperty("Value").LiteralValue, 'B');
            testCase.verifyEqual(control.getProperty("Tooltip").LiteralValue, "Long changed length");
        end

        function saveAsKeepsSeparatedPatchesAcrossUnrelatedSettings(testCase)
            % saveAsKeepsSeparatedPatchesAcrossUnrelatedSettings Rebase insertion and replacement without consuming another component's ranges.
            [document, registry, control] = testCase.fixture([ ...
                "app.Control = uidropdown(app.Left, Items=[""A"" ""B""]);", ...
                "app.Left.Title = 'Independent';", "app.Control.Value = 'A';"]);
            changes = [yamada.model.PropertyTransaction.singleChange("Tooltip", "Long changed hint"), ...
                yamada.model.PropertyTransaction.singleChange("Value", 'B')];
            document.setPropertyBatch(control.Id, changes, registry);
            source = yamada.source.AppClassIdentityRewriter.rewrite(document.CurrentText, "RenamedSeparatedApp");
            checkpoint = yamada.model.SavedSourceCheckpoint(document, source, "RenamedSeparatedApp.m", registry);
            document.confirmSavedSource(checkpoint, registry);
            document.undo();
            testCase.verifyEmpty(control.getProperty("Tooltip"));
            testCase.verifyEqual(control.getProperty("Value").LiteralValue, 'A');
            testCase.verifyEqual(document.getComponentByName("Left").getProperty("Title").LiteralValue, 'Independent');
            document.redo();
            testCase.verifyEqual(document.CurrentText, source);
            testCase.verifyEqual(control.getProperty("Value").LiteralValue, 'B');
        end

        function changedKnownStateAndStalePlansAreRejected(testCase)
            % changedKnownStateAndStalePlansAreRejected Preserve metadata and history when a save plan no longer represents the model.
            [document, registry, control] = testCase.fixture("app.Control = uidropdown(app.Left, Items=[""A"" ""B""], Value='A');");
            checkpoint = testCase.save(document, registry);
            source = replace(checkpoint.SourceText, "Value='A'", "Value='B'");
            testCase.verifyError(@() yamada.model.SavedSourceCheckpoint(document, source, "Other.m", registry), ...
                "yamada:SavedSourceCheckpoint:StateMismatch");
            document.setProperty(control.Id, "Value", 'B', registry);
            testCase.verifyError(@() document.confirmSavedSource(checkpoint, registry), ...
                "yamada:SavedSourceCheckpoint:StaleCheckpoint");
            testCase.verifyTrue(document.IsDirty);
            testCase.verifyEqual(document.SavedSource.SourceText, checkpoint.SourceText);
            testCase.verifyEqual(document.HistoryIndex, 1);
        end

        function sameHistoryIndexDoesNotHideChangedIntentions(testCase)
            % sameHistoryIndexDoesNotHideChangedIntentions Validate regenerated intentions rather than trusting the history counter alone.
            [document, registry, control] = testCase.fixture("app.Control = uidropdown(app.Left, Items=[""A"" ""B""], Value='A');");
            checkpoint = testCase.save(document, registry);
            control.getProperty("Value").setLiteral('B');
            testCase.verifyEqual(document.HistoryIndex, checkpoint.HistoryIndex);
            testCase.verifyError(@() checkpoint.assertCurrent(document, registry), ...
                "yamada:SavedSourceCheckpoint:StaleCheckpoint");
            testCase.verifyEqual(document.SavedSource.SourceText, checkpoint.SourceText);
        end

        function subtreeOperationsRemainUndoableAcrossSavedPositions(testCase)
            % subtreeOperationsRemainUndoableAcrossSavedPositions Preserve move, copy, and deletion intentions through successive saves.
            [document, registry, control, target] = testCase.fixture([ ...
                "app.Control = uidropdown(app.Left, Items=[""A"" ""B""], Value='A');", "app.Control.Value = 'B';"]);
            original = document.OriginalText;
            document.reparentSubtree(control.Id, target.Id, registry, [], [], [10 20 100 22]);
            moved = testCase.save(document, registry);
            copy = document.pasteSubtree(document.copySubtree(control.Id, registry), ...
                document.getComponentByName("Left").Id, registry);
            pasted = testCase.save(document, registry);
            document.removeSubtree(control.Id, registry);
            deleted = testCase.save(document, registry);
            testCase.verifyFalse(any(string({deleted.Snapshot.Records.Name}) == control.Name));
            testCase.verifyTrue(any(string({deleted.Snapshot.Records.Name}) == copy.Name));
            document.undo();
            testCase.verifyEqual(yamada.source.SourceWriter.normalize( ...
                yamada.source.RoundTripGenerator(registry).generate(document), document.LineEnding), pasted.SourceText);
            document.undo();
            testCase.verifyEqual(yamada.source.SourceWriter.normalize( ...
                yamada.source.RoundTripGenerator(registry).generate(document), document.LineEnding), moved.SourceText);
            document.undo();
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), original);
            document.redo();
            document.redo();
            document.redo();
            testCase.verifyEqual(yamada.source.SourceWriter.normalize( ...
                yamada.source.RoundTripGenerator(registry).generate(document), document.LineEnding), deleted.SourceText);
            testCase.verifyEqual(document.SavedSource.SourceText, deleted.SourceText);
        end

        function implicitEffectsAndAutomaticUnknownsSurviveSave(testCase)
            % implicitEffectsAndAutomaticUnknownsSurviveSave Compare effective state while retaining explicit inputs and unknown computed arrays.
            [document, registry, control] = testCase.fixture([ ...
                "app.Control = uislider(app.Left);", "app.Control.Value = 20;", ...
                "app.Control.Limits = [50 100];", "app.Control.MajorTicks = [50 75 100];", ...
                "app.Control.MajorTicksMode = 'auto';"], "matlab.ui.control.Slider");
            checkpoint = testCase.save(document, registry);
            testCase.verifyEqual(control.getProperty("Value").LiteralValue, 20);
            saved = yamada.source.AppSourceParser.parseText(checkpoint.SourceText, registry);
            other = saved.getComponentByName("Control");
            states = saved.getEffectivePropertyStates(registry, other.Id);
            value = states(arrayfun(@(state) state.Definition.Path == "Value", states)).Resolution;
            ticks = states(arrayfun(@(state) state.Definition.Path == "MajorTicks", states)).Resolution;
            testCase.verifyTrue(value.IsKnown);
            testCase.verifyEqual(value.EffectiveValue, 50);
            testCase.verifyFalse(ticks.IsKnown);
            testCase.verifyEqual(ticks.ReasonCode, "automatic");
            testCase.verifyEqual(other.getProperty("Value").LiteralValue, 20);
            testCase.verifyEqual(other.getProperty("MajorTicks").LiteralValue, [50 75 100]);
            testCase.verifyEqual(other.getProperty("MajorTicksMode").LiteralValue, 'auto');
        end

        function opaqueHistoryIsPreservedWithoutExecutingIt(testCase)
            % opaqueHistoryIsPreservedWithoutExecutingIt Keep earlier expressions while checking the known final value.
            [document, registry, control] = testCase.fixture([ ...
                "app.Control = uidropdown(app.Left, Items=[""A"" ""B""], Value=""A"" + """");", ...
                "app.Control.Value = 'A';"]);
            document.setProperty(control.Id, "Value", 'B', registry);
            checkpoint = testCase.save(document, registry);
            testCase.verifySubstring(checkpoint.SourceText, """A"" + """"");
            record = checkpoint.Snapshot.Records(string({checkpoint.Snapshot.Records.Name}) == "Control");
            settings = record.Settings(string({record.Settings.Path}) == "Value");
            testCase.verifyNumElements(settings, 2);
            testCase.verifyEqual(settings(1).Location.SourceExpression, """A"" + """"");
            testCase.verifyEqual(settings(2).Value, 'B');
        end
    end

    methods (Static, Access = private)
        function checkpoint = save(document, registry)
            % save Confirm owned generated text without performing filesystem I/O.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                registry (1, 1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                checkpoint (1, 1) yamada.model.SavedSourceCheckpoint
            end
            source = yamada.source.RoundTripGenerator(registry).generate(document);
            source = yamada.source.AppClassIdentityRewriter.rewrite(source, document.ClassName);
            checkpoint = yamada.model.SavedSourceCheckpoint(document, source, document.ClassName + ".m", registry);
            document.confirmSavedSource(checkpoint, registry);
        end

        function [document, registry, control, target] = fixture(body, declaredType)
            % fixture Build owned source with mixed property settings and a separate destination.
            arguments (Input)
                body (1, :) string
                declaredType (1, 1) string = "matlab.ui.control.DropDown"
            end
            arguments (Output)
                document (1, 1) yamada.model.DocumentModel
                registry (1, 1) yamada.model.ComponentRegistry
                control (1, 1) yamada.model.ComponentRecord
                target (1, 1) yamada.model.ComponentRecord
            end
            registry = yamada.model.ComponentRegistry.createDefault();
            source = strjoin(["classdef SavedSettingApp < handle", "properties", ...
                "UIFigure matlab.ui.Figure", "Left matlab.ui.container.Panel", "Right matlab.ui.container.Panel", ...
                "Control " + declaredType, "end", "methods", ...
                "function app = SavedSettingApp", "createComponents(app);", "end", ...
                "function createComponents(app)", "app.UIFigure = uifigure(Visible='off');", ...
                "app.Left = uipanel(app.UIFigure);", body, ...
                "app.Right = uipanel(app.UIFigure);", "end", "end", "end"], sprintf('\r\n'));
            document = yamada.source.AppSourceParser.parseText(source, registry);
            control = document.getComponentByName("Control");
            target = document.getComponentByName("Right");
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
