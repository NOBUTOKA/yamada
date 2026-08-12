classdef LexicalParsingTest < matlab.unittest.TestCase
    % LexicalParsingTest Verify non-evaluating source scanning and literals.
    %   This test class covers statement boundaries around quoted text, comments,
    %   continuations, and the conservative literal subset used by Phase 2.

    methods (Test)
        function scannerIgnoresQuotedDelimitersAndComments(testCase)
            % scannerIgnoresQuotedDelimitersAndComments Check lexical boundaries.

            % Include semicolons and percent signs that must remain inside text.
            source = "app.Label.Text = 'a; % b'; % ignored" + newline + ...
                "app.Value = [1 2; 3 4];";
            statements = macd.source.MatlabLexicalScanner.splitStatements(source);

            testCase.verifyEqual(numel(statements), 2);
            testCase.verifyEqual(statements(1).Text, ...
                "app.Label.Text = 'a; % b'");
            testCase.verifyEqual(statements(2).Text, ...
                "app.Value = [1 2; 3 4]");
            testCase.verifyGreaterThan(statements(2).Span.StartOffset, ...
                statements(1).Span.EndOffset);
        end

        function scannerKeepsBalancedContinuationAsOneStatement(testCase)
            % scannerKeepsBalancedContinuationAsOneStatement Check continuation.

            % Keep a callback expression intact without attempting to interpret it.
            source = "app.Button.ButtonPushedFcn = createCallbackFcn( ..." + ...
                newline + "    app, @Callback, true);";
            statements = macd.source.MatlabLexicalScanner.splitStatements(source);

            testCase.verifyEqual(numel(statements), 1);
            testCase.verifySubstring(statements.Text, "createCallbackFcn(");
            testCase.verifySubstring(statements.Text, "@Callback");
            testCase.verifyFalse(contains(statements.Text, "..."));
        end

        function literalParserAcceptsSafeValuesWithoutEvaluation(testCase)
            % literalParserAcceptsSafeValuesWithoutEvaluation Check safe literals.

            % Parse representative values that the source generator can round-trip.
            [matrix, isMatrix] = macd.source.MatlabLiteralParser.parse("[1 2; 3 4]");
            [items, isItems] = macd.source.MatlabLiteralParser.parse( ...
                "{'Add', 'Subtract'}");
            [stringItems, isStringItems] = macd.source.MatlabLiteralParser.parse( ...
                '["Add", "Subtract"]');
            [stringLines, isStringLines] = macd.source.MatlabLiteralParser.parse( ...
                '["First"; "Second"]');
            [logicalValues, isLogicalValues] = macd.source.MatlabLiteralParser.parse( ...
                "[true false true]");
            [text, isText] = macd.source.MatlabLiteralParser.parse("'It''s ready'");
            [emptyCharacters, isEmptyCharacters] = macd.source.MatlabLiteralParser.parse("''");
            [emptyArray, isEmptyArray] = macd.source.MatlabLiteralParser.parse("[]");
            [characters, isCharacters] = macd.source.MatlabLiteralParser.parse("['ab'; 'cd']");

            testCase.verifyTrue(isMatrix);
            testCase.verifyEqual(matrix, [1 2; 3 4]);
            testCase.verifyTrue(isItems);
            testCase.verifyEqual(items, {'Add', 'Subtract'});
            testCase.verifyTrue(isStringItems);
            testCase.verifyEqual(stringItems, ["Add", "Subtract"]);
            testCase.verifyTrue(isStringLines);
            testCase.verifyEqual(stringLines, ["First"; "Second"]);
            testCase.verifyTrue(isLogicalValues);
            testCase.verifyEqual(logicalValues, [true false true]);
            testCase.verifyTrue(isText);
            testCase.verifyEqual(text, 'It''s ready');
            testCase.verifyTrue(isEmptyCharacters);
            testCase.verifyEqual(emptyCharacters, '');
            testCase.verifyTrue(isEmptyArray);
            testCase.verifyEmpty(emptyArray);
            testCase.verifyTrue(isCharacters);
            testCase.verifyEqual(characters, ['ab'; 'cd']);
        end

        function literalParserRejectsExpressions(testCase)
            % literalParserRejectsExpressions Keep executable expressions opaque.

            % Confirm parsing never evaluates an expression to discover its value.
            [value, isLiteral] = macd.source.MatlabLiteralParser.parse( ...
                "loadItems(app)");

            testCase.verifyFalse(isLiteral);
            testCase.verifyEmpty(value);
        end
    end
end

%{
MatlabAppClassDesigner - Tests for non-evaluating lexical source parsing.
Copyright (C) 2026 MatlabAppClassDesigner contributors

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
