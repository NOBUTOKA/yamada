classdef (TestTags = {'fast', 'model', 'generation'}) SourceStrategyExperimentTest < matlab.unittest.TestCase
    % SourceStrategyExperimentTest Verify equivalent deferred and eager prototype source semantics.
    %   Tests compare saved values, growing and shrinking literals, positions, and model history.

    properties (TestParameter)
        Mode = {"deferred", "eager"}
    end

    methods (Test)
        function editsAndSavePreservePositionsAndValues(testCase, Mode)
            % editsAndSavePreservePositionsAndValues Compare replacement and insertion output with a parse oracle.
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            addpath(fullfile(root, "tests", "performance"));
            registry = macd.model.ComponentRegistry.createDefault();
            source = testCase.fixture();
            engine = SourceStrategyExperiment(source, Mode, registry);
            operations = {"Field", "Value", 12345; "Label", "Text", "A much longer Japanese string 日本語"; ...
                "Field", "Tooltip", "New hint"; "Label", "FontSize", 9; ...
                "Field", "Value", 2; "Field", "Tooltip", "Revised and longer hint"};
            for index = 1:size(operations, 1)
                engine.edit(operations{index, 1}, operations{index, 2}, operations{index, 3});
                output = engine.emit();
                parsed = macd.source.AppSourceParser.parseText(output, registry);
                for request = engine.Requests
                    entry = parsed.getComponentByName(request.Name).getProperty(request.Path);
                    testCase.verifyEqual(entry.LiteralValue, request.Value);
                end
                if Mode == "eager"
                    for component = parsed.Components
                        settingIndex = 0;
                        for setting = component.Settings
                            settingIndex = settingIndex + 1;
                            key = "occurrence:" + component.Name + ":" + settingIndex;
                            span = engine.Locations(string({engine.Locations.Key}) == key);
                            if isempty(span), continue, end
                            testCase.verifyEqual(span(end).Start, setting.ValueSpan.StartOffset);
                            testCase.verifyEqual(span(end).End, setting.ValueSpan.EndOffset);
                        end
                    end
                end
            end
            testCase.verifyEqual(engine.Document.HistoryIndex, size(operations, 1));
            path = string(tempname) + ".m";
            cleanup = onCleanup(@() delete(path));
            checkpoint = engine.save(path);
            testCase.verifyEqual(checkpoint.SourceText, engine.emit());
            testCase.verifyEqual(string(fileread(path)), checkpoint.SourceText);
            testCase.verifyFalse(engine.Document.IsDirty);
        end

        function independentProfilesKeepEveryEdit(testCase, Mode)
            % independentProfilesKeepEveryEdit Aggregate all action snapshots without last-action loss.
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            addpath(fullfile(root, "tests", "performance"));
            registry = macd.model.ComponentRegistry.createDefault();
            engine = SourceStrategyExperiment(testCase.fixture(), Mode, registry);
            operations = {"Field", "Value", 123; "Label", "Text", "Changed"; "Field", "Tooltip", "New"};
            profiles = cell(1, size(operations, 1));
            profileCleanup = onCleanup(@() profile("off"));
            for index = 1:size(operations, 1)
                profile clear; profile on;
                engine.edit(operations{index, 1}, operations{index, 2}, operations{index, 3});
                profile off;
                profiles{index} = profile("info");
            end
            folder = string(tempname);
            mkdir(folder);
            cleanup = onCleanup(@() SourceStrategyExperimentTest.removeProfiles(folder));
            writeSourceStrategyProfile(folder, "actions", profiles);
            functions = jsondecode(fileread(fullfile(folder, "actions.json")));
            match = functions(endsWith(string({functions.Name}), "SourceStrategyExperiment.edit"));
            testCase.verifyEqual(match.Calls, size(operations, 1));
        end

        function invalidLiteralLeavesBothStatesUnchanged(testCase, Mode)
            % invalidLiteralLeavesBothStatesUnchanged Reject numeric bounds failures before source or history mutation.
            root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            addpath(fullfile(root, "tests", "performance"));
            registry = macd.model.ComponentRegistry.createDefault();
            engine = SourceStrategyExperiment(testCase.fixture(), Mode, registry);
            engine.edit("Field", "Value", 123);
            before = engine.emit();
            history = engine.Document.HistoryIndex;
            failed = false;
            try
                engine.edit("Field", "Value", Inf);
            catch
                failed = true;
            end
            testCase.verifyTrue(failed);
            testCase.verifyEqual(engine.emit(), before);
            testCase.verifyEqual(engine.Document.HistoryIndex, history);
        end
    end

    methods (Static, Access = private)
        function removeProfiles(folder)
            % removeProfiles Remove only named profile artifacts created by this test.
            arguments (Input)
                folder (1, 1) string
            end
            for name = ["actions.json", "actions.mat"]
                path = fullfile(folder, name);
                if isfile(path), delete(path); end
            end
            rmdir(folder);
        end

        function source = fixture()
            % fixture Return a small straight-line fixture with explicit and absent settings.
            arguments (Output)
                source (1, 1) string
            end
            lines = ["classdef StrategyFixture < handle", "properties", ...
                "UIFigure matlab.ui.Figure", "Field matlab.ui.control.NumericEditField", ...
                "Label matlab.ui.control.Label", "end", "methods", ...
                "function app = StrategyFixture()", ...
                "app.UIFigure = uifigure('Visible', 'off');", ...
                "app.Field = uieditfield(app.UIFigure, 'numeric');", ...
                "app.Field.Value = 9;", ...
                "app.Label = uilabel(app.UIFigure);", ...
                "app.Label.Text = 'Earlier';", "app.Label.Text = 'Old';", "end", "end", "end"];
            source = strjoin(lines, string(sprintf("\r\n"))) + string(sprintf("\r\n"));
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
