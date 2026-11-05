classdef SourceOwnership
    % SourceOwnership Distinguish current physical source ownership from original provenance.
    %   Parsed and newly inserted components use the same checks after publication.
    methods (Static)
        function snapshots = snapshot(records)
            % snapshot Freeze only source ownership values needed by deletion, without retaining model handles.
            arguments (Input)
                records yamada.model.ComponentRecord
            end
            arguments (Output)
                snapshots struct
            end
            snapshots = struct("Id", {}, "Name", {}, "Origin", {}, "SourceSpans", {}, "Properties", {}, "Settings", {});
            for record = reshape(records, 1, [])
                properties = struct("SourceSpan", {});
                for entry = reshape(record.Properties, 1, [])
                    properties(end + 1) = struct("SourceSpan", entry.SourceSpan); %#ok<AGROW>
                end
                settings = struct("SourceSpan", {});
                for setting = reshape(record.Settings, 1, [])
                    settings(end + 1) = struct("SourceSpan", setting.SourceSpan); %#ok<AGROW>
                end
                spans = struct("Declaration", record.SourceSpans.Declaration, "Creation", record.SourceSpans.Creation);
                snapshots(end + 1) = struct("Id", record.Id, "Name", record.Name, "Origin", record.Origin, ...
                    "SourceSpans", spans, "Properties", properties, "Settings", settings); %#ok<AGROW>
            end
        end

        function result = hasSource(record)
            % hasSource Recognize imported ownership and already published generated factory statements.
            arguments (Input)
                record
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = record.Origin == "parsed" || (~isempty(record.SourceSpans.Creation) && ...
                isa(record.SourceSpans.Creation, "yamada.model.SourceSpan") && record.SourceSpans.Creation.isKnown());
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
