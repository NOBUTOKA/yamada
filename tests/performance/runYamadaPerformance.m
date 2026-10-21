function results = runYamadaPerformance(options)
% runYamadaPerformance Measure real editor callbacks and save every completed sample.
%   Use runYamadaPerformance.ps1 for independent process timeout supervision.
arguments (Input)
    options.OutputFolder (1, 1) string = fullfile(pwd, "testResults", "performance")
    options.Case (1, 1) string {mustBeMember(options.Case, ...
        ["absolute", "flatgrid", "nestedgrid", "gallery", "navigation"])} = "absolute"
    options.ComponentCount (1, 1) double {mustBeInteger, mustBeGreaterThanOrEqual(options.ComponentCount, 2)} = 12
    options.NestedDepth (1, 1) double {mustBeInteger, mustBeGreaterThanOrEqual(options.NestedDepth, 2)} = 2
    options.PropertyPath (1, 1) string {mustBeMember(options.PropertyPath, ["FontSize", "Text"])} = "FontSize"
    options.Samples (1, 1) double {mustBeInteger, mustBePositive} = 4
    options.Profile (1, 1) logical = false
    options.RenderAck (1, 1) logical = true
    options.RepeatedSelections (1, 1) double {mustBeInteger, mustBeNonnegative} = 0
    options.AlternatingSelections (1, 1) double {mustBeInteger, mustBeNonnegative} = 0
    options.DocumentCycles (1, 1) double {mustBeInteger, mustBeNonnegative} = 0
    options.AlternatingPropertyChanges (1, 1) double {mustBeInteger, mustBeNonnegative} = 0
    options.PropertyChanges (1, 1) double {mustBeInteger, mustBeNonnegative} = 0
    options.EnduranceOnly (1, 1) logical = false
end
arguments (Output)
    results (1, :) struct
end

assert(~options.EnduranceOnly || ((~options.Profile || options.AlternatingPropertyChanges > 0) && ...
    options.RepeatedSelections + options.AlternatingSelections + options.DocumentCycles + options.PropertyChanges + options.AlternatingPropertyChanges > 0), ...
    "EnduranceOnly requires retention operations; profiling also requires alternating property changes.");
normalSamples = options.Samples;
if options.EnduranceOnly, normalSamples = 0; end
% Keep tests and factories on the path when MATLAB changes the current folder.
projectRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(projectRoot);
if ~isfolder(options.OutputFolder), mkdir(options.OutputFolder); end
progress = fullfile(options.OutputFolder, "progress.jsonl");
publishProgress(progress, "start", "fixture");
registry = macd.model.ComponentRegistry.createDefault();
fixture = makeFixture(projectRoot, registry, options);
service = macd.ui.DocumentLifecycleService(struct("RequestOpenPathFcn", @() deal(true, fixture), ...
    "ConfirmUnsavedChangesFcn", @() "Discard"));
results = struct("action", {}, "phase", {}, "sample", {}, "callbackSeconds", {}, ...
    "settledSeconds", {}, "nativeObjects", {}, "timers", {}, "payloadBytes", {});
started = tic;
app = yamada(service);
cleanup = onCleanup(@() delete(app));
figure = findall(0, "Type", "figure", "Tag", "macd-yamada-editor");
setappdata(figure, "macdPerformanceMeasurement", options.RenderAck);
menus = findall(figure, "Type", "uimenu");
open = menus(erase(string({menus.Text}), "&") == "Open...");
results = measure(results, "startup", 1, toc(started), toc(started), figure, "first");
persist(options, results);
publishProgress(progress, "start", "open");
started = tic;
open.MenuSelectedFcn(open, struct());
callback = toc(started);
settle(figure, options.RenderAck);
results = measure(results, "open", 1, callback, toc(started), figure, "first");
options.ModelComponents = numel(app.Document.Components);
options.GridCount = sum([app.Document.Components.Factory] == "uigridlayout");
watchDocument(figure, app.Document);
persist(options, results);
publishProgress(progress, "complete", "open");

