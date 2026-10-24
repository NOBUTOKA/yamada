classdef (TestTags = {'lifecycle', 'ui'}) EditorLifecycleTest < matlab.unittest.TestCase
    % EditorLifecycleTest Verify injectable Save, Save As, and editor-close decisions.
    %   These tests use the real editor menu and close callbacks while replacing
    %   only native dialogs and filesystem decisions through the lifecycle service.

    methods (Test)
        function reloadDirtySaveAndDiscardResetToFreshHistory(testCase)
            % reloadDirtySaveAndDiscardResetToFreshHistory Resolve dirty changes before reading the replacement.
            for choice = ["Save", "Discard"]
                [target, ~] = reloadFixture();
                fileCleanup = onCleanup(@() deleteTemporaryFile(target));
                app = yamada(lifecycleForTest(struct("OpenPath", target, "UnsavedChoice", choice)));
                appCleanup = onCleanup(@() deleteIfValid(app));
                invokeEditorMenu("Open...");
                addPaletteComponent("Button");
                invokeEditorMenu("Reload Source" + string(char(9)) + "(F5)");
                testCase.verifyFalse(app.Document.IsDirty);
                testCase.verifyFalse(app.Document.canUndo());
                if choice == "Save"
                    testCase.verifyEqual(numel(app.Document.Components), 3);
                else
                    testCase.verifyEqual(numel(app.Document.Components), 2);
                end
                clear appCleanup fileCleanup
            end
        end

        function reloadChangedReadAndSaveFailureRetainCurrentState(testCase)
            % reloadChangedReadAndSaveFailureRetainCurrentState Reject changing snapshots and failed saves atomically.
            [target, ~] = reloadFixture();
            fileCleanup = onCleanup(@() deleteTemporaryFile(target));
            service = macd.ui.DocumentLifecycleService(struct( ...
                "RequestOpenPathFcn", @() deal(true, target), "ReadSourceBytesFcn", changingReader(target)));
            app = yamada(service);
            appCleanup = onCleanup(@() deleteIfValid(app));
            tool = findall(editorFigure(), "Tag", "macd-refresh-source");
            testCase.verifyEqual(string(tool.Enable), "off");
            invokeEditorMenu("Open...");
            original = app.Document;
            invokeEditorMenu("Reload Source" + string(char(9)) + "(F5)");
            testCase.verifyTrue(app.Document == original);
            testCase.verifyEqual(string(tool.Enable), "on");
            clear appCleanup
            app = yamada(lifecycleForTest(struct("OpenPath", target, "UnsavedChoice", "Save", "WriteSucceeds", false)));
            appCleanup = onCleanup(@() deleteIfValid(app));
            invokeEditorMenu("Open...");
            original = app.Document;
            addPaletteComponent("Button");
            invokeEditorMenu("Reload Source" + string(char(9)) + "(F5)");
            testCase.verifyTrue(app.Document == original);
            testCase.verifyTrue(app.Document.IsDirty);
        end

        function reloadEntriesReadFreshSourceAndResetHistory(testCase)
            % reloadEntriesReadFreshSourceAndResetHistory Exercise menu, toolbar and F5 dispatch.
            [target, source] = reloadFixture();
            fileCleanup = onCleanup(@() deleteTemporaryFile(target));
            app = yamada(lifecycleForTest(struct("OpenPath", target)));
            appCleanup = onCleanup(@() deleteIfValid(app));
            invokeEditorMenu("Open...");
            for entry = 1:3
                macd.source.SourceWriter.write(target, source + "% Revision " + entry + newline, "CRLF");
                if entry == 1
                    invokeEditorMenu("Reload Source" + string(char(9)) + "(F5)");
                elseif entry == 2
                    tool = findall(editorFigure(), "Tag", "macd-refresh-source");
                    tool.ClickedCallback(tool, []);
                else
                    figure = editorFigure();
                    figure.WindowKeyPressFcn(figure, struct("Key", "f5", "Modifier", {{}}));
                end
                testCase.verifySubstring(app.Document.OriginalText, "% Revision " + entry);
                testCase.verifyFalse(app.Document.IsDirty);
                testCase.verifyFalse(app.Document.canUndo());
            end
        end

        function reloadFailuresRetainDocument(testCase)
            % reloadFailuresRetainDocument Preserve model and history on unsuccessful reloads.
            [target, ~] = reloadFixture();
            fileCleanup = onCleanup(@() deleteTemporaryFile(target));
            app = yamada(lifecycleForTest(struct("OpenPath", target)));
            appCleanup = onCleanup(@() deleteIfValid(app));
            invokeEditorMenu("Open...");
            original = app.Document;
            macd.source.SourceWriter.write(target, "not an handle-based class", "CRLF");
            invokeEditorMenu("Reload Source" + string(char(9)) + "(F5)");
            testCase.verifyTrue(app.Document == original);
            addPaletteComponent("Button");
            invokeEditorMenu("Reload Source" + string(char(9)) + "(F5)");
            testCase.verifyTrue(app.Document == original);
            delete(target);
            invokeEditorMenu("Reload Source" + string(char(9)) + "(F5)");
            testCase.verifyTrue(app.Document == original);
            testCase.verifyTrue(app.Document.canUndo());
        end

        function reloadConflictProtectsExternalFileDuringSaveAs(testCase)
            % reloadConflictProtectsExternalFileDuringSaveAs Reject same-path saving and retain the original reload target.
            [target, source] = reloadFixture();
            fileCleanup = onCleanup(@() deleteTemporaryFile(target));
            separate = string(fullfile(tempdir, "ReloadSavedLocalApp.m"));
            separateCleanup = onCleanup(@() deleteTemporaryFile(separate));
            for saveTarget = [target, separate]
                service = lifecycleForTest(struct("OpenPath", target, "SavePath", saveTarget, "ReloadChoice", "Save As"));
                app = yamada(service);
                appCleanup = onCleanup(@() deleteIfValid(app));
                invokeEditorMenu("Open...");
                addPaletteComponent("Button");
                macd.source.SourceWriter.write(target, source + "% External edit" + newline, "CRLF");
                invokeEditorMenu("Reload Source" + string(char(9)) + "(F5)");
                testCase.verifySubstring(string(fileread(target)), "% External edit");
                if saveTarget == target
                    testCase.verifyTrue(app.Document.IsDirty);
                else
                    testCase.verifyTrue(isfile(separate));
                    testCase.verifyEqual(app.Document.FilePath, target);
                    testCase.verifyFalse(app.Document.IsDirty);
                    testCase.verifySubstring(app.Document.OriginalText, "% External edit");
                end
                clear appCleanup
                macd.source.SourceWriter.write(target, source, "CRLF");
            end
        end

        function saveAsReplacementAndNormalSaveFollowTheirSeparatePolicies(testCase)
            % saveAsReplacementAndNormalSaveFollowTheirSeparatePolicies Verify replacement prompts occur once.

            target = string(tempname) + ".m";
            cleanup = onCleanup(@() deleteTemporaryFile(target));
            macd.source.SourceWriter.write(target, "original", "CRLF");
            refused = lifecycleForTest(struct("SavePath", target, ...
                "SaveAccepted", true, "FileExists", true, "ReplaceAccepted", false));
            app = yamada(refused);
            appCleanup = onCleanup(@() deleteIfValid(app));
            addPaletteComponent("Button");

            invokeEditorMenu("Save As...");
            testCase.verifyTrue(app.Document.IsDirty);
            testCase.verifyEqual(string(fileread(target)), "original");

            clear appCleanup
            delete(app);
            service = lifecycleForTest(struct("SavePath", target, ...
                "SaveAccepted", true, "FileExists", true, "ReplaceAccepted", true));
            app = yamada(service);
            appCleanup = onCleanup(@() deleteIfValid(app));
            testCase.verifyEqual(string(editorFigure().Name), ...
                "UntitledApp - Yet Another MATLAB App Designer Alternative");
            invokeEditorMenu("Save As...");
            testCase.verifyFalse(app.Document.IsDirty);
            testCase.verifyEqual(app.Document.FilePath, target);
            figure = editorFigure();
            [~, base, extension] = fileparts(target);
            testCase.verifyEqual(app.Document.ClassName, string(base));
            savedSource = string(fileread(target));
            testCase.verifySubstring(savedSource, "classdef " + string(base) + ...
                " < handle");
            testCase.verifySubstring(savedSource, "function app = " + string(base));
            testCase.verifySubstring(savedSource, "app (1, 1) " + string(base));
            testCase.verifyFalse(contains(savedSource, "app (1, 1) UntitledApp"));
            testCase.verifyEqual(string(figure.Name), string(base) + string(extension) + ...
                " - Yet Another MATLAB App Designer Alternative");

            addPaletteComponent("Button");
            testCase.verifyTrue(app.Document.IsDirty);
            testCase.verifyEqual(string(editorFigure().Name), string(base) + ...
                string(extension) + "* - Yet Another MATLAB App Designer Alternative");
            invokeEditorMenu("Save");
            testCase.verifyFalse(app.Document.IsDirty);
            testCase.verifySubstring(string(fileread(target)), ...
                "classdef " + string(base) + " < handle");
            clear appCleanup
        end

        function saveAsRenamesOpenedClassAndLaterSaveKeepsItsIdentity(testCase)
            % saveAsRenamesOpenedClassAndLaterSaveKeepsItsIdentity Preserve parsed source edits across saves.
            fixture = string(fullfile(fileparts(fileparts(mfilename("fullpath"))), ...
                "fixtures", "handle", "SimpleCalculatorApp.m"));
            target = string(tempname) + ".m";
            cleanupFile = onCleanup(@() deleteTemporaryFile(target));
            service = lifecycleForTest(struct("OpenPath", fixture, "SavePath", target));
            app = yamada(service);
            cleanupApp = onCleanup(@() deleteIfValid(app));
            invokeEditorMenu("Open...");
            testCase.verifyEqual(app.Document.ClassName, "SimpleCalculatorApp");

            invokeEditorMenu("Save As...");
            [~, baseName] = fileparts(target);
            testCase.verifyEqual(app.Document.ClassName, string(baseName));
            source = string(fileread(target));
            testCase.verifySubstring(source, "classdef " + string(baseName) + ...
                " < handle");
            testCase.verifySubstring(source, "function app = " + string(baseName));
            testCase.verifyFalse(contains(source, "function app = SimpleCalculatorApp"));

            label = app.Document.getComponentByName("LeftValueLabel");
            app.Document.setProperty(label.Id, "Text", "Changed after Save As");
            invokeEditorMenu("Save");
            source = string(fileread(target));
            testCase.verifySubstring(source, "classdef " + string(baseName) + ...
                " < handle");
            testCase.verifySubstring(source, "Changed after Save As");
            clear cleanupApp cleanupFile
        end

        function propertyHistorySurvivesMenuSaveAndReopen(testCase)
            % propertyHistorySurvivesMenuSaveAndReopen Keep source ownership across Save As, Undo/Redo, and fresh parsing.
            originalPath = string(tempname) + ".m";
            target = string(tempname) + ".m";
            originalCleanup = onCleanup(@() deleteTemporaryFile(originalPath));
            targetCleanup = onCleanup(@() deleteTemporaryFile(target));
            source = strjoin(["classdef SaveHistoryFixture < handle", "properties", ...
                "UIFigure matlab.ui.Figure", "Choice matlab.ui.control.DropDown", "end", "methods", ...
                "function app = SaveHistoryFixture", "createComponents(app);", "end", ...
                "function createComponents(app)", "app.UIFigure = uifigure(Visible='off');", ...
                "app.Choice = uidropdown(app.UIFigure, Items=[""A"" ""B""], Value='A');", ...
                "app.Choice.Value = 'B';", "end", "end", "end"], sprintf('\r\n'));
            macd.source.SourceWriter.write(originalPath, source, "CRLF");
            app = yamada(lifecycleForTest(struct("OpenPath", originalPath, "SavePath", target)));
            appCleanup = onCleanup(@() deleteIfValid(app));
            invokeEditorMenu("Open...");
            control = app.Document.getComponentByName("Choice");
            settings = control.settingSnapshot();
            app.Document.setProperty(control.Id, "Value", 'A');
            invokeEditorMenu("Save As...");
            testCase.verifyFalse(app.Document.IsDirty);
            testCase.verifyEqual(app.Document.SavedSource.SourceText, string(fileread(target)));
            testCase.verifyEqual(app.Document.OriginalText, source);
            testCase.verifyEqual(control.settingSnapshot(), settings);
            app.Document.undo();
            invokeEditorMenu("Save");
            testCase.verifyFalse(app.Document.IsDirty);
            testCase.verifySubstring(string(fileread(target)), "app.Choice.Value = 'B';");
            app.Document.redo();
            invokeEditorMenu("Save");
            testCase.verifyFalse(app.Document.IsDirty);
            testCase.verifySubstring(string(fileread(target)), "app.Choice.Value = 'A';");
            testCase.verifyEqual(control.settingSnapshot(), settings);
            clear appCleanup

            app = yamada(lifecycleForTest(struct("OpenPath", target)));
            appCleanup = onCleanup(@() deleteIfValid(app));
            invokeEditorMenu("Open...");
            control = app.Document.getComponentByName("Choice");
            testCase.verifyNumElements(control.getSettings("Value"), 2);
            app.Document.setProperty(control.Id, "Value", 'B');
            invokeEditorMenu("Save");
            testCase.verifyFalse(app.Document.IsDirty);
            testCase.verifyEqual(app.Document.SavedSource.SourceText, string(fileread(target)));
            testCase.verifySubstring(string(fileread(target)), "Value='A'");
            testCase.verifySubstring(string(fileread(target)), "app.Choice.Value = 'B';");
        end

        function failedSecondWriteKeepsConfirmedCheckpoint(testCase)
            % failedSecondWriteKeepsConfirmedCheckpoint Retain saved source, dirty intentions, and history on write failure.
            target = string(tempname) + ".m";
            targetCleanup = onCleanup(@() deleteTemporaryFile(target));
            service = macd.ui.DocumentLifecycleService(struct( ...
                "RequestSavePathFcn", @(~) deal(true, target), ...
                "WriteSourceFcn", failingSecondWriter()));
            app = yamada(service);
            appCleanup = onCleanup(@() deleteIfValid(app));
            invokeEditorMenu("Save As...");
            testCase.verifyFalse(app.Document.IsDirty);
            first = app.Document.SavedSource;
            root = app.Document.getComponent(app.Document.RootComponentId);
            app.Document.setProperty(root.Id, "Name", "Unsaved change");
            history = app.Document.HistoryIndex;
            generated = app.Document.GeneratedText;
            diagnostics = app.Document.Diagnostics;
            invokeEditorMenu("Save");
            testCase.verifyTrue(app.Document.IsDirty);
            testCase.verifyEqual(app.Document.HistoryIndex, history);
            testCase.verifyEqual(app.Document.GeneratedText, generated);
            testCase.verifyEqual(app.Document.Diagnostics, diagnostics);
            testCase.verifyEqual(root.getProperty("Name").LiteralValue, "Unsaved change");
            testCase.verifyEqual(app.Document.SavedSource.SourceSnapshotId, first.SourceSnapshotId);
            testCase.verifyEqual(app.Document.SavedSource.SourceText, first.SourceText);
            testCase.verifyEqual(string(fileread(target)), first.SourceText);
        end

        function canceledAndFailedSavesKeepTheDocumentDirty(testCase)
            % canceledAndFailedSavesKeepTheDocumentDirty Preserve state after unsuccessful writes.

            canceled = lifecycleForTest(struct("SaveAccepted", false));
            app = yamada(canceled);
            cleanup = onCleanup(@() deleteIfValid(app));
            addPaletteComponent("Button");
            invokeEditorMenu("Save As...");
            testCase.verifyTrue(app.Document.IsDirty);
            testCase.verifyEqual(app.Document.FilePath, "");
            testCase.verifyEqual(app.Document.ClassName, "UntitledApp");
            clear cleanup
            delete(app);

            target = string(tempname) + ".m";
            cleanupFile = onCleanup(@() deleteTemporaryFile(target));
            failed = lifecycleForTest(struct("SavePath", target, ...
                "SaveAccepted", true, "WriteSucceeds", false));
            app = yamada(failed);
            cleanup = onCleanup(@() deleteIfValid(app));
            addPaletteComponent("Button");
            invokeEditorMenu("Save As...");
            testCase.verifyTrue(app.Document.IsDirty);
            testCase.verifyEqual(app.Document.FilePath, "");
            testCase.verifyEqual(app.Document.ClassName, "UntitledApp");
            testCase.verifyFalse(isfile(target));
            testCase.verifyEmpty(app.Document.SavedSource);
            clear cleanup
            delete(app);
            clear cleanupFile

            target = string(tempname) + ".m";
            cleanupFile = onCleanup(@() deleteTemporaryFile(target));
            blocked = lifecycleForTest(struct("SavePath", target, "SaveAccepted", true));
            app = yamada(blocked);
            cleanup = onCleanup(@() deleteIfValid(app));
            root = app.Document.getComponent(app.Document.RootComponentId);
            app.Document.setProperty(root.Id, "Position", [10 10 0 30]);
            invokeEditorMenu("Save As...");
            testCase.verifyTrue(app.Document.IsDirty);
            testCase.verifyFalse(isfile(target));
            clear cleanup
            delete(app);
            clear cleanupFile
        end

        function invalidSaveAsFilenameDoesNotChangeDocument(testCase)
            % invalidSaveAsFilenameDoesNotChangeDocument Require a valid MATLAB class file name.
            target = string(tempname) + " invalid.m";
            service = lifecycleForTest(struct("SavePath", target));
            app = yamada(service);
            cleanup = onCleanup(@() deleteIfValid(app));

            invokeEditorMenu("Save As...");

            testCase.verifyEqual(app.Document.ClassName, "UntitledApp");
            testCase.verifyEqual(app.Document.FilePath, "");
            testCase.verifyFalse(isfile(target));
            clear cleanup
        end

        function newAndOpenUseOneDiscardOrCancelGuard(testCase)
            % newAndOpenUseOneDiscardOrCancelGuard Preserve or replace only after the selected answer.

            fixture = fullfile(fileparts(fileparts(mfilename("fullpath"))), ...
                "fixtures", "handle", "SimpleCalculatorApp.m");
            canceled = lifecycleForTest(struct("NewClassName", "NextApp", ...
                "OpenPath", fixture, "UnsavedChoice", "Cancel"));
            app = yamada(canceled);
            cleanup = onCleanup(@() deleteIfValid(app));
            addPaletteComponent("Button");
            invokeEditorMenu("New");
            testCase.verifyEqual(app.Document.ClassName, "UntitledApp");
            invokeEditorMenu("Open...");
            testCase.verifyEqual(app.Document.ClassName, "UntitledApp");
            clear cleanup
            delete(app);

            discarded = lifecycleForTest(struct("NewClassName", "NextApp", ...
                "OpenPath", fixture, "UnsavedChoice", "Discard"));
            app = yamada(discarded);
            cleanup = onCleanup(@() deleteIfValid(app));
            addPaletteComponent("Button");
            invokeEditorMenu("New");
            testCase.verifyEqual(app.Document.ClassName, "NextApp");
            addPaletteComponent("Button");
            invokeEditorMenu("Open...");
            testCase.verifyEqual(app.Document.ClassName, "SimpleCalculatorApp");
            testCase.verifyFalse(app.Document.IsDirty);
            clear cleanup
        end

        function closeGuardSupportsCancelSaveDiscardAndCleanClose(testCase)
            % closeGuardSupportsCancelSaveDiscardAndCleanClose Exercise all editor close decisions.

            canceled = lifecycleForTest(struct("UnsavedChoice", "Cancel"));
            app = yamada(canceled);
            addPaletteComponent("Button");
            figure = editorFigure();
            figure.CloseRequestFcn(figure, struct());
            testCase.verifyTrue(isvalid(app));
            delete(app);

            target = string(tempname) + ".m";
            cleanupFile = onCleanup(@() deleteTemporaryFile(target));
            saved = lifecycleForTest(struct("UnsavedChoice", "Save", ...
                "SavePath", target, "SaveAccepted", true));
            app = yamada(saved);
            addPaletteComponent("Button");
            testCase.verifyTrue(app.Document.IsDirty);
            figure = editorFigure();
            figure.CloseRequestFcn(figure, struct());
            testCase.verifyEmpty(findall(0, "Type", "figure", "Tag", "macd-yamada-editor"));
            testCase.verifyTrue(isfile(target));

            discarded = lifecycleForTest(struct("UnsavedChoice", "Discard"));
            app = yamada(discarded);
            addPaletteComponent("Button");
            testCase.verifyTrue(app.Document.IsDirty);
            figure = editorFigure();
            figure.CloseRequestFcn(figure, struct());
            testCase.verifyEmpty(findall(0, "Type", "figure", "Tag", "macd-yamada-editor"));

            clean = lifecycleForTest(struct("SavePath", target, ...
                "SaveAccepted", true, "ConfirmMustNotRun", true));
            app = yamada(clean);
            invokeEditorMenu("Save As...");
            testCase.verifyFalse(app.Document.IsDirty);
            figure = editorFigure();
            figure.CloseRequestFcn(figure, struct());
            testCase.verifyEmpty(findall(0, "Type", "figure", "Tag", "macd-yamada-editor"));
            clear cleanupFile
        end
    end
