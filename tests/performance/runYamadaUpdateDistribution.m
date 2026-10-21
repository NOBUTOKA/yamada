function results = runYamadaUpdateDistribution(options)
% runYamadaUpdateDistribution Trace real edits, additions, geometry publication, and render acknowledgement.
%   The production editor is unchanged. All fixtures are synthetic handle-based source.
arguments (Input)
    options.OutputFolder (1, 1) string
    options.Case (1, 1) string {mustBeMember(options.Case, ["absolute", "flatgrid", "nestedgrid"])} = "nestedgrid"
    options.ComponentCount (1, 1) double {mustBeInteger, mustBePositive} = 12
    options.SurfaceHeight (1, 1) double {mustBeGreaterThanOrEqual(options.SurfaceHeight, 200)} = 650
    options.NestedDepth (1, 1) double {mustBeInteger, mustBeGreaterThanOrEqual(options.NestedDepth, 2)} = 8
    options.Samples (1, 1) double {mustBeInteger, mustBeNonnegative} = 12
    options.Additions (1, 1) double {mustBeInteger, mustBeNonnegative} = 4
    options.ExplicitValues (1, 1) logical = true
    options.ParentEachAddition (1, 1) logical = true
    options.AlternatingValueChanges (1, 1) double {mustBeInteger, mustBeNonnegative} = 0
    options.AlternatingTargetCount (1, 1) double {mustBeInteger, mustBePositive} = 12
    options.Comparisons (1, 1) logical = true
    options.Fit (1, 1) logical = true
    options.Profile (1, 1) logical = false
    options.ProfileParentSelection (1, 1) logical = false
    options.Trace (1, 1) logical = false
end
arguments (Output)
    results (1, :) struct
end
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(root);
if ~isfolder(options.OutputFolder), mkdir(options.OutputFolder); end
fixture = makeUpdateFixture(options);
service = macd.ui.DocumentLifecycleService(struct("RequestOpenPathFcn", @() deal(true, fixture), ...
    "ConfirmUnsavedChangesFcn", @() "Discard"));
results = struct("action", {}, "index", {}, "callbackSeconds", {}, "settledSeconds", {}, ...
    "nativeObjects", {}, "timers", {}, "history", {}, "pendingValueOwners", {}, "status", {}, "geometryAvailable", {}, "reason", {}, "layoutPolls", {}, "events", {});
startupClock = tic;
app = yamada(service);
startupSeconds = toc(startupClock);
cleanup = onCleanup(@() delete(app));
figure = findall(0, "Tag", "macd-yamada-editor");
setappdata(figure, "macdPerformanceMeasurement", true);
setappdata(figure, "distributionEvents", struct("seconds", {}, "revision", {}, "available", {}, "reason", {}, "activeGridId", {}));
probe = timer.empty;
if options.Trace
    probe = timer("ExecutionMode", "fixedSpacing", "Period", 0.05, ...
        "Tag", "yamada-distribution-probe", "TimerFcn", @(~, ~) recordOverlay(figure));
    probeCleanup = onCleanup(@() deleteProbe(probe));
    start(probe);
end
menus = findall(figure, "Type", "uimenu");
open = menus(erase(string({menus.Text}), "&") == "Open...");
runAction("open", 1, @() open.MenuSelectedFcn(open, struct()), false);
target = app.Document.getComponentByName("Field1");
label = app.Document.getComponentByName("ComparisonLabel");
runAction("selection-value", 1, @() selectId(figure, target.Id), false);
for index = 1:options.Samples
    runAction("Value", index, @() commitProperty(figure, "Value", index + 1), false);
    assert(app.Document.getComponent(target.Id).getProperty("Value").LiteralValue == index + 1);
end
if options.Profile && options.Samples > 0
    runAction("profile-Value", 1, @() commitProperty(figure, "Value", options.Samples + 2), true);
end
% Grow the number of modified owners without changing the component count.
for index = 1:options.AlternatingValueChanges
    ownerCount = min(options.AlternatingTargetCount, options.ComponentCount);
    current = app.Document.getComponentByName("Field" + (1 + mod(index - 1, ownerCount)));
    runAction("selection-alternating-Value", index, @() selectId(figure, current.Id), false);
    requested = 2 + floor((index - 1) / ownerCount);
    runAction("alternating-Value", index, @() commitProperty(figure, "Value", requested), false);
    assert(recordedNumericValue(app.Document.getComponent(current.Id)) == requested);
