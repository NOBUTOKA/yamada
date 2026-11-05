function results = ProbeAxisModeInteractions(outputPath)
% ProbeAxisModeInteractions Supplement R2024a documentation with owned axes setters.
%   Only allowlisted properties and test-authored literals reach native axes.
%   Results distinguish stored getter values, mode flags, and constructor order.
arguments (Input)
    outputPath (1, 1) string
end
arguments (Output)
    results (1, :) struct
end

% Keep every native object within one hidden, explicitly owned figure.
figure = uifigure("Visible", "off");
cleanup = onCleanup(@() delete(figure));
results = struct("Factory", {}, "Path", {}, "RequestedValue", {}, "DefaultMode", {}, "ManualValue", {}, ...
    "ManualMode", {}, "ManualMatches", {}, "AutomaticMatches", {}, ...
    "AutomaticRenderedMatches", {}, "ConstructorValueLastMode", {}, ...
    "ConstructorModeLastMode", {}, "Error", {});
common = {"FontSize", 14; "TickDir", "out"; "GridColor", [0.3 0.5 0.7]; ...
    "GridAlpha", 0.4; "CLim", [0 10]; "ALim", [0 2]};
cartesian = {"XTick", [0 0.5 1]; "YTick", [0 0.5 1]; "ZTick", [0 0.5 1]; ...
    "XTickLabel", {'low','high'}; "YTickLabel", {'low','high'}; "ZTickLabel", {'low','high'}; ...
    "XTickLabelRotation", 30; "YTickLabelRotation", 30; "ZTickLabelRotation", 30; ...
    "XLim", [2 4]; "YLim", [3 6]; "ZLim", [1 5]; ...
    "XColor", [0.3 0.5 0.7]; "YColor", [0.3 0.5 0.7]; "ZColor", [0.3 0.5 0.7]; ...
    "GridLineWidth", 2; "MinorGridLineWidth", 1; ...
    "MinorGridColor", [0.3 0.5 0.7]; "MinorGridAlpha", 0.4; ...
    "DataAspectRatio", [1 2 3]; "PlotBoxAspectRatio", [2 3 4]; ...
    "CameraPosition", [3 4 5]; "CameraTarget", [0.1 0.2 0.3]; ...
    "CameraUpVector", [0 0 1]; "CameraViewAngle", 25};
polar = {"RTick", [0 0.5 1]; "ThetaTick", [0 90 180]; ...
    "RTickLabel", {'low','high'}; "ThetaTickLabel", {'low','high'}; ...
    "RTickLabelRotation", 15; "RLim", [1 5]; "ThetaLim", [30 210]; ...
    "RAxisLocation", 30; "RColor", [0.3 0.5 0.7]; "ThetaColor", [0.3 0.5 0.7]; ...
    "MinorGridColor", [0.3 0.5 0.7]; "MinorGridAlpha", 0.4};

% Probe fresh objects so prior pairs cannot contaminate a getter or mode.
factories = ["axes", "uiaxes", "polaraxes", "geoaxes"];
caseSets = {[common; cartesian], [common; cartesian], [common; polar], ...
    [common; {"MapCenter", [35 140]; "ZoomLevel", 4}]};
for factoryIndex = 1:numel(factories)
    factory = factories(factoryIndex);
    cases = caseSets{factoryIndex};
    for index = 1:size(cases, 1)
        path = cases{index, 1};
        value = cases{index, 2};
        mode = path + "Mode";
        result = struct("Factory", factory, "Path", path, "RequestedValue", [], "DefaultMode", "", "ManualValue", "", ...
            "ManualMode", "", "ManualMatches", false, "AutomaticMatches", false, ...
            "AutomaticRenderedMatches", false, "ConstructorValueLastMode", "", ...
            "ConstructorModeLastMode", "", "Error", "");
        result.RequestedValue = value;
        target = [];
        first = [];
        second = [];
        try
            target = createAxes(factory, figure, {});
            result.DefaultMode = string(target.(mode));
            target.(path) = value;
            result.ManualValue = string(jsonencode(target.(path)));
            result.ManualMode = string(target.(mode));
            result.ManualMatches = equivalent(target.(path), value);
            target.(mode) = "auto";
            result.AutomaticMatches = equivalent(target.(path), value);
            drawnow;
            result.AutomaticRenderedMatches = equivalent(target.(path), value);
            first = createAxes(factory, figure, {mode, "auto", path, value});
            result.ConstructorValueLastMode = string(first.(mode));
            second = createAxes(factory, figure, {path, value, mode, "auto"});
            result.ConstructorModeLastMode = string(second.(mode));
        catch exception
            result.Error = string(exception.identifier) + ": " + string(exception.message);
        end
        deleteOwned(target);
        deleteOwned(first);
        deleteOwned(second);
        results(end + 1) = result; %#ok<AGROW>
    end
