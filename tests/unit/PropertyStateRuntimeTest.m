classdef (TestTags = {'model', 'preview', 'ui'}) PropertyStateRuntimeTest < matlab.unittest.TestCase
    % PropertyStateRuntimeTest Compare audited state resolution with owned R2024a controls.
    %   Native fixtures and symbolic replay consume the same fixed literals;
    %   the resolver never calls the factory or executes represented source.

    methods (Test)
        function resolutionAgreesWithOwnedInteractionObservations(testCase)
            % resolutionAgreesWithOwnedInteractionObservations Check constructor groups and setter effects independently.
            projectRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
            originalPath = path;
            cleanup = onCleanup(@() path(originalPath));
            addpath(fullfile(projectRoot, "dev", "component-data"));
            observations = ProbeApplicationInteractions();
            registry = yamada.model.ComponentRegistry.createDefault();
            unresolved = ["numeric-exclude-lower", "numeric-exclude-upper", "numeric-limit-while-exclusive"];
            for observation = observations
                definition = registry.get(observation.Factory, observation.CreationArguments);
                component = yamada.model.ComponentRecord("owned-runtime", "Owned", ...
                    observation.Factory, definition.DeclaredType, "parsed");
                component.CreationArguments = observation.CreationArguments;
                sequence = 0;
                pairs = observation.NameValueArguments;
                for index = 1:2:numel(pairs)
                    sequence = sequence + 1;
                    component.recordSetting(testCase.setting(pairs{index}, pairs{index + 1}, sequence, "nameValue"));
                end
                pairs = observation.Assignments;
                for index = 1:2:numel(pairs)
                    sequence = sequence + 1;
                    component.recordSetting(testCase.setting(pairs{index}, pairs{index + 1}, sequence, "assignment"));
                end
                [states, diagnostics] = yamada.model.PropertyStateResolver.resolve(component, definition.Properties);
                if ~observation.Success
                    testCase.verifyTrue(yamada.validation.ModelValidator.hasErrors(diagnostics), observation.Case);
                    continue
                end
                testCase.verifyEmpty(diagnostics, observation.Case);
                if startsWith(observation.Case, "panel-")
                    state = states(string({states.Path}) == "Position");
                    if observation.Case == "panel-position-first"
                        testCase.verifyFalse(state.IsKnown, observation.Case);
                        continue
                    end
                else
                    state = states(string({states.Path}) == "Value");
                end
                if any(unresolved == observation.Case)
                    testCase.verifyFalse(state.IsKnown, observation.Case);
                    testCase.verifyNotEmpty(state.Reason, observation.Case);
                    continue
                end
                testCase.assertTrue(state.IsKnown, observation.Case);
                expected = observation.Snapshot.(state.Path);
                actual = state.EffectiveValue;
                if ischar(expected) || isstring(expected), expected = string(expected); actual = string(actual); end
                testCase.verifyEqual(actual, expected, observation.Case);
                if startsWith(observation.Case, "ticks-")
                    mode = states(string({states.Path}) == "MajorTicksMode");
                    testCase.verifyEqual(string(mode.EffectiveValue), string(observation.Snapshot.MajorTicksMode));
                end
            end
            clear cleanup
        end

        function auditedDefaultSeedsMatchOwnedNativeControls(testCase)
            % auditedDefaultSeedsMatchOwnedNativeControls Verify every promoted seed without using it to construct controls.
            registry = yamada.model.ComponentRegistry.createDefault();
            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() delete(figure));
            for id = registry.listVariantIds()
                definition = registry.getById(id);
                selected = definition.Properties(arrayfun(@(property) property.Application.HasInitialValue, definition.Properties));
                if isempty(selected), continue, end
                if definition.IsRoot
                    target = figure;
                else
                    target = feval(definition.Factory, figure, definition.CreationArguments{:});
                end
                for property = reshape(selected, 1, [])
                    actual = target.(property.Path);
                    expected = property.Application.InitialValue;
                    if isa(actual, "matlab.lang.OnOffSwitchState"), actual = string(actual); end
                    if ischar(actual) || isstring(actual), actual = string(actual); expected = string(expected); end
                    testCase.verifyTrue(isequaln(actual, expected), id + "." + property.Path);
                end
                if target ~= figure, delete(target); end
            end
            clear cleanup
        end
    end

    methods (Static, Access = private)
        function setting = setting(path, value, sequence, method)
            % setting Capture an owned fixture argument or assignment without parsing executable code.
            arguments (Input)
                path (1, 1) string
                value
                sequence (1, 1) double
                method (1, 1) string
            end
            arguments (Output)
                setting (1, 1) yamada.model.PropertySetting
            end
            syntax = "dot";
            statementId = "assignment-" + sequence;
            if method == "nameValue", syntax = "quotedPair"; statementId = "owned-constructor"; end
            span = yamada.model.SourceSpan(sequence * 10, sequence * 10 + 1);
            setting = yamada.model.PropertySetting(path, value, struct("Method", method, "Syntax", syntax, ...
                "Sequence", sequence, "SourceSnapshotId", "owned-runtime", ...
                "StatementId", statementId, "SourceSpan", span, "ValueSpan", span));
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