% Exercise identical controls across separate parents whenever available.
targets = measurementTargets(app.Document, registry, options.PropertyPath);
assert(numel(targets) >= 2, "The benchmark requires two targets supporting the requested property.");
ids = [targets(1).Id, targets(max(2, ceil(numel(targets) / 2))).Id];
for index = 1:normalSamples
    publishProgress(progress, "start", "selection");
    started = tic;
    selectId(figure, ids(1 + mod(index, 2)));
    callback = toc(started);
    settle(figure, options.RenderAck);
    phase = "revisit";
    if index <= 2, phase = "first-target"; end
    results = measure(results, "selection", index, callback, toc(started), figure, phase);
    persist(options, results);
    publishProgress(progress, "complete", "selection");
end
% Separate unchanged selection and warmed revisits from first-target work.
for index = 1:normalSamples
    publishProgress(progress, "start", "same-selection");
    started = tic;
    selectId(figure, app.SelectedComponentId);
    callback = toc(started);
    settle(figure, options.RenderAck);
    results = measure(results, "same-selection", index, callback, toc(started), figure, "same-target");
    persist(options, results);
    publishProgress(progress, "complete", "same-selection");
end
propertySamples = normalSamples;
editable = false;
reason = "";
if propertySamples > 0, [editable, reason] = canCommitProperty(figure, options.PropertyPath); end
if propertySamples > 0 && ~editable
    assert(any(options.Case == ["gallery", "navigation"]), reason);
    propertySamples = 0;
    fid = fopen(fullfile(options.OutputFolder, "excluded-operations.json"), "w", "n", "UTF-8");
    assert(fid >= 0, "Cannot record the read-only fixture boundary.");
    fprintf(fid, "%s", jsonencode(struct("action", "property", "path", options.PropertyPath, "reason", reason)));
    fclose(fid);
end
for index = 1:propertySamples
    publishProgress(progress, "start", "property");
    started = tic;
    value = measurementValue(options.PropertyPath, 12 + index);
    commitProperty(figure, options.PropertyPath, value);
    callback = toc(started);
    settle(figure, options.RenderAck);
    verifyPropertyValue(app.Document, app.SelectedComponentId, options.PropertyPath, value);
    phase = "warm";
    if index == 1, phase = "first"; end
    results = measure(results, "property", index, callback, toc(started), figure, phase);
    persist(options, results);
    publishProgress(progress, "complete", "property");
end
if isappdata(figure, "macdPreviewStatistics")
    fid = fopen(fullfile(options.OutputFolder, "preview-statistics.json"), "w", "n", "UTF-8");
    assert(fid >= 0, "Cannot write preview counters.");
    fprintf(fid, "%s", jsonencode(struct("phase", "after-normal-properties", ...
        "counters", getappdata(figure, "macdPreviewStatistics"))));
    fclose(fid);
end
% Profile the actual repeated edit before changing selection for cold profiles.
if options.Profile && editable && propertySamples >= 2
    profileContext = struct("Phase", "warm-same-component", "PropertyPath", options.PropertyPath, "ComponentId", app.SelectedComponentId, ...
        "Before", app.Document.getComponent(app.SelectedComponentId).getProperty(options.PropertyPath).LiteralValue, ...
        "After", measurementValue(options.PropertyPath, 13 + options.Samples));
    publishProgress(progress, "start", "profile-property-warm");
    profile clear; profile on;
    commitProperty(figure, options.PropertyPath, profileContext.After);
    settle(figure, options.RenderAck);
    profile off;
    profileData = profile("info");
    save(fullfile(options.OutputFolder, "profile-property-warm.mat"), "profileData", "profileContext");
    assert(app.SelectedComponentId == profileContext.ComponentId);
end
if options.Profile
    publishProgress(progress, "start", "profile-selection");
    profile clear; profile on;
    selectId(figure, ids(1 + (app.SelectedComponentId == ids(1))));
    settle(figure, options.RenderAck);
    profile off;
    profileData = profile("info");
    save(fullfile(options.OutputFolder, "profile-selection.mat"), "profileData");
    if editable
        publishProgress(progress, "start", "profile-property");
        profile clear; profile on;
        commitProperty(figure, options.PropertyPath, measurementValue(options.PropertyPath, 13 + options.Samples));
        settle(figure, options.RenderAck);
        profile off;
        profileData = profile("info");
        save(fullfile(options.OutputFolder, "profile-property.mat"), "profileData");
    end
    persist(options, results);
