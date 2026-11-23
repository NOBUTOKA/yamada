classdef (TestTags = {'fast', 'model', 'generation'}) EditAvailabilityTest < matlab.unittest.TestCase
    % EditAvailabilityTest Verify condition-based command eligibility and execution-time checks.
    %   Queries must leave document and clipboard state intact, reject structural
    %   constraints, and avoid source generation even with a populated clipboard.
    methods (Test)
        function queriesDoNotGenerateOrReparseCandidateSource(testCase)
            % queriesDoNotGenerateOrReparseCandidateSource Preserve query results, source, history, and clipboard contents.
            % Guarantee: availability queries are side-effect free and cheap.
            % Failure mode: menu refreshes generate candidate source or alter history and clipboard.
            [document, registry, left, right, leaf] = EditAvailabilityTest.fixture(true);
            clipboard = yamada.model.ComponentClipboard();
            clipboard.copy(document, leaf.Id, registry);
            before = document.GeneratedText;
            history = document.HistoryIndex;
            copied = clipboard.availability("Copy", document, leaf.Id, registry);
            cut = clipboard.availability("Cut", document, leaf.Id, registry);
            pasted = clipboard.availability("Paste", document, right.Id, registry);
            deleted = yamada.model.DocumentEditAvailability.deletion(document, leaf.Id, registry);
            testCase.verifyTrue(copied.Enabled);
            testCase.verifyTrue(cut.Enabled);
            testCase.verifyTrue(pasted.Enabled);
            testCase.verifyTrue(deleted.Enabled);
            testCase.verifyTrue(EditAvailabilityTest.movable(document, leaf.Id, right.Id, registry));
            testCase.verifyEqual(document.GeneratedText, before);
            testCase.verifyEqual(document.HistoryIndex, history);
            testCase.verifyTrue(clipboard.hasContents(document));
        end

        % Guarantee: each command is enabled exactly when its catalog and model conditions hold, with a reason otherwise.
        % Failure mode: a valid command is disabled, such as Copy for read-only or opaque components, or an invalid one is enabled and fails.
        function readOnlyStateOnlyRestrictsMoving(testCase)
            % readOnlyStateOnlyRestrictsMoving Allow copying and deletion of indexed read-only components.
            [document, registry, left, right, leaf] = EditAvailabilityTest.fixture(false);
            clipboard = yamada.model.ComponentClipboard();
            testCase.verifyTrue(clipboard.availability("Copy", document, left.Id, registry).Enabled);
            leaf.IsEditable = false;
            testCase.verifyTrue(clipboard.availability("Copy", document, left.Id, registry).Enabled);
            testCase.verifyTrue(yamada.model.DocumentEditAvailability.deletion(document, left.Id, registry).Enabled);
            testCase.verifyFalse(EditAvailabilityTest.movable(document, left.Id, right.Id, registry));
            leaf.IsEditable = true;
            testCase.verifyFalse(EditAvailabilityTest.movable(document, left.Id, leaf.Id, registry));
            testCase.verifyTrue(EditAvailabilityTest.movable(document, left.Id, right.Id, registry));
        end

        function rootAndMissingTargetsHaveReasons(testCase)
            % rootAndMissingTargetsHaveReasons Disable invalid commands without throwing from query APIs.
            [document, registry] = EditAvailabilityTest.fixture(false);
            clipboard = yamada.model.ComponentClipboard();
            for id = [document.RootComponentId "missing"]
                for action = ["Copy" "Cut" "Paste"]
                    state = clipboard.availability(action, document, id, registry);
                    testCase.verifyFalse(state.Enabled);
                    testCase.verifyNotEmpty(state.Reason);
                end
                state = yamada.model.DocumentEditAvailability.deletion(document, id, registry);
                testCase.verifyFalse(state.Enabled);
                testCase.verifyNotEmpty(state.Reason);
            end
        end

        % Guarantee: commands recheck their conditions at execution and remain atomic.
        % Failure mode: a command enabled from an earlier query runs after the model changed and breaks a reference or overfills a grid.
        function fullGridIsRejectedAtPaste(testCase)
            % fullGridIsRejectedAtPaste Keep the command available and check available cells at execution.
            [document, registry, ~, right, leaf] = EditAvailabilityTest.fixture(false);
            grid = document.insertComponent(registry, "uigridlayout", right.Id);
            grid.setProperty("RowHeight", {"1x"});
            grid.setProperty("ColumnWidth", {"1x"});
            clipboard = yamada.model.ComponentClipboard();
            clipboard.copy(document, leaf.Id, registry);
            testCase.verifyTrue(clipboard.availability("Paste", document, grid.Id, registry).Enabled);
            inserted = clipboard.paste(document, grid.Id, registry);
            testCase.verifyTrue(clipboard.availability("Paste", document, grid.Id, registry).Enabled);
            document.removeSubtree(inserted.Id, registry);
            testCase.verifyTrue(clipboard.availability("Paste", document, grid.Id, registry).Enabled);
        end

        function tabGroupsAcceptOnlyTabs(testCase)
            % tabGroupsAcceptOnlyTabs Check catalog, insertion, paste, and reparenting for tab groups.
            % Guarantee and failure mode: shared with readOnlyStateOnlyRestrictsMoving.
            [document, registry, ~, right, leaf] = EditAvailabilityTest.fixture(false);
            for id = registry.listVariantIds()
                definition = registry.getById(id);
                testCase.verifyEqual(any(definition.AllowedParentFactories == "uitabgroup"), ...
                    definition.Factory == "uitab", id);
            end

            % Reject direct placement and resolve paste through the usual ancestor fallback.
            group = document.insertComponent(registry, "uitabgroup", right.Id);
            history = document.HistoryIndex;
            testCase.verifyError(@() document.insertComponent(registry, "uilabel", group.Id), ...
                "yamada:DocumentModel:InvalidInsertionParent");
            testCase.verifyError(@() document.reparentSubtree(leaf.Id, group.Id, registry), ...
                "yamada:DocumentModel:UnsafeSubtreeEdit");
            testCase.verifyEqual(document.HistoryIndex, history);
            clipboard = yamada.model.ComponentClipboard();
            clipboard.copy(document, leaf.Id, registry);
            pasted = clipboard.paste(document, group.Id, registry);
            testCase.verifyEqual(pasted.ParentId, right.Id);

            % Allow placing tabs in a group and controls inside a tab.
            tab = document.insertComponent(registry, "uitab", group.Id);
            testCase.verifyEqual(tab.ParentId, group.Id);
            pasted = clipboard.paste(document, tab.Id, registry);
            testCase.verifyEqual(pasted.ParentId, tab.Id);
            document.reparentSubtree(leaf.Id, tab.Id, registry);
            testCase.verifyEqual(leaf.ParentId, tab.Id);
        end

        function generatedSelectedTabReferencesConstrainLaterEdits(testCase)
            % generatedSelectedTabReferencesConstrainLaterEdits Keep editor-generated internal links valid.
            % Guarantee and failure mode: shared with fullGridIsRejectedAtPaste.
            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("GeneratedReferenceFixture", registry);
            right = yamada.model.ComponentRecord("right", "Right", "uipanel", "matlab.ui.container.Panel", "generated");
            right.setProperty("Position", [10 10 300 200]);
            document.addComponent(right, document.RootComponentId);
            group = yamada.model.ComponentRecord("group", "Group", "uitabgroup", "matlab.ui.container.TabGroup", "generated");
            group.setProperty("Position", [10 10 200 150]);
            document.addComponent(group, document.RootComponentId);
            tab = yamada.model.ComponentRecord("tab", "Selected", "uitab", "matlab.ui.container.Tab", "generated");
            document.addComponent(tab, group.Id);
            entry = group.setProperty("SelectedTab", []);
            entry.setSourceExpression("app.Selected");
            entry.Metadata.SubtreeReferenceId = tab.Id;
            second = yamada.model.ComponentRecord("second-group", "SecondGroup", "uitabgroup", "matlab.ui.container.TabGroup", "generated");
            second.setProperty("Position", [10 10 200 150]);
            document.addComponent(second, right.Id);
            testCase.verifyFalse(EditAvailabilityTest.movable(document, tab.Id, second.Id, registry));
            testCase.verifyTrue(yamada.model.DocumentEditAvailability.deletion(document, tab.Id, registry).Enabled);
            testCase.verifyTrue(yamada.model.DocumentEditAvailability.deletion(document, group.Id, registry).Enabled);
            testCase.verifyError(@() document.reparentSubtree(tab.Id, second.Id, registry), "yamada:DocumentModel:UnsafeSubtreeEdit");
        end

        function missingExternalReferenceIsRejectedAtPaste(testCase)
            % missingExternalReferenceIsRejectedAtPaste Revalidate snapshot targets after direct model changes.
            [document, registry, ~, right] = EditAvailabilityTest.fixture(false);
            definition = registry.get("uicontextmenu");
            menu = yamada.model.ComponentRecord("menu", "Menu", definition.Factory, definition.DeclaredType, "generated");
            document.addComponent(menu, document.RootComponentId);
            % Load this programmatic-only component before exercising editor insertion commands.
            rightName = right.Name;
            document = yamada.source.AppSourceParser.parseText(yamada.source.NewAppGenerator(registry).generate(document), registry);
            right = document.getComponentByName(rightName);
            menu = document.getComponentByName("Menu");
            button = document.insertComponent(registry, "uibutton", document.RootComponentId);
            entry = button.setProperty("ContextMenu", []);
            entry.setSourceExpression("app." + menu.Name);
            entry.Metadata.SubtreeReferenceId = menu.Id;
            clipboard = yamada.model.ComponentClipboard();
            clipboard.copy(document, button.Id, registry);
            testCase.verifyTrue(clipboard.availability("Paste", document, right.Id, registry).Enabled);
            document.Components(document.Components == menu) = [];
            document.getComponent(document.RootComponentId).removeChild(menu.Id);
            testCase.verifyTrue(clipboard.availability("Paste", document, right.Id, registry).Enabled);
            testCase.verifyTrue(clipboard.hasContents(document));
        end

        function measuredGeometryParticipatesInReparentConditions(testCase)
            % measuredGeometryParticipatesInReparentConditions Require measured bounds when moving a grid child to an absolute parent.
            % Guarantee and failure mode: shared with readOnlyStateOnlyRestrictsMoving.
            [document, registry, ~, right, leaf] = EditAvailabilityTest.fixture(false);
            grid = document.insertComponent(registry, "uigridlayout", document.RootComponentId);
            document.reparentSubtree(leaf.Id, grid.Id, registry);
            testCase.verifyFalse(EditAvailabilityTest.movable(document, leaf.Id, right.Id, registry));
            testCase.verifyTrue(EditAvailabilityTest.movable(document, leaf.Id, right.Id, registry, [10 20 90 25]));
            testCase.verifyFalse(EditAvailabilityTest.movable(document, leaf.Id, right.Id, registry));
        end

        function constructorConditionsSurviveDiagnosticRefresh(testCase)
            % constructorConditionsSurviveDiagnosticRefresh Keep copy available with opaque constructor settings.
            [original, registry, ~, ~, leaf] = EditAvailabilityTest.fixture(true);
            source = replace(original.OriginalText, "app." + leaf.Name + " = uilabel(app.Panel);", ...
                "app." + leaf.Name + " = uilabel(app.Panel, 'UnknownSetting', 17);");
            document = yamada.source.AppSourceParser.parseText(source, registry);
            leaf = document.getComponentByName(leaf.Name);
            before = yamada.model.DocumentEditAvailability.copying(document, leaf.Id, registry);
            document.Diagnostics = yamada.model.Diagnostic.empty;
            state = yamada.model.DocumentEditAvailability.copying(document, leaf.Id, registry);
            testCase.verifyTrue(state.Enabled);
            testCase.verifyEqual(state, before);
        end

        function chosenCommandsRemainAtomicAndUndoable(testCase)
            % chosenCommandsRemainAtomicAndUndoable Execute permitted edits only after the query returns.
            % Guarantee and failure mode: shared with fullGridIsRejectedAtPaste.
            [document, registry, ~, right, leaf] = EditAvailabilityTest.fixture(true);
            before = document.OriginalText;
            history = document.HistoryIndex;
            testCase.assertTrue(EditAvailabilityTest.movable(document, leaf.Id, right.Id, registry));
            document.reparentSubtree(leaf.Id, right.Id, registry);
            testCase.verifyEqual(document.HistoryIndex, history + 1);
            document.undo();
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), before);
            testCase.assertTrue(yamada.model.DocumentEditAvailability.deletion(document, leaf.Id, registry).Enabled);
            document.removeSubtree(leaf.Id, registry);
            testCase.verifyEmpty(document.getComponent(leaf.Id));
            document.undo();
            testCase.verifyEqual(yamada.source.RoundTripGenerator(registry).generate(document), before);
        end
    end

    methods (Static, Access = private)
        function result = movable(document, id, parentId, registry, measured)
            % movable Report whether the drop-time reparent command accepts a destination on an independent candidate.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                id (1, 1) string
                parentId (1, 1) string
                registry (1, 1) yamada.model.ComponentRegistry
                measured double = []
            end
            arguments (Output)
                result (1, 1) logical
            end
            candidate = document.structuralCandidate(registry);
            try
                candidate.reparentSubtree(id, parentId, registry, measured);
                result = true;
            catch
                result = false;
            end
        end

        function [document, registry, left, right, leaf] = fixture(parsed)
            % fixture Create compatible absolute parents and an optional parsed source checkpoint.
            arguments (Input)
                parsed (1, 1) logical
            end
            arguments (Output)
                document (1, 1) yamada.model.DocumentModel
                registry (1, 1) yamada.model.ComponentRegistry
                left (1, 1) yamada.model.ComponentRecord
                right (1, 1) yamada.model.ComponentRecord
                leaf (1, 1) yamada.model.ComponentRecord
            end
            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("AvailabilityFixture", registry);
            left = document.insertComponent(registry, "uipanel", document.RootComponentId);
            right = document.insertComponent(registry, "uipanel", document.RootComponentId);
            leaf = document.insertComponent(registry, "uilabel", left.Id);
            if ~parsed, return, end
            source = yamada.source.NewAppGenerator(registry).generate(document);
            document = yamada.source.AppSourceParser.parseText(source, registry);
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
