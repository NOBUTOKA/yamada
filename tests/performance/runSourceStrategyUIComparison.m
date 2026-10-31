function runSourceStrategyUIComparison(layout, mode, count, output, profiled)
% runSourceStrategyUIComparison Compare prototype strategies through actual Inspector and Preview callbacks.
arguments (Input)
    layout (1, 1) string
    mode (1, 1) string
    count (1, 1) double
    output (1, 1) string
    profiled (1, 1) logical = false
end
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(root, fullfile(root, "tests", "performance"));
base = fullfile(root, "testResults", "performance", "source-strategy-20261031");
variants = jsondecode(fileread(fullfile(base, "variants.json")));
addpath(variants.(mode).root, "-begin");
cd(variants.(mode).root);
fixtures = jsondecode(fileread(fullfile(base, "fixtures.json")));
operations = jsondecode(fileread(fullfile(base, "operations.json")));
source = string(fileread(fixtures.(layout).path));
registry = macd.model.ComponentRegistry.createDefault();
engine = SourceStrategyExperiment(source, mode, registry);
service = macd.ui.DocumentLifecycleService(struct("RequestOpenPathFcn", ...
    @() deal(true, string(fixtures.(layout).path)), "ConfirmUnsavedChangesFcn", @() "Discard"));
app = yamada(service);
cleanup = onCleanup(@() delete(app));
figure = findall(0, "Tag", "macd-yamada-editor");
setappdata(figure, "macdPerformanceMeasurement", true);
menus = findall(figure, "Type", "uimenu");
open = menus(erase(string({menus.Text}), "&") == "Open...");
open.MenuSelectedFcn(open, struct());
settle(figure, true);
assert(string(which("yamada")) == fullfile(string(variants.(mode).root), "yamada.m"));
engine.attach(app.Document);
setappdata(figure, "SourceStrategyExperiment", engine);
setappdata(figure, "SourceStrategySavePath", fullfile(output, "UpdateDistributionFixture.m"));
samples = struct("Index", {}, "Name", {}, "Path", {}, "Existing", {}, ...
    "Seconds", {}, "SelectionSeconds", {}, "CallbackSeconds", {});
profiles = cell(1, count);
if profiled, profile clear; end
for index = 1:count
    operation = operations(index);
    value = operation.value;
    if ischar(value), value = string(value); end
    component = app.Document.getComponentByName(string(operation.name));
    assert(~isempty(component.getProperty(string(operation.path))) == operation.existing);
    clock = tic;
    selectId(figure, component.Id);
    settle(figure, true);
    selection = toc(clock);
    if profiled, profile clear; profile on; end
    clock = tic;
    commitProperty(figure, string(operation.path), value);
    callback = toc(clock);
    settle(figure, true);
    elapsed = toc(clock);
    if profiled, profile off; profiles{index} = profile("info"); end
    assert(app.Document.HistoryIndex == index);
    entry = component.getProperty(string(operation.path));
    assert(~isempty(entry) && isequaln(entry.LiteralValue, value));
    samples(end + 1) = struct("Index", index, "Name", string(operation.name), ...
        "Path", string(operation.path), "Existing", operation.existing, "Seconds", elapsed, ...
        "SelectionSeconds", selection, "CallbackSeconds", callback); %#ok<AGROW>
    writeJson(fullfile(output, "progress.json"), struct("phase", "editing", "index", index));
end
if profiled, writeSourceStrategyProfile(output, "edits", profiles); profile clear; end
writeJson(fullfile(output, "progress.json"), struct("phase", "saving", "index", count));
menus = findall(figure, "Type", "uimenu");
saveMenu = menus(erase(string({menus.Text}), "&") == "Save");
assert(isscalar(saveMenu));
if profiled, profile on; end
clock = tic;
saveMenu.MenuSelectedFcn(saveMenu, struct());
settle(figure, true);
saveSeconds = toc(clock);
if profiled, profile off; writeSourceStrategyProfile(output, "save"); end
assert(~app.Document.IsDirty && isfile(fullfile(output, "UpdateDistributionFixture.m")));
text = string(fileread(fullfile(output, "UpdateDistributionFixture.m")));
parsed = macd.source.AppSourceParser.parseText(text, registry);
for request = engine.Requests
    entry = parsed.getComponentByName(request.Name).getProperty(request.Path);
    assert(~isempty(entry) && isequaln(entry.LiteralValue, request.Value));