end
% Measure pending additions across two components in the same parent.
if options.AlternatingPropertyChanges > 0
    siblings = targets([targets.ParentId] == targets(1).ParentId);
    assert(numel(siblings) >= 2, "Alternating property changes require two editable siblings.");
    editIds = [siblings(1).Id, siblings(2).Id];
    for index = 1:options.AlternatingPropertyChanges
        publishProgress(progress, "start", "alternating-property");
        started = tic;
        selectId(figure, editIds(1 + mod(index - 1, 2)));
        callback = toc(started);
        settle(figure, options.RenderAck);
        results = measure(results, "alternating-property-selection", index, callback, toc(started), figure, "switch-target");
        [editable, reason] = canCommitProperty(figure, options.PropertyPath);
        assert(editable, reason);
        started = tic;
        value = measurementValue(options.PropertyPath, 13 + mod(index, 5));
        commitProperty(figure, options.PropertyPath, value);
        callback = toc(started);
        settle(figure, options.RenderAck);
        verifyPropertyValue(app.Document, app.SelectedComponentId, options.PropertyPath, value);
        phase = "multiple-pending";
        if index == 1, phase = "first-target"; end
        results = measure(results, "alternating-property", index, callback, toc(started), figure, phase);
        persist(options, results);
        publishProgress(progress, "complete", "alternating-property");
    end
    if options.Profile
        selectId(figure, editIds(1));
        settle(figure, options.RenderAck);
        profileContext = struct("PropertyPath", options.PropertyPath, "ComponentIds", editIds, "SelectedId", app.SelectedComponentId, ...
            "Before", app.Document.getComponent(app.SelectedComponentId).getProperty(options.PropertyPath).LiteralValue, "After", measurementValue(options.PropertyPath, 18));
        publishProgress(progress, "start", "profile-alternating-property");
        profile clear; profile on;
        commitProperty(figure, options.PropertyPath, profileContext.After);
        settle(figure, options.RenderAck);
        profile off; profileData = profile("info");
        save(fullfile(options.OutputFolder, "profile-property-multiple.mat"), "profileData", "profileContext");
    end
end
% Exercise real bounded value changes separately from ordinary latency samples.
if options.PropertyChanges > 0
    selectId(figure, ids(1));
    settle(figure, options.RenderAck);
    [editable, reason] = canCommitProperty(figure, options.PropertyPath);
    assert(editable, reason);
end
for index = 1:options.PropertyChanges
    publishProgress(progress, "start", "retention-property");
    value = measurementValue(options.PropertyPath, 13 + mod(index, 5));
    started = tic;
    commitProperty(figure, options.PropertyPath, value);
    callback = toc(started);
    settle(figure, options.RenderAck);
    verifyPropertyValue(app.Document, app.SelectedComponentId, options.PropertyPath, value);
    phase = "warm";
    if index == 1, phase = "first"; end
    results = measure(results, "retention-property", index, callback, toc(started), figure, phase);
    persist(options, results);
    publishProgress(progress, "complete", "retention-property");
end
% Keep endurance work separate from the latency distribution and normal history.
for index = 1:options.RepeatedSelections
    publishProgress(progress, "start", "retention-selection");
    started = tic;
    selectId(figure, app.SelectedComponentId);
    callback = toc(started);
    settle(figure, options.RenderAck);
    results = measure(results, "retention-selection", index, callback, toc(started), figure, "same-target");
    persist(options, results);
    publishProgress(progress, "complete", "retention-selection");
end
for index = 1:options.AlternatingSelections
    publishProgress(progress, "start", "retention-alternating-selection");
    started = tic;
    selectId(figure, ids(1 + (app.SelectedComponentId == ids(1))));
    callback = toc(started);
    settle(figure, options.RenderAck);
    results = measure(results, "retention-alternating-selection", index, callback, toc(started), figure, "alternating-target");
    persist(options, results);
    publishProgress(progress, "complete", "retention-alternating-selection");
