classdef (TestTags = {'model', 'parser', 'generation', 'preview'}) PositionAliasSourceTest < matlab.unittest.TestCase
    % PositionAliasSourceTest Verify shared geometry through editing, copying, and Preview.
    %   Owned source fixtures are parsed without executing their constructors.
    %   Native Preview checks use only the editor's safe renderer.

    methods (Test, TestTags = {'fast'})
        function previewArgumentsRespectSkippedPropertiesAndKeepSource(testCase)
            % previewArgumentsRespectSkippedPropertiesAndKeepSource Filter native inputs without changing token ownership.
            cases = {"app.Control = uibutton(app.Left, Text='Owned', CreateFcn='disp(''owned'')', DeleteFcn='disp(''owned'')');", "uibutton-push"; ...
                "app.Control = uihtml(app.Left, HTMLSource='owned-missing.html', Position=[10 20 130 35]);", "uihtml"};
            for index = 1:size(cases, 1)
                [document, registry, control] = testCase.fixture(cases{index, 1}, cases{index, 2});
                before = control.CreationArguments;
                values = macd.model.PropertyApplicationPlanner.forPreviewArguments(control, registry);
                testCase.verifyFalse(any(ismember(string(values(1:2:end)), ...
                    ["CreateFcn", "DeleteFcn", "HTMLSource", "Position", "InnerPosition", "OuterPosition"])));
                testCase.verifyEqual(control.CreationArguments, before);
                testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(document), document.OriginalText);
            end
        end

        function laterAliasesKeepIndependentInputsAndSharedGetters(testCase)
            % laterAliasesKeepIndependentInputsAndSharedGetters Retain explicit source while the later alias determines geometry.
            [document, registry, control] = testCase.fixture([ ...
                "app.Control = uibutton(app.Left);", "app.Control.Position = [10 20 130 35];", ...
                "app.Control.InnerPosition = [30 40 150 45];"]);
            before = control.settingSnapshot();
            for path = ["Position", "InnerPosition", "OuterPosition"]
                state = testCase.state(document, registry, control, path);
                testCase.verifyTrue(state.IsKnown);
                testCase.verifyEqual(state.EffectiveValue, [30 40 150 45]);
                testCase.verifyEqual(state.EffectSettingId, control.getSettings("InnerPosition").Id);
            end
            position = testCase.state(document, registry, control, "Position");
            testCase.verifyEqual(position.ExplicitValue, [10 20 130 35]);
            testCase.verifyNotEqual(position.LastSettingId, position.EffectSettingId);
            testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(document), document.OriginalText);
            testCase.verifyEqual(control.settingSnapshot(), before);
        end

        function shadowedPositionEditsFailAtomically(testCase)
            % shadowedPositionEditsFailAtomically Refuse edits at an earlier token overridden by a later alias.
            [document, registry, control] = testCase.fixture([ ...
                "app.Control = uibutton(app.Left);", "app.Control.Position = [10 20 130 35];", ...
                "app.Control.InnerPosition = [30 40 150 45];"]);
            before = control.settingSnapshot();
            testCase.verifyError(@() document.setProperty(control.Id, "Position", [50 60 170 55], registry), ...
                "macd:DocumentModel:UnsafePropertyEdit");
            testCase.verifyEqual(control.settingSnapshot(), before);
            testCase.verifyEqual(document.HistoryIndex, 0);
            testCase.verifyFalse(document.IsDirty);
        end

        function newPositionsUseAValidatedSlotAfterAliases(testCase)
            % newPositionsUseAValidatedSlotAfterAliases Preserve assignment and both constructor spellings through insertion and history.
            bodies = {["app.Control = uibutton(app.Left);", "app.Control.InnerPosition = [30 40 150 45];"], ...
                "app.Control = uibutton(app.Left, InnerPosition=[30 40 150 45]);", ...
                "app.Control = uibutton(app.Left, 'InnerPosition', [30 40 150 45]);"};
            for index = 1:numel(bodies)
                [document, registry, control] = testCase.fixture(bodies{index});
                original = document.OriginalText;
                document.setProperty(control.Id, "Position", [50 60 170 55], registry);
                generator = macd.source.RoundTripGenerator(registry);
                source = generator.generate(document);
                testCase.verifyEqual(generator.generate(document), source);
                reopened = macd.source.AppSourceParser.parseText(source, registry);
                other = reopened.getComponentByName("Control");
                method = "nameValue";
                if index == 1, method = "assignment"; end
                testCase.verifyEqual(other.getSettings("Position").Method, method);
                testCase.verifyNumElements(other.getSettings("Position"), 1);
                testCase.verifyLessThan(other.getSettings("InnerPosition").Sequence, other.getSettings("Position").Sequence);
                testCase.verifyEqual(testCase.state(reopened, registry, other, "InnerPosition").EffectiveValue, [50 60 170 55]);
                document.undo();
                testCase.verifyEqual(generator.generate(document), original);
                document.redo();
                testCase.verifyEqual(generator.generate(document), source);
            end
        end

        function copiesCanonicalizeAliasesAndVerifyTheirOffset(testCase)
            % copiesCanonicalizeAliasesAndVerifyTheirOffset Freeze one Position instead of letting copied aliases overwrite placement.
            bodies = {["app.Control = uibutton(app.Left);", "app.Control.Position = [10 20 130 35];", ...
                "app.Control.InnerPosition = [30 40 150 45];"], ...
                "app.Control = uibutton(app.Left, Position=[10 20 130 35], InnerPosition=[30 40 150 45]);", ...
                "app.Control = uibutton(app.Left, 'InnerPosition', [30 40 150 45]);"};
            for body = bodies
                [document, registry, control, target] = testCase.fixture(body{1});
                before = control.settingSnapshot();
                snapshot = document.copySubtree(control.Id, registry);
                values = snapshot.CopyConfiguration.Properties;
                testCase.verifyFalse(any(ismember(string({values.Path}), ["InnerPosition", "OuterPosition"])));
                testCase.verifyEqual(values(string({values.Path}) == "Position").LiteralValue, [30 40 150 45]);
                copy = document.pasteSubtree(snapshot, target.Id, registry);
                testCase.verifyEqual(copy.getProperty("Position").LiteralValue, [40 50 150 45]);
                testCase.verifyEmpty(copy.getProperty("InnerPosition"));
                testCase.verifyEqual(testCase.state(document, registry, copy, "OuterPosition").EffectiveValue, [40 50 150 45]);
                testCase.verifyEqual(SourceAssertions.retained(control.settingSnapshot(), before), SourceAssertions.semantics(before));
                testCase.verifyEqual(document.HistoryIndex, 1);
                document.undo();
                testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(document), document.OriginalText);
                document.redo();
                testCase.verifyEqual(testCase.state(document, registry, document.getComponent(copy.Id), "Position").EffectiveValue, [40 50 150 45]);
            end
        end

        function unresolvedAliasesInvalidateEveryGetterUntilAWriteRestoresThem(testCase)
            % unresolvedAliasesInvalidateEveryGetterUntilAWriteRestoresThem Avoid falling back to an earlier numeric position.
            body = ["app.Control = uibutton(app.Left);", "app.Control.Position = [10 20 130 35];", ...
                "app.Control.InnerPosition = [10 20 130 35] + [0 0 0 0];"];
            [document, registry, control] = testCase.fixture(body);
            for path = ["Position", "InnerPosition", "OuterPosition"]
                state = testCase.state(document, registry, control, path);
                testCase.verifyFalse(state.IsKnown);
                testCase.verifyEqual(state.ReasonCode, "position-alias");
            end
            testCase.verifyError(@() document.copySubtree(control.Id, registry), "macd:DocumentModel:UnsafeSubtreeCopy");
            testCase.verifyEqual(macd.source.RoundTripGenerator(registry).generate(document), document.OriginalText);
            [document, registry, control] = testCase.fixture([body, "app.Control.Position = [50 60 170 55];"]);
            testCase.verifyEqual(testCase.state(document, registry, control, "InnerPosition").EffectiveValue, [50 60 170 55]);
        end

        function zeroSizeCopiesKeepTheirKnownDimensions(testCase)
            % zeroSizeCopiesKeepTheirKnownDimensions Accept native nonnegative geometry when applying a paste offset.
            [document, registry, control, target] = testCase.fixture( ...
                "app.Control = uibutton(app.Left, InnerPosition=[10 20 0 0]);");
            copy = document.pasteSubtree(document.copySubtree(control.Id, registry), target.Id, registry);
            testCase.verifyEqual(copy.getProperty("Position").LiteralValue, [20 30 0 0]);
            testCase.verifyEqual(testCase.state(document, registry, copy, "InnerPosition").EffectiveValue, [20 30 0 0]);
        end

        function shadowedRelocationRequestsFailWithoutMovingAnything(testCase)
            % shadowedRelocationRequestsFailWithoutMovingAnything Refuse a destination position overridden by a preserved alias.
            [document, registry, control, target] = testCase.fixture([ ...
                "app.Control = uibutton(app.Left);", "app.Control.Position = [10 20 130 35];", ...
                "app.Control.InnerPosition = [30 40 150 45];"]);
            before = control.settingSnapshot();
            parent = control.ParentId;
            testCase.verifyError(@() document.reparentSubtree(control.Id, target.Id, registry, [], [], [60 70 150 45]), ...
                "macd:DocumentModel:UnsafeSubtreeEdit");
            testCase.verifyEqual(control.ParentId, parent);
            testCase.verifyEqual(control.settingSnapshot(), before);
            testCase.verifyEqual(document.HistoryIndex, 0);
            testCase.verifyFalse(document.IsDirty);
        end

        function lampCopiesUseTheCoercedSquareAndKeepOriginalVectors(testCase)
            % lampCopiesUseTheCoercedSquareAndKeepOriginalVectors Distinguish square getters from explicit rectangular input.
            [document, registry, control, target] = testCase.fixture( ...
                "app.Control = uilamp(app.Left, InnerPosition=[10 20 130 35]);", "uilamp");
            testCase.verifyEqual(control.getProperty("InnerPosition").LiteralValue, [10 20 130 35]);
            testCase.verifyEqual(testCase.state(document, registry, control, "Position").EffectiveValue, [10 20 35 35]);
            copy = document.pasteSubtree(document.copySubtree(control.Id, registry), target.Id, registry);
            testCase.verifyEqual(copy.getProperty("Position").LiteralValue, [20 30 35 35]);
            testCase.verifyEqual(testCase.state(document, registry, copy, "InnerPosition").EffectiveValue, [20 30 35 35]);
        end

        function gridAliasesDoNotPretendToDetermineGeometry(testCase)
            % gridAliasesDoNotPretendToDetermineGeometry Copy grid placement and require measured geometry for absolute paste.
            [document, registry, control, target] = testCase.fixture([ ...
                "app.Control = uibutton(app.Grid);", "app.Control.InnerPosition = [10 20 130 35];", ...
                "app.Control.Layout.Row = 1;", "app.Control.Layout.Column = 1;"], "uibutton-push", true);
            state = testCase.state(document, registry, control, "InnerPosition");
            testCase.verifyFalse(state.IsKnown);
            testCase.verifyEqual(state.ReasonCode, "layout-managed");
            snapshot = document.copySubtree(control.Id, registry);
            testCase.verifyFalse(any(ismember(string({snapshot.CopyConfiguration.Properties.Path}), ["Position", "InnerPosition", "OuterPosition"])));
            copy = document.pasteSubtree(snapshot, target.Id, registry, [10 20 130 35]);
            testCase.verifyEqual(copy.getProperty("Position").LiteralValue, [20 30 130 35]);
        end

        function relocationUsesEffectiveGeometryAndRetainsAliasStatements(testCase)
            % relocationUsesEffectiveGeometryAndRetainsAliasStatements Add a destination position after a preserved sole alias.
            [document, registry, control, target] = testCase.fixture([ ...
                "app.Control = uibutton(app.Left);", "app.Control.InnerPosition = [30 40 150 45];"]);
            document.reparentSubtree(control.Id, target.Id, registry, [], [], [60 70 150 45]);
            source = document.GeneratedText;
            testCase.verifySubstring(source, "app.Control.InnerPosition = [30 40 150 45];");
            testCase.verifyEqual(testCase.state(document, registry, control, "Position").EffectiveValue, [60 70 150 45]);
            reopened = macd.source.AppSourceParser.parseText(source, registry);
            testCase.verifyEqual(testCase.state(reopened, registry, reopened.getComponentByName("Control"), "Position").EffectiveValue, [60 70 150 45]);
        end
    end

    methods (Test, TestTags = {'ui'})
        function previewNeverInvokesOwnedConstructorCallbacks(testCase)
            % previewNeverInvokesOwnedConstructorCallbacks Check both creation and cleanup with an owned inert sentinel.
            key = "yamadaPreview" + replace(string(java.util.UUID.randomUUID()), "-", "");
            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() testCase.cleanProbe(figure, key));
            callback = "'setappdata(groot, ''" + key + "'', true)'";
            [document, registry, control] = testCase.fixture( ...
                "app.Control = uibutton(app.Left, Text='Owned', CreateFcn=" + callback + ", DeleteFcn=" + callback + ");");
            [handles, diagnostics] = macd.ui.PreviewRenderer(registry).render(document, figure);
            testCase.assertTrue(isKey(handles, char(control.Id)));
            testCase.verifyEmpty(handles(char(control.Id)).CreateFcn);
            testCase.verifyEmpty(handles(char(control.Id)).DeleteFcn);
            testCase.verifyFalse(any(string({diagnostics.Code}) == "preview-render-failed"));
            testCase.verifyFalse(isappdata(groot, char(key)));
            delete(figure);
            testCase.verifyFalse(isappdata(groot, char(key)));
        end

        function namedImagesUseTheAssignmentAssetAdapter(testCase)
            % namedImagesUseTheAssignmentAssetAdapter Preserve local named-image previews after filtering constructor inputs.
            imagePath = string(tempname) + ".png";
            imwrite(zeros(2, 2, 3), imagePath);
            fileCleanup = onCleanup(@() delete(imagePath));
            figure = uifigure("Visible", "off");
            figureCleanup = onCleanup(@() delete(figure));
            [document, registry, control] = testCase.fixture( ...
                "app.Control = uiimage(app.Left, ImageSource=" + macd.source.LiteralEncoder.encode(imagePath) + ", Position=[10 20 130 35]);", "uiimage");
            [handles, diagnostics] = macd.ui.PreviewRenderer(registry).render(document, figure);
            testCase.assertTrue(isKey(handles, char(control.Id)));
            testCase.verifyEqual(string(handles(char(control.Id)).ImageSource), imagePath);
            testCase.verifyFalse(any(string({diagnostics.Code}) == "preview-property-failed"));
        end

        function previewProjectsKnownAliasesAndReportsUnknownOnes(testCase)
            % previewProjectsKnownAliasesAndReportsUnknownOnes Match the shared state without executing source expressions.
            figure = uifigure("Visible", "off");
            cleanup = onCleanup(@() delete(figure));
            cases = {["app.Control = uibutton(app.Left);", "app.Control.Position = [10 20 130 35];", ...
                "app.Control.InnerPosition = [30 40 150 45];"], "uibutton-push", [30 40 150 45]; ...
                "app.Control = uilamp(app.Left, InnerPosition=[10 20 130 35]);", "uilamp", [10 20 35 35]; ...
                ["app.Control = uibutton(app.Left);", "app.Control.Position = [10 20 130 35];", ...
                "app.Control.InnerPosition = [10 20 130 35] + [0 0 0 0];"], "uibutton-push", []};
            for index = 1:size(cases, 1)
                [document, registry, control] = testCase.fixture(cases{index, 1}, cases{index, 2});
                [handles, diagnostics] = macd.ui.PreviewRenderer(registry).render(document, figure);
                testCase.verifyTrue(isKey(handles, char(control.Id)));
                if isempty(cases{index, 3})
                    testCase.verifyTrue(any(string({diagnostics.Code}) == "preview-position-unknown"));
                else
                    testCase.verifyEqual(handles(char(control.Id)).Position, cases{index, 3});
                    testCase.verifyFalse(any(string({diagnostics.Code}) == "preview-position-unknown"));
                end
            end
        end
    end

    methods (Static, Access = private)
        function cleanProbe(figure, key)
            % cleanProbe Delete an owned Preview and clear only its unique callback sentinel.
            arguments (Input)
                figure
                key (1, 1) string
            end
            if isvalid(figure), delete(figure); end
            if isappdata(groot, char(key)), rmappdata(groot, char(key)); end
        end

        function [document, registry, control, target] = fixture(body, id, grid)
            % fixture Parse owned initializer text with independent source and destination parents.
            arguments (Input)
                body (1, :) string
                id (1, 1) string = "uibutton-push"
                grid (1, 1) logical = false
            end
            arguments (Output)
                document (1, 1) macd.model.DocumentModel
                registry (1, 1) macd.model.ComponentRegistry
                control (1, 1) macd.model.ComponentRecord
                target (1, 1) macd.model.ComponentRecord
            end
            registry = macd.model.ComponentRegistry.createDefault();
            definition = registry.getById(id);
            gridDeclaration = strings(1, 0);
            gridCreation = strings(1, 0);
            if grid
                gridDeclaration = "Grid matlab.ui.container.GridLayout";
                gridCreation = "app.Grid = uigridlayout(app.Left, RowHeight={100}, ColumnWidth={100});";
            end
            source = strjoin(["classdef PositionAliasFixture < handle", "properties", ...
                "UIFigure matlab.ui.Figure", "Left matlab.ui.container.Panel", "Right matlab.ui.container.Panel", ...
                "Control " + definition.DeclaredType, gridDeclaration, "end", "methods", ...
                "function app = PositionAliasFixture", "createComponents(app);", "end", "function createComponents(app)", ...
                "app.UIFigure = uifigure(Visible='off', Position=[100 100 450 350]);", ...
                "app.Left = uipanel(app.UIFigure, Units='pixels', Position=[1 1 200 300]);", gridCreation, body, ...
                "app.Right = uipanel(app.UIFigure, Units='pixels', Position=[220 1 200 300]);", ...
                "end", "end", "end"], sprintf('\r\n'));
            document = macd.source.AppSourceParser.parseText(source, registry);
            control = document.getComponentByName("Control");
            target = document.getComponentByName("Right");
        end

        function resolution = state(document, registry, control, path)
            % state Select a shared effective result from the public document projection.
            arguments (Input)
                document (1, 1) macd.model.DocumentModel
                registry (1, 1) macd.model.ComponentRegistry
                control (1, 1) macd.model.ComponentRecord
                path (1, 1) string
            end
            arguments (Output)
                resolution (1, 1) macd.model.PropertyState
            end
            states = document.getEffectivePropertyStates(registry, control.Id);
            resolution = states(arrayfun(@(item) item.Definition.Path == path, states)).Resolution;
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