end
if mode == "eager"
    for component = parsed.Components
        settingIndex = 0;
        for setting = component.Settings
            settingIndex = settingIndex + 1;
            key = "occurrence:" + component.Name + ":" + settingIndex;
            spans = engine.Locations(string({engine.Locations.Key}) == key);
            assert(isscalar(spans) && spans.Start == setting.ValueSpan.StartOffset && spans.End == setting.ValueSpan.EndOffset);
        end
    end
end
writeJson(fullfile(output, "results.json"), struct("layout", layout, "mode", mode, "count", count, ...
    "profiled", profiled, "samples", samples, "editTotalSeconds", sum([samples.Seconds]), ...
    "selectionTotalSeconds", sum([samples.SelectionSeconds]), "saveSeconds", saveSeconds, ...
    "history", app.Document.HistoryIndex, "locations", numel(engine.Locations), ...
    "sourceCharacters", strlength(text), "matched", numel(engine.Requests), "sourceEngineOnly", false, ...
    "loaded", string(which("yamada"))));
writeJson(fullfile(output, "progress.json"), struct("phase", "complete", "index", count));
end

function writeJson(path, value)
% writeJson Persist progress or measurements outside operation timing intervals.
arguments (Input)
    path (1, 1) string
    value
end
file = fopen(path, "w", "n", "UTF-8");
assert(file >= 0);
cleanup = onCleanup(@() fclose(file));
fprintf(file, "%s", jsonencode(value));
end


function selectId(figure, id)
% selectId Invoke the same callback as a native hierarchy selection.
arguments (Input)
    figure (1, 1) matlab.ui.Figure
    id (1, 1) string
end
tree = findall(figure, "Type", "uitree");
nodes = findall(tree, "Type", "uitreenode");
node = nodes(arrayfun(@(item) string(item.NodeData) == id, nodes));
tree.SelectedNodes = node;
tree.SelectionChangedFcn(tree, struct("SelectedNodes", node));
end

function commitProperty(figure, propertyPath, value)
% commitProperty Commit a numeric or text change through the actual Inspector.
arguments (Input)
    figure (1, 1) matlab.ui.Figure
    propertyPath (1, 1) string
    value
end
labels = findall(figure, "Tag", "macd-inspector-property-label");
label = labels(string({labels.Text}) == propertyPath);
editor = findall(label.Parent, "Tag", "macd-inspector-property-editor");
if isa(editor, "matlab.ui.control.EditField") || isa(editor, "matlab.ui.control.TextArea")
    editor.Value = char(string(value));
else
    editor.Value = value;
end
editor.ValueChangedFcn(editor, struct());
end

function settle(figure, renderAck)
% settle Wait for editor layout work and the current HTML rendering notification.
arguments (Input)
    figure (1, 1) matlab.ui.Figure
    renderAck (1, 1) logical
end
started = tic;
while true
    drawnow;
    timers = timerfindall;
    % Layout callbacks may delete timers between enumeration and state access.
    active = false;
    for current = reshape(timers, 1, [])
        try
            if isvalid(current), active = active || string(current.Running) == "on"; end
        catch exception
            if isvalid(current), rethrow(exception), end
        end
    end
    overlay = findall(figure, "Tag", "macd-interaction-overlay");
    acknowledged = ~renderAck || (~isempty(overlay) && ...
        isappdata(figure, "macdRenderedRevision") && ...
        isequal(getappdata(figure, "macdRenderedRevision"), overlay.Data.gridEditor.revision));
    if ~active && acknowledged, return, end
    assert(toc(started) < 600, "Performance measurement did not settle within 600 seconds.");
    pause(0.01);
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