end
for index = 1:options.DocumentCycles
    publishProgress(progress, "start", "document-cycle");
    previousSnapshot = app.Document.Metadata.SourceSnapshotId;
    started = tic;
    open.MenuSelectedFcn(open, struct());
    callback = toc(started);
    settle(figure, options.RenderAck);
    assert(app.Document.Metadata.SourceSnapshotId ~= previousSnapshot && ~app.Document.IsDirty, ...
        "The benchmark document transition was not completed.");
    watchDocument(figure, app.Document);
    results = measure(results, "document-cycle", index, callback, toc(started), figure, "reopen");
    persist(options, results);
    publishProgress(progress, "complete", "document-cycle");
end
if isappdata(figure, "macdDocumentLifetime")
    lifetime = getappdata(figure, "macdDocumentLifetime");
    lifetime.active = app.Document.Metadata.SourceSnapshotId;
    fid = fopen(fullfile(options.OutputFolder, "document-lifetime.json"), "w", "n", "UTF-8");
    assert(fid >= 0, "Cannot record document lifetime.");
    fprintf(fid, "%s", jsonencode(lifetime));
    fclose(fid);
end
publishProgress(progress, "complete", "fixture");
end

function watchDocument(figure, document)
% watchDocument Observe destruction without retaining documents or listener handles.
arguments (Input)
    figure (1, 1) matlab.ui.Figure
    document (1, 1) macd.model.DocumentModel
end
if ~isappdata(figure, "macdDocumentLifetime")
    setappdata(figure, "macdDocumentLifetime", struct("observed", strings(1, 0), "destroyed", strings(1, 0)));
end
snapshot = document.Metadata.SourceSnapshotId;
lifetime = getappdata(figure, "macdDocumentLifetime");
lifetime.observed(end + 1) = snapshot;
setappdata(figure, "macdDocumentLifetime", lifetime);
addlistener(document, "ObjectBeingDestroyed", @(~, ~) recordDestroyedDocument(figure, snapshot));
end

function recordDestroyedDocument(figure, snapshot)
% recordDestroyedDocument Record a snapshot identity without holding its model.
arguments (Input)
    figure (1, 1) matlab.ui.Figure
    snapshot (1, 1) string
end
if ~isvalid(figure), return, end
lifetime = getappdata(figure, "macdDocumentLifetime");
lifetime.destroyed(end + 1) = snapshot;
setappdata(figure, "macdDocumentLifetime", lifetime);
end

function targets = measurementTargets(document, registry, propertyPath)
% measurementTargets Prefer matched labels and allow other controls supporting the measured property.
arguments (Input)
    document (1, 1) macd.model.DocumentModel
    registry (1, 1) macd.model.ComponentRegistry
    propertyPath (1, 1) string
end
arguments (Output)
    targets macd.model.ComponentRecord
end
targets = document.Components([document.Components.Factory] == "uilabel");
if numel(targets) >= 2, return, end
targets = macd.model.ComponentRecord.empty;
for component = document.Components
    if component.Id == document.RootComponentId || ~registry.contains(component.Factory), continue, end
    parent = document.getComponent(component.ParentId);
    parentFactory = "";
    if ~isempty(parent), parentFactory = parent.Factory; end
    definitions = registry.getEffectiveProperties(component.Factory, parentFactory, component.CreationArguments);
    property = definitions(string({definitions.Path}) == propertyPath);
    if ~isempty(property) && property.IsEditable && property.PreviewPolicy == "apply"
        targets(end + 1) = component; %#ok<AGROW>
    end
end
end

function [editable, reason] = canCommitProperty(figure, propertyPath)
% canCommitProperty Respect the actual Inspector's source-safety boundary in preserved fixtures.
arguments (Input)
    figure (1, 1) matlab.ui.Figure
    propertyPath (1, 1) string
end
arguments (Output)
    editable (1, 1) logical
    reason (1, 1) string
end
editable = false;
reason = "No editable " + propertyPath + " row is available in the current fixture state.";
labels = findall(figure, "Tag", "macd-inspector-property-label");
label = labels(string({labels.Text}) == propertyPath);
if isempty(label), return, end
editor = findall(label.Parent, "Tag", "macd-inspector-property-editor");
if isempty(editor), return, end
editable = string(editor.Enable) == "on";
if isprop(editor, "Editable"), editable = editable && string(editor.Editable) == "on"; end
if ~editable && strlength(string(editor.Tooltip)) > 0, reason = string(editor.Tooltip); end
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
    fixture = fullfile(projectRoot, "tests", "fixtures", "handle", "ControlGalleryApp.m");
    return
