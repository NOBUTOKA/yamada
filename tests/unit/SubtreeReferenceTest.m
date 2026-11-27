classdef (TestTags = {'fast', 'model', 'generation'}) SubtreeReferenceTest < matlab.unittest.TestCase
    % SubtreeReferenceTest Verify internal reference remapping and external reference scope.
    %   References are emitted after target creation without evaluating expressions.

    methods (Test)
        % Guarantee: references inside a copied subtree point to the copied targets, and deletion repairs them in the same undo step.
        % Failure mode: a copied group selects the original tab, or deleting its selected tab leaves a dangling reference.
        function selectedTabMapsToCopiedChildAndReopens(testCase)
            % selectedTabMapsToCopiedChildAndReopens Bind the copied group to its own copied tab.
            [document, registry, group] = SubtreeReferenceTest.fixture();
            clipboard = yamada.model.ComponentClipboard();
            clipboard.copy(document, group.Id, registry);
            copied = clipboard.paste(document, document.RootComponentId, registry);
            entry = copied.getProperty("SelectedTab");
            target = document.getComponent(entry.Metadata.SubtreeReferenceId);
            testCase.verifyEqual(target.ParentId, copied.Id);
            testCase.verifyNotEqual(target.Id, document.getComponentByName("SecondTab").Id);
            testCase.verifySubstring(document.GeneratedText, "app." + copied.Name + ".SelectedTab = app." + target.Name + ";");
            creation = strfind(document.GeneratedText, "app." + target.Name + " = uitab(");
            assignment = strfind(document.GeneratedText, "app." + copied.Name + ".SelectedTab =");
            testCase.verifyLessThan(creation, assignment);
            reopened = yamada.source.AppSourceParser.parseText(document.GeneratedText, registry);
            testCase.verifyEqual(reopened.getComponentByName(copied.Name).getProperty("SelectedTab").SourceExpression, "app." + target.Name);
        end

        function externalContextMenuSurvivesTargetRename(testCase)
            % externalContextMenuSurvivesTargetRename Keep external identity while resolving its current name.
            % Guarantee: references outside the subtree follow the target's identity through renames.
            % Failure mode: Paste emits the old name of a renamed context menu and the source no longer runs.
            [document, registry, ~, button, menu] = SubtreeReferenceTest.fixture();
            clipboard = yamada.model.ComponentClipboard();
            clipboard.copy(document, button.Id, registry);
            document.renameComponent(menu.Id, "RenamedMenu", registry);
            copied = clipboard.paste(document, document.RootComponentId, registry);
            testCase.verifyEqual(copied.getProperty("ContextMenu").Metadata.SubtreeReferenceId, menu.Id);
            testCase.verifySubstring(document.GeneratedText, "app." + copied.Name + ".ContextMenu = app.RenamedMenu;");
            testCase.verifyEqual(button.getProperty("ContextMenu").SourceExpression, "app.RenamedMenu");
        end

        function deletionRetargetsCopiedSelectedTab(testCase)
            % deletionRetargetsCopiedSelectedTab Repair a surviving group selection in the same undoable deletion.
            % Guarantee and failure mode: shared with selectedTabMapsToCopiedChildAndReopens.
            [document, registry, group] = SubtreeReferenceTest.fixture();
            clipboard = yamada.model.ComponentClipboard();
            clipboard.copy(document, group.Id, registry);
            copied = clipboard.paste(document, document.RootComponentId, registry);
            target = document.getComponent(copied.getProperty("SelectedTab").Metadata.SubtreeReferenceId);
            history = document.HistoryIndex;
            testCase.verifyError(@() document.reparentSubtree(target.Id, group.Id, registry), "yamada:DocumentModel:UnsafeSubtreeEdit");
            testCase.verifyEqual(target.ParentId, copied.Id);
            before = document.CurrentText;
            previous = document.getComponent(copied.Children(1));
            document.removeSubtree(target.Id, registry);
            after = document.CurrentText;
            testCase.verifyEqual(copied.getProperty("SelectedTab").SourceExpression, "app." + previous.Name);
            testCase.verifyEqual(copied.getProperty("SelectedTab").Metadata.SubtreeReferenceId, previous.Id);
            testCase.verifyEqual(document.HistoryIndex, history + 1);
            document.undo();
            testCase.verifyEqual(document.CurrentText, before);
            testCase.verifyEqual(copied.getProperty("SelectedTab").Metadata.SubtreeReferenceId, target.Id);
            document.redo();
            testCase.verifyEqual(document.CurrentText, after);
            document.removeSubtree(previous.Id, registry);
            testCase.verifyEmpty(copied.Children);
            testCase.verifyEmpty(copied.getProperty("SelectedTab"));
            document.undo();
            testCase.verifyEqual(document.CurrentText, after);
        end

        % Guarantee: relocation emits references only after their targets exist, and otherwise rejects without change.
        % Failure mode: a move emits a forward reference or relocates an unsupported internal reference.
        function parsedGroupMovesWithReferenceAfterTargetCreation(testCase)
            % parsedGroupMovesWithReferenceAfterTargetCreation Preserve initialization dependency order when relocating a group.
            [document, registry, group] = SubtreeReferenceTest.fixture();
            panel = document.insertComponent(registry, "uipanel", document.RootComponentId);
            document.reparentSubtree(group.Id, panel.Id, registry);
            source = document.GeneratedText;
            creation = strfind(source, "app.SecondTab = uitab(");
            assignment = strfind(source, "app." + group.Name + ".SelectedTab = app.SecondTab;");
            testCase.verifyLessThan(creation, assignment);
            reopened = yamada.source.AppSourceParser.parseText(source, registry);
            testCase.verifyEqual(reopened.getComponentByName(group.Name).ParentId, reopened.getComponentByName(panel.Name).Id);
        end

        function unsupportedInternalReferenceBlocksRelocation(testCase)
            % unsupportedInternalReferenceBlocksRelocation Preserve opaque dependencies rather than emitting forward references.
            [original, registry, group] = SubtreeReferenceTest.fixture();
            source = replace(original.OriginalText, ".SelectedTab = app.SecondTab;", ".UserData = app.SecondTab;");
            document = yamada.source.AppSourceParser.parseText(source, registry);
            group = document.getComponentByName(group.Name);
            panel = document.insertComponent(registry, "uipanel", document.RootComponentId);
            parentId = group.ParentId;
            history = document.HistoryIndex;
            testCase.verifyError(@() document.reparentSubtree(group.Id, panel.Id, registry), "yamada:DocumentModel:UnsafeSubtreeEdit");
            testCase.verifyEqual(group.ParentId, parentId);
            testCase.verifyEqual(document.HistoryIndex, history);
        end
    end

    methods (Static, Access = private)
        function [document, registry, group, button, menu] = fixture()
            % fixture Create and parse direct SelectedTab and ContextMenu references.
            arguments (Output)
                document (1, 1) yamada.model.DocumentModel
                registry (1, 1) yamada.model.ComponentRegistry
                group (1, 1) yamada.model.ComponentRecord
                button (1, 1) yamada.model.ComponentRecord
                menu (1, 1) yamada.model.ComponentRecord
            end
            registry = yamada.model.ComponentRegistry.createDefault();
            original = yamada.model.NewAppFactory.createEmpty("ReferenceApp", registry);
            group = yamada.model.ComponentRecord("group", "Group", "uitabgroup", "matlab.ui.container.TabGroup", "generated");
            group.setProperty("Position", [10 10 300 200]);
            original.addComponent(group, original.RootComponentId);
            first = yamada.model.ComponentRecord("first-tab", "FirstTab", "uitab", "matlab.ui.container.Tab", "generated");
            original.addComponent(first, group.Id);
            second = yamada.model.ComponentRecord("second-tab", "SecondTab", "uitab", "matlab.ui.container.Tab", "generated");
            original.addComponent(second, group.Id);
            entry = group.setProperty("SelectedTab", []);
            entry.setSourceExpression("app.SecondTab");
            entry.Metadata.SubtreeReferenceId = second.Id;
            definition = registry.get("uicontextmenu");
            menu = yamada.model.ComponentRecord("menu", "Menu", definition.Factory, definition.DeclaredType, "generated");
            original.addComponent(menu, original.RootComponentId);
            button = yamada.model.ComponentRecord("button", "Button", "uibutton", "matlab.ui.control.Button", "generated");
            button.setProperty("Position", [10 10 100 22]);
            original.addComponent(button, original.RootComponentId);
            entry = button.setProperty("ContextMenu", []);
            entry.setSourceExpression("app.Menu");
            entry.Metadata.SubtreeReferenceId = menu.Id;
            source = yamada.source.NewAppGenerator(registry).generate(original);
            document = yamada.source.AppSourceParser.parseText(source, registry);
            group = document.getComponentByName(group.Name);
            button = document.getComponentByName(button.Name);
            menu = document.getComponentByName(menu.Name);
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
