function result = verifyHandleAppContract()
% verifyHandleAppContract Verify root-count diagnostics using complete factory-call syntax.
%   This static verification does not construct any app or execute callbacks.
arguments (Output)
    result (1, 1) struct
end

% Use valid factory calls so multiple roots cannot be mistaken for absent roots.
registry = macd.model.ComponentRegistry.createDefault();
counts = zeros(1, 3);
for expectedCount = 0:2
    lines = ["classdef ContractApp < handle"; "properties"; ...
        "Main matlab.ui.Figure"; "Other matlab.ui.Figure"; "end"; ...
        "methods"; "function app = ContractApp"];
    if expectedCount >= 1, lines(end + 1) = "app.Main = uifigure();"; end %#ok<AGROW>
    if expectedCount >= 2, lines(end + 1) = "app.Other = uifigure();"; end %#ok<AGROW>
    source = strjoin([lines; "end"; "end"; "end"], newline);
    [document, diagnostics] = macd.source.AppSourceParser.parseText(source, registry);
    counts(expectedCount + 1) = nnz(string({document.Components.Factory}) == "uifigure");
    assert(counts(expectedCount + 1) == expectedCount, ...
        "test:HandleRootRecognition", "Root factory calls were not recognized.");
    rootError = any(string({diagnostics.Code}) == "invalid-root-count");
    assert(rootError == (expectedCount ~= 1), ...
        "test:HandleRootCount", "The root-count contract was not enforced.");
    assert(macd.validation.ModelValidator.hasErrors(diagnostics) == (expectedCount ~= 1), ...
        "test:HandleRootValidation", "Unexpected model validation result.");
end
result = struct("RecognizedCounts", counts, "Passed", true);
fprintf("HANDLE_ROOT_CONTRACT Counts=%d,%d,%d Passed=1\n", counts);
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