end

% Persist supplemental facts separately from documentation and runtime metadata.
artifact = struct("matlabRelease", "R2024a", "results", results, "couplings", probeCouplings(figure));
file = fopen(outputPath, "w", "n", "UTF-8");
assert(file >= 0, "yamada:ProbeAxisModeInteractions:WriteFailed", "Cannot open probe output.");
fileCleanup = onCleanup(@() fclose(file));
fprintf(file, "%s\n", jsonencode(artifact, "PrettyPrint", true));
fprintf("AXIS_MODE_PROBE Cases=%d Errors=%d\n", numel(results), sum(strlength(string({results.Error})) > 0));
end

function target = createAxes(factory, figure, pairs)
% createAxes Construct one allowlisted native axes without loading geographic tiles.
arguments (Input)
    factory (1, 1) string
    figure (1, 1) matlab.ui.Figure
    pairs (1, :) cell
end
arguments (Output)
    target (1, 1) matlab.graphics.axis.AbstractAxes
end
if factory == "geoaxes", pairs = [{"Basemap", "none"}, pairs]; end
target = feval(factory, figure, pairs{:});
end

function result = equivalent(actual, expected)
% equivalent Compare stored literals without mistaking row/column label storage for a changed value.
arguments (Input)
    actual
    expected
end
arguments (Output)
    result (1, 1) logical
end
if (iscell(actual) || isstring(actual) || ischar(actual)) && ...
        (iscell(expected) || isstring(expected) || ischar(expected))
    actual = string(actual);
    expected = string(expected);
    result = isequal(actual(:), expected(:));
else
    result = isequaln(actual, expected);
end
end

function result = probeCouplings(figure)
% probeCouplings Check documented width followers and nonliteral automatic-limit inputs.
arguments (Input)
    figure (1, 1) matlab.ui.Figure
end
arguments (Output)
    result (1, 1) struct
end
target = axes(figure);
cleanup = onCleanup(@() delete(target));
target.LineWidth = 2;
result.WidthFollowers = [target.LineWidth target.GridLineWidth target.MinorGridLineWidth];
target.MinorGridLineWidth = 3;
target.GridLineWidth = 4;
result.ProtectedMinorWidth = target.MinorGridLineWidth;
target.MinorGridLineWidthMode = "auto";
result.AutomaticMinorWidth = target.MinorGridLineWidth;
target.GridLineWidthMode = "auto";
result.RestoredWidthFollowers = [target.LineWidth target.GridLineWidth target.MinorGridLineWidth];
target.XLim = [-Inf 10];
result.AutomaticEndpoint = target.XLim;
result.AutomaticEndpointMode = string(target.XLimMode);
target.PlotBoxAspectRatio = [2 3 4];
target.DataAspectRatio = [1 2 3];
target.XLim = [2 4];
target.YLim = [3 6];
target.ZLim = [1 5];
drawnow;
result.ConstrainedPlotBox = target.PlotBoxAspectRatio;
target.XLim = [0 10];
target.XScale = "log";
result.LogarithmicLimits = target.XLim;
end

function deleteOwned(target)
% deleteOwned Release a probe-owned object after either success or a setter failure.
arguments (Input)
    target
end
if ~isempty(target) && isvalid(target), delete(target); end
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
