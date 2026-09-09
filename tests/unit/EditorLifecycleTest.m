classdef EditorLifecycleTest < matlab.unittest.TestCase
    % EditorLifecycleTest Verify injectable Save, Save As, and editor-close decisions.
    %   These tests use the real editor menu and close callbacks while replacing
    %   only native dialogs and filesystem decisions through the lifecycle service.

    methods (Test)
        function saveAsReplacementAndNormalSaveFollowTheirSeparatePolicies(testCase)
            % saveAsReplacementAndNormalSaveFollowTheirSeparatePolicies Verify replacement prompts occur once.

            target = string(tempname) + ".m";
            cleanup = onCleanup(@() deleteTemporaryFile(target));
            macd.source.SourceWriter.write(target, "original", "CRLF");
            refused = lifecycleForTest(struct("SavePath", target, ...
                "SaveAccepted", true, "FileExists", true, "ReplaceAccepted", false));
            app = yamada(refused);
            appCleanup = onCleanup(@() deleteIfValid(app));

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
                "UntitledApp* - Yet Another MATLAB App Designer Alternative");
            invokeEditorMenu("Save As...");
            testCase.verifyFalse(app.Document.IsDirty);
            testCase.verifyEqual(app.Document.FilePath, target);
            figure = editorFigure();
            [~, base, extension] = fileparts(target);
            testCase.verifyEqual(string(figure.Name), string(base) + string(extension) + ...
                " - Yet Another MATLAB App Designer Alternative");

            addPaletteComponent("Button");
            testCase.verifyTrue(app.Document.IsDirty);
            testCase.verifyEqual(string(editorFigure().Name), string(base) + ...
                string(extension) + "* - Yet Another MATLAB App Designer Alternative");
            invokeEditorMenu("Save");
            testCase.verifyFalse(app.Document.IsDirty);
            clear appCleanup
        end

        function canceledAndFailedSavesKeepTheDocumentDirty(testCase)
            % canceledAndFailedSavesKeepTheDocumentDirty Preserve state after unsuccessful writes.

            canceled = lifecycleForTest(struct("SaveAccepted", false));
            app = yamada(canceled);
            cleanup = onCleanup(@() deleteIfValid(app));
            invokeEditorMenu("Save As...");
            testCase.verifyTrue(app.Document.IsDirty);
            testCase.verifyEqual(app.Document.FilePath, "");
            clear cleanup
            delete(app);

            target = string(tempname) + ".m";
            cleanupFile = onCleanup(@() deleteTemporaryFile(target));
            failed = lifecycleForTest(struct("SavePath", target, ...
                "SaveAccepted", true, "WriteSucceeds", false));
            app = yamada(failed);
            cleanup = onCleanup(@() deleteIfValid(app));
            invokeEditorMenu("Save As...");
            testCase.verifyTrue(app.Document.IsDirty);
            testCase.verifyEqual(app.Document.FilePath, "");
            testCase.verifyFalse(isfile(target));
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

        function newAndOpenUseOneDiscardOrCancelGuard(testCase)
            % newAndOpenUseOneDiscardOrCancelGuard Preserve or replace only after the selected answer.

            fixture = fullfile(fileparts(fileparts(mfilename("fullpath"))), ...
                "fixtures", "SimpleCalculatorApp.m");
            canceled = lifecycleForTest(struct("NewClassName", "NextApp", ...
                "OpenPath", fixture, "UnsavedChoice", "Cancel"));
            app = yamada(canceled);
            cleanup = onCleanup(@() deleteIfValid(app));
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
            invokeEditorMenu("New");
            testCase.verifyEqual(app.Document.ClassName, "NextApp");
            invokeEditorMenu("Open...");
            testCase.verifyEqual(app.Document.ClassName, "SimpleCalculatorApp");
            testCase.verifyFalse(app.Document.IsDirty);
            clear cleanup
        end

        function closeGuardSupportsCancelSaveDiscardAndCleanClose(testCase)
            % closeGuardSupportsCancelSaveDiscardAndCleanClose Exercise all editor close decisions.

            canceled = lifecycleForTest(struct("UnsavedChoice", "Cancel"));
            app = yamada(canceled);
            figure = editorFigure();
            figure.CloseRequestFcn(figure, struct());
            testCase.verifyTrue(isvalid(app));
            delete(app);

            target = string(tempname) + ".m";
            cleanupFile = onCleanup(@() deleteTemporaryFile(target));
            saved = lifecycleForTest(struct("UnsavedChoice", "Save", ...
                "SavePath", target, "SaveAccepted", true));
            app = yamada(saved);
            figure = editorFigure();
            figure.CloseRequestFcn(figure, struct());
            testCase.verifyEmpty(findall(0, "Type", "figure", "Tag", "macd-yamada-editor"));
            testCase.verifyTrue(isfile(target));

            discarded = lifecycleForTest(struct("UnsavedChoice", "Discard"));
            app = yamada(discarded);
            figure = editorFigure();
            figure.CloseRequestFcn(figure, struct());
            testCase.verifyEmpty(findall(0, "Type", "figure", "Tag", "macd-yamada-editor"));

            clean = lifecycleForTest(struct("SavePath", target, ...
                "SaveAccepted", true, "ConfirmMustNotRun", true));
            app = yamada(clean);
            invokeEditorMenu("Save As...");
            figure = editorFigure();
            figure.CloseRequestFcn(figure, struct());
            testCase.verifyEmpty(findall(0, "Type", "figure", "Tag", "macd-yamada-editor"));
            clear cleanupFile
        end
    end
end

function service = lifecycleForTest(options)
% lifecycleForTest Create deterministic lifecycle callbacks from one options structure.
arguments (Input)
    options (1, 1) struct
end

defaults = struct("NewClassName", "NextApp", "OpenPath", "", ...
    "SavePath", "", "SaveAccepted", true, "UnsavedChoice", "Cancel", ...
    "FileExists", false, "ReplaceAccepted", true, "WriteSucceeds", true, ...
    "ConfirmMustNotRun", false);
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
