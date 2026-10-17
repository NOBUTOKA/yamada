function results = runYamadaPerformance(options)
% runYamadaPerformance Measure real editor callbacks and save every completed sample.
%   Use runYamadaPerformance.ps1 for independent process timeout supervision.
arguments (Input)
    options.OutputFolder (1, 1) string = fullfile(pwd, "testResults", "performance")
    options.Case (1, 1) string {mustBeMember(options.Case, ...
        ["absolute", "flatgrid", "nestedgrid", "gallery", "navigation"])} = "absolute"
    options.ComponentCount (1, 1) double {mustBeInteger, mustBePositive} = 12
    options.Samples (1, 1) double {mustBeInteger, mustBePositive} = 4
    options.Profile (1, 1) logical = false
    options.RenderAck (1, 1) logical = true
end
arguments (Output)
    results (1, :) struct
end

% Keep tests and factories on the path when MATLAB changes the current folder.
projectRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(projectRoot);
if ~isfolder(options.OutputFolder), mkdir(options.OutputFolder); end
progress = fullfile(options.OutputFolder, "progress.jsonl");
publishProgress(progress, "start", "fixture");
registry = macd.model.ComponentRegistry.createDefault();
fixture = makeFixture(projectRoot, registry, options);
service = macd.ui.DocumentLifecycleService(struct("RequestOpenPathFcn", @() deal(true, fixture)));
results = struct("action", {}, "sample", {}, "callbackSeconds", {}, "settledSeconds", {});
started = tic;
app = yamada(service);
cleanup = onCleanup(@() delete(app));
figure = findall(0, "Type", "figure", "Tag", "macd-yamada-editor");
setappdata(figure, "macdPerformanceMeasurement", options.RenderAck);
menus = findall(figure, "Type", "uimenu");
open = menus(erase(string({menus.Text}), "&") == "Open...");
results = measure(results, "startup", 1, toc(started), toc(started));
publishProgress(progress, "start", "open");
started = tic;
open.MenuSelectedFcn(open, struct());
callback = toc(started);
settle(figure, options.RenderAck);
results = measure(results, "open", 1, callback, toc(started));
persist(options, results);
publishProgress(progress, "complete", "open");

% Exercise identical controls across separate parents whenever available.
labels = app.Document.Components([app.Document.Components.Factory] == "uilabel");
assert(numel(labels) >= 2, "The benchmark requires two label targets.");
ids = [labels(1).Id, labels(ceil(numel(labels) / 2)).Id];
for index = 1:options.Samples
    publishProgress(progress, "start", "selection");
    started = tic;
    selectId(figure, ids(1 + mod(index, 2)));
    callback = toc(started);
    settle(figure, options.RenderAck);
    results = measure(results, "selection", index, callback, toc(started));
    persist(options, results);
    publishProgress(progress, "complete", "selection");
end
for index = 1:options.Samples
    publishProgress(progress, "start", "property");
    started = tic;
    commitFontSize(figure, 12 + index);
    callback = toc(started);
    settle(figure, options.RenderAck);
    assert(app.Document.getComponent(app.SelectedComponentId).getProperty("FontSize").LiteralValue == 12 + index);
    results = measure(results, "property", index, callback, toc(started));
    persist(options, results);
    publishProgress(progress, "complete", "property");
end
if options.Profile
    publishProgress(progress, "start", "profile");
    profile clear; profile on;
    selectId(figure, ids(1 + (app.SelectedComponentId == ids(1))));
    settle(figure, options.RenderAck);
    profile off;
    profileData = profile("info");
    save(fullfile(options.OutputFolder, "profile.mat"), "profileData");
    persist(options, results);
end
publishProgress(progress, "complete", "fixture");
end

function fixture = makeFixture(projectRoot, registry, options)
% makeFixture Generate matched layouts or use a preserved product fixture.
arguments (Input)
    projectRoot (1, 1) string
    registry (1, 1) macd.model.ComponentRegistry
    options (1, 1) struct
end
arguments (Output)
    fixture (1, 1) string
end
if options.Case == "gallery"
    fixture = fullfile(projectRoot, "tests", "fixtures", "ControlGalleryApp.m");
    return
elseif options.Case == "navigation"
    fixture = fullfile(projectRoot, "tests", "fixtures", "NavigationDataApp.m");
    return
