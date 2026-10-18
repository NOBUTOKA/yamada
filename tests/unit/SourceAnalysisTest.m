classdef (TestTags = {'fast', 'model', 'generation'}) SourceAnalysisTest < matlab.unittest.TestCase
    % SourceAnalysisTest Verify exact-source sharing without mutable model ownership.
    %   Cached lexical and initialization data must retain the independent
    %   compiler's results, including unsafe input and source-version changes.
    methods (Test)
        function tracesMatchIndependentCompilerAcrossOffsetInputs(testCase)
            % tracesMatchIndependentCompilerAcrossOffsetInputs Preserve trace keys and independent returned values.
            analysis = macd.source.SourceAnalysis(analysisSource());
            statements = analysis.Statements;
            offsets = [statements(contains(string({statements.Text}), "= uifigure")).Span.StartOffset, ...
                statements(contains(string({statements.Text}), "= uilabel")).Span.StartOffset];
            testCase.verifyNumElements(offsets, 2);
            inputs = {[], offsets, offsets(1), fliplr(offsets), offsets};
            for input = inputs
                [order, diagnostics, certain, layout, returns] = ...
                    macd.source.CallbackSourceAnalyzer.initializationStatements(statements, input{1});
                trace = analysis.initialization(input{1});
                testCase.verifyEqual(trace.Order, order);
                testCase.verifyEqual(trace.Diagnostics, diagnostics);
                testCase.verifyEqual(trace.Certain, certain);
                testCase.verifyEqual(trace.Returns, returns);
                testCase.verifyEqual(analysis.Layout, layout);
            end
            % Caller-owned output edits cannot corrupt the retained result.
            testCase.verifyNotEmpty(order);
            trace.Order(:) = 0;
            trace = analysis.initialization(offsets);
            testCase.verifyEqual(trace.Order, order);
            layout.Valid = ~layout.Valid;
            testCase.verifyNotEqual(analysis.Layout.Valid, layout.Valid);
        end

        function candidatesShareDerivedInputButNotComponentValues(testCase)
            % candidatesShareDerivedInputButNotComponentValues Keep shared analysis independent of mutable records.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.source.AppSourceParser.parseText(analysisSource(), registry);
            context = document.evaluationContext(registry);
            analysis = document.sourceAnalysis();
            candidate = document.structuralCandidate();
            testCase.verifyEqual(candidate.sourceAnalysis(), analysis);
            candidate.getComponentByName("Label").setProperty("FontSize", 18);
            testCase.verifyEqual(document.getComponentByName("Label").getProperty("FontSize").LiteralValue, 12);
            testCase.verifyTrue(context.matches(document, registry));
            testCase.verifyEqual(candidate.sourceAnalysis(), analysis);
        end

        function sourceChangesReplaceOnlyTheChangedDocumentAnalysis(testCase)
            % sourceChangesReplaceOnlyTheChangedDocumentAnalysis Reject a stale source while preserving the original.
            registry = macd.model.ComponentRegistry.createDefault();
            source = analysisSource();
            document = macd.source.AppSourceParser.parseText(source, registry);
            candidate = document.structuralCandidate();
            original = document.sourceAnalysis();
            candidate.OriginalText = source + newline + "% Changed source version";
            replacement = candidate.sourceAnalysis();
            testCase.verifyNotEqual(replacement, original);
            testCase.verifyTrue(original.matches(source));
            testCase.verifyTrue(replacement.matches(candidate.OriginalText));
            testCase.verifyEqual(document.sourceAnalysis(), original);
            [~, diagnostics] = macd.source.RoundTripGenerator(registry).generate(candidate);
            testCase.verifyTrue(any(string({diagnostics.Code}) == "stale-source-snapshot"));
        end

        function opaqueValuesRemainUnknownAndReadOnly(testCase)
            % opaqueValuesRemainUnknownAndReadOnly Never execute or upgrade opaque source through a shared cache.
            registry = macd.model.ComponentRegistry.createDefault();
            source = replace(analysisSource(), "app.Label.FontSize = 12;", ...
                "app.Label.FontSize = externalValue();");
            document = macd.source.AppSourceParser.parseText(source, registry);
            candidate = document.structuralCandidate();
            testCase.verifyEqual(document.sourceAnalysis(), candidate.sourceAnalysis());
            for current = [document, candidate]
                component = current.getComponentByName("Label");
                states = current.getEffectivePropertyStates(registry, component.Id);
                state = states(arrayfun(@(item) item.Definition.Path == "FontSize", states)).Resolution;
                testCase.verifyFalse(state.IsKnown);
                testCase.verifyFalse(state.IsEditable);
            end
        end
    end
end

function source = analysisSource()
% analysisSource Provide a minimal AppBase source fixture without executing application code.
arguments (Output)
    source (1, 1) string
end
source = join(["classdef AnalysisFixture < matlab.apps.AppBase", ...
    "properties (Access = public)", "UIFigure matlab.ui.Figure", ...
    "Label matlab.ui.control.Label", "end", "methods (Access = private)", ...
    "function createComponents(app)", "app.UIFigure = uifigure();", ...
    "app.Label = uilabel(app.UIFigure);", "app.Label.FontSize = 12;", "end", "end", ...
    "methods (Access = public)", "function app = AnalysisFixture", ...
    "createComponents(app);", "end", "end", "end"], newline);
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
