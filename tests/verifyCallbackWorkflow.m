function evidence = verifyCallbackWorkflow(outputDirectory)
% verifyCallbackWorkflow Exercise visible mixed-source callback editing and lifecycle cleanup.
%   This developer-only verification uses native context-menu gestures and exports
%   popup images for visual inspection. Input apps and their handlers are not run.
arguments (Input)
    outputDirectory (1, 1) string
end
arguments (Output)
    evidence (1, 1) struct
end

% Clear the marker before exercising source analysis and Safe Preview.
evalin("base", "clear macdCallbackWorkflowSentinel");

% Build a nested fixture with shared handlers, an anonymous binding, and ordinary controls.
registry = macd.model.ComponentRegistry.createDefault();
[source, leftName, rightName] = mixedFixture(registry);
path = string(tempname) + ".m";
fileCleanup = onCleanup(@() delete(path));
macd.source.SourceWriter.write(path, source, "CRLF");
service = macd.ui.DocumentLifecycleService(struct( ...
    "RequestOpenPathFcn", @() deal(true, path), ...
    "RequestNewClassNameFcn", @() deal(true, "WorkflowReplacement"), ...
    "ConfirmUnsavedChangesFcn", @() "Discard", ...
    "ConfirmReloadConflictFcn", @() "Discard"));
app = yamada(service);
appCleanup = onCleanup(@() delete(app));
window = findall(0, "Type", "figure", "Tag", "macd-yamada-editor");
open = findall(window, "Type", "uimenu", "Text", "&Open...");
open.MenuSelectedFcn(open, []);
tree = findall(window, "Type", "uitree");
nodes = findall(tree, "Type", "uitreenode");
for node = nodes(:)', expand(node); end
drawnow;
% Actual F5 works with both Hierarchy and Inspector focus.
nativeReload(app, window, findall(window, "Type", "uitree"));
fields = findall(window, "Type", "uieditfield");
assert(~isempty(fields));
nativeReload(app, window, fields(1));

tree = findall(window, "Type", "uitree");
nodes = findall(tree, "Type", "uitreenode");
for node = nodes(:)', expand(node); end
test = matlab.uitest.TestCase.forInteractiveUse;
selected = app.SelectedComponentId;

% Native right-click must leave selection untouched and show both actions disabled for sharing.
left = app.Document.getComponentByName(leftName);
popup = openPopup(test, tree, left.Id);
add = findall(popup, "Tag", "macd-callback-add", "UserData", "ButtonPushedFcn");
remove = findall(popup, "Tag", "macd-callback-delete", "UserData", "ButtonPushedFcn");
assert(string(add.Enable) == "off" && string(remove.Enable) == "off");
assert(app.SelectedComponentId == selected);
exportapp(popup, fullfile(outputDirectory, "callback-shared-popup.png"));
close(popup);

% Anonymous bindings are visible but do not permit either mutation action.
drop = app.Document.Components([app.Document.Components.Factory] == "uidropdown");
popup = openPopup(test, tree, drop.Id);
add = findall(popup, "Tag", "macd-callback-add", "UserData", "ValueChangedFcn");
remove = findall(popup, "Tag", "macd-callback-delete", "UserData", "ValueChangedFcn");
assert(string(add.Enable) == "off" && string(remove.Enable) == "off");
close(popup);

% A root's complete catalog list exercises scrolling and immediate atomic source changes.
popup = openPopup(test, tree, app.Document.RootComponentId);
rows = findall(popup, "Tag", "macd-callback-add");
assert(numel(rows) == numel(registry.getEffectiveCallbacks("uifigure")));
grids = findall(popup, "Type", "uigridlayout");
assert(any(arrayfun(@(grid) string(grid.Scrollable) == "on", grids)));
exportapp(popup, fullfile(outputDirectory, "callback-root-popup.png"));
clickAction(popup, "Add", "SizeChangedFcn");
assert(contains(app.Document.GeneratedText, "SizeChangedFcn = createCallbackFcn"));
clickAction(popup, "Delete", "SizeChangedFcn");
assert(~contains(app.Document.GeneratedText, "SizeChangedFcn = createCallbackFcn"));