end

function writer = failingSecondWriter()
% failingSecondWriter Return an owned writer that fails before changing the second target.
arguments (Output)
    writer (1, 1) function_handle
end
count = 0;
writer = @write;
    function write(path, source, lineEnding)
        % write Write the first output and inject a failure for later writes.
        count = count + 1;
        if count > 1
            error("macd:EditorLifecycleTest:WriteFailed", "Injected second write failure.");
        end
        macd.source.SourceWriter.write(path, source, lineEnding);
    end
end

function reader = changingReader(target)
% changingReader Return a reader whose third snapshot differs from the parsed file.
arguments (Input)
    target (1, 1) string
end
arguments (Output)
    reader (1, 1) function_handle
end
count = 0;
reader = @read;
    function bytes = read(~)
        % read Supply deterministic byte snapshots to exercise concurrent change detection.
        count = count + 1;
        bytes = unicode2native(fileread(target), "UTF-8");
        if count == 3, bytes(end + 1) = uint8(32); end
    end
end

function [target, source] = reloadFixture()
% reloadFixture Write a source-only application for lifecycle verification.
arguments (Output)
    target (1, 1) string
    source (1, 1) string
end
registry = macd.model.ComponentRegistry.createDefault();
document = macd.model.NewAppFactory.createEmpty("ReloadFixture", registry);
document.insertComponent(registry, "uibutton", document.RootComponentId);
source = macd.source.RoundTripGenerator(registry).generate(document);
target = string(tempname) + ".m";
macd.source.SourceWriter.write(target, source, "CRLF");
end

