classdef OnOffForm
    % OnOffForm Enumerate the independent source forms of an on/off state.
    %   Each place that accepts an on/off state lists the forms it accepts, and
    %   yamada.model.OnOffState reads a value whose form is in that list. The
    %   member names match the onOffForms values of the axes setting catalog.
    %
    %   Example:
    %       forms = yamada.model.OnOffForm(["text", "logical"]);

    enumeration
        % text - "on" or "off" in any letter case.
        text
        % lowercaseText - "on" or "off" in lowercase only.
        lowercaseText
        % logical - true or false.
        logical
        % finiteNumber - A real finite numeric scalar, on when nonzero.
        finiteNumber
        % nonfiniteNumber - NaN, Inf, or -Inf, which are on.
        nonfiniteNumber
        % switchState - A matlab.lang.OnOffSwitchState member.
        switchState
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
