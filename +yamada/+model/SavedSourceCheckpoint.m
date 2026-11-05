classdef SavedSourceCheckpoint
    % SavedSourceCheckpoint Retain independent positions in confirmed saved output.
    %   This value object reparses generated text without executing it and compares
    %   audited effective values before a write. Saved locations remain separate
    %   from the immutable edit baseline used by existing Undo/Redo intentions.
    %
    %   Example:
    %       checkpoint = yamada.model.SavedSourceCheckpoint(document, source, path, registry);

    properties (SetAccess = private)
        % SourceText - Normalized text whose offsets describe the saved file.
        SourceText string = ""
        % FilePath - Intended path, confirmed only when the document accepts this checkpoint.
        FilePath string = ""
        % ClassName - Class identity parsed from the normalized output.
        ClassName string = ""
        % SourceSnapshotId - Independent source version owning the saved positions.
        SourceSnapshotId string = ""
        % Snapshot - Value-only records, settings, and positions in the saved source.
        Snapshot yamada.model.SubtreeSnapshot = yamada.model.SubtreeSnapshot.empty
        % ComponentMap - Editable component identities paired with saved parsed identities.
        ComponentMap struct = struct("ComponentId", {}, "SavedId", {}, "Name", {})
        % HistoryIndex - Document history position represented by this saved output.
        HistoryIndex double = 0
    end

    properties (Access = private)
        Validation yamada.model.DocumentValidationProof = yamada.model.DocumentValidationProof.empty
        InputContext yamada.model.EvaluationContext = yamada.model.EvaluationContext.empty
        BaselineText string = ""
        BaselineSnapshotId string = ""
        BaselineClassName string = ""
        LineEnding string = ""
    end

    methods
        function obj = SavedSourceCheckpoint(document, source, filePath, registry)
            % SavedSourceCheckpoint Prepare saved positions and verify known initial states before I/O.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                source (1, 1) string
                filePath (1, 1) string
                registry (1, 1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                obj (1, 1) yamada.model.SavedSourceCheckpoint
            end

            % Parse the same normalized text that SourceWriter will encode.
            obj.SourceText = yamada.source.SourceWriter.normalize(source, document.LineEnding);
            obj.FilePath = filePath;
            obj.HistoryIndex = document.HistoryIndex;
            obj.BaselineText = document.CurrentText;
            obj.BaselineClassName = document.ClassName;
            obj.LineEnding = document.LineEnding;
            if isfield(document.Metadata, "SourceSnapshotId")
                obj.BaselineSnapshotId = string(document.Metadata.SourceSnapshotId);
            end
            [saved, diagnostics] = yamada.source.AppSourceParser.parseText(obj.SourceText, registry, filePath);
            yamada.model.SavedSourceCheckpoint.assertDiagnostics(diagnostics);
            obj.ClassName = saved.ClassName;
            obj.SourceSnapshotId = saved.Metadata.SourceSnapshotId;
            if numel(document.Components) ~= numel(saved.Components)
                error("yamada:SavedSourceCheckpoint:StateMismatch", "Saved output changes the component set.");
            end

            % Join by the final member name, retaining independent parsed identities.
            for component = document.Components
                matches = saved.Components(string({saved.Components.Name}) == component.Name);
                if numel(matches) ~= 1 || matches.Factory ~= component.Factory || ...
                        yamada.model.SavedSourceCheckpoint.parentName(document, component) ~= ...
                        yamada.model.SavedSourceCheckpoint.parentName(saved, matches)
                    error("yamada:SavedSourceCheckpoint:StateMismatch", ...
                        "Saved output changes component identity or parent: %s.", component.Name);
                end
                [expected, stateDiagnostics] = document.getEffectivePropertyStates(registry, component.Id);
                yamada.model.SavedSourceCheckpoint.assertDiagnostics(stateDiagnostics);
                [actual, stateDiagnostics] = saved.getEffectivePropertyStates(registry, matches.Id);
                yamada.model.SavedSourceCheckpoint.assertDiagnostics(stateDiagnostics);
                for state = expected
                    if ~state.Resolution.IsKnown, continue, end
                    other = actual(arrayfun(@(item) item.Definition.Path == state.Definition.Path, actual));
                    if numel(other) ~= 1 || ~other.Resolution.IsKnown || ...
                            ~isequaln(state.Resolution.EffectiveValue, other.Resolution.EffectiveValue)
                        error("yamada:SavedSourceCheckpoint:StateMismatch", ...
                            "Saved output changes known initial state: %s.%s.", component.Name, state.Definition.Path);
                    end
                end
                obj.ComponentMap(end + 1) = struct("ComponentId", component.Id, ...
                    "SavedId", matches.Id, "Name", component.Name);
            end
            obj.Validation = saved.captureValidationProof(registry);
            obj.Snapshot = yamada.model.SubtreeSnapshot(saved, saved.RootComponentId);
            obj.InputContext = document.evaluationContext(registry);
            obj.assertCurrent(document, registry);
        end

        function assertCurrent(obj, document, registry)
            % assertCurrent Reject a checkpoint prepared against different edit intentions or source ownership.
            arguments (Input)
                obj (1, 1) yamada.model.SavedSourceCheckpoint
                document (1, 1) yamada.model.DocumentModel
                registry (1, 1) yamada.model.ComponentRegistry
            end

            % Never attach saved locations to a changed source epoch or history branch.
            epoch = "";
            if isfield(document.Metadata, "SourceSnapshotId"), epoch = string(document.Metadata.SourceSnapshotId); end
            if document.HistoryIndex ~= obj.HistoryIndex || document.CurrentText ~= obj.BaselineText || ...
                    epoch ~= obj.BaselineSnapshotId || document.ClassName ~= obj.BaselineClassName || ...
                    document.LineEnding ~= obj.LineEnding || ...
                    ~isequal(string({document.Components.Id}), string({obj.ComponentMap.ComponentId})) || ...
                    ~isequal(string({document.Components.Name}), string({obj.ComponentMap.Name}))
                error("yamada:SavedSourceCheckpoint:StaleCheckpoint", "The document changed while saving.");
            end

            % Current source is already published; the input stamp guards low-level mutations too.
            if isempty(obj.InputContext) || ~obj.InputContext.matches(document, registry)
                error("yamada:SavedSourceCheckpoint:StaleCheckpoint", "The document changed while saving.");
            end
            current = document.CurrentText;
            if strlength(current) == 0
                current = yamada.source.RoundTripGenerator(registry).generate(document.structuralCandidate());
            end
            [current, diagnostics] = yamada.source.AppClassIdentityRewriter.rewrite(current, obj.ClassName);
            yamada.model.SavedSourceCheckpoint.assertDiagnostics(diagnostics);
            if yamada.source.SourceWriter.normalize(current, obj.LineEnding) ~= obj.SourceText
                error("yamada:SavedSourceCheckpoint:StaleCheckpoint", "The document changed while saving.");
            end
        end
    end

    methods (Access = ?yamada.model.DocumentModel)
        function proof = validationProof(obj)
            % validationProof Return immutable saved-output validation without exposing the checkpoint's input context.
            arguments (Input)
                obj (1, 1) yamada.model.SavedSourceCheckpoint
            end
            arguments (Output)
                proof yamada.model.DocumentValidationProof
            end
            proof = obj.Validation;
        end
    end

    methods (Static, Access = private)
        function name = parentName(document, component)
            % parentName Compare hierarchy by final member names across independent parser identities.
            arguments (Input)
                document (1, 1) yamada.model.DocumentModel
                component (1, 1) yamada.model.ComponentRecord
            end
            arguments (Output)
                name (1, 1) string
            end
            name = "";
            if strlength(component.ParentId) > 0
                parent = document.getComponent(component.ParentId);
                name = parent.Name;
            end
        end

        function assertDiagnostics(diagnostics)
            % assertDiagnostics Refuse source and effective-state errors before confirming a save.
            arguments (Input)
                diagnostics yamada.model.Diagnostic
            end
            if yamada.validation.ModelValidator.hasErrors(diagnostics)
                error("yamada:SavedSourceCheckpoint:InvalidSource", "%s", strjoin(string({diagnostics.Message}), newline));
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
