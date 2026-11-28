classdef ValidationReuse
    % ValidationReuse Bind reusable validation results to the document and input revision that produced them.
    %   A document stores one ValidationReuse value instead of separate
    %   context, diagnostics, and pending-owner fields. Readers ask whether
    %   the value is current for a document and catalog; a value issued for
    %   another document, an older input revision, or another catalog
    %   revision reads as absent, so writers need not clear it.
    %
    %   Example:
    %       reuse = yamada.model.ValidationReuse(document, context, diagnostics);
    %       if reuse.isComplete(document, registry), diagnostics = reuse.Diagnostics; end

    properties (GetAccess = ?yamada.model.DocumentModel, SetAccess = private)
        % Context - Evaluation context whose input token certifies these results.
        Context yamada.model.EvaluationContext = yamada.model.EvaluationContext.empty
        % Diagnostics - Validation diagnostics computed for Context's inputs.
        Diagnostics yamada.model.Diagnostic = yamada.model.Diagnostic.empty
        % Pending - Owner names whose diagnostics still need a bounded recheck.
        Pending string = strings(1, 0)
    end

    properties (Access = private)
        Document yamada.model.DocumentModel = yamada.model.DocumentModel.empty
    end

    methods (Access = ?yamada.model.DocumentModel)
        function obj = ValidationReuse(document, context, diagnostics, pending)
            % ValidationReuse Issue results for one document and the input token of one evaluation context.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                context (1, 1) yamada.model.EvaluationContext
                diagnostics yamada.model.Diagnostic
                pending (1, :) string = strings(1, 0)
            end
            arguments (Output)
                obj (1, 1) yamada.model.ValidationReuse
            end
            obj.Document = document; obj.Context = context;
            obj.Diagnostics = diagnostics; obj.Pending = pending;
        end

        function result = isCurrent(obj, document, registry)
            % isCurrent Require the issuing document and an unchanged input and catalog token.
            arguments (Input)
                obj (1, 1) yamada.model.ValidationReuse
                document (1, 1) yamada.model.DocumentModel
                registry (1, 1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = obj.Document == document && obj.Context.matches(document, registry);
        end

        function result = isComplete(obj, document, registry)
            % isComplete Require current results with no pending owner and no error.
            arguments (Input)
                obj (1, 1) yamada.model.ValidationReuse
                document (1, 1) yamada.model.DocumentModel
                registry (1, 1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = isempty(obj.Pending) && obj.isCurrent(document, registry) && ...
                ~yamada.validation.ModelValidator.hasErrors(obj.Diagnostics);
        end

        function result = isTracked(obj)
            % isTracked Report whether the certifying context still follows a live write token.
            arguments (Input)
                obj (1, 1) yamada.model.ValidationReuse
            end
            arguments (Output)
                result (1, 1) logical
            end
            [~, result] = obj.Context.revisionToken();
        end

        function obj = withChecked(obj, diagnostics)
            % withChecked Replace diagnostics after the pending owners have been rechecked.
            arguments (Input)
                obj (1, 1) yamada.model.ValidationReuse
                diagnostics yamada.model.Diagnostic
            end
            arguments (Output)
                obj (1, 1) yamada.model.ValidationReuse
            end
            obj.Diagnostics = diagnostics; obj.Pending = strings(1, 0);
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
