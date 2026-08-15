classdef InspectorValueFormatterTest < matlab.unittest.TestCase
    % InspectorValueFormatterTest Verify safe display text for property inspector values.
    %   These tests ensure unsupported literals remain visible without being
    %   evaluated or passed through the source generator's literal subset.

    methods (Test)
        function encodesSupportedLiteral(testCase)
            % encodesSupportedLiteral Render a supported scalar through LiteralEncoder.

            % Keep source-safe scalar display unchanged.
            entry = macd.model.PropertyEntry("Text", "Button");
            text = macd.ui.InspectorValueFormatter.format(entry);
            testCase.verifyEqual(text, """Button""");
        end

        function preservesCharacterVectorSyntax(testCase)
            % preservesCharacterVectorSyntax Render a char row with single-quote syntax.

            entry = macd.model.PropertyEntry("Text", 'Button');
            text = macd.ui.InspectorValueFormatter.format(entry);
            testCase.verifyEqual(text, "'Button'");
        end

        function preservesEmptyCharacterSyntax(testCase)
            % preservesEmptyCharacterSyntax Render an empty char value without changing type.

            entry = macd.model.PropertyEntry("Text", '');
            text = macd.ui.InspectorValueFormatter.format(entry);
            testCase.verifyEqual(text, "''");
        end

        function encodesStringArray(testCase)
            % encodesStringArray Render string arrays using safe matrix literal syntax.

            % Matrix support preserves ItemsData string values through source generation.
            entry = macd.model.PropertyEntry("Items", ["Light", "Dark", "System"]);
            text = macd.ui.InspectorValueFormatter.format(entry);
            testCase.verifyEqual(text, "[""Light"" ""Dark"" ""System""]");
        end

        function preservesSourceExpression(testCase)
            % preservesSourceExpression Display source-backed values without evaluation.

            % Preserve the parser's source text as the existing inspector contract.
            entry = macd.model.PropertyEntry();
            entry.setSourceExpression("app.updateTheme");
            text = macd.ui.InspectorValueFormatter.format(entry);
            testCase.verifyEqual(text, "app.updateTheme");
        end

        function encodesCharacterMatrix(testCase)
            % encodesCharacterMatrix Render a character matrix without an unsupported placeholder.

            entry = macd.model.PropertyEntry("CharData", ['ab'; 'cd']);
            text = macd.ui.InspectorValueFormatter.format(entry);
            testCase.verifyEqual(text, "['ab'; 'cd']");
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