end
if options.Profile && options.AlternatingValueChanges > 0
    selectId(figure, target.Id); settleUpdate(figure);
    requested = 2 + ceil(options.AlternatingValueChanges / min(options.AlternatingTargetCount, options.ComponentCount));
    runAction("profile-alternating-Value", 1, @() commitProperty(figure, "Value", requested), true);
    assert(recordedNumericValue(app.Document.getComponent(target.Id)) == requested);
end
if options.Comparisons
runAction("selection-label", 1, @() selectId(figure, label.Id), false);
for index = 1:min(options.Samples, 4)
    runAction("FontSize", index, @() commitProperty(figure, "FontSize", 12 + index), false);
end
if options.Profile
    runAction("profile-FontSize", 1, @() commitProperty(figure, "FontSize", 17), true);
end
for index = 1:min(options.Samples, 4)
    runAction("Text", index, @() commitProperty(figure, "Text", "Comparison " + index), false);
    assert(string(app.Document.getComponent(label.Id).getProperty("Text").LiteralValue) == "Comparison " + index);
end
if options.Profile
    runAction("profile-Text", 1, @() commitProperty(figure, "Text", "Profile comparison"), true);
end
end
parentId = target.ParentId;
for index = 1:options.Additions
    if index == 1 || options.ParentEachAddition
        selectionAction = "selection-add-parent";
        if options.ProfileParentSelection, selectionAction = "profile-selection-add-parent"; end
        runAction(selectionAction, index, @() selectId(figure, parentId), options.ProfileParentSelection);
    end
    before = numel(app.Document.Components);
    runAction("add", index, @() addLabel(figure), false);
    assert(numel(app.Document.Components) == before + 1, "The palette addition did not commit.");
end
if options.Profile && options.Additions > 0
    if options.ParentEachAddition, selectId(figure, parentId); settleUpdate(figure); end
    before = numel(app.Document.Components);
    runAction("profile-add", 1, @() addLabel(figure), true);
    assert(numel(app.Document.Components) == before + 1);
end
if options.Additions > 0
    runAction("selection-value-after-add", 1, @() selectId(figure, target.Id), false);
    for index = 1:min(options.Samples, 4)
        value = options.Samples + 10 + index;
        runAction("Value-after-add", index, @() commitProperty(figure, "Value", value), false);
        actual = app.Document.getComponent(target.Id).getProperty("Value").LiteralValue;
        if ~isequaln(actual, value)
            writeUpdateJson(fullfile(options.OutputFolder, "rejected-operation.json"), ...
                struct("action", "Value-after-add", "index", index, "requested", value, "actual", actual, ...
                "status", results(end).status));
            break
        end
    end
end
if options.Profile && options.Samples > 0 && options.Additions > 0
    runAction("profile-Value-after-add", 1, @() commitProperty(figure, "Value", options.Samples + 20), true);
    assert(app.Document.getComponent(target.Id).getProperty("Value").LiteralValue == options.Samples + 20);
end
% Verify emitted edits without timing the final audit as an interactive operation.
registry = macd.model.ComponentRegistry.createDefault();
[source, diagnostics] = macd.source.RoundTripGenerator(registry).generate(app.Document);
assert(~any(string({diagnostics.Severity}) == "error"));
parsed = macd.source.AppSourceParser.parseText(source, registry);
assert(numel(parsed.Components) == numel(app.Document.Components));
for number = 1:options.ComponentCount
    name = "Field" + number;
    assert(recordedNumericValue(parsed.getComponentByName(name)) == ...
        recordedNumericValue(app.Document.getComponentByName(name)));
