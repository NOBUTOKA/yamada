classdef OnOffState
    % OnOffState Interpret and write on/off states in their source representations.
    %   An on/off argument or property accepts a set of forms: "text" ("on" or
    %   "off" in any letter case), "lowercaseText" ("on" or "off" only), "logical"
    %   (true or false), "finiteNumber" (a real finite numeric scalar, on when
    %   nonzero), "nonfiniteNumber" (NaN, Inf, or -Inf, which are on), and
    %   "switchState" (a matlab.lang.OnOffSwitchState scalar). The forms are not
    %   ordered: each place lists what it accepts, and every reader of an on/off
    %   state uses this class.
    %
    %   Example:
    %       [state, known] = yamada.model.OnOffState.read(1, ["text", "finiteNumber"])  % "on", true
    %       value = yamada.model.OnOffState.like("off", true)  % false

    methods (Static)
        function forms = propertyForms()
            % propertyForms Return the forms that every on/off property assignment accepts.
            %   Native R2023a through R2026b observations: assignments and name-value
            %   arguments accept all forms, and treat NaN and Inf as on.
            arguments (Output)
                forms (1, :) string
            end

            forms = ["text", "logical", "finiteNumber", "nonfiniteNumber", "switchState"];
        end

        function [state, known] = read(value, forms)
            % read Return "on" or "off" for a value whose form is one of the accepted forms.
            arguments (Input)
                value
                forms (1, :) string {mustBeMember(forms, ["text", "lowercaseText", "logical", ...
                    "finiteNumber", "nonfiniteNumber", "switchState"])} = yamada.model.OnOffState.propertyForms()
            end
            arguments (Output)
                state (1, 1) string
                known (1, 1) logical
            end

            state = "off";
            known = false;
            % Identify the single form of the value; an OnOffSwitchState is also a logical.
            if (ischar(value) && isrow(value)) || (isstring(value) && isscalar(value) && ~ismissing(value))
                text = string(value);
                if any(forms == "text"), text = lower(text); elseif ~any(forms == "lowercaseText"), return, end
                known = any(text == ["on", "off"]);
                if known, state = text; end
                return
            end
            if ~isscalar(value), return, end
            if isa(value, "matlab.lang.OnOffSwitchState")
                form = "switchState";
            elseif class(value) == "logical"
                form = "logical";
            elseif isnumeric(value) && isreal(value) && isfinite(value)
                form = "finiteNumber";
            elseif isnumeric(value) && isreal(value)
                form = "nonfiniteNumber";
            else
                return
            end
            known = any(forms == form);
            if known && logical(value ~= 0), state = "on"; end
        end

        function result = isOn(value, forms)
            % isOn Report whether a value is a known on state.
            arguments (Input)
                value
                forms (1, :) string = yamada.model.OnOffState.propertyForms()
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
