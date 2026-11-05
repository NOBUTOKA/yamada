function runSourceStrategyComparison(layout, mode, count, output, profiled)
% runSourceStrategyComparison Measure distinct length-changing edits and a save at one history length.
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
fixtures = jsondecode(fileread(fullfile(base, "fixtures.json")));
operations = jsondecode(fileread(fullfile(base, "operations.json")));
source = string(fileread(fixtures.(layout).path));
registry = yamada.model.ComponentRegistry.createDefault();
clock = tic;
engine = SourceStrategyExperiment(source, mode, registry);
initialization = toc(clock);
samples = struct("Index", {}, "Name", {}, "Path", {}, "Existing", {}, "Seconds", {});
if profiled, profile clear; profile on; end
for index = 1:count
    operation = operations(index);
    value = operation.value;
    if ischar(value), value = string(value); end
    component = engine.Document.getComponentByName(string(operation.name));
    assert(~isempty(component.getProperty(string(operation.path))) == operation.existing);
    clock = tic;
    engine.edit(string(operation.name), string(operation.path), value);
    elapsed = toc(clock);
    assert(engine.Document.HistoryIndex == index);
    samples(end + 1) = struct("Index", index, "Name", string(operation.name), ...
        "Path", string(operation.path), "Existing", operation.existing, "Seconds", elapsed); %#ok<AGROW>
    writeJson(fullfile(output, "progress.json"), struct("phase", "editing", "index", index));
end
if profiled
    profile off;
    writeSourceStrategyProfile(output, "edits");
    profile clear; profile on;
end
writeJson(fullfile(output, "progress.json"), struct("phase", "saving", "index", count));
clock = tic;
checkpoint = engine.save(fullfile(output, "UpdateDistributionFixture.m"));
saveSeconds = toc(clock);
if profiled, profile off; writeSourceStrategyProfile(output, "save"); end
% Output correctness and full index checks remain outside operation timings.
parsed = yamada.source.AppSourceParser.parseText(checkpoint.SourceText, registry);
for request = engine.Requests
    entry = parsed.getComponentByName(request.Name).getProperty(request.Path);
    assert(isequaln(entry.LiteralValue, request.Value));
end
if mode == "eager"
    for component = parsed.Components
        settingIndex = 0;
        for setting = component.Settings
            settingIndex = settingIndex + 1;
            key = "occurrence:" + component.Name + ":" + settingIndex;
            spans = engine.Locations(string({engine.Locations.Key}) == key);
            if isempty(spans), continue, end
            assert(spans(end).Start == setting.ValueSpan.StartOffset && ...
                spans(end).End == setting.ValueSpan.EndOffset, "Position mismatch %s: retained [%d %d], parsed [%d %d].", key, spans(end).Start, spans(end).End, setting.ValueSpan.StartOffset, setting.ValueSpan.EndOffset);
        end
    end
end
bytes = fileread(fullfile(output, "UpdateDistributionFixture.m"));
assert(string(bytes) == checkpoint.SourceText);
writeJson(fullfile(output, "results.json"), struct("layout", layout, "mode", mode, ...
    "count", count, "profiled", profiled, "initializationSeconds", initialization, ...
    "samples", samples, "editTotalSeconds", sum([samples.Seconds]), "saveSeconds", saveSeconds, ...
    "history", engine.Document.HistoryIndex, "locations", numel(engine.Locations), ...
    "sourceCharacters", strlength(checkpoint.SourceText), "matched", numel(engine.Requests), ...
    "sourceEngineOnly", true));
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
