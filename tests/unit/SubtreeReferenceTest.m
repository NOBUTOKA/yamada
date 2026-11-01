classdef (TestTags = {'fast', 'model', 'generation'}) SubtreeReferenceTest < matlab.unittest.TestCase
    % SubtreeReferenceTest Verify internal reference remapping and external reference scope.
    %   References are emitted after target creation without evaluating expressions.

    methods (Test)
        function selectedTabMapsToCopiedChildAndReopens(testCase)
            % selectedTabMapsToCopiedChildAndReopens Bind the copied group to its own copied tab.
            [document, registry, group] = SubtreeReferenceTest.fixture();
            clipboard = macd.model.ComponentClipboard();
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
            reopened = macd.source.AppSourceParser.parseText(document.GeneratedText, registry);
            testCase.verifyEqual(reopened.getComponentByName(copied.Name).getProperty("SelectedTab").SourceExpression, "app." + target.Name);
        end

        function externalContextMenuSurvivesTargetRename(testCase)
            % externalContextMenuSurvivesTargetRename Keep external identity while resolving its current name.
            [document, registry, ~, button, menu] = SubtreeReferenceTest.fixture();
            clipboard = macd.model.ComponentClipboard();
            clipboard.copy(document, button.Id, registry);
            document.renameComponent(menu.Id, "RenamedMenu", registry);
            copied = clipboard.paste(document, document.RootComponentId, registry);
            testCase.verifyEqual(copied.getProperty("ContextMenu").Metadata.SubtreeReferenceId, menu.Id);
            testCase.verifySubstring(document.GeneratedText, "app." + copied.Name + ".ContextMenu = app.RenamedMenu;");
            testCase.verifyEqual(button.getProperty("ContextMenu").SourceExpression, "app.RenamedMenu");
        end

        function referenceScopeBlocksMovingOrDeletingCopiedSelectedTab(testCase)
            % referenceScopeBlocksMovingOrDeletingCopiedSelectedTab Keep reference relationships valid on later edits.
            [document, registry, group] = SubtreeReferenceTest.fixture();
            clipboard = macd.model.ComponentClipboard();
            clipboard.copy(document, group.Id, registry);
            copied = clipboard.paste(document, document.RootComponentId, registry);
            target = document.getComponent(copied.getProperty("SelectedTab").Metadata.SubtreeReferenceId);
            history = document.HistoryIndex;
            testCase.verifyError(@() document.reparentSubtree(target.Id, group.Id, registry), "macd:DocumentModel:UnsafeSubtreeEdit");
            testCase.verifyEqual(target.ParentId, copied.Id);
            testCase.verifyError(@() document.removeSubtree(target.Id, registry), "macd:SubtreeSourceEdits:UnsafeDeletion");
            testCase.verifyEqual(document.HistoryIndex, history);
        end

        function parsedGroupMovesWithReferenceAfterTargetCreation(testCase)
            % parsedGroupMovesWithReferenceAfterTargetCreation Preserve initialization dependency order when relocating a group.
            [document, registry, group] = SubtreeReferenceTest.fixture();
            panel = document.insertComponent(registry, "uipanel", document.RootComponentId);
            document.reparentSubtree(group.Id, panel.Id, registry);
            source = document.GeneratedText;
            creation = strfind(source, "app.SecondTab = uitab(");
            assignment = strfind(source, "app." + group.Name + ".SelectedTab = app.SecondTab;");
            testCase.verifyLessThan(creation, assignment);
            reopened = macd.source.AppSourceParser.parseText(source, registry);
            testCase.verifyEqual(reopened.getComponentByName(group.Name).ParentId, reopened.getComponentByName(panel.Name).Id);
        end

        function unsupportedInternalReferenceBlocksRelocation(testCase)
            % unsupportedInternalReferenceBlocksRelocation Preserve opaque dependencies rather than emitting forward references.
            [original, registry, group] = SubtreeReferenceTest.fixture();
            source = replace(original.OriginalText, ".SelectedTab = app.SecondTab;", ".UserData = app.SecondTab;");
            document = macd.source.AppSourceParser.parseText(source, registry);
            group = document.getComponentByName(group.Name);
            panel = document.insertComponent(registry, "uipanel", document.RootComponentId);
            parentId = group.ParentId;
            history = document.HistoryIndex;
            testCase.verifyError(@() document.reparentSubtree(group.Id, panel.Id, registry), "macd:DocumentModel:UnsafeSubtreeEdit");
            testCase.verifyEqual(group.ParentId, parentId);
            testCase.verifyEqual(document.HistoryIndex, history);
        end

        function staleExternalTargetRejectsPasteWithoutChangingClipboard(testCase)
            % staleExternalTargetRejectsPasteWithoutChangingClipboard Reject a snapshot whose external target no longer exists.
            [document, registry, ~, button, menu] = SubtreeReferenceTest.fixture();
            clipboard = macd.model.ComponentClipboard();
            clipboard.copy(document, button.Id, registry);
            % Simulate a replaced external target without bypassing the paste validation gate.
            document.Components(document.Components == menu) = [];
            root = document.getComponent(document.RootComponentId);
            root.removeChild(menu.Id);
            history = document.HistoryIndex;
            testCase.verifyError(@() clipboard.paste(document, root.Id, registry), "macd:DocumentModel:UnsafeSubtreeCopy");
            testCase.verifyEqual(document.HistoryIndex, history);
            testCase.verifyTrue(clipboard.hasContents(document));
        end
    end

    methods (Static, Access = private)
        function [document, registry, group, button, menu] = fixture()
            % fixture Create and parse direct SelectedTab and ContextMenu references.
            arguments (Output)
                document (1, 1) macd.model.DocumentModel
                registry (1, 1) macd.model.ComponentRegistry
                group (1, 1) macd.model.ComponentRecord
                button (1, 1) macd.model.ComponentRecord
                menu (1, 1) macd.model.ComponentRecord
            end
            registry = macd.model.ComponentRegistry.createDefault();
            original = macd.model.NewAppFactory.createEmpty("ReferenceApp", registry);
            group = macd.model.ComponentRecord("group", "Group", "uitabgroup", "matlab.ui.container.TabGroup", "generated");
            group.setProperty("Position", [10 10 300 200]);
            original.addComponent(group, original.RootComponentId);
            first = macd.model.ComponentRecord("first-tab", "FirstTab", "uitab", "matlab.ui.container.Tab", "generated");
            original.addComponent(first, group.Id);
            second = macd.model.ComponentRecord("second-tab", "SecondTab", "uitab", "matlab.ui.container.Tab", "generated");
            original.addComponent(second, group.Id);
            entry = group.setProperty("SelectedTab", []);
            entry.setSourceExpression("app.SecondTab");
            entry.Metadata.SubtreeReferenceId = second.Id;
            definition = registry.get("uicontextmenu");
            menu = macd.model.ComponentRecord("menu", "Menu", definition.Factory, definition.DeclaredType, "generated");
            original.addComponent(menu, original.RootComponentId);
            button = macd.model.ComponentRecord("button", "Button", "uibutton", "matlab.ui.control.Button", "generated");
            button.setProperty("Position", [10 10 100 22]);
            original.addComponent(button, original.RootComponentId);
            entry = button.setProperty("ContextMenu", []);
            entry.setSourceExpression("app.Menu");
            entry.Metadata.SubtreeReferenceId = menu.Id;
            source = macd.source.NewAppGenerator(registry).generate(original);
            document = macd.source.AppSourceParser.parseText(source, registry);
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
