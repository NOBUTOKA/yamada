classdef SourceSettingStore < handle
    % SourceSettingStore Own canonical value settings and maintained source-position indexes.
    %   Documents and their components share this private storage, never mutable Setting
    %   instances. Detached snapshots contain values only. Slots stay stable across owners.
    properties (SetAccess = private)
        % Revision - Version of canonical records, including derived position updates.
        Revision uint64 = uint64(0)
    end
    properties (GetAccess = ?yamada.model.ComponentRecord, SetAccess = private)
        Records yamada.model.PropertySetting = yamada.model.PropertySetting.empty
    end
    properties (Access = private)
        NextId double = 1
        Owners string = strings(1, 0)
        Active logical = false(1, 0)
        Ranges cell = cell(5, 0)
        SourceOrder double = zeros(1, 0)
        SourceStarts double = zeros(1, 0)
        ValueStarts double = zeros(1, 0)
    end
    methods
        function reserveIds(obj, ids)
            % reserveIds Protect every imported canonical address before allocating detached additions.
            arguments (Input)
                obj (1, 1) yamada.model.SourceSettingStore
                ids (1, :) double
            end
            obj.NextId = max(obj.NextId, max([0 ids]) + 1);
        end

        function setting = canonicalize(obj, setting)
            % canonicalize Reserve a stable ID before preparing or publishing a candidate occurrence.
            arguments (Input)
                obj (1, 1) yamada.model.SourceSettingStore
                setting (1, 1) yamada.model.PropertySetting
            end
            arguments (Output)
                setting (1, 1) yamada.model.PropertySetting
            end
            if setting.Id > 0, return, end
            setting = setting.withIdentity(obj.NextId, setting.SourceSnapshotId);
            obj.NextId = obj.NextId + 1;
        end

        function settings = get(obj, slots)
            % get Return independent value records by stable owner slots without rebuilding them.
            arguments (Input)
                obj (1, 1) yamada.model.SourceSettingStore
                slots (1, :) double
            end
            arguments (Output)
                settings yamada.model.PropertySetting
            end
            settings = obj.Records(slots);
        end

        function slots = replace(obj, owner, slots, settings)
            % replace Update one owner's records and its index while preserving every other owner's slots.
            arguments (Input)
                obj (1, 1) yamada.model.SourceSettingStore
                owner (1, 1) string
                slots (1, :) double
                settings yamada.model.PropertySetting
            end
            arguments (Output)
                slots (1, :) double
            end
            obj.reserveIds([settings.Id]);
            for index = 1:numel(settings)
                setting = settings(index);
                id = setting.Id;
                collision = id > 0 && id <= numel(obj.Records) && strlength(obj.Owners(id)) > 0 && obj.Owners(id) ~= owner;
                if id <= 0 || collision
                    setting = setting.withIdentity(obj.NextId, setting.SourceSnapshotId);
                    obj.NextId = obj.NextId + 1;
                    settings(index) = setting;
                else
                    obj.NextId = max(obj.NextId, id + 1);
                end
            end
            ids = [settings.Id];
            assert(numel(unique(ids)) == numel(ids), "yamada:SourceSettingStore:DuplicateIdentity", ...
                "Every source occurrence needs a distinct canonical ID.");
            removed = setdiff(slots, ids);
            obj.Active(removed) = false;
            for slot = removed, obj.Records(slot) = yamada.model.PropertySetting(); end
            obj.Ranges(:, removed) = repmat({yamada.model.SourceSpan.empty}, 5, numel(removed));
            slots = ids;
            count = numel(slots);
            if ~isempty(slots) && max(slots) > numel(obj.Records)
                last = max(slots);
                obj.Records(last) = yamada.model.PropertySetting();
                obj.Active(last) = false;
                obj.Owners(last) = "";
                obj.Ranges(:, end + 1:last) = repmat({yamada.model.SourceSpan.empty}, 5, last - size(obj.Ranges, 2));
            end
            if count > 0
                obj.Records(slots) = reshape(settings, 1, []);
                obj.Owners(slots) = owner;
                obj.Active(slots) = true;
                fields = ["SourceSpan", "ValueSpan", "NameSpan", "PairSpan", "ScopeSpan"];
                for field = 1:5
                    obj.Ranges(field, slots) = arrayfun(@(item) {item.(fields(field))}, reshape(settings, 1, []));
                end
            end
            obj.SourceStarts(slots) = yamada.model.SourceSettingStore.starts(obj.Ranges(1, slots));
            obj.ValueStarts(slots) = yamada.model.SourceSettingStore.starts(obj.Ranges(2, slots));
            obj.reorder();
            obj.Revision = obj.Revision + uint64(1);
        end

        function [settings, owners] = inSourceOrder(obj)
            % inSourceOrder Read the maintained physical ordering independently from execution sequence.
            arguments (Input)
                obj (1, 1) yamada.model.SourceSettingStore
            end
            arguments (Output)
                settings yamada.model.PropertySetting
                owners (1, :) string
            end
            settings = obj.Records(obj.SourceOrder);
            owners = obj.Owners(obj.SourceOrder);
        end

        function projection = prepare(obj, batch, execution, excludedOwner)
            % prepare Transform the maintained range index once and derive execution order without owner serialization.
            arguments (Input)
                obj (1, 1) yamada.model.SourceSettingStore
                batch (1, 1) yamada.source.SourcePatchBatch
                execution (1, 1) struct
                excludedOwner (1, :) string
            end
            arguments (Output)
                projection (1, 1) struct
            end
            slots = obj.SourceOrder(~ismember(obj.Owners(obj.SourceOrder), excludedOwner));
            indexed = obj.Ranges;
            excluded = find(obj.Active & ismember(obj.Owners, excludedOwner));
            indexed(:, excluded) = repmat({yamada.model.SourceSpan.empty}, 5, numel(excluded));
            if isfield(execution, "ScopeMethods"), indexed(5, :) = {yamada.model.SourceSpan.empty}; end
            [ranges, valid] = batch.mapSpanCells(indexed);
            ranges(:, excluded) = obj.Ranges(:, excluded);
            assert(all(valid, "all"), "yamada:SourceLiteralTransaction:WiderProof", "Indexed settings require syntax rebinding.");
            if isfield(execution, "ScopeMethods")
                for slot = slots
                    match = find(string({execution.ScopeMethods.Name}) == obj.Records(slot).OwnerMethod);
                    if isscalar(match), ranges{5, slot} = execution.ScopeMethods(match).Span; end
                end
            end
            settings = obj.Records;
            if ~isempty(slots)
                statements = [ranges{1, slots}];
                assert(numel(statements) == numel(slots), "yamada:SourceLiteralTransaction:WiderProof", "Every indexed setting needs a source statement.");
                if isfield(execution, "SequenceMap")
                    before = [settings(slots).Sequence];
                    assert(all(before > 0 & before <= numel(execution.SequenceMap)));
                    sequences = execution.SequenceMap(before);
                else
                    [found, positions] = ismember([[statements.StartOffset]' [statements.EndOffset]'], ...
                        [execution.RangeStarts(:) execution.RangeEnds(:)], "rows");
                    assert(all(found), "yamada:SourceLiteralTransaction:WiderProof", "Indexed setting execution must remain unique.");
                    visits = reshape(execution.Visits(positions), 1, []);
                    sequences = reshape(execution.Assignment(visits), 1, []);
                    constructor = string({settings(slots).Method}) == "nameValue";
                    % Existing constructor-pair order remains fixed for a position-only projection.
                    ids = string({settings(slots).StatementId});
                    ordinal = zeros(size(slots));
                    for index = find(constructor)
                        ordinal(index) = nnz(constructor(1:index) & ids(1:index) == ids(index));
                    end
                    sequences(constructor) = reshape(execution.Creation(visits(constructor)), 1, []) + ordinal(constructor);
                end
                settings(slots) = settings(slots).withIndexedLocations(ranges(:, slots), sequences);
            end
            projection = struct("Revision", obj.Revision, "Before", obj.Records, ...
                "After", settings, "Ranges", {ranges});
        end

        function publish(obj, projection)
            % publish Adopt a fully prepared derived projection after the document validates all owners.
            arguments (Input)
                obj (1, 1) yamada.model.SourceSettingStore
                projection (1, 1) struct
            end
            assert(obj.Revision == projection.Revision, "yamada:SourceSettingStore:StaleProjection", "The setting store changed during preparation.");
            obj.Records = projection.After;
            obj.Ranges = projection.Ranges;
            obj.SourceStarts = yamada.model.SourceSettingStore.starts(obj.Ranges(1, :));
            obj.ValueStarts = yamada.model.SourceSettingStore.starts(obj.Ranges(2, :));
            obj.Revision = obj.Revision + uint64(1);
        end
    end
    methods (Access = ?yamada.model.DocumentModel)
        function reserveAfter(obj, previous)
            % reserveAfter Keep detached candidate allocation above every issued live occurrence address.
            arguments (Input)
                obj (1, 1) yamada.model.SourceSettingStore
                previous (1, 1) yamada.model.SourceSettingStore
            end
            obj.NextId = max(obj.NextId, previous.NextId);
        end
    end

    methods (Access = private)
        function reorder(obj)
            % reorder Maintain a source-order index after explicit insertion, removal or structural replacement.
            arguments (Input)
                obj (1, 1) yamada.model.SourceSettingStore
            end
            slots = find(obj.Active);
            [~, order] = sortrows([obj.SourceStarts(slots)' obj.ValueStarts(slots)'], [1 2]);
            obj.SourceOrder = slots(order);
        end
    end
    methods (Static, Access = private)
        function offsets = starts(ranges)
            % starts Maintain numeric sort keys from the prepared range index, never by gathering owner settings.
            arguments (Input)
                ranges cell
            end
            arguments (Output)
                offsets double
            end
            offsets = inf(size(ranges));
            present = find(~cellfun(@isempty, ranges));
            if isempty(present), return, end
            spans = [ranges{present}];
            values = [spans.StartOffset];
            values(values == 0) = inf;
            offsets(present) = values;
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
