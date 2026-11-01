classdef (TestTags = {'fast', 'model', 'generation'}) EditAvailabilityTest < matlab.unittest.TestCase
    % EditAvailabilityTest Verify condition-based eligibility without speculative edits.
    %   Queries must leave document and clipboard state intact, reject structural
    %   constraints, and avoid source generation even with a populated clipboard.
    methods (Test)
        function queriesDoNotGenerateOrReparseCandidateSource(testCase)
            % queriesDoNotGenerateOrReparseCandidateSource Measure the actual query call graph on opened source.
            [document, registry, left, right, leaf] = EditAvailabilityTest.fixture(true);
            clipboard = macd.model.ComponentClipboard();
            clipboard.copy(document, leaf.Id, registry);
            before = document.GeneratedText;
            history = document.HistoryIndex;
            profile clear;
            profile on;
            cleanup = onCleanup(@() profile("off"));
            copied = clipboard.availability("Copy", document, leaf.Id, registry);
            cut = clipboard.availability("Cut", document, leaf.Id, registry);
            pasted = clipboard.availability("Paste", document, right.Id, registry);
            deleted = macd.model.DocumentEditAvailability.deletion(document, leaf.Id, registry);
            states = macd.model.DocumentEditAvailability.reparenting(document, leaf.Id, registry);
            profile off;
            functions = string({profile("info").FunctionTable.FunctionName});
            forbidden = ["structuralCandidate", "copySubtree", "removeSubtree", "pasteSubtree", ...
                "reparentSubtree", "parseText", "RoundTripGenerator", "NewAppGenerator"];
            for name = forbidden
                testCase.verifyFalse(any(contains(functions, name)), name);
            end
            testCase.verifyTrue(copied.Enabled);
            testCase.verifyTrue(cut.Enabled);
            testCase.verifyTrue(pasted.Enabled);
            testCase.verifyTrue(deleted.Enabled);
            testCase.verifyTrue(states(string({states.Id}) == right.Id).Enabled);
            testCase.verifyFalse(states(string({states.Id}) == left.Id).Enabled);
            testCase.verifyEqual(document.GeneratedText, before);
            testCase.verifyEqual(document.HistoryIndex, history);
            testCase.verifyTrue(clipboard.hasContents(document));
        end

        function hierarchyChangesInvalidateConditionsImmediately(testCase)
            % hierarchyChangesInvalidateConditionsImmediately Do not retain an enabled state after direct changes.
            [document, registry, left, right, leaf] = EditAvailabilityTest.fixture(false);
            clipboard = macd.model.ComponentClipboard();
            testCase.verifyTrue(clipboard.availability("Copy", document, left.Id, registry).Enabled);
            leaf.IsEditable = false;
            testCase.verifyFalse(clipboard.availability("Copy", document, left.Id, registry).Enabled);
            testCase.verifyFalse(macd.model.DocumentEditAvailability.deletion(document, left.Id, registry).Enabled);
            states = macd.model.DocumentEditAvailability.reparenting(document, left.Id, registry);
            testCase.verifyFalse(any([states.Enabled]));
            leaf.IsEditable = true;
            states = macd.model.DocumentEditAvailability.reparenting(document, left.Id, registry);
            testCase.verifyFalse(states(string({states.Id}) == leaf.Id).Enabled);
            testCase.verifyTrue(states(string({states.Id}) == right.Id).Enabled);
        end

        function rootAndMissingTargetsHaveReasons(testCase)
            % rootAndMissingTargetsHaveReasons Disable invalid commands without throwing from query APIs.
            [document, registry] = EditAvailabilityTest.fixture(false);
            clipboard = macd.model.ComponentClipboard();
            for id = [document.RootComponentId "missing"]
                for action = ["Copy" "Cut" "Paste"]
                    state = clipboard.availability(action, document, id, registry);
                    testCase.verifyFalse(state.Enabled);
                    testCase.verifyNotEmpty(state.Reason);
                end
                state = macd.model.DocumentEditAvailability.deletion(document, id, registry);
                testCase.verifyFalse(state.Enabled);
                testCase.verifyNotEmpty(state.Reason);
            end
        end

        function placementConditionsMatchFullGridRejection(testCase)
            % placementConditionsMatchFullGridRejection Recheck occupied cells without trying a paste.
            [document, registry, ~, right, leaf] = EditAvailabilityTest.fixture(false);
            grid = document.insertComponent(registry, "uigridlayout", right.Id);
            grid.setProperty("RowHeight", {"1x"});
            grid.setProperty("ColumnWidth", {"1x"});
            clipboard = macd.model.ComponentClipboard();
            clipboard.copy(document, leaf.Id, registry);
            testCase.verifyTrue(clipboard.availability("Paste", document, grid.Id, registry).Enabled);
            inserted = clipboard.paste(document, grid.Id, registry);
            testCase.verifyFalse(clipboard.availability("Paste", document, grid.Id, registry).Enabled);
            states = macd.model.DocumentEditAvailability.reparenting(document, leaf.Id, registry);
            testCase.verifyFalse(states(string({states.Id}) == grid.Id).Enabled);
            document.removeSubtree(inserted.Id, registry);
            testCase.verifyTrue(clipboard.availability("Paste", document, grid.Id, registry).Enabled);
        end

        function generatedSelectedTabReferencesConstrainLaterEdits(testCase)
            % generatedSelectedTabReferencesConstrainLaterEdits Keep editor-generated internal links valid.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("GeneratedReferenceFixture", registry);
            right = macd.model.ComponentRecord("right", "Right", "uipanel", "matlab.ui.container.Panel", "generated");
            right.setProperty("Position", [10 10 300 200]);
            document.addComponent(right, document.RootComponentId);
            group = macd.model.ComponentRecord("group", "Group", "uitabgroup", "matlab.ui.container.TabGroup", "generated");
            group.setProperty("Position", [10 10 200 150]);
            document.addComponent(group, document.RootComponentId);
            tab = macd.model.ComponentRecord("tab", "Selected", "uitab", "matlab.ui.container.Tab", "generated");
            document.addComponent(tab, group.Id);
            entry = group.setProperty("SelectedTab", []);
            entry.setSourceExpression("app.Selected");
            entry.Metadata.SubtreeReferenceId = tab.Id;
            second = macd.model.ComponentRecord("second-group", "SecondGroup", "uitabgroup", "matlab.ui.container.TabGroup", "generated");
            second.setProperty("Position", [10 10 200 150]);
            document.addComponent(second, right.Id);
            states = macd.model.DocumentEditAvailability.reparenting(document, tab.Id, registry);
            testCase.verifyFalse(states(string({states.Id}) == second.Id).Enabled);
            testCase.verifyFalse(macd.model.DocumentEditAvailability.deletion(document, tab.Id, registry).Enabled);
            testCase.verifyTrue(macd.model.DocumentEditAvailability.deletion(document, group.Id, registry).Enabled);
            testCase.verifyError(@() document.reparentSubtree(tab.Id, second.Id, registry), "macd:DocumentModel:UnsafeSubtreeEdit");
        end

        function missingExternalReferenceDisablesStoredPaste(testCase)
            % missingExternalReferenceDisablesStoredPaste Revalidate snapshot targets after direct model changes.
            [document, registry, ~, right] = EditAvailabilityTest.fixture(false);
            definition = registry.get("uicontextmenu");
            menu = macd.model.ComponentRecord("menu", "Menu", definition.Factory, definition.DeclaredType, "generated");
            document.addComponent(menu, document.RootComponentId);
            button = document.insertComponent(registry, "uibutton", document.RootComponentId);
            entry = button.setProperty("ContextMenu", []);
            entry.setSourceExpression("app.Menu");
            entry.Metadata.SubtreeReferenceId = menu.Id;
            clipboard = macd.model.ComponentClipboard();
            clipboard.copy(document, button.Id, registry);
            testCase.verifyTrue(clipboard.availability("Paste", document, right.Id, registry).Enabled);
            document.Components(document.Components == menu) = [];
            document.getComponent(document.RootComponentId).removeChild(menu.Id);
            testCase.verifyFalse(clipboard.availability("Paste", document, right.Id, registry).Enabled);
            testCase.verifyTrue(clipboard.hasContents(document));
        end

        function measuredGeometryParticipatesInReparentConditions(testCase)
            % measuredGeometryParticipatesInReparentConditions Do not reuse a missing-geometry result for measured bounds.
            [document, registry, ~, right, leaf] = EditAvailabilityTest.fixture(false);
            grid = document.insertComponent(registry, "uigridlayout", document.RootComponentId);
            document.reparentSubtree(leaf.Id, grid.Id, registry);
            states = macd.model.DocumentEditAvailability.reparenting(document, leaf.Id, registry);
            testCase.verifyFalse(states(string({states.Id}) == right.Id).Enabled);
            states = macd.model.DocumentEditAvailability.reparenting(document, leaf.Id, registry, [10 20 90 25]);
            testCase.verifyTrue(states(string({states.Id}) == right.Id).Enabled);
            states = macd.model.DocumentEditAvailability.reparenting(document, leaf.Id, registry);
            testCase.verifyFalse(states(string({states.Id}) == right.Id).Enabled);
        end

        function constructorConditionsSurviveDiagnosticRefresh(testCase)
            % constructorConditionsSurviveDiagnosticRefresh Base eligibility on preserved tokens rather than UI warnings.
            [original, registry, ~, ~, leaf] = EditAvailabilityTest.fixture(true);
            source = replace(original.OriginalText, "app." + leaf.Name + " = uilabel(app.Panel);", ...
                "app." + leaf.Name + " = uilabel(app.Panel, 'UnknownSetting', 17);");
            document = macd.source.AppSourceParser.parseText(source, registry);
            leaf = document.getComponentByName(leaf.Name);
            before = macd.model.DocumentEditAvailability.copying(document, leaf.Id, registry);
            document.Diagnostics = macd.model.Diagnostic.empty;
            state = macd.model.DocumentEditAvailability.copying(document, leaf.Id, registry);
            testCase.verifyFalse(state.Enabled);
            testCase.verifyNotEmpty(state.Reason);
            testCase.verifyEqual(state, before);
        end

        function chosenCommandsRemainAtomicAndUndoable(testCase)
            % chosenCommandsRemainAtomicAndUndoable Execute permitted edits only after the query returns.
            [document, registry, ~, right, leaf] = EditAvailabilityTest.fixture(true);
            before = document.OriginalText;
            history = document.HistoryIndex;
            states = macd.model.DocumentEditAvailability.reparenting(document, leaf.Id, registry);
            testCase.assertTrue(states(string({states.Id}) == right.Id).Enabled);
            document.reparentSubtree(leaf.Id, right.Id, registry);
            testCase.verifyEqual(document.HistoryIndex, history + 1);
            document.undo();
            testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(document), before);
            testCase.assertTrue(macd.model.DocumentEditAvailability.deletion(document, leaf.Id, registry).Enabled);
            document.removeSubtree(leaf.Id, registry);
            testCase.verifyEmpty(document.getComponent(leaf.Id));
            document.undo();
            testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(document), before);
        end
    end

    methods (Static, Access = private)
        function [document, registry, left, right, leaf] = fixture(parsed)
            % fixture Create compatible absolute parents and an optional parsed source checkpoint.
            arguments (Input)
                parsed (1, 1) logical
            end
            arguments (Output)
                document (1, 1) macd.model.DocumentModel
                registry (1, 1) macd.model.ComponentRegistry
                left (1, 1) macd.model.ComponentRecord
                right (1, 1) macd.model.ComponentRecord
                leaf (1, 1) macd.model.ComponentRecord
            end
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("AvailabilityFixture", registry);
            left = document.insertComponent(registry, "uipanel", document.RootComponentId);
            right = document.insertComponent(registry, "uipanel", document.RootComponentId);
            leaf = document.insertComponent(registry, "uilabel", left.Id);
            if ~parsed, return, end
            source = macd.source.NewAppGenerator(registry).generate(document);
            document = macd.source.AppSourceParser.parseText(source, registry);
            left = document.getComponentByName(left.Name);
            right = document.getComponentByName(right.Name);
            leaf = document.getComponentByName(leaf.Name);
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