% Deleting the actual target closes its popup and undo restores the component record.
close(popup);
nodes = findall(tree, "Type", "uitreenode");
leftNode = nodes(arrayfun(@(node) string(node.NodeData) == left.Id, nodes));
tree.SelectedNodes = leftNode;
tree.SelectionChangedFcn(tree, struct("SelectedNodes", leftNode));
popup = openPopup(test, tree, left.Id);
removeComponent = findall(window, "Type", "uimenu", "Text", "&Delete");
removeComponent.MenuSelectedFcn(removeComponent, []);
assert(~isvalid(popup));
assert(isempty(app.Document.getComponent(left.Id)));
undo = findall(window, "Type", "uimenu", "Text", "&Undo");
undo.MenuSelectedFcn(undo, []);
assert(~isempty(app.Document.getComponent(left.Id)));
tree = findall(window, "Type", "uitree");
popup = openPopup(test, tree, app.Document.RootComponentId);
undo = findall(window, "Type", "uimenu", "Text", "&Undo");
undo.MenuSelectedFcn(undo, []);
assert(contains(app.Document.GeneratedText, "SizeChangedFcn = createCallbackFcn"));
redo = findall(window, "Type", "uimenu", "Text", "&Redo");
redo.MenuSelectedFcn(redo, []);
assert(~contains(app.Document.GeneratedText, "SizeChangedFcn = createCallbackFcn"));

% Reload externally saved method bodies through F5 while the modal popup has focus.
clickAction(popup, "Add", "SizeChangedFcn");
saved = replace(app.Document.GeneratedText, "% Add callback behavior here.", ...
    "disp('macdReloadedBody');");
macd.source.SourceWriter.write(path, saved, "CRLF");
popup.WindowKeyPressFcn(popup, struct("Key", "f5", "Modifier", {{}}));
assert(~isvalid(popup));
assert(contains(app.Document.OriginalText, "macdReloadedBody"));
assert(~app.Document.canUndo() && ~app.Document.IsDirty);
tree = findall(window, "Type", "uitree");
popup = openPopup(test, tree, app.Document.RootComponentId);
clickAction(popup, "Delete", "SizeChangedFcn");
assert(~contains(app.Document.GeneratedText, "macdReloadedBody"));
undo.MenuSelectedFcn(undo, []);
assert(contains(app.Document.GeneratedText, "macdReloadedBody"));

% Preserve selection through unrelated external changes and block newly shared handlers.
close(popup);
selectComponent(window, app.Document.getComponentByName(leftName).Id);
states = macd.source.CallbackSourceAnalyzer.analyze(app.Document, app.Document.RootComponentId, registry);
handler = states([states.Name] == "SizeChangedFcn").HandlerName;
saved = app.Document.GeneratedText;
saved = replace(saved, 'app.UIFigure.Visible = "on";', ...
    "app.UIFigure.WindowKeyPressFcn = createCallbackFcn(app, @" + handler + ", true);" + newline + ...
    '        app.UIFigure.Visible = "on";');
saved = saved + join(repmat("% External long-source verification", 2000, 1), newline) + newline;
macd.source.SourceWriter.write(path, saved, "CRLF");
reload = findall(window, "Tag", "macd-reload-source");
reload.MenuSelectedFcn(reload, []);
assert(app.Document.getComponent(app.SelectedComponentId).Name == leftName);
states = macd.source.CallbackSourceAnalyzer.analyze(app.Document, app.Document.RootComponentId, registry);
assert(states([states.Name] == "SizeChangedFcn").State == "unsupported");
assert(contains(app.Document.OriginalText, "macdReloadedBody"));

% Renaming the active component externally falls back to the root and clears old spans/history.
saved = regexprep(saved, "(?<!\w)" + leftName + "(?!\w)", "ExternallyRenamedButton");
macd.source.SourceWriter.write(path, saved, "CRLF");
reload.MenuSelectedFcn(reload, []);
assert(app.SelectedComponentId == app.Document.RootComponentId);
assert(isempty(app.Document.getComponentByName(leftName)));
assert(~isempty(app.Document.getComponentByName("ExternallyRenamedButton")));
assert(~app.Document.canUndo());

% Removing the selected component externally and repeated reloads must leave no stale target.
selectComponent(window, app.Document.getComponentByName("ExternallyRenamedButton").Id);
replacement = macd.model.NewAppFactory.createEmpty("MixedCallbackFixture", registry);
saved = macd.source.RoundTripGenerator(registry).generate(replacement);
macd.source.SourceWriter.write(path, saved, "CRLF");
for repetition = 1:3
    reload.MenuSelectedFcn(reload, []);
    assert(app.SelectedComponentId == app.Document.RootComponentId);
    assert(isscalar(app.Document.Components) && ~app.Document.canUndo());
