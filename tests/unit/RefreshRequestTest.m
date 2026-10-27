classdef (TestTags = {'fast', 'catalog'}) RefreshRequestTest < matlab.unittest.TestCase
    % RefreshRequestTest Verify catalog-controlled placement and fit invalidation.
    %   Unknown capabilities and unavailable native inputs retain full refresh.
    methods (Test)
        function separatesFreeFixedAndFitGeometry(testCase)
            % separatesFreeFixedAndFitGeometry Retain geometry only when the layout mechanism requires it.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("GeometryPolicyFixture", registry);
            label = document.insertComponent(registry, "uilabel", document.RootComponentId);
            handles = containers.Map("KeyType", "char", "ValueType", "any");
            request = macd.ui.RefreshRequest("properties", label.Id, "Text");
            testCase.verifyFalse(request.affectsGeometry(document, registry, handles));
            grid = document.insertComponent(registry, "uigridlayout", document.RootComponentId);
            label.ParentId = grid.Id;
            figure = uifigure(Visible="off");
            cleanup = onCleanup(@() delete(figure));
            native = uigridlayout(figure, [1 1]);
            handles(char(grid.Id)) = native;
            native.RowHeight = {100}; native.ColumnWidth = {'1x'};
            testCase.verifyFalse(request.affectsGeometry(document, registry, handles));
            native.RowHeight = {'fit'};
            testCase.verifyTrue(request.affectsGeometry(document, registry, handles));
            testCase.verifyFalse(macd.ui.RefreshRequest("properties", label.Id, "FontColor").affectsGeometry(document, registry, handles));
            testCase.verifyTrue(macd.ui.RefreshRequest("properties", label.Id, "Layout.Row").affectsGeometry(document, registry, handles));
            testCase.verifyTrue(macd.ui.RefreshRequest("properties", grid.Id, "Padding").affectsGeometry(document, registry, handles));
            remove(handles, char(grid.Id));
            testCase.verifyTrue(request.affectsGeometry(document, registry, handles));
            clear cleanup
        end

        function followsAncestorFitAndCatalogOverrides(testCase)
            % followsAncestorFitAndCatalogOverrides Detect nested fit dependencies and avoid property-name rules.
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("NestedGeometryFixture", registry);
            outer = document.insertComponent(registry, "uigridlayout", document.RootComponentId);
            inner = document.insertComponent(registry, "uigridlayout", outer.Id);
            label = document.insertComponent(registry, "uilabel", inner.Id);
            figure = uifigure(Visible="off");
            cleanup = onCleanup(@() delete(figure));
            nativeOuter = uigridlayout(figure, [1 1]);
            nativeInner = uigridlayout(nativeOuter, [1 1]);
            nativeOuter.RowHeight = {'fit'}; nativeOuter.ColumnWidth = {100};
            nativeInner.RowHeight = {100}; nativeInner.ColumnWidth = {100};
            handles = containers.Map(cellstr([outer.Id, inner.Id]), {nativeOuter, nativeInner});
            request = macd.ui.RefreshRequest("properties", label.Id, "Text");
            testCase.verifyTrue(request.affectsGeometry(document, registry, handles));
            definition = registry.get("uilabel");
            properties = definition.Properties;
            index = find(string({properties.Path}) == "FontColor", 1);
            metadata = properties(index).Metadata;
            metadata.gridGeometryImpact = "required";
            properties(index) = macd.model.PropertyDefinition("FontColor", [], false, true, metadata);
            properties(end + 1) = macd.model.PropertyDefinition("Unusual", [], false, true, ...
                struct("gridGeometryImpact", "none", "absoluteGeometryImpact", false));
            registry.register(macd.model.ComponentDefinition("uilabel", definition.DeclaredType, ...
                definition.AllowedParentFactories, false, {}, properties));
            testCase.verifyTrue(macd.ui.RefreshRequest("properties", label.Id, "FontColor").affectsGeometry(document, registry, handles));
            testCase.verifyFalse(macd.ui.RefreshRequest("properties", label.Id, "Unusual").affectsGeometry(document, registry, handles));
            testCase.verifyTrue(macd.ui.RefreshRequest("properties", label.Id, "Missing").affectsGeometry(document, registry, handles));
            testCase.verifyTrue(macd.ui.RefreshRequest("structure").affectsGeometry(document, registry, handles));
            clear cleanup
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
