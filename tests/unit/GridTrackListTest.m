classdef GridTrackListTest < matlab.unittest.TestCase
    % GridTrackListTest Verify literal validation for R2024a GridLayout tracks.

    methods (Test)
        function acceptsDocumentedLiteralContainers(testCase)
            % acceptsDocumentedLiteralContainers Accept fixed, fit, and weighted tracks.

            values = {{'1x', 'fit', 120}, [0 120], ...
                ["1x" "2.5x" "fit"], {"FIT", 0, '0x'}};
            for index = 1:numel(values)
                testCase.verifyEqual(macd.model.GridTrackList.validate(values{index}), "");
            end
        end

        function rejectsUnsupportedTrackTokensAndContainers(testCase)
            % rejectsUnsupportedTrackTokensAndContainers Keep invalid source literals out of preview.

            testCase.verifyEqual(macd.model.GridTrackList.validate('1x'), ...
                "Enter a numeric, string, or cell vector of track values.");
            testCase.verifyEqual(macd.model.GridTrackList.validate({'-1x'}), ...
                "Track values must be nonnegative numbers, fit, or nonnegative x weights.");
            testCase.verifyEqual(macd.model.GridTrackList.validate({'auto'}), ...
                "Track values must be nonnegative numbers, fit, or nonnegative x weights.");
            testCase.verifyEqual(macd.model.GridTrackList.validate([-1 10]), ...
                "Fixed track sizes must be finite nonnegative numbers.");
            testCase.verifyEqual(macd.model.GridTrackList.validate([]), ...
                "Enter a numeric, string, or cell vector of track values.");
            testCase.verifyEqual(macd.model.GridTrackList.validate([1 2; 3 4]), ...
                "Enter a numeric, string, or cell vector of track values.");
        end

        function validatesTrackListsThroughPropertyTransactions(testCase)
            % validatesTrackListsThroughPropertyTransactions Reuse one model boundary for editor commits.

            definition = macd.model.PropertyDefinition("ColumnWidth", [], false, true, ...
                struct("editor", "gridTrackList", "auditDisposition", "editable", ...
                "valueSchema", struct("kind", "gridTrackList", "allowsEmpty", true)));
            transaction = macd.model.PropertyTransaction("ColumnWidth", {{'1x', 120}}, true);

            testCase.verifyEqual(macd.validation.PropertyBatchValidator.validate( ...
                definition, transaction), "");
            transaction.stage("ColumnWidth", {'auto'});
            testCase.verifyEqual(macd.validation.PropertyBatchValidator.validate( ...
                definition, transaction), ...
                "Track values must be nonnegative numbers, fit, or nonnegative x weights.");
        end

        function describesTrackTokensWithoutChangingTheirLiteralContainer(testCase)
            % describesTrackTokens Normalize tokens for a canvas without source evaluation.

            tracks = macd.model.GridTrackList.describe({'fit', 80, '2.5x'});

            testCase.verifyEqual(string({tracks.kind}), ["fit", "fixed", "flexible"]);
            testCase.verifyEqual([tracks.value], [0 80 2.5]);
            testCase.verifyEqual(string({tracks.label}), ["fit", "80", "2.5x"]);
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
