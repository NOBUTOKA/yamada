classdef SourcePropertyHistory
    % SourcePropertyHistory Retain primary source edits and occurrence identities, never derived positions.
    %   Exact forward/inverse text patches and typed primary values avoid reparsing. Occurrence IDs
    %   and edited-path guards restore ownership when applying the indexed edit in either direction.
    methods (Static)
        function history = capture(before, after, paths)
            % capture Record only identity additions/removals and the edited paths' ownership guards.
            arguments (Input)
                before macd.model.PropertySetting
                after macd.model.PropertySetting
                paths (1, :) string
            end
            arguments (Output)
                history (1, 1) struct
            end
            targets = struct("Path", {}, "BeforeId", {}, "AfterId", {}, "BeforeValue", {}, "AfterValue", {});
            for path = paths
                old = before(string({before.Path}) == path);
                current = after(string({after.Path}) == path);
                first = 0; last = 0;
                if ~isempty(old), first = old(end).Id; end
                if ~isempty(current), last = current(end).Id; end
                beforeValue = []; afterValue = [];
                if ~isempty(old), beforeValue = old(end).LiteralValue; end
                if ~isempty(current), afterValue = current(end).LiteralValue; end
                targets(end + 1) = struct("Path", path, "BeforeId", first, "AfterId", last, ...
                    "BeforeValue", {beforeValue}, "AfterValue", {afterValue}); %#ok<AGROW>
            end
            removed = macd.model.SourcePropertyHistory.identities(before, ~ismember(string({before.Id}), string({after.Id})));
            added = macd.model.SourcePropertyHistory.identities(after, ~ismember(string({after.Id}), string({before.Id})));
            history = struct("Targets", targets, "Removed", removed, "Added", added);
        end

        function settings = restoreIdentities(settings, identities)
            % restoreIdentities Restore only primary occurrence identities after current positions are derived from source.
            arguments (Input)
                settings macd.model.PropertySetting
                identities struct
            end
            arguments (Output)
                settings macd.model.PropertySetting
            end
            for identity = identities
                candidates = find(string({settings.Path}) == identity.Path & string({settings.Method}) == identity.Method);
                assert(numel(candidates) >= identity.Ordinal, "macd:SourcePropertyHistory:MissingOccurrence", ...
                    "The inverse source patch must restore the same setting occurrence.");
                index = candidates(identity.Ordinal);
                settings(index) = settings(index).withHistoryIdentity(identity);
            end
        end
    end
    methods (Static, Access = private)
        function records = identities(settings, included)
            % identities Capture stable IDs and within-path ordinals without source ranges, values or execution sequences.
            arguments (Input)
                settings macd.model.PropertySetting
                included logical
            end
            arguments (Output)
                records struct
            end
            records = struct("Path", {}, "Method", {}, "Ordinal", {}, "Id", {}, ...
                "SourceSnapshotId", {}, "StatementId", {}, "InitializationScopeId", {});
            for index = find(included)
                setting = settings(index);
                preceding = settings(1:index);
                ordinal = nnz(string({preceding.Path}) == setting.Path & string({preceding.Method}) == setting.Method);
                records(end + 1) = struct("Path", setting.Path, "Method", setting.Method, "Ordinal", ordinal, ...
                    "Id", setting.Id, "SourceSnapshotId", setting.SourceSnapshotId, "StatementId", setting.StatementId, ...
                    "InitializationScopeId", setting.InitializationScopeId); %#ok<AGROW>
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
