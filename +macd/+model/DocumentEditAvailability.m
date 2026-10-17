classdef DocumentEditAvailability
    % DocumentEditAvailability Share exact-state deletion preflight across editor commands.
    %   Results contain only enabled state and reasons. Actual commands retain
    %   their authoritative atomic preflight before mutating the live document.
    methods (Static)
        function state = deletion(document, id, registry)
            % deletion Check subtree deletion once for each unchanged semantic input.
            arguments (Input)
                document (1, 1) macd.model.DocumentModel
                id (1, 1) string
                registry (1, 1) macd.model.ComponentRegistry
            end
            arguments (Output)
                state (1, 1) struct
            end
            context = document.evaluationContext(registry);
            key = "delete:" + id;
            [state, found] = context.lookup(key);
            if found, return, end
            state = struct("Enabled", false, "Reason", "");
            try
                candidate = document.structuralCandidate();
                candidate.removeSubtree(id, registry);
                state.Enabled = true;
            catch exception
                state.Reason = string(exception.message);
            end
            context.remember(key, state);
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
