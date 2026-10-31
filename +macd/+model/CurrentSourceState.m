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
        Analysis macd.source.SourceAnalysis
    end

    methods
        function obj = CurrentSourceState(source, analysis)
            % CurrentSourceState Adopt a parser-owned analysis or compile the initial lexical input once.
            arguments (Input)
                source (1, 1) string = ""
                analysis macd.source.SourceAnalysis = macd.source.SourceAnalysis.empty
            end
            arguments (Output)
                obj (1, 1) macd.model.CurrentSourceState
            end
            if isempty(analysis), analysis = macd.source.SourceAnalysis(source); end
            assert(isscalar(analysis) && analysis.matches(source), ...
                "macd:CurrentSourceState:StaleAnalysis", "Analysis must describe the exact working source.");
            obj.Text = source;
            obj.Analysis = analysis;
            obj.StateId = string(java.util.UUID.randomUUID());
        end

        function [candidate, statistics] = withBatch(obj, batch, restoredStateId)
            % withBatch Prepare a new source revision without changing already published state.
            arguments (Input)
                obj (1, 1) macd.model.CurrentSourceState
                batch (1, 1) macd.source.SourcePatchBatch
                restoredStateId (1, 1) string = ""
            end
            arguments (Output)
                candidate (1, 1) macd.model.CurrentSourceState
                statistics (1, 1) struct
            end
            batch.apply(obj.Text);
            [analysis, ~, statistics] = obj.Analysis.withPatches(batch);
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

        function assertRevision(obj, revision, stateId)
            % assertRevision Reject a candidate prepared before another transaction was published.
            arguments (Input)
                obj (1, 1) macd.model.CurrentSourceState
                revision (1, 1) uint64
                stateId (1, 1) string
            end
            assert(obj.Revision == revision && obj.StateId == stateId, ...
                "macd:CurrentSourceState:StaleCandidate", "The working state changed during transaction preparation.");
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