end

% Further callback changes can be saved and reopened after source replacement.
tree = findall(window, "Type", "uitree");
popup = openPopup(test, tree, app.Document.RootComponentId);
clickAction(popup, "Add", "SizeChangedFcn");
save = findall(window, "Type", "uimenu", "Text", "&Save");
save.MenuSelectedFcn(save, []);
assert(~app.Document.IsDirty);
assert(contains(string(fileread(path)), "SizeChangedFcn = createCallbackFcn"));

% Open and New must dispose popup targets; repeated opens must not accumulate dialogs.
open.MenuSelectedFcn(open, []);
assert(~isvalid(popup));
tree = findall(window, "Type", "uitree");
for repetition = 1:3
    popup = openPopup(test, tree, app.Document.RootComponentId);
    assert(isscalar(findall(0, "Tag", "macd-callback-manager")));
    close(popup);
end
popup = openPopup(test, tree, app.Document.RootComponentId);
new = findall(window, "Type", "uimenu", "Text", "&New");
new.MenuSelectedFcn(new, []);
assert(~isvalid(popup));
assert(app.Document.ClassName == "WorkflowReplacement");
assert(evalin("base", "exist('macdCallbackWorkflowSentinel', 'var')") == 0);

evidence = struct("SharedComponent", leftName, "SecondSharedComponent", rightName, ...
    "RootCallbackCount", numel(rows), "NativeSelectionPreserved", true, ...
    "SourceHistoryVerified", true, "LifecycleVerified", true, ...
    "AnonymousBindingBlocked", true, "TargetDeletionVerified", true, ...
    "SafePreviewCallbacksInert", true, "ExternalBodyReloadVerified", true, ...
    "ReloadSelectionVerified", true, "ExternalSharingBlocked", true, ...
    "LongSourceAndRepeatedReloadVerified", true, "PostReloadSaveReopenVerified", true, ...
    "HierarchyAndInspectorNativeF5Verified", true);
disp(evidence);
end

function nativeReload(app, window, target)
% nativeReload Verify an actual F5 while a selected editor control owns keyboard focus.
arguments (Input)
    app (1, 1) yamada
    window (1, 1) matlab.ui.Figure
    target
