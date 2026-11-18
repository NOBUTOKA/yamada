function figure = createEditorFigure(options)
% createEditorFigure Create an editor-owned uifigure whose window can run the layout wait.
%   figure = yamada.ui.createEditorFigure(Name=Value) accepts settable
%   uifigure properties and returns a uifigure hosted in its own browser
%   window. yamada.ui.waitForPreviewLayout runs its settle script in that
%   window, which exists for every uifigure through R2024b and under
%   matlab -batch. From R2025a the MATLAB desktop hosts uifigures inside the
%   desktop page, which MATLAB cannot run scripts in, so this adapter asks
%   for an isolated figure window instead. When that request is unavailable
%   or fails, it creates an ordinary uifigure and the wait reports
%   yamada:PreviewLayout:NoFigureWindow, which retains the legacy geometry
%   recovery path. doc/ARCHITECTURE.md records the verified releases.
%
%   Example:
%       figure = yamada.ui.createEditorFigure(Visible="off", Name="Editor");
arguments (Input)
    options.?matlab.ui.Figure
end
arguments (Output)
    figure (1, 1) matlab.ui.Figure
end
values = namedargs2cell(options);
% Releases before R2025a have no isolated request and always use a separate window.
if isMATLABReleaseOlderThan("R2025a")
    figure = uifigure(values{:});
    return
end
% Request a separate window; an unsupported request falls back to the desktop host.
try
    figure = matlab.ui.internal.uifigureIsolated(values{:});
catch
    figure = uifigure(values{:});
end
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