function service = lifecycleForTest(options)
% lifecycleForTest Create deterministic lifecycle callbacks from one options structure.
arguments (Input)
    options (1, 1) struct
end

defaults = struct("NewClassName", "NextApp", "OpenPath", "", ...
    "SavePath", "", "SaveAccepted", true, "UnsavedChoice", "Cancel", ...
    "FileExists", false, "ReplaceAccepted", true, "WriteSucceeds", true, ...
    "ConfirmMustNotRun", false, "ReloadChoice", "Cancel");
names = string(fieldnames(defaults));
for index = 1:numel(names)
    name = names(index);
    if ~isfield(options, name)
        options.(name) = defaults.(name);
    end
end
callbacks = struct( ...
    "RequestNewClassNameFcn", @() selectedText(options.NewClassName), ...
    "RequestOpenPathFcn", @() selectedText(options.OpenPath), ...
    "RequestSavePathFcn", @(~) selectedPath(options.SavePath, options.SaveAccepted), ...
    "ConfirmUnsavedChangesFcn", @() unsavedChoice(options), ...
    "ConfirmReloadConflictFcn", @() options.ReloadChoice, ...
    "ConfirmReplaceFcn", @(~) options.ReplaceAccepted, ...
    "FileExistsFcn", @(~) options.FileExists, ...
    "WriteSourceFcn", @(path, source, lineEnding) writeForTest( ...
    path, source, lineEnding, options.WriteSucceeds));
