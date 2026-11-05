classdef SourceAssertions
    % SourceAssertions Compare stable source occurrence semantics independently of current coordinates.
    %   Test helpers retain identity and literal/source-expression assertions while offsets move.
    methods (Static)
        function actual = retained(records, previous)
            % retained Select surviving occurrence identities in their original relative order.
            arguments (Input)
                records struct
                previous struct
            end
            arguments (Output)
                actual struct
            end
            ids = strings(1, numel(previous));
            for index = 1:numel(previous), ids(index) = previous(index).Location.Id; end
            current = strings(1, numel(records));
            for index = 1:numel(records), current(index) = records(index).Location.Id; end
            actual = yamadaTestSemantics(records(ismember(current, ids)));
        end

        function actual = semantics(records)
            % semantics Preserve value, syntax and opaque identities while excluding movable source positions.
            arguments (Input)
                records struct
            end
            arguments (Output)
                actual struct
            end
            actual = yamadaTestSemantics(records);
        end
    end
end

function records = yamadaTestSemantics(records)
% yamadaTestSemantics Normalize physical locations without hiding changed explicit settings.
arguments (Input)
    records struct
end
arguments (Output)
    records struct
end
for index = 1:numel(records)
    fields = intersect(string(fieldnames(records(index).Location)), ...
        ["SourceSpan", "ValueSpan", "NameSpan", "PairSpan", "ScopeSpan", "Sequence", "FactoryArgumentIndex"]);
    records(index).Location = rmfield(records(index).Location, fields);
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
