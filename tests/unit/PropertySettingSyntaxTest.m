classdef (TestTags = {'fast', 'parser', 'model'}) PropertySettingSyntaxTest < matlab.unittest.TestCase
    % PropertySettingSyntaxTest Verify source occurrences and lossless token positions.
    %   These tests exercise both constructor spellings, comments, continuations,
    %   assignment values, and immutable setting data without running an app.

    methods (Test)
        function quotedConcatenationRemainsAnUnevaluatedExpression(testCase)
            % quotedConcatenationRemainsAnUnevaluatedExpression Avoid mistaking outer quotes for one literal.

            for expression = ["""A"" + findText() + ""B""", "'A' + findText() + 'B'"]
                source = "app.DropDown = uidropdown(app.UIFigure, Value=" + expression + ");";
                statement = yamada.source.MatlabLexicalScanner.splitStatements(source);
                [~, factoryArguments, settings] = ...
                    yamada.source.PropertySettingSyntax.factory(statement, testCase.definition(), "snapshot");
                testCase.verifyEmpty(factoryArguments);
                testCase.verifyEqual(settings.ValueKind, "expression");
                testCase.verifyEqual(settings.SourceExpression, expression);
                testCase.verifyFalse(settings.IsEditable);
            end
        end

        function mapsMixedConstructorSyntaxAcrossCommentsAndContinuations(testCase)
            % mapsMixedConstructorSyntaxAcrossCommentsAndContinuations Retain exact original value tokens.

            source = strjoin([ ...
                "  app.DropDown = uidropdown(app.UIFigure, ... % constructor comment", ...
                "      ""Items"", [""A"", ""B""], ...", ...
                "      Value = ""B"", ...", ...
                "      ItemsData = [10 20]); % trailing comment"], sprintf("\r\n"));
            statement = yamada.source.MatlabLexicalScanner.splitStatements(source);
            [parent, factoryArguments, settings, skipped, supported] = ...
                yamada.source.PropertySettingSyntax.factory(statement, testCase.definition(), "snapshot");
            testCase.verifyTrue(supported);
            testCase.verifyEqual(parent, "UIFigure");
            testCase.verifyEmpty(skipped);
            testCase.verifyEqual(factoryArguments, {"Items", ["A", "B"], "Value", "B", "ItemsData", [10 20]});
            testCase.verifyEqual(string({settings.Path}), ["Items", "Value", "ItemsData"]);
            testCase.verifyEqual(string({settings.Syntax}), ["quotedPair", "nameEquals", "nameEquals"]);
            testCase.verifyEqual(testCase.slice(source, settings(2).NameSpan), "Value");
            testCase.verifyEqual(testCase.slice(source, settings(2).ValueSpan), """B""");
            testCase.verifyEqual(testCase.slice(source, settings(3).ValueSpan), "[10 20]");
            testCase.verifyEqual(settings(1).StatementId, settings(3).StatementId);
        end

        function capturesExpressionWithoutLosingFollowingArguments(testCase)
            % capturesExpressionWithoutLosingFollowingArguments Preserve opaque values without execution.

            source = "app.DropDown = uidropdown(app.UIFigure, Value=chooseValue(), Items=[""A"", ""B""]);";
            statement = yamada.source.MatlabLexicalScanner.splitStatements(source);
            [~, factoryArguments, settings, skipped, supported] = ...
                yamada.source.PropertySettingSyntax.factory(statement, testCase.definition(), "snapshot");
            testCase.verifyTrue(supported);
            testCase.verifyEqual(factoryArguments, {"Items", ["A", "B"]});
            testCase.verifyEqual(skipped, "Value");
            testCase.verifyEqual(settings(1).ValueKind, "expression");
            testCase.verifyEqual(settings(1).SourceExpression, "chooseValue()");
            testCase.verifyFalse(settings(1).IsEditable);
            testCase.verifyEqual(testCase.slice(source, settings(1).ValueSpan), "chooseValue()");
        end

        function retainsQuotedDelimitersAndNestedLiteralRanges(testCase)
            % retainsQuotedDelimitersAndNestedLiteralRanges Keep commas and parentheses inside values.

            source = "app.DropDown = uidropdown(app.UIFigure, 'Items', {'A,B','C)D'}, 'Value', 'C)D');";
            statement = yamada.source.MatlabLexicalScanner.splitStatements(source);
            [~, ~, settings, ~, supported] = ...
                yamada.source.PropertySettingSyntax.factory(statement, testCase.definition(), "snapshot");
            testCase.verifyTrue(supported);
            testCase.verifyNumElements(settings, 2);
            testCase.verifyEqual(testCase.slice(source, settings(1).ValueSpan), "{'A,B','C)D'}");
            testCase.verifyEqual(testCase.slice(source, settings(2).ValueSpan), "'C)D'");
        end

        function retainsOriginalAssignmentSpanAcrossContinuation(testCase)
            % retainsOriginalAssignmentSpanAcrossContinuation Separate normalized values from source ownership.

            source = strjoin(["  app.DropDown.Value = [1 ... % value comment", "      2];"], newline);
            statement = yamada.source.MatlabLexicalScanner.splitStatements(source);
            setting = yamada.source.PropertySettingSyntax.assignment(statement, "snapshot", 7);
            testCase.verifyEqual(setting.Path, "Value");
            testCase.verifyEqual(setting.LiteralValue, [1 2]);
            testCase.verifyEqual(setting.Sequence, 7);
            testCase.verifyEqual(setting.Method, "assignment");
            testCase.verifySubstring(testCase.slice(source, setting.ValueSpan), "% value comment");
        end

        function duplicateConstructorKeysRemainUncertain(testCase)
            % duplicateConstructorKeysRemainUncertain Avoid assuming last-key-wins constructor semantics.

            source = "app.DropDown = uidropdown(app.UIFigure, 'Value', 'A', Value='B');";
            statement = yamada.source.MatlabLexicalScanner.splitStatements(source);
            [~, ~, settings] = yamada.source.PropertySettingSyntax.factory(statement, testCase.definition(), "snapshot");
            testCase.verifyNumElements(settings, 2);
            testCase.verifyFalse(any([settings.IsCertain]));
            testCase.verifyFalse(any([settings.IsEditable]));
        end

        function snapshotRecordIsIndependentAndRestorable(testCase)
            % snapshotRecordIsIndependentAndRestorable Preserve immutable source data across value snapshots.

            setting = yamada.model.PropertySetting("Value", [10 20], ...
                struct("SourceSnapshotId", "one", "Sequence", 3));
            record = setting.toStruct();
            record.Value(1) = 99;
            testCase.verifyEqual(setting.LiteralValue, [10 20]);
            restored = yamada.model.PropertySetting(record.Path, record.Value, record.Location);
            testCase.verifyEqual(restored.Id, setting.Id);
            testCase.verifyEqual(restored.LiteralValue, [99 20]);
        end
    end

    methods (Static, Access = private)
        function definition = definition()
            % definition Create a nonvisual factory surface for lexical tests.
            arguments (Output)
                definition (1, 1) yamada.model.ComponentDefinition
            end

            definition = yamada.model.ComponentDefinition.fromPaths("uidropdown", ...
                "matlab.ui.control.DropDown", "uifigure", false, {}, ...
                ["Items", "ItemsData", "Value", "Editable"], struct());
        end

        function text = slice(source, span)
            % slice Read a token's exact source spelling using its retained offsets.
            arguments (Input)
                source (1, 1) string
                span (1, 1) yamada.model.SourceSpan
            end
            arguments (Output)
                text (1, 1) string
            end

            text = extractBetween(source, span.StartOffset, span.EndOffset);
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
