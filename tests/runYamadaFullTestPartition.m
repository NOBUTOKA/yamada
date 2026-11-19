function results = runYamadaFullTestPartition(selection, shard, shardCount)
% runYamadaFullTestPartition Run a subset of the full suite in this MATLAB session.
%   Use "all", "ui", or "non-ui" to select tests by their ui tag. When
%   splitting across CI jobs, pass a one-based shard and the total shard
%   count. Classes stay intact within the selected subset.
arguments (Input)
    selection (1, 1) string {mustBeMember(selection, ["all", "ui", "non-ui"])}
    shard (1, 1) double {mustBeInteger, mustBePositive} = 1
    shardCount (1, 1) double {mustBeInteger, mustBePositive} = 1
end
arguments (Output)
    results (1, :) matlab.unittest.TestResult
end

% Select complementary UI subsets from the same full profile.
suite = selectYamadaTests("full", string.empty(1, 0));
fullCount = numel(suite);
isUi = arrayfun(@(test) any(strcmp(test.Tags, "ui")), suite);
switch selection
    case "ui"
        suite = suite(isUi);
        isUi = isUi(isUi);
    case "non-ui"
        suite = suite(~isUi);
        isUi = isUi(~isUi);
end

% Assign every selected class exactly once using deterministic size estimates.
[classNames, ~, classIndex] = unique(extractBefore(string({suite.Name}), "/"));
if shard > shardCount || shardCount > numel(classNames)
    error("yamada:TestSelection:InvalidPartition", ...
        "Shard %d of %d cannot be selected from %d test classes.", ...
        shard, shardCount, numel(classNames));
end
classCosts = accumarray(classIndex(:), 1 + 3 * isUi(:));
[~, order] = sort(classCosts, "descend");
costByShard = zeros(1, shardCount);
shardByClass = zeros(size(classNames));
for index = order.'
    [~, nextShard] = min(costByShard);
    shardByClass(index) = nextShard;
    costByShard(nextShard) = costByShard(nextShard) + classCosts(index);
end
selected = shardByClass(classIndex) == shard;
fprintf("FULL_SHARD Selection=%s Index=%d Shards=%d Full=%d Included=%d Selected=%d UI=%d\n", ...
    selection, shard, shardCount, fullCount, numel(suite), nnz(selected), nnz(selected & isUi));

% Report skips separately from failures for CI and local acceptance records.
started = tic;
results = run(suite(selected));
fprintf("FULL_SHARD_RESULT Index=%d Passed=%d Failed=%d Incomplete=%d Wall=%.3f\n", ...
    shard, sum([results.Passed]), sum([results.Failed]), sum([results.Incomplete]), toc(started));
assertSuccess(results);
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
