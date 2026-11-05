classdef (TestTags = {'fast', 'catalog', 'model'}) PropertyApplicationPolicyTest < matlab.unittest.TestCase
    % PropertyApplicationPolicyTest Verify initialization policies and dependency ordering.
    %   These nonvisual tests cover declarative validation and graph semantics,
    %   independently of MATLAB setters or Inspector presentation order.

    methods (Test)
        function legacyPolicyRetainsConservativeDefaults(testCase)
            % legacyPolicyRetainsConservativeDefaults Preserve unknown setter effects without a constructor-support flag.

            policy = yamada.model.PropertyApplicationPolicy();
            testCase.verifyEmpty(policy.ApplyAfter);
            testCase.verifyFalse(isprop(policy, "NameValue"));
            testCase.verifyEqual(policy.EffectPolicy, "none");
            testCase.verifyEqual(policy.EffectStatus, "unknown");
            testCase.verifyEmpty(policy.AffectedPaths);
            definitions = [yamada.model.PropertyDefinition("Value"), ...
                yamada.model.PropertyDefinition("Items")];
            testCase.verifyEqual(yamada.model.PropertyApplicationPolicy.orderDefinitions(definitions), [1 2]);
        end

        function ordersDependenciesStablyAcrossIndependentProperties(testCase)
            % ordersDependenciesStablyAcrossIndependentProperties Respect prerequisites while retaining ready-node order.

            definitions = [ ...
                yamada.model.PropertyDefinition("Value", [], false, true, ...
                    struct("application", struct("applyAfter", {{"Items", "ItemsData"}}))), ...
                yamada.model.PropertyDefinition("Text"), ...
                yamada.model.PropertyDefinition("ItemsData", [], false, true, ...
                    struct("application", struct("applyAfter", {{"Items"}}))), ...
                yamada.model.PropertyDefinition("Items")];
            testCase.verifyEqual(yamada.model.PropertyApplicationPolicy.orderDefinitions(definitions), [2 4 3 1]);
        end

        function rejectsInvalidShapesDuplicatesAndSymbols(testCase)
            % rejectsInvalidShapesDuplicatesAndSymbols Reject malformed policies before application.

            invalid = {[], struct("applyAfter", 'Items'), ...
                struct("applyAfter", {{"Items", "Items"}}), ...
                struct("applyAfter", {{"not a property"}}), ...
                struct("nameValue", "supported"), ...
                struct("effectPolicy", "arbitrary"), struct("execute", "system"), ...
                struct("effectStatus", "approved"), struct("effectReason", ""), ...
                struct("affectedPaths", {{"A", "A"}}), struct("affectedPaths", {{"bad path"}})};
            for index = 1:numel(invalid)
                testCase.verifyError(@() yamada.model.PropertyApplicationPolicy(invalid{index}), ...
                    "yamada:ComponentCatalogLoader:InvalidCatalog");
            end
        end

        function rejectsSelfReferenceAndIndirectCycles(testCase)
            % rejectsSelfReferenceAndIndirectCycles Reject both immediate and transitive graph failures.

            make = @(name, dependency) yamada.model.PropertyDefinition(name, [], false, true, ...
                struct("application", struct("applyAfter", {{dependency}})));
            testCase.verifyError(@() yamada.model.PropertyApplicationPolicy.orderDefinitions(make("A", "A")), ...
                "yamada:ComponentCatalogLoader:InvalidCatalog");
            definitions = [make("A", "B"), make("B", "C"), make("C", "A")];
            testCase.verifyError(@() yamada.model.PropertyApplicationPolicy.orderDefinitions(definitions), ...
                "yamada:ComponentCatalogLoader:InvalidCatalog");
        end

        function parsesOnlyAuditedInertDefaults(testCase)
            % parsesOnlyAuditedInertDefaults Keep seeds separate from source and reject executable expressions.
            policy = yamada.model.PropertyApplicationPolicy(struct("defaultLiteral", "[-Inf Inf]"));
            testCase.verifyTrue(policy.HasInitialValue);
            testCase.verifyEqual(policy.InitialValue, [-Inf Inf]);
            policy = yamada.model.PropertyApplicationPolicy(struct("defaultLiteral", "NaT"));
            testCase.verifyTrue(isnat(policy.InitialValue));
            for invalid = ["", "createSomething()", "1+2"]
                testCase.verifyError(@() yamada.model.PropertyApplicationPolicy( ...
                    struct("defaultLiteral", invalid)), "yamada:ComponentCatalogLoader:InvalidCatalog");
            end
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
