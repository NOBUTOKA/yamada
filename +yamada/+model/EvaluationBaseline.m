classdef EvaluationBaseline
    % EvaluationBaseline Read-only view of the last accepted evaluation state of a document.
    %   A structural candidate plans its validation against the evaluation
    %   state of the document it was copied from. The baseline exposes only
    %   the reads that planning needs, so a candidate cannot record values
    %   in, or inherit into, the source document's own evaluation context.
    %   Only EvaluationContext reads the wrapped context, to rebase states.
    %
    %   Example:
    %       baseline = yamada.model.EvaluationBaseline(context);
    %       scope = baseline.editScope(candidate, changedIds);

    properties (Access = private)
        Context yamada.model.EvaluationContext = yamada.model.EvaluationContext.empty
    end

    methods
        function obj = EvaluationBaseline(context)
            % EvaluationBaseline Wrap one accepted evaluation context without copying it.
            arguments (Input)
                context (1, 1) yamada.model.EvaluationContext
            end
            arguments (Output)
                obj (1, 1) yamada.model.EvaluationBaseline
            end

            obj.Context = context;
        end

        function [token, tracked] = revisionToken(obj)
            % revisionToken Return the input and catalog identities of the baseline.
            arguments (Input)
                obj (1, 1) yamada.model.EvaluationBaseline
            end
            arguments (Output)
                token (1, 1) struct
                tracked (1, 1) logical
            end

            [token, tracked] = obj.Context.revisionToken();
        end

        function plan = editScope(obj, document, changed)
            % editScope Derive checked owners and invalidated dependencies against the baseline.
            arguments (Input)
                obj (1, 1) yamada.model.EvaluationBaseline
                document (1, 1) yamada.model.DocumentModel
                changed (1, :) string
            end
            arguments (Output)
                plan (1, 1) struct
            end

            plan = obj.Context.editScope(document, changed);
        end
    end

    methods (Access = ?yamada.model.EvaluationContext)
        function context = context(obj)
            % context Return the wrapped context for read-only state rebasing.
            arguments (Input)
                obj (1, 1) yamada.model.EvaluationBaseline
            end
            arguments (Output)
                context (1, 1) yamada.model.EvaluationContext
            end

            context = obj.Context;
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