service = macd.ui.DocumentLifecycleService(callbacks);
end

function [accepted, text] = selectedText(text)
% selectedText Return an accepted nonempty test dialog value.
text = string(text);
accepted = strlength(text) > 0;
end

function [accepted, path] = selectedPath(path, accepted)
% selectedPath Return the configured Save As selection result.
path = string(path);
accepted = logical(accepted);
end

function choice = unsavedChoice(options)
% unsavedChoice Return one configured unsaved-document response.
if options.ConfirmMustNotRun
    error("macd:EditorLifecycleTest:UnexpectedConfirmation", ...
        "A clean document must not ask about unsaved changes.");
end
choice = string(options.UnsavedChoice);
end

function writeForTest(path, source, lineEnding, succeeds)
% writeForTest Write source or raise the configured injected failure.
if ~succeeds
    error("macd:EditorLifecycleTest:WriteFailed", "Injected write failure.");
end
macd.source.SourceWriter.write(path, source, lineEnding);
end

function invokeEditorMenu(text)
% invokeEditorMenu Trigger one editor menu callback by its visible text.
menus = findall(editorFigure(), "Type", "uimenu");
menu = menus(erase(string({menus.Text}), "&") == text);
assert(isscalar(menu), "macd:EditorLifecycleTest:MissingMenu", ...
    "Expected one editor menu named ""%s"".", text);
