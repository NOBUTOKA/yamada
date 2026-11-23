classdef DialogFocus
    % DialogFocus Return focus to yamada and its dialog after a native picker closes.
    %   Desktop pickers such as uisetcolor can activate the MATLAB desktop
    %   instead of the window that opened them. Focusing a modal dialog alone
    %   leaves the editor behind other applications, so the editor is raised
    %   first and the dialog second.
    %
    %   Example:
    %       selected = uisetcolor(current);
    %       yamada.ui.DialogFocus.restore(editorFigure, dialogFigure);

    methods (Static)
        function restore(owner, dialog)
            % restore Raise the owning editor, then the dialog that opened the picker.
            arguments (Input)
                owner
                dialog = []
            end

            % Skip windows that are gone or hidden; focus cannot target them.
            if yamada.ui.DialogFocus.isShown(owner)
                focus(owner);
            end
            if yamada.ui.DialogFocus.isShown(dialog) && ~isequal(dialog, owner)
                focus(dialog);
            end
        end
    end

    methods (Static, Access = private)
        function result = isShown(window)
            % isShown Return whether a window is a live, visible figure.
            arguments (Input)
                window
            end
            arguments (Output)
                result (1, 1) logical
            end

            result = ~isempty(window) && isa(window, "matlab.ui.Figure") && ...
                isvalid(window) && window.Visible == "on";
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