end
document = macd.model.NewAppFactory.createEmpty("PerformanceFixture", registry);
parentId = document.RootComponentId;
if options.Case == "nestedgrid"
    outer = document.insertComponent(registry, "uigridlayout", parentId);
    outer.setProperty("RowHeight", {"1x"});
    outer.setProperty("ColumnWidth", {"1x", "1x", "1x"});
    parentId = outer.Id;
end
perGroup = ceil(options.ComponentCount / 3);
for group = 1:3
    panel = document.insertComponent(registry, "uipanel", parentId);
    if options.Case == "nestedgrid"
        panel.setProperty("Layout.Row", 1);
        panel.setProperty("Layout.Column", group);
    else
        panel.setProperty("Position", [10 + (group - 1) * 205, 30, 195, 400]);
    end
    target = panel.Id;
    if options.Case ~= "absolute"
        grid = document.insertComponent(registry, "uigridlayout", target);
        grid.setProperty("RowHeight", repmat({"1x"}, 1, ceil(perGroup / 2)));
        grid.setProperty("ColumnWidth", {"1x", "1x"});
        target = grid.Id;
    end
    for index = 1:perGroup
        number = (group - 1) * perGroup + index;
        if number > options.ComponentCount, break, end
        label = document.insertComponent(registry, "uilabel", target);
        label.setProperty("Text", "Label " + number);
        if options.Case == "absolute"
            label.setProperty("Position", [10 + 80 * mod(index - 1, 2), 300 - 25 * floor((index - 1) / 2), 75, 22]);
        else
            label.setProperty("Layout.Row", 1 + floor((index - 1) / 2));
            label.setProperty("Layout.Column", 1 + mod(index - 1, 2));
        end
    end
end
[source, diagnostics] = macd.source.NewAppGenerator(registry).generate(document);
assert(strlength(source) > 0, strjoin(string({diagnostics.Message}), newline));
fixture = fullfile(options.OutputFolder, "PerformanceFixture.m");
macd.source.SourceWriter.write(fixture, source, "CRLF");
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

function commitFontSize(figure, value)
% commitFontSize Commit an actual numeric Inspector edit.
arguments (Input)
    figure (1, 1) matlab.ui.Figure
    value (1, 1) double
end
labels = findall(figure, "Tag", "macd-inspector-property-label");
label = labels(string({labels.Text}) == "FontSize");
editor = findall(label.Parent, "Tag", "macd-inspector-property-editor");
if isa(editor, "matlab.ui.control.EditField")
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
    active = ~isempty(timers) && any(string({timers.Running}) == "on");
    overlay = findall(figure, "Tag", "macd-interaction-overlay");
    acknowledged = ~renderAck || (~isempty(overlay) && ...
        isappdata(figure, "macdRenderedRevision") && ...
        isequal(getappdata(figure, "macdRenderedRevision"), overlay.Data.gridEditor.revision));
    if ~active && acknowledged, return, end
    assert(toc(started) < 30, "Performance measurement did not settle within 30 seconds.");
    pause(0.01);
end
end

function results = measure(results, action, sample, callback, settled)
% measure Append one completed measurement without including profiler overhead.
arguments (Input)
    results (1, :) struct
    action (1, 1) string
    sample (1, 1) double
    callback (1, 1) double
    settled (1, 1) double
end
arguments (Output)
    results (1, :) struct
end
results(end + 1) = struct("action", action, "sample", sample, ...
    "callbackSeconds", callback, "settledSeconds", settled);
end

function persist(options, results)
% persist Save all completed samples after each operation.
arguments (Input)
    options (1, 1) struct
    results (1, :) struct
end
fid = fopen(fullfile(options.OutputFolder, "measurements.json"), "w", "n", "UTF-8");
assert(fid >= 0, "Cannot write performance measurements.");
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, "%s", jsonencode(struct("matlab", version, "case", options.Case, ...
    "componentCount", options.ComponentCount, "renderAck", options.RenderAck, "samples", results)));
end

function publishProgress(path, phase, action)
% publishProgress Flush operation boundaries for the independent watchdog.
arguments (Input)
    path (1, 1) string
    phase (1, 1) string
    action (1, 1) string
end
fid = fopen(path, "a", "n", "UTF-8");
assert(fid >= 0, "Cannot write performance progress.");
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, "%s\n", jsonencode(struct("phase", phase, "action", action, ...
    "timestamp", posixtime(datetime("now", "TimeZone", "UTC")))));
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
