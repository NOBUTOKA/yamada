classdef InputChangeClock < handle
    % InputChangeClock Track semantic writes without retaining documents or records.
    %   Model owners share this acyclic revision token. Shared record ownership
    %   disables the fast path conservatively.
    properties (SetAccess = private)
        % Revision - Monotonically increasing semantic-write counter.
        Revision uint64 = uint64(0)
        % IsTracked - Whether all subsequent mutations can be observed locally.
        IsTracked logical = true
    end

    methods
        function touch(obj)
            % touch Record one semantic assignment.
            arguments (Input)
                obj (1, 1) yamada.model.InputChangeClock
            end
            obj.Revision = obj.Revision + uint64(1);
        end

        function disable(obj)
            % disable Require exact-value comparison after ownership becomes ambiguous.
            arguments (Input)
                obj (1, 1) yamada.model.InputChangeClock
            end
            obj.IsTracked = false;
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
