function observations = ProbeApplicationInteractions()
% ProbeApplicationInteractions Observe owned R2024a constructor and setter interactions.
%   The fixed cases below are audit fixtures, not user-supplied source. The
%   returned values are observations for review and never executable policy.
arguments (Output)
    observations (1, :) struct
end

% Keep every constructed component under one invisible, owned figure.
figure = uifigure("Visible", "off", "Position", [100 100 600 400]);
cleanup = onCleanup(@() delete(figure));
cases = {
    "slider-value-first", "uislider", {}, {"Value", 150, "Limits", [120 200]}, {};
    "slider-limits-first", "uislider", {}, {"Limits", [120 200], "Value", 150}, {};
    "slider-invalid-value-first", "uislider", {}, {"Value", 20, "Limits", [50 100]}, {};
    "slider-invalid-limits-first", "uislider", {}, {"Limits", [50 100], "Value", 20}, {};
    "numeric-round-first", "uieditfield", {"numeric"}, {"RoundFractionalValues", "on", "Value", 2.4}, {};
    "numeric-value-first", "uieditfield", {"numeric"}, {"Value", 2.4, "RoundFractionalValues", "on"}, {};
    "numeric-round-assignment", "uieditfield", {"numeric"}, {"RoundFractionalValues", "on"}, {"Value", 2.4};
    "numeric-exclude-lower", "uieditfield", {"numeric"}, {"Limits", [0 1]}, {"LowerLimitInclusive", "off"};
    "numeric-exclude-upper", "uieditfield", {"numeric"}, {"Limits", [0 1], "Value", 1}, {"UpperLimitInclusive", "off"};
    "numeric-limit-while-exclusive", "uieditfield", {"numeric"}, {"LowerLimitInclusive", "off", "Limits", [0 1], "Value", 0.5}, {"Limits", [1 2]};
    "numeric-clear-allowempty", "uieditfield", {"numeric"}, {"AllowEmpty", "on", "Value", []}, {"AllowEmpty", "off"};
    "numeric-round-outside-limit", "uieditfield", {"numeric"}, {"Limits", [0 2], "RoundFractionalValues", "on"}, {"Value", 2.4};
    "numeric-round-outside-open-limit", "uieditfield", {"numeric"}, {"Limits", [0 2], "UpperLimitInclusive", "off", "RoundFractionalValues", "on"}, {"Value", 1.9};
    "numeric-clear-empty-with-limits", "uieditfield", {"numeric"}, {"Limits", [50 100], "AllowEmpty", "on", "Value", []}, {"AllowEmpty", "off"};
    "dropdown-value-first", "uidropdown", {}, {"Value", 20, "ItemsData", [10 20], "Items", {'A','B'}}, {};
    "dropdown-renamed-items", "uidropdown", {}, {"Items", {'A','B'}, "Value", 'B'}, {"Items", {'C','D'}};
    "dropdown-data-retains-index", "uidropdown", {}, {"Items", {'A','B'}, "Value", 'B'}, {"ItemsData", [10 20]};
    "dropdown-new-data", "uidropdown", {}, {"Items", {'A','B'}, "ItemsData", [10 20], "Value", 20}, {"ItemsData", [30 40]};
    "dropdown-short-data", "uidropdown", {}, {"Items", {'A','B','C'}, "Value", 'C'}, {"ItemsData", [10 20]};
    "dropdown-extra-data-selection", "uidropdown", {}, {"Items", {'A','B'}, "ItemsData", [10 20 30]}, {"Value", 30};
    "dropdown-removes-data", "uidropdown", {}, {"Items", {'A','B'}, "ItemsData", [10 20], "Value", 20}, {"ItemsData", []};
    "listbox-disable-multiselect", "uilistbox", {}, {"Items", {'A','B','C'}, "Multiselect", "on", "Value", {'B','C'}}, {"Multiselect", "off"};
    "ticks-mode-first", "uislider", {}, {"MajorTicksMode", "auto", "MajorTicks", [10 90]}, {};
    "ticks-values-first", "uislider", {}, {"MajorTicks", [10 90], "MajorTicksMode", "auto"}, {};
    "panel-position-first", "uipanel", {}, {"Position", [1 1 200 100], "Units", "normalized"}, {};
    "panel-units-first", "uipanel", {}, {"Units", "normalized", "Position", [0.1 0.1 0.5 0.5]}, {};
    "text-empty-with-lower-limit", "uieditfield", {"text"}, {"CharacterLimits", [6 Inf]}, {"Value", ''};
    "text-reject-short", "uieditfield", {"text"}, {"CharacterLimits", [6 Inf]}, {"Value", 'Hello'}
    };
observations = repmat(struct("Case", "", "Success", false, ...
    "Snapshot", struct(), "ErrorId", "", "Factory", "", ...
    "CreationArguments", {{}}, "NameValueArguments", {{}}, "Assignments", {{}}), 1, size(cases, 1));
paths = ["Value", "Items", "ItemsData", "Limits", "AllowEmpty", ...
    "LowerLimitInclusive", "UpperLimitInclusive", "RoundFractionalValues", ...
    "Multiselect", "MajorTicks", "MajorTicksMode", "Position", "Units"];
for index = 1:size(cases, 1)
    observations(index).Case = cases{index, 1};
    observations(index).Factory = cases{index, 2};
    observations(index).CreationArguments = cases{index, 3};
    observations(index).NameValueArguments = cases{index, 4};
    observations(index).Assignments = cases{index, 5};
    target = [];
    try
        target = feval(cases{index, 2}, figure, cases{index, 3}{:}, cases{index, 4}{:});
        assignments = cases{index, 5};
        for assignment = 1:2:numel(assignments)
            target.(assignments{assignment}) = assignments{assignment + 1};
        end
        observations(index).Success = true;
    catch exception
        observations(index).ErrorId = string(exception.identifier);
    end
    if ~isempty(target) && isvalid(target)
        snapshot = struct();
        for path = paths
            if ~isprop(target, path), continue, end
            value = target.(path);
            if isa(value, "matlab.lang.OnOffSwitchState"), value = string(value); end
            snapshot.(path) = value;
        end
        observations(index).Snapshot = snapshot;
        delete(target);
    end
end
clear cleanup
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