end
% Check that a delayed native update has not been mistaken for settled geometry.
runAction("idle-observation", 1, @() pause(2), false);
if ~isempty(probe), clear probeCleanup, end
overlay = findall(figure, "Tag", "macd-interaction-overlay");
writeUpdateJson(fullfile(options.OutputFolder, "grid-state.json"), overlay.Data.gridEditor);
writeUpdateJson(fullfile(options.OutputFolder, "measurements.json"), struct("options", options, "startupSeconds", startupSeconds, "samples", results));
clear cleanup

    function runAction(action, index, callback, profiling)
        % runAction Keep wall-clock observations separate from inclusive profiler data.
        publishUpdateProgress(options.OutputFolder, "start", action);
        setappdata(figure, "distributionClock", tic);
        setappdata(figure, "distributionEvents", struct("seconds", {}, "revision", {}, "available", {}, "reason", {}, "activeGridId", {}));
        if profiling, profile clear; profile on; end
        started = tic;
        callback();
        callbackSeconds = toc(started);
        recordOverlay(figure);
        settleUpdate(figure);
        elapsed = toc(started);
        if profiling
            profile off;
            profileData = profile("info");
            save(fullfile(options.OutputFolder, action + ".mat"), "profileData");
            exportUpdateProfile(fullfile(options.OutputFolder, action + ".json"), profileData);
        end
        overlay = findall(figure, "Tag", "macd-interaction-overlay");
        grid = overlay.Data.gridEditor;
        results(end + 1) = struct("action", action, "index", index, "callbackSeconds", callbackSeconds, ...
            "settledSeconds", elapsed, "nativeObjects", numel(findall(figure)), "timers", numel(timerfindall), ...
            "history", app.Document.HistoryIndex, "pendingValueOwners", pendingValueOwners(app.Document), "status", string(findall(figure, "Tag", "macd-status").Text), "geometryAvailable", grid.geometryAvailable, ...
            "reason", string(grid.readOnlyReason), "layoutPolls", layoutPolls(), "events", getappdata(figure, "distributionEvents"));
        writeUpdateJson(fullfile(options.OutputFolder, "measurements.json"), struct("options", options, "startupSeconds", startupSeconds, "samples", results));
        publishUpdateProgress(options.OutputFolder, "complete", action);
    end
end

function recordOverlay(figure)
% recordOverlay Record only value payloads without retaining preview controls or documents.
arguments (Input)
    figure (1, 1) matlab.ui.Figure
end
if ~isappdata(figure, "distributionClock"), return, end
overlay = [];
if isappdata(figure, "distributionOverlay")
    overlay = getappdata(figure, "distributionOverlay");
end
% Reacquire the disposable HTML handle only after a full Preview reconstruction.
if isempty(overlay) || ~isvalid(overlay)
    overlay = findall(figure, "Tag", "macd-interaction-overlay");
    if isempty(overlay), return, end
    setappdata(figure, "distributionOverlay", overlay);
end
data = overlay.Data;
if ~isstruct(data) || ~isfield(data, "gridEditor"), return, end
grid = data.gridEditor;
events = getappdata(figure, "distributionEvents");
if ~isempty(events) && events(end).revision == grid.revision && ...
        events(end).activeGridId == string(grid.activeGridId)
    return
end
events(end + 1) = struct("seconds", toc(getappdata(figure, "distributionClock")), ...
    "revision", grid.revision, "available", grid.geometryAvailable, "reason", string(grid.readOnlyReason), ...
    "activeGridId", string(grid.activeGridId));
setappdata(figure, "distributionEvents", events);
end

function value = recordedNumericValue(component)
% recordedNumericValue Read a fixture's stored scalar or its known numeric default.
arguments (Input)
    component (1, 1) macd.model.ComponentRecord
end
arguments (Output)
    value (1, 1) double
end
entry = component.getProperty("Value");
value = 0;
if ~isempty(entry), value = entry.LiteralValue; end
end

function count = pendingValueOwners(document)
% pendingValueOwners Count numeric Value settings inserted without an original source span.
arguments (Input)
    document (1, 1) macd.model.DocumentModel
end
arguments (Output)
    count (1, 1) double
end
count = 0;
for component = document.Components
    if component.Factory ~= "uieditfield", continue, end
    entry = component.getProperty("Value");
    if ~isempty(entry) && isempty(entry.SourceSpan), count = count + 1; end
end
end

function count = layoutPolls()
% layoutPolls Observe the editor timer without changing callbacks or scheduling.
arguments (Output)
    count (1, 1) double
