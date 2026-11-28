classdef OnOffState
    % OnOffState Interpret and write on/off states in their source representations.
    %   Each place that accepts an on/off state lists the independent forms it
    %   accepts as yamada.model.OnOffForm members, and every reader of an on/off
    %   state uses this class. A value is read when its form is in the list.
    %
    %   Example:
    %       [state, known] = yamada.model.OnOffState.read(1, ["text", "finiteNumber"])  % "on", true
    %       value = yamada.model.OnOffState.like("off", true)  % false

    properties (Constant)
        % PropertyForms - Forms that every on/off property assignment accepts.
        %   Native R2023a through R2026b observations: assignments and name-value
        %   arguments accept all forms except lowercase-only text, and treat NaN
        %   and Inf as on.
        PropertyForms yamada.model.OnOffForm = [yamada.model.OnOffForm.text, yamada.model.OnOffForm.logical, ...
            yamada.model.OnOffForm.finiteNumber, yamada.model.OnOffForm.nonfiniteNumber, ...
            yamada.model.OnOffForm.switchState]
    end

    methods (Static)
        function [state, known] = read(value, forms)
            % read Return "on" or "off" for a value whose form is one of the accepted forms.
            arguments (Input)
                value
                forms (1, :) yamada.model.OnOffForm = yamada.model.OnOffState.PropertyForms
            end
            arguments (Output)
                state (1, 1) string
                known (1, 1) logical
            end

            state = "off";
            known = false;
            text = "";
            isText = (ischar(value) && isrow(value)) || (isstring(value) && isscalar(value) && ~ismissing(value));
            if isText, text = string(value); end
            % Check the value against each accepted form; an OnOffSwitchState is not a plain logical.
            for form = forms
                switch form
                    case yamada.model.OnOffForm.text
                        known = isText && any(lower(text) == ["on", "off"]);
                        if known, state = lower(text); end
                    case yamada.model.OnOffForm.lowercaseText
                        known = isText && any(text == ["on", "off"]);
                        if known, state = text; end
                    case yamada.model.OnOffForm.logical
                        known = isscalar(value) && class(value) == "logical";
                    case yamada.model.OnOffForm.finiteNumber
                        known = isscalar(value) && isnumeric(value) && isreal(value) && isfinite(value);
                    case yamada.model.OnOffForm.nonfiniteNumber
                        known = isscalar(value) && isnumeric(value) && isreal(value) && ~isfinite(value);
                    case yamada.model.OnOffForm.switchState
                        known = isscalar(value) && isa(value, "matlab.lang.OnOffSwitchState");
                end
                if known
                    % A nonzero state is on, including NaN.
                    if ~isText && logical(value ~= 0), state = "on"; end
                    return
                end
            end
        end

        function result = isOn(value, forms)
            % isOn Report whether a value is a known on state.
            arguments (Input)
                value
                forms (1, :) yamada.model.OnOffForm = yamada.model.OnOffState.PropertyForms
            end
            arguments (Output)
                result (1, 1) logical
            end

            [state, known] = yamada.model.OnOffState.read(value, forms);
            result = known && state == "on";
        end

        function value = like(state, original)
            % like Write an on/off state in the form of the owned value it replaces.
            %   A logical stays logical, a number becomes 1 or 0, and an OnOffSwitchState
            %   stays an enumeration member. Text and new values are written as the
            %   string "on" or "off", following the project's text literal convention.
            arguments (Input)
                state
                original
            end
            arguments (Output)
                value
            end

            on = yamada.model.OnOffState.isOn(state);
            if isa(original, "matlab.lang.OnOffSwitchState") && isscalar(original)
                value = matlab.lang.OnOffSwitchState(on);
            elseif class(original) == "logical" && isscalar(original)
                value = on;
            elseif isnumeric(original) && isscalar(original)
                value = double(on);
            elseif (ischar(state) && isrow(state)) || (isstring(state) && isscalar(state))
                % Requested text is written as requested, as for other text properties.
                value = state;
            elseif on
                value = "on";
            else
                value = "off";
            end
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
