classdef SourceHistoryRebaser
    % SourceHistoryRebaser Rebase current text and reversible history when Save As changes class identity.
    %   Saving changes no history node and introduces no extra Undo operation.
    methods (Static)
        function [text, history] = rename(current, history, index, className)
            % rename Prepare renamed source transitions and setting ranges across both history branches.
            arguments (Input)
                current (1, 1) string
                history cell
                index (1, 1) double
                className (1, 1) string
            end
            arguments (Output)
                text (1, 1) string
                history cell
            end
            sources = strings(1, numel(history) + 1);
            sources(index + 1) = current;
            for cursor = index:-1:1
                assert(isfield(history{cursor}, "SourceInverse"), ...
                    "yamada:SourceHistoryRebaser:UnpublishedHistory", "History must own exact source patches before Save As.");
                batch = yamada.source.SourcePatchBatch(sources(cursor + 1), history{cursor}.SourceInverse);
                sources(cursor) = batch.AfterText;
            end
            for cursor = index + 1:numel(history)
                batch = yamada.source.SourcePatchBatch(sources(cursor), history{cursor}.SourceForward);
                sources(cursor + 1) = batch.AfterText;
            end
            renamed = strings(size(sources));
            mappings = cell(size(sources));
            for cursor = 1:numel(sources)
                [renamed(cursor), diagnostics] = yamada.source.AppClassIdentityRewriter.rewrite(sources(cursor), className);
                assert(~yamada.validation.ModelValidator.hasErrors(diagnostics));
                mappings{cursor} = yamada.model.SourceHistoryRebaser.lineChanges(sources(cursor), renamed(cursor));
            end
            for cursor = 1:numel(history)
                edit = history{cursor};
                transition = yamada.model.SourceHistoryRebaser.transition(edit, sources(cursor), ...
                    renamed(cursor), renamed(cursor + 1), mappings{cursor}, mappings{cursor + 1});
                edit.SourceForward = transition.Edits;
                edit.SourceInverse = transition.InverseEdits;
                if edit.Kind == "source-property" && isfield(edit, "BeforeSettings")
                    edit.BeforeSettings = yamada.model.SourceLocationUpdate.relocateSettings(edit.BeforeSettings, mappings{cursor});
                    edit.AfterSettings = yamada.model.SourceLocationUpdate.relocateSettings(edit.AfterSettings, mappings{cursor + 1});
                end
                % Insertion anchors belong to the before-source coordinate system, including nested batch owners.
                if isfield(edit, "Insertions")
                    edit.Insertions = yamada.model.SourceHistoryRebaser.mapInsertions(edit.Insertions, mappings{cursor});
                end
                if isfield(edit, "Owners")
                    for ownerIndex = 1:numel(edit.Owners)
                        edit.Owners(ownerIndex).Insertions = yamada.model.SourceHistoryRebaser.mapInsertions( ...
                            edit.Owners(ownerIndex).Insertions, mappings{cursor});
                    end
                end
                if any(edit.Kind == ["source-subtree-insert", "source-subtree-delete"]) || (edit.Kind == "rename" && isfield(edit, "IndexedRename"))
                    forwardField = "ComponentForward"; inverseField = "ComponentInverse";
                    if edit.Kind == "rename", forwardField = "IdentifierForward"; inverseField = "IdentifierInverse"; end
                    if isempty(edit.StagedEdit)
                        edit.(forwardField) = transition.Edits; edit.(inverseField) = transition.InverseEdits;
                    else
                        staged = edit.StagedEdit;
                        middle = yamada.source.SourcePatchBatch(sources(cursor), staged.SourceForward).AfterText;
                        renamedMiddle = yamada.source.AppClassIdentityRewriter.rewrite(middle, className);
                        middleMap = yamada.model.SourceHistoryRebaser.lineChanges(middle, renamedMiddle);
                        stagedBatch = yamada.model.SourceHistoryRebaser.transition(staged, sources(cursor), ...
                            renamed(cursor), renamedMiddle, mappings{cursor}, middleMap);
                        staged.SourceForward = stagedBatch.Edits; staged.SourceInverse = stagedBatch.InverseEdits;
                        for ownerIndex = 1:numel(staged.Owners)
                            staged.Owners(ownerIndex).Insertions = yamada.model.SourceHistoryRebaser.mapInsertions( ...
                                staged.Owners(ownerIndex).Insertions, mappings{cursor});
                        end
                        component = struct("SourceForward", edit.(forwardField));
                        componentBatch = yamada.model.SourceHistoryRebaser.transition(component, middle, ...
                            renamedMiddle, renamed(cursor + 1), middleMap, mappings{cursor + 1});
                        edit.(forwardField) = componentBatch.Edits; edit.(inverseField) = componentBatch.InverseEdits;
                        edit.StagedEdit = staged;
                    end
                end
                history{cursor} = edit;
            end
            text = renamed(index + 1);
        end

        function batch = lineChanges(before, after)
            % lineChanges Keep unaffected line locations mappable while allowing line insertions in history transitions.
            arguments (Input)
                before (1, 1) string
                after (1, 1) string
            end
            arguments (Output)
                batch (1, 1) yamada.source.SourcePatchBatch
            end
            old = regexp(char(before), '[^\n]*\n|[^\n]+$', 'match');
            current = regexp(char(after), '[^\n]*\n|[^\n]+$', 'match');
            edits = struct("Start", {}, "End", {}, "Text", {});
            if numel(old) == numel(current)
                offset = 0;
                for index = 1:numel(old)
                    edit = yamada.model.SourceHistoryRebaser.changedRange(old{index}, current{index}, offset);
                    edits = [edits edit]; %#ok<AGROW>
                    offset = offset + numel(old{index});
                end
            else
                edits = yamada.model.SourceHistoryRebaser.changedRange(char(before), char(after), 0);
            end
            batch = yamada.source.SourcePatchBatch(before, edits);
        end
    end
    methods (Static, Access = private)
        function batch = transition(edit, before, renamedBefore, renamedAfter, beforeMap, afterMap)
            % transition Retain separate owned edit ranges when class identity changes across history.
            arguments (Input)
                edit (1, 1) struct
                before (1, 1) string
                renamedBefore (1, 1) string
                renamedAfter (1, 1) string
                beforeMap (1, 1) yamada.source.SourcePatchBatch
                afterMap (1, 1) yamada.source.SourcePatchBatch
            end
            arguments (Output)
                batch (1, 1) yamada.source.SourcePatchBatch
            end
            original = yamada.source.SourcePatchBatch(before, edit.SourceForward);
            edits = struct("Start", {}, "End", {}, "Text", {});
            shift = 0;
            for index = 1:numel(original.Edits)
                forward = original.Edits(index);
                inverse = struct("Start", forward.Start + shift, "End", forward.Start + shift + strlength(forward.Text) - 1);
                shift = shift + strlength(forward.Text) - (forward.End - forward.Start + 1);
                [first, valid] = beforeMap.mapBoundary(forward.Start - 1, "right");
                assert(valid);
                last = first;
                if forward.End >= forward.Start
                    [last, valid] = beforeMap.mapBoundary(forward.End, "left");
                    assert(valid);
                end
                replacement = "";
                if inverse.End >= inverse.Start
                    [span, valid] = afterMap.mapSpan(yamada.model.SourceSpan(inverse.Start, inverse.End));
                    assert(valid);
                    replacement = extractBetween(renamedAfter, span.StartOffset, span.EndOffset);
                end
                edits(end + 1) = struct("Start", first + 1, "End", last, "Text", replacement); %#ok<AGROW>
            end
            batch = yamada.source.SourcePatchBatch(renamedBefore, edits);
            assert(batch.AfterText == renamedAfter, "yamada:SourceHistoryRebaser:TransitionMismatch", ...
                "Renamed history must reproduce the exact current source.");
        end

        function placements = mapInsertions(placements, mapping)
            % mapInsertions Retain primary insertion anchors when Save As shifts source positions.
            arguments (Input)
                placements (1, :) struct
                mapping (1, 1) yamada.source.SourcePatchBatch
            end
            arguments (Output)
                placements (1, :) struct
            end
            for index = 1:numel(placements)
                [offset, valid] = mapping.mapBoundary(placements(index).Offset, "right");
                assert(valid, "yamada:SourceHistoryRebaser:InsertionMismatch", "Save As must preserve an owned insertion anchor.");
                placements(index).Offset = offset;
            end
        end

        function edits = changedRange(old, current, offset)
            % changedRange Find one exact replacement within a line or a wider structural history transition.
            arguments (Input)
                old (1, :) char
                current (1, :) char
                offset (1, 1) double
            end
            arguments (Output)
                edits struct
            end
            first = 1;
            while first <= min(numel(old), numel(current)) && old(first) == current(first), first = first + 1; end
            lastOld = numel(old);
            lastNew = numel(current);
            while lastOld >= first && lastNew >= first && old(lastOld) == current(lastNew)
                lastOld = lastOld - 1;
                lastNew = lastNew - 1;
            end
            edits = struct("Start", {}, "End", {}, "Text", {});
            if first <= lastOld || first <= lastNew
                edits = struct("Start", offset + first, "End", offset + lastOld, "Text", string(current(first:lastNew)));
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
