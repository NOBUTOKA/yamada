function results = runYamadaTestShards(suite, profile, areas, workers)
% runYamadaTestShards Run a profile suite across separate MATLAB processes.
%   RESULTS = runYamadaTestShards(SUITE, PROFILE, AREAS, WORKERS) starts
%   WORKERS batch MATLAB processes that share a queue of whole test classes,
%   waits for them, and returns every result in SUITE order. Classes stay
%   intact so class-level fixtures run once. Larger UI classes are queued
%   first so the dynamic queue finishes evenly.
arguments (Input)
    suite (1, :) matlab.unittest.Test
    profile (1, 1) string
    areas (1, :) string
    workers (1, 1) double {mustBeInteger, mustBePositive}
end
arguments (Output)
    results (1, :) matlab.unittest.TestResult
end

% Order whole classes by a simple cost estimate: UI tests dominate run time.
names = string({suite.Name});
owners = extractBefore(names, "/");
classes = unique(owners, "stable");
weights = zeros(1, numel(classes));
for index = 1:numel(classes)
    members = suite(owners == classes(index));
    isUi = arrayfun(@(test) any(strcmp(test.Tags, "ui")), members);
    weights(index) = sum(isUi) * 4 + sum(~isUi);
end
[~, order] = sort(weights, "descend");
classes = classes(order);

% Prepare the shared queue folder that workers claim from.
queueFolder = string(tempname);
mkdir(queueFolder);
mkdir(fullfile(queueFolder, "claims"));
mkdir(fullfile(queueFolder, "results"));
writelines(classes, fullfile(queueFolder, "classes.txt"));

% Start every worker before waiting so they run concurrently.
privateFolder = fileparts(mfilename("fullpath"));
testsFolder = fileparts(privateFolder);
projectRoot = fileparts(testsFolder);
executable = fullfile(matlabroot, "bin", "matlab");
if ispc, executable = executable + ".exe"; end
areaText = "";
if ~isempty(areas), areaText = join(areas, ","); end
command = sprintf("addpath(%s, %s); runYamadaTestWorker(%s, %s, %s);", ...
    quoted(projectRoot), quoted(testsFolder), quoted(profile), ...
    quoted(areaText), quoted(queueFolder));
logs = strings(1, workers);
processes = cell(1, workers);
started = tic;
try
    for index = 1:workers
        logs(index) = fullfile(queueFolder, "worker" + index + ".log");
        builder = java.lang.ProcessBuilder({char(executable), '-batch', char(command), ...
            '-logfile', char(logs(index))});
        builder.directory(java.io.File(char(projectRoot)));
        builder.redirectErrorStream(true);
        builder.redirectOutput(java.io.File(char(fullfile(queueFolder, "worker" + index + ".out"))));
        processes{index} = builder.start();
    end
catch exception
    stopWorkers(processes);
    rethrow(exception);
end
fprintf("TEST_WORKERS Started=%d Classes=%d Queue=%s\n", workers, numel(classes), queueFolder);

% Stop orphaned workers if the caller interrupts the wait.
stopper = onCleanup(@() stopWorkers(processes));

% Wait for every worker and keep the queue folder when anything went wrong.
codes = zeros(1, workers);
for index = 1:workers
    codes(index) = processes{index}.waitFor();
end
clear stopper
fprintf("TEST_WORKERS Finished Wall=%.3f ExitCodes=%s\n", toc(started), mat2str(codes));

% Collect saved class results and restore the original suite order.
results = matlab.unittest.TestResult.empty(1, 0);
missing = strings(1, 0);
for index = 1:numel(classes)
    resultPath = fullfile(queueFolder, "results", string(index) + ".mat");
    if ~isfile(resultPath)
        missing(end + 1) = classes(index); %#ok<AGROW>
        continue
    end
    saved = load(resultPath, "results");
    results = [results, reshape(saved.results, 1, [])]; %#ok<AGROW>
end
if ~isempty(missing) || any(codes ~= 0)
    error("yamada:TestSelection:WorkerFailed", ...
        "Test workers did not finish every class (exit codes %s). Missing: %s. Logs: %s", ...
        mat2str(codes), join(missing, ", "), join(logs, ", "));
end
[found, location] = ismember(names, string({results.Name}));
if ~all(found) || numel(results) ~= numel(names)
    error("yamada:TestSelection:WorkerResultsMismatch", ...
        "Worker results do not match the selected suite. Logs: %s", join(logs, ", "));
end
results = results(location);

% Keep worker logs for diagnostics whenever a test did not pass.
if all([results.Passed])
    rmdir(queueFolder, "s");
else
    fprintf("TEST_WORKERS LogsKept=%s\n", join(logs, ", "));
end
end

function stopWorkers(processes)
% stopWorkers Terminate any worker process that is still running.
arguments (Input)
    processes (1, :) cell
end
for index = 1:numel(processes)
    process = processes{index};
    if ~isempty(process) && process.isAlive(), process.destroy(); end
end
end

function text = quoted(value)
% quoted Return a single-quoted MATLAB character literal for a batch command.
arguments (Input)
    value (1, 1) string
end
arguments (Output)
    text (1, 1) string
end
text = "'" + replace(value, "'", "''") + "'";
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