menu.MenuSelectedFcn(menu, struct());
drawnow;
end

function addPaletteComponent(name)
% addPaletteComponent Insert a component through the real palette callback.
palette = findall(editorFigure(), "Type", "uitable");
palette = palette(arrayfun(@(candidate) any(string(candidate.ColumnName) == "Component") && ...
    any(string(candidate.ColumnName) == "Category"), palette));
row = find(string(palette.Data(:, 1)) == name, 1);
assert(~isempty(row), "macd:EditorLifecycleTest:MissingPaletteComponent", ...
    "Expected palette component ""%s"".", name);
palette.DoubleClickedFcn(palette, struct("InteractionInformation", struct("Row", row)));
drawnow;
end

function figure = editorFigure()
% editorFigure Return the one stable-tag editor figure.
figure = findall(0, "Type", "figure", "Tag", "macd-yamada-editor");
assert(isscalar(figure), "macd:EditorLifecycleTest:MissingEditor", ...
    "Expected one editor figure.");
end

function deleteIfValid(value)
% deleteIfValid Delete a still-valid editor test fixture without prompting.
if ~isempty(value) && isvalid(value)
    delete(value);
end
end

function deleteTemporaryFile(path)
% deleteTemporaryFile Remove one exact temporary test file when it exists.
if isfile(path)
    delete(path);
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
