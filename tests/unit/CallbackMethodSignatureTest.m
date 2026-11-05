classdef (TestTags = {'fast', 'parser'}) CallbackMethodSignatureTest < matlab.unittest.TestCase
    % CallbackMethodSignatureTest Verify cached positional signatures without executing app code.
    %   Tests cover forwarding forms, validation text and unsupported declarations.

    methods (Test)
        function fixedInputsChooseDocumentedForwarders(testCase)
            % fixedInputsChooseDocumentedForwarders Use declared arity rather than argument spelling.
            cases = {"function run(app)", "@(~, ~) app.run()"; ...
                "function output = run(app, arbitrary)", "@(~, event) app.run(event)"; ...
                "function [one, two] = run(app, source, event)", "@app.run"; ...
                "function run(~, ~, event)", "@app.run"};
            for index = 1:size(cases, 1)
                analysis = CallbackMethodSignatureTest.compile([cases{index, 1}; "end"]);
                signature = analysis.Layout.Methods.Signature;
                testCase.verifyTrue(signature.Eligible);
                testCase.verifyEqual(signature.binding("run"), cases{index, 2});
            end
        end

        function continuedDeclarationsAndStaticMethodsRespectScopes(testCase)
            % continuedDeclarationsAndStaticMethodsRespectScopes Read continued signatures and exclude noninstance methods.
            source = strjoin(["classdef Example < handle"; "methods (Static)"; ...
                "function ignored(app, event)"; "end"; "end"; "methods (Access = private)"; ...
                "function [first, second] = run(app, ..."; "source, event)"; "end"; "end"; "end"], newline);
            analysis = yamada.source.SourceAnalysis(source);
            testCase.verifyTrue(analysis.Layout.Valid);
            testCase.verifyEqual(string({analysis.Layout.Methods.Name}), "run");
            testCase.verifyEqual(analysis.Layout.Methods.Signature.Inputs, ["app", "source", "event"]);
        end

        function unsupportedInputsStayOutOfTheIndex(testCase)
            % unsupportedInputsStayOutOfTheIndex Reject uncertain and nonpositional declarations conservatively.
            cases = {["function run(app, src, event, optional)"; "arguments"; ...
                "app"; "src"; "event"; "optional = dangerous()"; "end"; "end"]; ...
                ["function run(app, varargin)"; "end"]; ...
                ["function run(app, options)"; "arguments"; "app"; "options.Name string"; "end"; "end"]; ...
                ["function run(app, event)"; "arguments (Repeating)"; "app"; "event"; "end"; "end"]};
            for index = 1:numel(cases)
                analysis = CallbackMethodSignatureTest.compile(cases{index});
                testCase.verifyFalse(analysis.Layout.Methods.Signature.Eligible);
            end
        end

        function validationIsRecordedWithoutEvaluation(testCase)
            % validationIsRecordedWithoutEvaluation Retain class names and annotate arbitrary validators.
            analysis = CallbackMethodSignatureTest.compile(["function run(app, src, event)"; ...
                "arguments (Input)"; "app Example"; "src matlab.ui.control.Button"; ...
                "event (1, 1) matlab.ui.eventdata.ButtonPushedData {dangerousValidator}"; "end"; "end"]);
            signature = analysis.Layout.Methods.Signature;
            testCase.verifyTrue(signature.Eligible);
            testCase.verifyEqual(signature.Classes, ["Example", "matlab.ui.control.Button", "matlab.ui.eventdata.ButtonPushedData"]);
            testCase.verifyEqual(signature.Unchecked, [false false true]);
        end

        function accessorsAndNestedFunctionsDoNotHideEligibleMethods(testCase)
            % accessorsAndNestedFunctionsDoNotHideEligibleMethods Keep class layout valid while excluding accessor signatures.
            analysis = CallbackMethodSignatureTest.compile(["function output = get.Value(app)"; "output = 1"; "end"; ...
                "function run(app)"; "function nested(x)"; "end"; "end"]);
            testCase.verifyTrue(analysis.Layout.Valid);
            testCase.verifyEqual(string({analysis.Layout.Methods.Name}), ["get.Value", "run"]);
            testCase.verifyFalse(analysis.Layout.Methods(1).Signature.Eligible);
            testCase.verifyTrue(analysis.Layout.Methods(2).Signature.Eligible);
        end

        function editorBodyEditsPreserveCachedSignature(testCase)
            % editorBodyEditsPreserveCachedSignature Project existing signatures without rescanning method bodies.
            analysis = CallbackMethodSignatureTest.compile(["function run(app, event)"; "value = 12345"; "end"]);
            source = strjoin(["classdef Example < handle"; "methods (Access = private)"; ...
                "function run(app, event)"; "value = 12345"; "end"; "end"; "end"], newline);
            offset = strfind(source, "12345");
            batch = yamada.source.SourcePatchBatch(source, struct("Start", offset, "End", offset + 4, "Text", "42"));
            [after, local, statistics] = analysis.withPatches(batch, true);
            testCase.verifyTrue(local);
            testCase.verifyFalse(statistics.FullScan);
            testCase.verifyEqual(after.Layout.Methods.Signature, analysis.Layout.Methods.Signature);
        end
    end

    methods (Static, Access = private)
        function analysis = compile(body)
            % compile Build an owned class fixture using the production lexical cache.
            arguments (Input)
                body (:, 1) string
            end
            arguments (Output)
                analysis (1, 1) yamada.source.SourceAnalysis
            end
            analysis = yamada.source.SourceAnalysis(strjoin(["classdef Example < handle"; ...
                "methods (Access = private)"; body; "end"; "end"], newline));
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
