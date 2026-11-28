classdef (TestTags = {'fast', 'model'}) ComponentLookupTest < matlab.unittest.TestCase
    % ComponentLookupTest Verify read-only identity reuse under every collection mutation.
    %   Lookup preserves mutable record visibility and independent documents
    %   without retaining stale matches or misses.
    methods (Test)
        % Guarantee: cached component lookups always return the current record, and reads never count as semantic mutations.
        % Failure mode: the lookup index survives insertion, removal, rename, Undo, or Redo and returns a stale record or another document's component, or reads bump the input revision.
        function repeatedReadsKeepIdentityAndInputRevision(testCase)
            % repeatedReadsKeepIdentityAndInputRevision Return current records without semantic mutations.
            document = yamada.model.DocumentModel("LookupFixture");
            records = yamada.model.ComponentRecord.empty;
            for index = 1:3
                records(end + 1) = ComponentLookupTest.record("id" + index, "Label" + index); %#ok<AGROW>
            end
            for record = records, document.addComponent(record); end
            registry = yamada.model.ComponentRegistry.createDefault();
            context = document.evaluationContext(registry);
            before = context.inputs();
            for repeat = 1:2
                for index = 3:-1:1
                    testCase.verifyEqual(document.getComponent("id" + index), records(index));
                end
            end
            testCase.verifyEqual(document.evaluationContext(registry), context);
            after = context.inputs();
            testCase.verifyEqual(after, before);
        end

        function renamedRecordsAndDocumentsRemainIndependent(testCase)
            % renamedRecordsAndDocumentsRemainIndependent Store indices rather than stale objects or names.
            firstDocument = yamada.model.DocumentModel("FirstLookupFixture");
            secondDocument = yamada.model.DocumentModel("SecondLookupFixture");
            first = ComponentLookupTest.record("shared", "First");
            second = ComponentLookupTest.record("shared", "Second");
            firstDocument.addComponent(first);
            secondDocument.addComponent(second);
            testCase.verifyEqual(firstDocument.getComponent("shared"), first);
            testCase.verifyEqual(secondDocument.getComponent("shared"), second);
            first.Name = "Changed";
            testCase.verifyEqual(firstDocument.getComponent("shared").Name, "Changed");
            testCase.verifyEqual(secondDocument.getComponent("shared").Name, "Second");
        end

        function structuralHistoryReturnsTheCurrentCollection(testCase)
            % structuralHistoryReturnsTheCurrentCollection Follow insertion, removal, Undo, and Redo.
            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("HistoryLookupFixture", registry);
            root = document.getComponent(document.RootComponentId);
            label = document.insertComponent(registry, "uilabel", root.Id);
            last = document.insertComponent(registry, "uibutton", root.Id);
            testCase.verifyEqual(document.getComponent(label.Id), label);
            % Removal shifts later indices, so a reused index must not return another record.
            document.removeSubtree(label.Id, registry);
            testCase.verifyEmpty(document.getComponent(label.Id));
            testCase.verifyEqual(document.getComponent(last.Id), last);
            document.undo();
            testCase.verifyEqual(document.getComponent(label.Id), label);
            testCase.verifyEqual(document.getComponent(last.Id), last);
            document.undo();
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
