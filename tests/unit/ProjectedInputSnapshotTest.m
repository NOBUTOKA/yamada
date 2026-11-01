classdef (TestTags = {'fast', 'model', 'generation', 'preview'}) ProjectedInputSnapshotTest < matlab.unittest.TestCase
    % ProjectedInputSnapshotTest Verify incremental inputs against full capture and independent source parsing.
    methods (Test)
        function distinctChangesAndHistoryMatchFullCapture(testCase)
            % distinctChangesAndHistoryMatchFullCapture Preserve all values and source ranges across replacements and insertions.
            registry = macd.model.ComponentRegistry.createDefault();
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            source = string(fileread(fullfile(root, "tests", "fixtures", "handle", "SmallPreviewFixtureApp.m")));
            document = macd.source.AppSourceParser.parseText(source, registry);
            operations = {"TopLeftLabel", "Text", "A much longer label"; ...
                "BottomRightButton", "Tooltip", "New tooltip"; ...
                "CenterLabel", "FontSize", 19; "TopLeftLabel", "FontColor", [0.1 0.2 0.3]};
            for index = 1:size(operations, 1)
                owner = document.getComponentByName(operations{index, 1});
                previous = document.evaluationContext(registry);
                token = previous.revisionToken();
                before = previous.inputs();
                document.setProperty(owner.Id, operations{index, 2}, operations{index, 3}, registry);
                current = document.evaluationContext(registry);
                request = macd.ui.RefreshRequest("properties", owner.Id, operations{index, 2});
                testCase.verifyTrue(current.isLiteralTransition(token, request));
                projected = current.inputs();
                fresh = macd.model.EvaluationContext(document, registry).inputs();
                testCase.verifyEqual(projected, fresh);
                testCase.verifyNotEqual(before.OriginalText, projected.OriginalText);
                projected.Components(1).Name = "Caller mutation";
                testCase.verifyEqual(document.evaluationContext(registry).inputs(), fresh);
            end
            for index = 1:4
                document.undo();
                testCase.verifyEqual(document.evaluationContext(registry).inputs(), ...
                    macd.model.EvaluationContext(document, registry).inputs());
            end
            for index = 1:4
                document.redo();
                testCase.verifyEqual(document.evaluationContext(registry).inputs(), ...
                    macd.model.EvaluationContext(document, registry).inputs());
            end
        end

        function equalValuesOfDifferentClassesStillReplaceTheLiteral(testCase)
            % equalValuesOfDifferentClassesStillReplaceTheLiteral Preserve empty text and nested numeric storage types.
            cases = {[], ''; 1, single(1); {1}, {single(1)}; struct("Value", 1), struct("Value", single(1))};
            for index = 1:size(cases, 1)
                entry = macd.model.PropertyEntry("Value", cases{index, 1}, "parsed");
                setting = macd.model.PropertySetting("Value", cases{index, 2}, ...
                    struct("Id", "setting", "Method", "assignment", "IsEditable", true));
                entry.applySourceSetting(setting);
                testCase.verifyEqual(entry.LiteralValue, cases{index, 2});
                if index == 1, testCase.verifyClass(entry.LiteralValue, "char"); end
                if index == 2, testCase.verifyClass(entry.LiteralValue, "single"); end
                if index == 3, testCase.verifyClass(entry.LiteralValue{1}, "single"); end
                if index == 4, testCase.verifyClass(entry.LiteralValue.Value, "single"); end
            end
        end

        function identicalSourceSettingsDoNotInvalidateInputs(testCase)
            % identicalSourceSettingsDoNotInvalidateInputs Retain the input revision when a current binding is reapplied.
            registry = macd.model.ComponentRegistry.createDefault();
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            document = macd.source.AppSourceParser.parseText(string(fileread(fullfile(root, ...
                "tests", "fixtures", "handle", "SmallPreviewFixtureApp.m"))), registry);
            owner = document.getComponentByName("TopLeftLabel");
            entry = owner.getProperty("Text");
            settings = owner.getSettings("Text");
            before = document.evaluationContext(registry).revisionToken();
            entry.applySourceSetting(settings(end));
            after = document.evaluationContext(registry).revisionToken();
            testCase.verifyEqual(after.Revision, before.Revision);
            testCase.verifyEqual(entry.LiteralValue, settings(end).LiteralValue);
        end

        function foreignDocumentTokensNeverCertifyTransitions(testCase)
            % foreignDocumentTokensNeverCertifyTransitions Require exact clock ownership even for identical revision numbers.
            registry = macd.model.ComponentRegistry.createDefault();
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            source = string(fileread(fullfile(root, "tests", "fixtures", "handle", "SmallPreviewFixtureApp.m")));
            first = macd.source.AppSourceParser.parseText(source, registry);
            second = macd.source.AppSourceParser.parseText(source, registry);
            foreign = first.evaluationContext(registry).revisionToken();
            own = second.evaluationContext(registry).revisionToken();
            testCase.verifyEqual(foreign.Revision, own.Revision);
            owner = second.getComponentByName("TopLeftLabel");
            second.setProperty(owner.Id, "Text", "Changed", registry);
            context = second.evaluationContext(registry);
            request = macd.ui.RefreshRequest("properties", owner.Id, "Text");
            testCase.verifyTrue(context.isLiteralTransition(own, request));
            testCase.verifyFalse(context.isLiteralTransition(foreign, request));
        end

        function directChangesRejectThePreviousTransitionToken(testCase)
            % directChangesRejectThePreviousTransitionToken Keep management-free input mutations on exact comparison.
            registry = macd.model.ComponentRegistry.createDefault();
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            document = macd.source.AppSourceParser.parseText(string(fileread(fullfile(root, ...
                "tests", "fixtures", "handle", "SmallPreviewFixtureApp.m"))), registry);
            owner = document.getComponentByName("TopLeftLabel");
            context = document.evaluationContext(registry);
            token = context.revisionToken();
            document.setProperty(owner.Id, "Text", "Changed", registry);
            request = macd.ui.RefreshRequest("properties", owner.Id, "Text");
            current = document.evaluationContext(registry);
            testCase.verifyTrue(current.isLiteralTransition(token, request));
            owner.Metadata.DirectMutation = true;
            testCase.verifyFalse(current.isLiteralTransition(token, request));
            testCase.verifyEqual(document.evaluationContext(registry).inputs(), ...
                macd.model.EvaluationContext(document, registry).inputs());
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
