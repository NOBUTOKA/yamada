classdef SourceAnalysis < handle
    % SourceAnalysis Share read-only lexical input and a bounded initialization trace.
    %   This derived cache retains source values only, without document, record,
    %   registry, or native UI references. Trace results are keyed by exact factory
    %   offsets and returned by value. Input application code is never executed.
    %
    %   Example:
    %       analysis = document.sourceAnalysis();
    %       statements = analysis.Statements;
    properties (SetAccess = private)
        % Statements - Immutable lexical statements with original source offsets.
        Statements macd.source.SourceStatement = macd.source.SourceStatement.empty
        % Layout - Value-only method and scope layout for the exact input source.
        Layout struct = struct()
    end

    properties (Access = private)
        Source string = ""
        TraceOffsets double = []
        Trace struct = struct()
        HasTrace logical = false
    end

    methods
        function obj = SourceAnalysis(source)
            % SourceAnalysis Compile one exact source without evaluating its contents.
            arguments (Input)
                source string = ""
            end
            arguments (Output)
                obj (1, 1) macd.source.SourceAnalysis
            end
            obj.Source = source;
            obj.Statements = macd.source.MatlabLexicalScanner.splitStatements(source);
            obj.Layout = macd.source.CallbackSourceAnalyzer.sourceLayout(obj.Statements);
        end

        function result = matches(obj, source)
            % matches Require exact text equality before sharing derived source analysis.
            arguments (Input)
                obj (1, 1) macd.source.SourceAnalysis
                source string
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = isequaln(obj.Source, source);
        end

        function trace = initialization(obj, creationOffsets)
            % initialization Return a value-only trace for the exact factory-offset input.
            arguments (Input)
                obj (1, 1) macd.source.SourceAnalysis
                creationOffsets double = []
            end
            arguments (Output)
                trace (1, 1) struct
            end
            if obj.HasTrace && isequaln(obj.TraceOffsets, creationOffsets)
                trace = obj.Trace;
                return
            end
            % Replace the single retained trace only after analysis succeeds.
            [order, diagnostics, certain, returns] = macd.source.InitializationSourceAnalyzer.analyze( ...
                obj.Statements, obj.Layout, creationOffsets);
            trace = struct("Order", order, "Diagnostics", diagnostics, ...
                "Certain", certain, "Returns", returns);
            obj.Trace = trace;
            obj.TraceOffsets = creationOffsets;
            obj.HasTrace = true;
        end
    end

    methods (Static, Access = ?macd.source.AppSourceParser)
        function obj = fromParsed(source, statements, layout, offsets, trace)
            % fromParsed Retain the parser's completed analysis without compiling it again.
            arguments (Input)
                source string
                statements macd.source.SourceStatement
                layout (1, 1) struct
                offsets double
                trace (1, 1) struct
            end
            arguments (Output)
                obj (1, 1) macd.source.SourceAnalysis
            end
            obj = macd.source.SourceAnalysis();
            obj.Source = source;
            obj.Statements = statements;
            obj.Layout = layout;
            obj.TraceOffsets = offsets;
            obj.Trace = trace;
            obj.HasTrace = true;
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
