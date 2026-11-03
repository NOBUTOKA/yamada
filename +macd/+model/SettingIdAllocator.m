classdef SettingIdAllocator
    % SettingIdAllocator Issue temporary identities for detached setting values before document registration.
    %   Positive canonical IDs are reserved by each document-owned store. This scalar
    %   token counter retains no document, setting payload, or per-revision map.
    methods (Static)
        function id = temporary()
            % temporary Issue an opaque negative token until a document assigns the canonical array address.
            arguments (Output)
                id (1, 1) double
            end
            persistent next
            if isempty(next), next = -1; end
            id = next;
            next = next - 1;
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
