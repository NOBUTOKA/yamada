classdef CurrentSourceState
    % CurrentSourceState Hold one exact working source and its revision-bound lexical analysis.
    %   Candidates are immutable values. The document must validate and publish model
    %   changes atomically with this source state; this class never mutates a live model.

    properties (SetAccess = private)
        % Text - Exact current working source shared by editing, output and diagnostics.
        Text string = ""
        % Revision - Monotonic source-publication revision, including Undo and Redo.
        Revision uint64 = uint64(1)
        % StateId - History identity independent of offsets and monotonic revisions.
        StateId string = ""
        % Analysis - Read-only lexical data compiled for Text, without live model references.
        Analysis yamada.source.SourceAnalysis
    end

    methods
        function obj = CurrentSourceState(source, analysis)
            % CurrentSourceState Adopt a parser-owned analysis or compile the initial lexical input once.
            arguments (Input)
                source (1, 1) string = ""
                analysis yamada.source.SourceAnalysis = yamada.source.SourceAnalysis.empty
            end
            arguments (Output)
                obj (1, 1) yamada.model.CurrentSourceState
            end
            if isempty(analysis), analysis = yamada.source.SourceAnalysis(source); end
            assert(isscalar(analysis) && analysis.matches(source), ...
                "yamada:CurrentSourceState:StaleAnalysis", "Analysis must describe the exact working source.");
            obj.Text = source;
            obj.Analysis = analysis;
            obj.StateId = string(java.util.UUID.randomUUID());
        end

        function [candidate, statistics] = withBatch(obj, batch, restoredStateId, preparedAnalysis)
            % withBatch Prepare a new source revision without changing already published state.
            arguments (Input)
                obj (1, 1) yamada.model.CurrentSourceState
                batch (1, 1) yamada.source.SourcePatchBatch
                restoredStateId (1, 1) string = ""
                preparedAnalysis yamada.source.SourceAnalysis = yamada.source.SourceAnalysis.empty
            end
            arguments (Output)
                candidate (1, 1) yamada.model.CurrentSourceState
                statistics (1, 1) struct
            end
            batch.apply(obj.Text);
            if isempty(preparedAnalysis)
                [analysis, ~, statistics] = obj.Analysis.withPatches(batch);
            else
                assert(preparedAnalysis.matches(batch.AfterText));
                analysis = preparedAnalysis;
                statistics = struct("ScannedCharacters", 0, "ReusedStatements", numel(analysis.Statements), "FullScan", false);
            end
            candidate = obj;
            candidate.Text = batch.AfterText;
            candidate.Analysis = analysis;
            candidate.Revision = obj.Revision + uint64(1);
            if strlength(restoredStateId) > 0
                % Undo/Redo restores a history node while still invalidating older caches.
                candidate.StateId = restoredStateId;
            else
                candidate.StateId = string(java.util.UUID.randomUUID());
            end
        end

        function obj = withAnalysis(obj, analysis)
            % withAnalysis Adopt an already validated exact-source index without changing revision or history identity.
            arguments (Input)
                obj (1, 1) yamada.model.CurrentSourceState
                analysis (1, 1) yamada.source.SourceAnalysis
            end
            arguments (Output)
                obj (1, 1) yamada.model.CurrentSourceState
            end
            assert(analysis.matches(obj.Text));
            obj.Analysis = analysis;
        end

        function assertRevision(obj, revision, stateId)
            % assertRevision Reject a candidate prepared before another transaction was published.
            arguments (Input)
                obj (1, 1) yamada.model.CurrentSourceState
                revision (1, 1) uint64
                stateId (1, 1) string
            end
            assert(obj.Revision == revision && obj.StateId == stateId, ...
                "yamada:CurrentSourceState:StaleCandidate", "The working state changed during transaction preparation.");
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
