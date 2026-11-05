classdef (TestTags = {'fast', 'model'}) ComponentLookupTest < matlab.unittest.TestCase
    % ComponentLookupTest Verify read-only identity reuse under every collection mutation.
    %   Lookup preserves first-match order, invalid-handle behavior, mutable
    %   record visibility, and independent documents without retaining misses.
    methods (Test)
        function repeatedReadsKeepIdentityAndInputRevision(testCase)
            % repeatedReadsKeepIdentityAndInputRevision Return current records without semantic mutations.
            document = yamada.model.DocumentModel("LookupFixture");
            records = yamada.model.ComponentRecord.empty;
            for index = 1:64
                records(end + 1) = ComponentLookupTest.record("id" + index, "Label" + index); %#ok<AGROW>
            end
            document.Components = records;
            registry = yamada.model.ComponentRegistry.createDefault();
            context = document.evaluationContext(registry);
            [before, safe] = context.inputs();
            testCase.assertTrue(safe);
            for repeat = 1:3
                for index = 64:-1:1
                    testCase.verifyEqual(document.getComponent("id" + index), records(index));
                end
            end
            testCase.verifyEqual(document.evaluationContext(registry), context);
            [after, safe] = context.inputs();
            testCase.verifyTrue(safe);
            testCase.verifyEqual(after, before);
        end

        function reorderedDuplicatesRetainFirstMatch(testCase)
            % reorderedDuplicatesRetainFirstMatch Respect ordering even in a deliberately invalid identity graph.
            document = yamada.model.DocumentModel("DuplicateLookupFixture");
            first = ComponentLookupTest.record("same", "First");
            second = ComponentLookupTest.record("same", "Second");
            document.Components = [first second];
            testCase.verifyEqual(document.getComponent("same"), first);
            testCase.verifyEqual(document.getComponent("same"), first);
            document.Components = [second first];
            testCase.verifyEqual(document.getComponent("same"), second);
        end

        function indexedAssignmentsInvalidateEveryAffectedResult(testCase)
            % indexedAssignmentsInvalidateEveryAffectedResult Observe append, replacement, removal, and reshaping.
            document = yamada.model.DocumentModel("CollectionLookupFixture");
            first = ComponentLookupTest.record("one", "First");
            second = ComponentLookupTest.record("two", "Second");
            document.Components = [first second];
            testCase.verifyEqual(document.getComponent("one"), first);
            testCase.verifyEmpty(document.getComponent("three"));
            third = ComponentLookupTest.record("three", "Third");
            document.Components(end + 1) = third;
            testCase.verifyEqual(document.getComponent("three"), third);
            replacement = ComponentLookupTest.record("one", "Replacement");
            document.Components(1) = replacement;
            testCase.verifyEqual(document.getComponent("one"), replacement);
            document.Components(2) = [];
            testCase.verifyEmpty(document.getComponent("two"));
            testCase.verifyEqual(document.getComponent("three"), third);
            document.Components = reshape(document.Components, [], 1);
            testCase.verifyEqual(document.getComponent("one"), replacement);
            document.Components = yamada.model.ComponentRecord.empty;
            testCase.verifyEmpty(document.getComponent("one"));
        end

        function renamedRecordsAndDocumentsRemainIndependent(testCase)
            % renamedRecordsAndDocumentsRemainIndependent Store indices rather than stale objects or names.
            firstDocument = yamada.model.DocumentModel("FirstLookupFixture");
            secondDocument = yamada.model.DocumentModel("SecondLookupFixture");
            first = ComponentLookupTest.record("shared", "First");
            second = ComponentLookupTest.record("shared", "Second");
            firstDocument.Components = first;
            secondDocument.Components = second;
            testCase.verifyEqual(firstDocument.getComponent("shared"), first);
            testCase.verifyEqual(secondDocument.getComponent("shared"), second);
            first.Name = "Changed";
            first.ParentId = "new-parent";
            testCase.verifyEqual(firstDocument.getComponent("shared").Name, "Changed");
            testCase.verifyEqual(firstDocument.getComponent("shared").ParentId, "new-parent");
            testCase.verifyEqual(secondDocument.getComponent("shared").Name, "Second");
        end

        function unusualIdsPreserveOrderedSearchSemantics(testCase)
            % unusualIdsPreserveOrderedSearchSemantics Retain empty and non-scalar query behavior.
            document = yamada.model.DocumentModel("UnusualLookupFixture");
            empty = ComponentLookupTest.record("", "EmptyId");
            normal = ComponentLookupTest.record("normal", "Normal");
            document.Components = [empty normal];
            testCase.verifyEqual(document.getComponent(""), empty);
            testCase.verifyEqual(document.getComponent(["normal", "normal"]), normal);
            testCase.verifyEmpty(document.getComponent(["normal", "other"]));
            testCase.verifyEmpty(document.getComponent(string(missing)));
            testCase.verifyEmpty(document.getComponent(strings(0, 0)));
        end

        function invalidRecordsKeepEarlierMatchAndFailureOrder(testCase)
            % invalidRecordsKeepEarlierMatchAndFailureOrder Do not hide invalid handles after warming an identity.
            document = yamada.model.DocumentModel("InvalidLookupFixture");
            first = ComponentLookupTest.record("first", "First");
            last = ComponentLookupTest.record("last", "Last");
            document.Components = [first last];
            testCase.verifyEqual(document.getComponent("first"), first);
            testCase.verifyEqual(document.getComponent("last"), last);
            delete(last);
            testCase.verifyEqual(document.getComponent("first"), first);
            testCase.verifyError(@() document.getComponent("last"), "MATLAB:class:InvalidHandle");
            testCase.verifyError(@() document.getComponent("missing"), "MATLAB:class:InvalidHandle");
        end

        function insertionHistoryReturnsTheCurrentCollection(testCase)
            % insertionHistoryReturnsTheCurrentCollection Follow source-safe insertion, Undo, and Redo.
            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("HistoryLookupFixture", registry);
            root = document.getComponent(document.RootComponentId);
            label = document.insertComponent(registry, "uilabel", root.Id);
            testCase.verifyEqual(document.getComponent(label.Id), label);
            document.undo();
            testCase.verifyEmpty(document.getComponent(label.Id));
            testCase.verifyEqual(document.getComponent(root.Id), root);
            document.redo();
            testCase.verifyEqual(document.getComponent(label.Id), label);
        end
    end

    methods (Static, Access = private)
        function value = record(id, name)
            % record Construct an unparented record for identity-only collection tests.
            arguments (Input)
                id (1, 1) string
                name (1, 1) string
            end
            arguments (Output)
                value (1, 1) yamada.model.ComponentRecord
            end
            value = yamada.model.ComponentRecord(id, name, "uilabel", "matlab.ui.control.Label", "generated");
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
