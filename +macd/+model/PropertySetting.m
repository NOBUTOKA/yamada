classdef PropertySetting
    % PropertySetting Retain one immutable explicit property-setting occurrence.
    %   Source occurrences retain original values and token ownership. Requested
    %   edits and user Undo/Redo history belong to the document, not this record.
    %
    %   Example:
    %       setting = macd.model.PropertySetting("Text", "Ready");

    properties (SetAccess = private)
        % Id - Stable identity of this occurrence within its source snapshot.
        Id string = ""
        % Path - Component property path written by this occurrence.
        Path string = ""
        % ValueKind - Literal or unevaluated expression storage form.
        ValueKind string = "literal"
        % LiteralValue - Original safe value, never a requested replacement.
        LiteralValue = []
        % SourceExpression - Original unevaluated right-hand-side expression.
        SourceExpression string = ""
        % Method - nameValue, assignment, or generated setting location.
        Method string = "generated"
        % Syntax - quotedPair, nameEquals, dot, or generated spelling.
        Syntax string = "generated"
        % SourceSpan - Complete owning statement in the original source.
        SourceSpan macd.model.SourceSpan = macd.model.SourceSpan.empty
        % ValueSpan - Original token range that may be replaced by a literal.
        ValueSpan macd.model.SourceSpan = macd.model.SourceSpan.empty
        % NameSpan - Property name token range in the original source.
        NameSpan macd.model.SourceSpan = macd.model.SourceSpan.empty
        % PairSpan - Complete constructor pair or property assignment range.
        PairSpan macd.model.SourceSpan = macd.model.SourceSpan.empty
        % SourceSnapshotId - Identity of the source version owning all spans.
        SourceSnapshotId string = ""
        % StatementId - Identity shared by arguments of one factory call.
        StatementId string = ""
        % Sequence - Execution-visit order across distinct property paths.
        Sequence double = 0
        % OwnerMethod - Instance initializer method that contains this source occurrence.
        OwnerMethod string = ""
        % ScopeSpan - Original complete initializer method span, when proven.
        ScopeSpan macd.model.SourceSpan = macd.model.SourceSpan.empty
        % InitializationScopeId - Source-version-bound identity of the owning method.
        InitializationScopeId string = ""
        % FactoryArgumentIndex - Literal value index in the legacy factory-argument projection.
        FactoryArgumentIndex double = 0
        % IsCertain - Whether straight-line initialization owns this occurrence.
        IsCertain logical = true
        % IsEditable - Whether its value is a literal with certain ownership.
        IsEditable logical = true
    end

    methods
        function obj = PropertySetting(path, value, location)
            % PropertySetting Capture one source occurrence or pending generated setting.
            arguments (Input)
                path (1, 1) string = ""
                value = []
                location (1, 1) struct = struct()
            end
            arguments (Output)
                obj (1, 1) macd.model.PropertySetting
            end

            % Validate metadata before copying it into immutable source ownership.
            allowed = ["Method", "Syntax", "SourceSpan", "ValueSpan", "NameSpan", ...
                "PairSpan", "SourceSnapshotId", "StatementId", "Sequence", "IsCertain", ...
                "SourceExpression", "IsEditable", "FactoryArgumentIndex", ...
                "OwnerMethod", "ScopeSpan", "InitializationScopeId"];
            unknown = setdiff(string(fieldnames(location)), allowed);
            if ~isempty(unknown)
                error("macd:PropertySetting:InvalidLocation", "Unknown setting field %s.", unknown(1));
            end
            obj.Path = path;
            obj.LiteralValue = value;
            for field = allowed
                if isfield(location, field), obj.(field) = location.(field); end
            end
            if ~isscalar(obj.Method) || ~any(obj.Method == ["generated", "assignment", "nameValue"]) || ...
                    ~isscalar(obj.Syntax) || ~any(obj.Syntax == ["generated", "dot", "quotedPair", "nameEquals"])
                error("macd:PropertySetting:InvalidLocation", "Unknown setting method or syntax.");
            end
            validateattributes(obj.Sequence, "double", {"scalar", "integer", "nonnegative"});
            validateattributes(obj.FactoryArgumentIndex, "double", {"scalar", "integer", "nonnegative"});
            validateattributes(obj.IsCertain, "logical", {"scalar"});
            validateattributes(obj.IsEditable, "logical", {"scalar"});
            if isfield(location, "SourceExpression")
                obj.ValueKind = "expression";
                obj.LiteralValue = [];
                obj.IsEditable = false;
            end
            obj.IsEditable = obj.IsEditable && obj.IsCertain;

            % An occurrence identity remains independent of future requested values.
            start = 0;
            if ~isempty(obj.SourceSpan), start = obj.SourceSpan.StartOffset; end
            valueStart = start;
            if ~isempty(obj.ValueSpan), valueStart = obj.ValueSpan.StartOffset; end
            obj.Id = obj.SourceSnapshotId + ":" + string(valueStart) + ":" + path;
            if strlength(obj.StatementId) == 0
                obj.StatementId = obj.SourceSnapshotId + ":" + string(start);
            end
        end

        function record = toStruct(obj)
            % toStruct Export independent value data for document and subtree snapshots.
            arguments (Input)
                obj (1, 1) macd.model.PropertySetting
            end
            arguments (Output)
                record (1, 1) struct
            end

            % Retain expression absence separately from an expression's empty text.
            location = struct("Method", obj.Method, "Syntax", obj.Syntax, ...
                "SourceSpan", obj.SourceSpan, "ValueSpan", obj.ValueSpan, ...
                "NameSpan", obj.NameSpan, "PairSpan", obj.PairSpan, ...
                "SourceSnapshotId", obj.SourceSnapshotId, "StatementId", obj.StatementId, ...
                "Sequence", obj.Sequence, "IsCertain", obj.IsCertain, "IsEditable", obj.IsEditable, ...
                "FactoryArgumentIndex", obj.FactoryArgumentIndex, "OwnerMethod", obj.OwnerMethod, ...
                "ScopeSpan", obj.ScopeSpan, "InitializationScopeId", obj.InitializationScopeId);
            if obj.ValueKind == "expression", location.SourceExpression = obj.SourceExpression; end
            record = struct("Path", obj.Path, "Value", {obj.LiteralValue}, "Location", location);
        end

        function obj = withScope(obj, owner, span)
            % withScope Return a source-version-bound initializer ownership annotation.
            arguments (Input)
                obj (1, 1) macd.model.PropertySetting
                owner (1, 1) string
                span macd.model.SourceSpan
            end
            arguments (Output)
                obj (1, 1) macd.model.PropertySetting
            end
            obj.OwnerMethod = owner;
            obj.ScopeSpan = span;
            if ~isempty(span) && span.isKnown()
                obj.InitializationScopeId = obj.SourceSnapshotId + ":scope:" + span.StartOffset;
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