end
count = 0;
for current = reshape(timerfindall, 1, [])
    if isvalid(current) && isa(current.TimerFcn, "function_handle") && ...
            contains(string(func2str(current.TimerFcn)), "refreshOverlayAfterTabLayout")
        count = double(current.TasksExecuted);
    end
end
end

function deleteProbe(probe)
% deleteProbe Release only the measurement timer owned by this invocation.
arguments (Input)
    probe (1, 1) timer
end
if isvalid(probe), stop(probe); delete(probe); end
end

function settleUpdate(figure)
% settleUpdate Wait up to four minutes for owned editor timers and the published HTML revision.
arguments (Input)
    figure (1, 1) matlab.ui.Figure
end
started = tic;
while true
    drawnow;
    active = false;
    for current = reshape(timerfindall, 1, [])
        try
            if isvalid(current) && string(current.Tag) ~= "yamada-distribution-probe"
                active = active || string(current.Running) == "on";
            end
        catch exception
            if isvalid(current), rethrow(exception), end
        end
    end
    recordOverlay(figure);
    overlay = findall(figure, "Tag", "macd-interaction-overlay");
    acknowledged = isappdata(figure, "macdRenderedRevision") && ...
        isequal(getappdata(figure, "macdRenderedRevision"), overlay.Data.gridEditor.revision);
    if ~active && acknowledged, return, end
    assert(toc(started) < 240, "The update did not settle within 240 seconds.");
    pause(0.01);
end
end

function addLabel(figure)
% addLabel Invoke the normal palette double-click insertion command.
arguments (Input)
    figure (1, 1) matlab.ui.Figure
end
palette = findall(figure, "Type", "uitable");
palette = palette(arrayfun(@(item) ~isempty(item.DoubleClickedFcn), palette));
row = find(string(palette.Data(:, 1)) == "Label", 1);
assert(~isempty(row));
palette.DoubleClickedFcn(palette, struct("InteractionInformation", struct("Row", row)));
end

function fixture = makeUpdateFixture(options)
% makeUpdateFixture Write matched numeric-control fixtures without executing their source.
arguments (Input)
    options (1, 1) struct
end
arguments (Output)
    fixture (1, 1) string
end
properties = ["UIFigure matlab.ui.Figure"; "ComparisonLabel matlab.ui.control.Label"];
body = ["app.UIFigure = uifigure('Visible','off');"; "app.UIFigure.Position = [100 100 1000 " + options.SurfaceHeight + "];"];
parent = "UIFigure";
if options.Case == "nestedgrid"
    for depth = 1:options.NestedDepth - 1
        name = "Outer" + depth;
        properties(end + 1) = name + " matlab.ui.container.GridLayout"; %#ok<AGROW>
        body = [body; "app." + name + " = uigridlayout(app." + parent + ",[1 1]);"; ...
            "app." + name + ".RowHeight = {'1x'};"; "app." + name + ".ColumnWidth = {'1x'};"]; %#ok<AGROW>
        parent = name;
    end
    body(end + 1) = "app." + parent + ".ColumnWidth = {'1x','1x','1x'};";
