classdef PropertySourcePlan
    % PropertySourcePlan Share parsed property placement across state and Preview consumers.
    %   Source additions and pending subtree relocations produce independent
    %   parsed configurations. Original records and edit identities stay intact.

    methods (Static)
        function plan = combined(document, component, registry)
            % combined Reparse complete emitted initialization without executing the input app.
            arguments (Input)
                document (1, 1) macd.model.DocumentModel
                component (1, 1) macd.model.ComponentRecord
                registry (1, 1) macd.model.ComponentRegistry
            end
            arguments (Output)
                plan (1, 1) struct
            end
            context = document.evaluationContext(registry);
            [plan, found] = context.configuration("combined", component.Name);
            if found, return, end
            % The detached candidate may use conservative states during generation.
            candidate = document.structuralCandidate();
            candidate.Metadata.ResolvingCombinedPropertySource = true;
            [source, diagnostics] = macd.source.RoundTripGenerator(registry).generate(candidate);
            if strlength(source) == 0 || macd.validation.ModelValidator.hasErrors(diagnostics)
                error("macd:PropertySourcePlan:UnsafeCombinedPlacement", "%s", strjoin(string({diagnostics.Message}), newline));
            end
            [parsed, diagnostics] = macd.source.AppSourceParser.parseText(source, registry);
            if macd.validation.ModelValidator.hasErrors(diagnostics)
                error("macd:PropertySourcePlan:UnsafeCombinedPlacement", "%s", strjoin(string({diagnostics.Message}), newline));
            end
            configured = parsed.getComponentByName(component.Name);
            if isempty(configured)
                error("macd:PropertySourcePlan:UnsafeCombinedPlacement", "The configured component was not retained.");
            end
            plan = struct("Document", parsed, "Component", configured);
            context.rememberConfiguration("combined", parsed);
        end

        function result = needsPlan(document, component)
            % needsPlan Identify parsed components whose initialization source will change location.
            arguments (Input)
                document (1, 1) macd.model.DocumentModel
                component (1, 1) macd.model.ComponentRecord
            end
            arguments (Output)
                result (1, 1) logical
            end
            result = component.Origin == "parsed" && ...
                (macd.source.SubtreeReparentSourceEdits.contains(document, component.Id) || ...
                macd.source.PropertyInsertionPlanner.needsPlan(document, component));
        end

        function plan = plan(document, component, registry)
            % plan Return the actual parsed configuration used by localized source generation.
            arguments (Input)
                document (1, 1) macd.model.DocumentModel
                component (1, 1) macd.model.ComponentRecord
                registry (1, 1) macd.model.ComponentRegistry
            end
            arguments (Output)
                plan (1, 1) struct
            end
            context = document.evaluationContext(registry);
            [plan, found] = context.configuration("placement:" + component.Id, ...
                document.sourceComponentName(component.Id));
            if found, return, end
            if macd.source.SubtreeReparentSourceEdits.contains(document, component.Id)
                [~, ~, candidate] = macd.source.SubtreeReparentSourceEdits.build(document, registry);
                configured = candidate.getComponentByName(document.sourceComponentName(component.Id));
                plan = struct("Document", candidate, "Component", configured);
            else
                plan = macd.source.PropertyInsertionPlanner.plan(document, component, registry);
            end
            context.rememberConfiguration("placement:" + component.Id, plan.Document);
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
