classdef (TestTags = {'fast', 'catalog', 'model'}) PropertyApplicationPolicyTest < matlab.unittest.TestCase
    % PropertyApplicationPolicyTest Verify initialization policies and dependency ordering.
    %   These nonvisual tests cover declarative validation and graph semantics,
    %   independently of MATLAB setters or Inspector presentation order.

    methods (Test)
        function legacyPolicyRetainsConservativeDefaults(testCase)
            % legacyPolicyRetainsConservativeDefaults Avoid claiming unaudited constructor support.

            policy = macd.model.PropertyApplicationPolicy();
            testCase.verifyEmpty(policy.ApplyAfter);
            testCase.verifyEqual(policy.NameValue, "unknown");
            testCase.verifyEqual(policy.EffectPolicy, "none");
            testCase.verifyEqual(policy.EffectStatus, "unknown");
            testCase.verifyEmpty(policy.AffectedPaths);
            definitions = [macd.model.PropertyDefinition("Value"), ...
                macd.model.PropertyDefinition("Items")];
            testCase.verifyEqual(macd.model.PropertyApplicationPolicy.orderDefinitions(definitions), [1 2]);
        end

        function ordersDependenciesStablyAcrossIndependentProperties(testCase)
            % ordersDependenciesStablyAcrossIndependentProperties Respect prerequisites while retaining ready-node order.

            definitions = [ ...
                macd.model.PropertyDefinition("Value", [], false, true, ...
                    struct("application", struct("applyAfter", {{"Items", "ItemsData"}}))), ...
                macd.model.PropertyDefinition("Text"), ...
                macd.model.PropertyDefinition("ItemsData", [], false, true, ...
                    struct("application", struct("applyAfter", {{"Items"}}))), ...
                macd.model.PropertyDefinition("Items")];
            testCase.verifyEqual(macd.model.PropertyApplicationPolicy.orderDefinitions(definitions), [2 4 3 1]);
        end

        function rejectsInvalidShapesDuplicatesAndSymbols(testCase)
            % rejectsInvalidShapesDuplicatesAndSymbols Reject malformed policies before application.

            invalid = {[], struct("applyAfter", 'Items'), ...
                struct("applyAfter", {{"Items", "Items"}}), ...
                struct("applyAfter", {{"not a property"}}), ...
                struct("nameValue", 1), struct("nameValue", "yes"), ...
                struct("effectPolicy", "arbitrary"), struct("execute", "system"), ...
                struct("effectStatus", "approved"), struct("effectReason", ""), ...
                struct("affectedPaths", {{"A", "A"}}), struct("affectedPaths", {{"bad path"}})};
            for index = 1:numel(invalid)
                testCase.verifyError(@() macd.model.PropertyApplicationPolicy(invalid{index}), ...
                    "macd:ComponentCatalogLoader:InvalidCatalog");
            end
        end

        function rejectsSelfReferenceAndIndirectCycles(testCase)
            % rejectsSelfReferenceAndIndirectCycles Reject both immediate and transitive graph failures.

            make = @(name, dependency) macd.model.PropertyDefinition(name, [], false, true, ...
                struct("application", struct("applyAfter", {{dependency}})));
            testCase.verifyError(@() macd.model.PropertyApplicationPolicy.orderDefinitions(make("A", "A")), ...
                "macd:ComponentCatalogLoader:InvalidCatalog");
            definitions = [make("A", "B"), make("B", "C"), make("C", "A")];
            testCase.verifyError(@() macd.model.PropertyApplicationPolicy.orderDefinitions(definitions), ...
                "macd:ComponentCatalogLoader:InvalidCatalog");
        end

        function parsesOnlyAuditedInertDefaults(testCase)
            % parsesOnlyAuditedInertDefaults Keep seeds separate from source and reject executable expressions.
            policy = macd.model.PropertyApplicationPolicy(struct("defaultLiteral", "[-Inf Inf]"));
            testCase.verifyTrue(policy.HasInitialValue);
            testCase.verifyEqual(policy.InitialValue, [-Inf Inf]);
            policy = macd.model.PropertyApplicationPolicy(struct("defaultLiteral", "NaT"));
            testCase.verifyTrue(isnat(policy.InitialValue));
            for invalid = ["", "createSomething()", "1+2"]
                testCase.verifyError(@() macd.model.PropertyApplicationPolicy( ...
                    struct("defaultLiteral", invalid)), "macd:ComponentCatalogLoader:InvalidCatalog");
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