elseif options.Case == "navigation"
    fixture = fullfile(projectRoot, "tests", "fixtures", "handle", "NavigationDataApp.m");
    return
end
document = macd.model.NewAppFactory.createEmpty("PerformanceFixture", registry);
parentId = document.RootComponentId;
if options.Case == "nestedgrid"
    for depth = 1:options.NestedDepth - 1
        outer = document.insertComponent(registry, "uigridlayout", parentId);
        outer.setProperty("RowHeight", {"1x"});
        outer.setProperty("ColumnWidth", {"1x"});
        if depth > 1
            outer.setProperty("Layout.Row", 1);
            outer.setProperty("Layout.Column", 1);
        end
        if depth == options.NestedDepth - 1
            outer.setProperty("ColumnWidth", {"1x", "1x", "1x"});
        end
        parentId = outer.Id;
    end
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

function value = measurementValue(propertyPath, number)
% measurementValue Preserve numeric edit sequences and provide distinct bounded text values.
arguments (Input)
    propertyPath (1, 1) string
    number (1, 1) double
end
arguments (Output)
    value (1, 1)
end
value = number;
if propertyPath == "Text", value = "Text edit " + string(number); end
end

function verifyPropertyValue(document, id, propertyPath, expected)
% verifyPropertyValue Reject missing edits without coercing numeric settings into text.
arguments (Input)
    document (1, 1) macd.model.DocumentModel
    id (1, 1) string
    propertyPath (1, 1) string
    expected
end
entry = document.getComponent(id).getProperty(propertyPath);
assert(~isempty(entry), "The requested property edit was not recorded.");
actual = entry.LiteralValue;
if propertyPath == "Text"
    actual = string(actual);
    expected = string(expected);
end
assert(isequaln(actual, expected), "The requested property edit was not applied.");
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
    assert(toc(started) < 30, "Performance measurement did not settle within 30 seconds.");
    pause(0.01);
end
end

function results = measure(results, action, sample, callback, settled, figure, phase)
% measure Append one completed measurement without including profiler overhead.
arguments (Input)
    results (1, :) struct
    action (1, 1) string
    sample (1, 1) double
    callback (1, 1) double
    settled (1, 1) double
    figure (1, 1) matlab.ui.Figure
    phase (1, 1) string
end
arguments (Output)
    results (1, :) struct
end
overlay = findall(figure, "Tag", "macd-interaction-overlay");
bytes = 0;
if ~isempty(overlay), bytes = numel(unicode2native(jsonencode(overlay.Data), "UTF-8")); end
results(end + 1) = struct("action", action, "phase", phase, "sample", sample, ...
    "callbackSeconds", callback, "settledSeconds", settled, ...
    "nativeObjects", numel(findall(figure)), "timers", numel(timerfindall), "payloadBytes", bytes);
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
modelComponents = NaN;
if isfield(options, "ModelComponents"), modelComponents = options.ModelComponents; end
fprintf(fid, "%s", jsonencode(struct("matlab", version, "case", options.Case, ...
    "componentCount", options.ComponentCount, "modelComponents", modelComponents, "renderAck", options.RenderAck, ...
    "nestedDepth", options.NestedDepth, "propertyPath", options.PropertyPath, ...
    "samples", results, "summary", summarize(results))));
end

function summary = summarize(results)
% summarize Report median and nearest-rank p95 without requiring a statistics toolbox.
arguments (Input)
    results (1, :) struct
end
arguments (Output)
    summary (1, :) struct
end
summary = struct("action", {}, "phase", {}, "count", {}, "medianSeconds", {}, "p95Seconds", {});
for action = unique(string({results.action}), "stable")
    matching = results(string({results.action}) == action);
    for phase = unique(string({matching.phase}), "stable")
        samples = matching(string({matching.phase}) == phase);
        values = sort([samples.settledSeconds]);
        summary(end + 1) = struct("action", action, "phase", phase, "count", numel(values), ...
            "medianSeconds", median(values), "p95Seconds", values(ceil(0.95 * numel(values)))); %#ok<AGROW>
    end
end
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
