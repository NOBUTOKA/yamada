function data = waitForPreviewLayout(figure, target)
% waitForPreviewLayout Wait for the editor figure's browser layout before capturing geometry.
%   Create the figure with yamada.ui.createEditorFigure to provide a browser
%   window in desktop MATLAB. The target is validated for existing callers.
arguments (Input)
    figure (1, 1) matlab.ui.Figure
    target (1, 1) matlab.graphics.Graphics %#ok<INUSA>
end
arguments (Output)
    data (1, 1) struct
end

% Delegate browser synchronization and preserve the editor's error identifiers.
try
    data = yamada.ui.layoutwait.waitForFigureLayout(figure);
catch exception
    switch exception.identifier
        case "waitForFigureLayout:NoFigureWindow"
            error("yamada:PreviewLayout:NoFigureWindow", "%s", exception.message);
        case "waitForFigureLayout:SettleReply"
            error("yamada:PreviewLayout:SettleReply", "%s", exception.message);
        otherwise
            rethrow(exception);
    end
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
