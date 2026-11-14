classdef (TestTags = {'lifecycle'}) ExampleAppTest < matlab.unittest.TestCase
    % ExampleAppTest Verify the project-owned tutorial application in examples.
    %   The tutorial runs as an ordinary MATLAB app and stays editable by
    %   yamada without executing it. These checks need no packaged Toolbox.

    properties (Access = private)
        ProjectRoot string
    end

    methods (TestMethodSetup)
        function locateProject(testCase)
            % locateProject Resolve the checkout that owns the tutorial source.
            testCase.ProjectRoot = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
        end
    end

    methods (Test, TestTags = {'ui'})
        function includedExampleRunsAndCloses(testCase)
            % includedExampleRunsAndCloses Exercise the tutorial's real callback and owner cleanup.
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(testCase.ProjectRoot, "examples")));
            app = WelcomeApp;
            testCase.addTeardown(@() deleteIfValid(app));
            figure = findall(0, "Type", "figure", "Name", "Welcome to yamada");
            testCase.assertNumElements(figure, 1);
            button = findall(figure, "Text", "Say hello");
            testCase.assertNumElements(button, 1);
            button.ButtonPushedFcn(button, struct());
            testCase.verifyNumElements(findall(figure, "Text", "Hello from your app!"), 1);
            close(figure);
            testCase.verifyFalse(isvalid(app));
            testCase.verifyEmpty(findall(0, "Type", "figure", "Name", "Welcome to yamada"));
        end
    end

    methods (Test, TestTags = {'fast', 'parser'})
        function includedExampleIsEditableWithoutExecution(testCase)
            % includedExampleIsEditableWithoutExecution Parse the owned tutorial app without creating its window.
            registry = yamada.model.ComponentRegistry.createDefault();
            before = findall(0, "Type", "figure");
            [document, diagnostics] = yamada.source.AppSourceParser.parseFile( ...
                fullfile(testCase.ProjectRoot, "examples", "WelcomeApp.m"), registry);
            testCase.verifyFalse(yamada.validation.ModelValidator.hasErrors(diagnostics));
            testCase.verifyEqual(document.ClassName, "WelcomeApp");
            testCase.verifyNotEmpty(document.getComponentByName("GreetingLabel"));
            testCase.verifyNotEmpty(document.getComponentByName("GreetButton"));
            testCase.verifyEqual(findall(0, "Type", "figure"), before);
        end
    end
end

function deleteIfValid(object)
% deleteIfValid Release a tutorial owner only if a failed test left it alive.
arguments (Input)
    object (1, 1) handle
end
if isvalid(object), delete(object); end
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
