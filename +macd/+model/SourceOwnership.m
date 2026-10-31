classdef SourceOwnership
    % SourceOwnership Distinguish current physical source ownership from original provenance.
    %   Parsed and newly inserted components use the same checks after publication.
    methods (Static)
        function result = hasSource(record)
            % hasSource Return whether a component or value snapshot owns a current factory statement.
            arguments (Input)
                record
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = ~isempty(record.SourceSpans.Creation) && ...
                isa(record.SourceSpans.Creation, "macd.model.SourceSpan") && record.SourceSpans.Creation.isKnown();
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