end
perGroup = ceil(options.ComponentCount / 3);
for group = 1:3
    panel = "Panel" + group;
    properties(end + 1) = panel + " matlab.ui.container.Panel"; %#ok<AGROW>
    body(end + 1) = "app." + panel + " = uipanel(app." + parent + ");"; %#ok<AGROW>
    if options.Case == "nestedgrid"
        body = [body; "app." + panel + ".Layout.Row = 1;"; "app." + panel + ".Layout.Column = " + group + ";"]; %#ok<AGROW>
    else
        body(end + 1) = "app." + panel + ".Position = [" + (10 + 325 * (group - 1)) + " 10 315 " + (options.SurfaceHeight - 40) + "];"; %#ok<AGROW>
    end
    target = panel;
    if options.Case ~= "absolute"
        target = "Grid" + group;
        properties(end + 1) = target + " matlab.ui.container.GridLayout"; %#ok<AGROW>
        rows = ceil(perGroup / 2) + 1;
        heights = repmat("'1x'", 1, rows);
        widths = ["'1x'", "'1x'"];
        if options.Fit
            heights(1:end-1) = "'fit'";
            widths(1) = "'fit'";
        end
        body = [body; "app." + target + " = uigridlayout(app." + panel + ",[" + rows + " 2]);"; ...
            "app." + target + ".RowHeight = {" + strjoin(heights, ",") + "};"; ...
            "app." + target + ".ColumnWidth = {" + strjoin(widths, ",") + "};"]; %#ok<AGROW>
    end
    for index = 1:perGroup
        number = (group - 1) * perGroup + index;
        if number > options.ComponentCount, break, end
        name = "Field" + number;
        properties(end + 1) = name + " matlab.ui.control.NumericEditField"; %#ok<AGROW>
        body(end + 1) = "app." + name + " = uieditfield(app." + target + ",'numeric');"; %#ok<AGROW>
        if options.ExplicitValues, body(end + 1) = "app." + name + ".Value = 1;"; end %#ok<AGROW>
        if options.Case == "absolute"
            body(end + 1) = "app." + name + ".Position = [" + (5 + 150 * mod(index - 1, 2)) + " " + (options.SurfaceHeight - 80 - 25 * floor((index - 1) / 2)) + " 140 22];"; %#ok<AGROW>
        else
            body = [body; "app." + name + ".Layout.Row = " + (1 + floor((index - 1) / 2)) + ";"; ...
                "app." + name + ".Layout.Column = " + (1 + mod(index - 1, 2)) + ";"]; %#ok<AGROW>
        end
    end
    if group == 1
        body = [body; "app.ComparisonLabel = uilabel(app." + target + ");"; "app.ComparisonLabel.Text = 'Comparison';"]; %#ok<AGROW>
        if options.Case ~= "absolute"
            body = [body; "app.ComparisonLabel.Layout.Row = " + (ceil(perGroup / 2) + 1) + ";"; ...
                "app.ComparisonLabel.Layout.Column = [1 2];"]; %#ok<AGROW>
        end
    end
end
source = strjoin(["classdef UpdateDistributionFixture < handle"; "properties"; ...
    properties; "end"; "methods"; "function app = UpdateDistributionFixture"; "createComponents(app);"; ...
    "end"; "function createComponents(app)"; body; "end"; "end"; "end"], sprintf('\r\n'));
fixture = fullfile(options.OutputFolder, "UpdateDistributionFixture.m");
macd.source.SourceWriter.write(fixture, source, "CRLF");
end

function exportUpdateProfile(path, profileData)
% exportUpdateProfile Export inclusive function and child timings without rerunning recorded code.
arguments (Input)
    path (1, 1) string
    profileData (1, 1) struct
end
functions = profileData.FunctionTable;
rows = struct("name", {}, "file", {}, "calls", {}, "totalSeconds", {}, "children", {});
for index = 1:numel(functions)
    current = functions(index);
    children = struct("name", {}, "calls", {}, "totalSeconds", {});
    for edge = reshape(current.Children, 1, [])
        children(end + 1) = struct("name", string(functions(edge.Index).FunctionName), ...
            "calls", edge.NumCalls, "totalSeconds", edge.TotalTime); %#ok<AGROW>
    end
    rows(end + 1) = struct("name", string(current.FunctionName), "file", string(current.FileName), ...
        "calls", current.NumCalls, "totalSeconds", current.TotalTime, "children", children); %#ok<AGROW>
end
writeUpdateJson(path, struct("functions", rows));
end

function writeUpdateJson(path, value)
% writeUpdateJson Persist completed observations after the timed region.
arguments (Input)
    path (1, 1) string
    value (1, 1) struct
end
fid = fopen(path, "w", "n", "UTF-8");
assert(fid >= 0);
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, "%s", jsonencode(value));
end

function publishUpdateProgress(folder, phase, action)
% publishUpdateProgress Flush operation boundaries for independent process supervision.
arguments (Input)
    folder (1, 1) string
    phase (1, 1) string
    action (1, 1) string
end
fid = fopen(fullfile(folder, "progress.jsonl"), "a", "n", "UTF-8");
assert(fid >= 0);
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, "%s\n", jsonencode(struct("phase", phase, "action", action, ...
    "timestamp", posixtime(datetime("now", "TimeZone", "UTC")))));
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