end
previous = app.Document;
focus(window);
focus(target);
drawnow;
windows = matlab.internal.webwindowmanager.instance.findAllWebwindows();
owned = windows(arrayfun(@(candidate) string(candidate.Title) == string(window.Name), windows));
assert(isscalar(owned));
owned.bringToFront();
titlePath = string(tempname) + ".txt";
titleCleanup = onCleanup(@() delete(titlePath));
macd.source.SourceWriter.write(titlePath, string(window.Name), "LF");
helper = fullfile(fileparts(mfilename("fullpath")), "focusVerificationWindow.ps1");
[status, message] = system("powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ + ...
    helper + """ -TitleFile """ + titlePath + """ -OwnerProcessId " + feature("getpid"));
assert(status == 0, "macd:CallbackWorkflow:ActivateFailed", "%s", message);
focus(window);
focus(target);
started = tic;
while ~(owned.isFocused && owned.isWindowActive) && toc(started) < 10, drawnow; end
assert(owned.isFocused && owned.isWindowActive, ...
    "macd:CallbackWorkflow:FocusUnavailable", ...
    "Expected active editor: focused=%d, active=%d.", owned.isFocused, owned.isWindowActive);
robot = javaObject("java.awt.Robot");
robot.keyPress(116);
robot.keyRelease(116);
started = tic;
while app.Document == previous && toc(started) < 10, drawnow; end
assert(app.Document ~= previous && ~app.Document.IsDirty && ~app.Document.canUndo());
end

function selectComponent(window, componentId)
% selectComponent Select a live hierarchy node through the editor selection binding.
arguments (Input)
    window (1, 1) matlab.ui.Figure
    componentId (1, 1) string
end
tree = findall(window, "Type", "uitree");
nodes = findall(tree, "Type", "uitreenode");
node = nodes(arrayfun(@(candidate) string(candidate.NodeData) == componentId, nodes));
tree.SelectedNodes = node;
tree.SelectionChangedFcn(tree, struct("SelectedNodes", node));
drawnow;
end

function [source, leftName, rightName] = mixedFixture(registry)
% mixedFixture Build source-only nested controls with deliberately unsupported callback forms.
arguments (Input)
    registry (1, 1) macd.model.ComponentRegistry
end
arguments (Output)
    source (1, 1) string
    leftName (1, 1) string
    rightName (1, 1) string
end
document = macd.model.NewAppFactory.createEmpty("MixedCallbackFixture", registry);
panel = document.insertComponent(registry, "uipanel", document.RootComponentId);
grid = document.insertComponent(registry, "uigridlayout", panel.Id);
left = document.insertComponent(registry, "uibutton", grid.Id);
right = document.insertComponent(registry, "uibutton", grid.Id);
drop = document.insertComponent(registry, "uidropdown", grid.Id);
document.insertComponent(registry, "uitable", grid.Id);
document.insertComponent(registry, "uitextarea", grid.Id);
document.applyCallbackAction(left.Id, "ButtonPushedFcn", "Add", registry);
leftHandler = document.CallbackEdits(end).HandlerName;
document.applyCallbackAction(right.Id, "ButtonPushedFcn", "Add", registry);
rightHandler = document.CallbackEdits(end).HandlerName;
document.applyCallbackAction(drop.Id, "ValueChangedFcn", "Add", registry);
dropHandler = document.CallbackEdits(end).HandlerName;
source = macd.source.RoundTripGenerator(registry).generate(document);
source = replace(source, "% Add callback behavior here.", ...
    "assignin('base','macdCallbackWorkflowSentinel',true);");
source = replace(source, "@" + rightHandler + ", true", "@" + leftHandler + ", true");
source = replace(source, "createCallbackFcn(app, @" + dropHandler + ", true)", ...
    "@(src,event) disp(event)");
leftName = left.Name;
rightName = right.Name;
end

function popup = openPopup(test, tree, componentId)
% openPopup Open the real editor popup through a native context-menu gesture.
arguments (Input)
    test (1, 1) matlab.uitest.TestCase
    tree (1, 1) matlab.ui.container.Tree
    componentId (1, 1) string
end
arguments (Output)
    popup (1, 1) matlab.ui.Figure
end
nodes = findall(tree, "Type", "uitreenode");
node = nodes(arrayfun(@(candidate) string(candidate.NodeData) == componentId, nodes));
item = findall(tree.ContextMenu, "Tag", "macd-manage-callbacks");
test.chooseContextMenu(node, item);
popup = findall(0, "Tag", "macd-callback-manager");
drawnow;
test.hover(popup, [10 10]);
windows = matlab.internal.webwindowmanager.instance.findAllWebwindows();
owned = windows(arrayfun(@(candidate) string(candidate.Title) == string(popup.Name), windows));
labels = findall(popup, "Type", "uilabel");
labels = labels(arrayfun(@(label) label.Parent == gridsForRows(popup) && label.Layout.Row <= 3, labels));
started = tic;
ready = false;
while ~ready && toc(started) < 10
    drawnow;
    rendered = string(jsondecode(owned.executeJS("document.body.innerText")));
    ready = true;
    for label = labels(:)'
        ready = ready && contains(rendered, string(label.Text));
    end
end
assert(ready, "macd:CallbackWorkflow:LabelsNotReady", "Callback names must be visibly rendered before capture.");
end

function grid = gridsForRows(popup)
% gridsForRows Return the scrollable callback-row grid for visible-label verification.
arguments (Input)
    popup (1, 1) matlab.ui.Figure
end
arguments (Output)
    grid (1, 1) matlab.ui.container.GridLayout
end
grids = findall(popup, "Type", "uigridlayout");
grid = grids(arrayfun(@(candidate) string(candidate.Scrollable) == "on", grids));
end

function clickAction(popup, action, name)
% clickAction Dispatch one bound immediate action in the native callback popup.
arguments (Input)
    popup (1, 1) matlab.ui.Figure
    action (1, 1) string
    name (1, 1) string
end
button = findall(popup, "Tag", "macd-callback-" + lower(action), "UserData", name);
button.ButtonPushedFcn(button, []);
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
