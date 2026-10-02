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
    "ConfirmUnsavedChangesFcn", @() "Discard"));
app = yamada(service);
appCleanup = onCleanup(@() delete(app));
window = findall(0, "Type", "figure", "Tag", "macd-yamada-editor");
open = findall(window, "Type", "uimenu", "Text", "&Open...");
open.MenuSelectedFcn(open, []);
tree = findall(window, "Type", "uitree");
nodes = findall(tree, "Type", "uitreenode");
for node = nodes(:)', expand(node); end
drawnow;
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
    "SafePreviewCallbacksInert", true);
disp(evidence);
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
