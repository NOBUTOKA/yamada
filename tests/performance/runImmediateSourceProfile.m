function runImmediateSourceProfile(projectRoot, fixtureName, output, dataRoot, profiled)
% runImmediateSourceProfile Measure distinct owned settings on a preserved fixture without executing its class.
arguments (Input)
    projectRoot (1,1) string
    fixtureName (1,1) string
    output (1,1) string
    dataRoot (1,1) string
    profiled (1,1) logical = false
end
cd(projectRoot); addpath(projectRoot);
base=dataRoot;
paths=jsondecode(fileread(fullfile(base,"fixtures.json")));
fixture=string(paths.(matlab.lang.makeValidName(fixtureName)));
all=jsondecode(fileread(fullfile(base,"operations.json")));
operations=all.(matlab.lang.makeValidName(fixtureName));
if size(operations,2)==1 && iscell(operations{1})
    rows=cellfun(@(row) reshape(row,1,[]),operations,UniformOutput=false); operations=vertcat(rows{:});
end
registry=macd.model.ComponentRegistry.createDefault();
service=macd.ui.DocumentLifecycleService(struct("RequestOpenPathFcn",@() deal(true,fixture),"ConfirmUnsavedChangesFcn",@() "Discard"));
clock=tic; app=yamada(service); startup=toc(clock); cleanup=onCleanup(@() delete(app));
figure=findall(0,"Tag","macd-yamada-editor"); setappdata(figure,"macdPerformanceMeasurement",true);
menus=findall(figure,"Type","uimenu"); open=menus(erase(string({menus.Text}),"&")=="Open...");
clock=tic; open.MenuSelectedFcn(open,struct()); settle(figure,true); openSeconds=toc(clock);
assert(startsWith(string(which("yamada")),projectRoot));
samples=struct("name",{},"path",{},"value",{},"hadSetting",{},"selectionSeconds",{},"callbackSeconds",{},"settledSeconds",{},"history",{});
profiles = cell(1, size(operations,1));
for index=1:size(operations,1)
    name=string(operations{index,1}); path=string(operations{index,2}); value=operations{index,3};
    if ischar(value), value=string(value); end
    component=app.Document.getComponentByName(name); assert(~isempty(component));
    entry=component.getProperty(path); hadSetting=~isempty(entry);
    if hadSetting, assert(~isequaln(entry.LiteralValue,value),"Operation must change its value."); end
    writeJson(fullfile(output,"progress.json"),struct("action","selection","index",index,"name",name,"path",path));
    clock=tic; selectId(figure,component.Id); settle(figure,true); selection=toc(clock);
    writeJson(fullfile(output,"progress.json"),struct("action","property","index",index,"name",name,"path",path));
    if profiled, profile clear; profile on; end
    clock=tic; commitProperty(figure,path,value); callback=toc(clock); settle(figure,true); elapsed=toc(clock);
    if profiled, profile off; profiles{index}=profile("info"); end
    entry=component.getProperty(path); assert(~isempty(entry)&&isequaln(entry.LiteralValue,value));
    assert(app.Document.HistoryIndex==index);
    samples(end+1)=struct("name",name,"path",path,"value",value,"hadSetting",hadSetting,"selectionSeconds",selection,"callbackSeconds",callback,"settledSeconds",elapsed,"history",app.Document.HistoryIndex);
    writeJson(fullfile(output,"measurements.json"),struct("fixture",fixtureName,"loaded",string(which("yamada")),"startupSeconds",startup,"openSeconds",openSeconds,"samples",samples));
end
if profiled, writeSourceStrategyProfile(output, "edits", profiles); end
source=macd.source.RoundTripGenerator(registry).generate(app.Document);
parsed=macd.source.AppSourceParser.parseText(source,registry);
for item=samples
    entry=parsed.getComponentByName(item.name).getProperty(item.path);
    assert(~isempty(entry)&&isequaln(entry.LiteralValue,item.value));
end
% Audit current offsets against the exact editor text rather than normalized save output.
if isprop(app.Document,"CurrentText")
    current=macd.source.AppSourceParser.parseText(app.Document.CurrentText,registry);
    for owner=app.Document.Components
        expected=current.getComponentByName(owner.Name);
        assert(isequaln(owner.SourceSpans,expected.SourceSpans));
        assert(numel(owner.Settings)==numel(expected.Settings));
        for settingIndex=1:numel(owner.Settings)
            assert(isequaln(owner.Settings(settingIndex).ValueSpan,expected.Settings(settingIndex).ValueSpan));
        end
    end
end
writeJson(fullfile(output,"audit.json"),struct("matched",numel(samples),"components",numel(parsed.Components),"gridCount",sum(string({parsed.Components.Factory})=="uigridlayout")));
writeJson(fullfile(output,"progress.json"),struct("action","complete","index",numel(samples)));
end

function writeJson(path,value)
% writeJson Persist each completed operation outside its timing interval.
arguments (Input)
    path (1,1) string
    value
end
file=fopen(path,"w","n","UTF-8"); assert(file>=0); cleanup=onCleanup(@() fclose(file)); fprintf(file,"%s",jsonencode(value));
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

function saveProfile(output, action)
% saveProfile Preserve raw call graphs and bounded value-only summaries outside operation clocks.
arguments (Input)
    output (1,1) string
    action (1,1) string
end
data=profile("info"); save(fullfile(output,action+".mat"),"data");
exportUpdateProfile(fullfile(output,action+".json"),data);
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
