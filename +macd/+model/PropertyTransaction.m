classdef PropertyTransaction < handle
    % PropertyTransaction Stage a typed property change-set without model mutation.
    %   This UI-independent class copies a caller-provided effective property
    %   snapshot, stages replacement or empty-value operations, and exposes the
    %   resulting batch for one validated document mutation. It does not read a
    %   catalog, validate values, or change a DocumentModel.
    %
    %   Example:
    %       transaction = macd.model.PropertyTransaction("Text", "Ready");
    %       transaction.stage("Text", "Done");
    %       changes = transaction.changes();

    properties (SetAccess = private)
        % Paths - Effective property paths represented by this candidate state.
        Paths string = strings(1, 0)
        % InitialValues - Values copied from the caller's starting snapshot.
        InitialValues cell = {}
        % DraftValues - Current candidate values, including staged replacements.
        DraftValues cell = {}
        % KnownValues - Whether each candidate value is known as a safe literal.
        KnownValues logical = false(1, 0)
        % IsStaged - Whether each path differs through an explicit transaction operation.
        IsStaged logical = false(1, 0)
    end

    methods
        function obj = PropertyTransaction(paths, values, hasValue)
            % PropertyTransaction Copy one effective candidate state for later staging.
            arguments (Input)
                paths string
                values cell
                hasValue logical = true(1, numel(paths))
            end
            arguments (Output)
                obj (1, 1) macd.model.PropertyTransaction
            end

            paths = reshape(paths, 1, []);
            if numel(values) ~= numel(paths) || numel(hasValue) ~= numel(paths)
                error("macd:PropertyTransaction:SnapshotSizeMismatch", ...
                    "Paths, values, and availability must have matching lengths.");
            end
            if numel(unique(paths)) ~= numel(paths)
                error("macd:PropertyTransaction:DuplicatePath", ...
                    "A transaction snapshot cannot contain duplicate property paths.");
            end

            % Keep value containers private so dialog edits cannot mutate the snapshot.
            obj.Paths = paths;
            obj.InitialValues = reshape(values, 1, []);
            obj.DraftValues = obj.InitialValues;
            obj.KnownValues = reshape(hasValue, 1, []);
            obj.IsStaged = false(1, numel(paths));
        end

        function stage(obj, path, value)
            % stage Replace one candidate property value without changing the document.
            arguments (Input)
                obj (1, 1) macd.model.PropertyTransaction
                path (1, 1) string
                value
            end

            index = obj.pathIndex(path);
            obj.DraftValues{index} = value;
            obj.KnownValues(index) = true;
            obj.IsStaged(index) = true;
        end

        function clear(obj, path)
            % clear Stage an empty literal value without removing the property path.
            arguments (Input)
                obj (1, 1) macd.model.PropertyTransaction
                path (1, 1) string
            end

            obj.stage(path, []);
        end

        function value = value(obj, path)
            % value Return one current typed candidate value.
            arguments (Input)
                obj (1, 1) macd.model.PropertyTransaction
                path (1, 1) string
            end
            arguments (Output)
                value
            end

            value = obj.DraftValues{obj.pathIndex(path)};
        end

        function result = hasValue(obj, path)
            % hasValue Report whether one candidate path has a known literal value.
            arguments (Input)
                obj (1, 1) macd.model.PropertyTransaction
                path (1, 1) string
            end
            arguments (Output)
                result (1, 1) logical
            end

            result = obj.KnownValues(obj.pathIndex(path));
        end

        function changes = changes(obj)
            % changes Return staged values as one typed property-batch structure.
            arguments (Input)
                obj (1, 1) macd.model.PropertyTransaction
            end
            arguments (Output)
                changes (1, :) struct
            end

            indices = find(obj.IsStaged);
            changes = repmat(struct("Path", "", "Value", []), 1, numel(indices));
            for resultIndex = 1:numel(indices)
                index = indices(resultIndex);
                changes(resultIndex).Path = obj.Paths(index);
                changes(resultIndex).Value = obj.DraftValues{index};
            end
        end
    end

    methods (Access = private)
        function index = pathIndex(obj, path)
            % pathIndex Resolve one known transaction path or report a programming error.
            arguments (Input)
                obj (1, 1) macd.model.PropertyTransaction
                path (1, 1) string
            end
            arguments (Output)
                index (1, 1) double
            end

            index = find(obj.Paths == path, 1);
            if isempty(index)
                error("macd:PropertyTransaction:UnknownPath", ...
                    "Property ""%s"" is not part of this transaction.", path);
            end
        end
    end
end

%{
Copyright (C) 2026 Nobuto Kaitoh

This file is part of MatlabAppClassDesigner.

MatlabAppClassDesigner is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

MatlabAppClassDesigner is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with MatlabAppClassDesigner. If not, see <https://www.gnu.org/licenses/>.
%}
