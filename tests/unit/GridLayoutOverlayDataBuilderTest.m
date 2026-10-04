classdef (TestTags = {'gridOverlay', 'preview', 'ui'}) GridLayoutOverlayDataBuilderTest < matlab.unittest.TestCase
    % GridLayoutOverlayDataBuilderTest Verify public-geometry grid overlay payloads.

    methods (Test, TestTags = {'fast'})
        function publishesFixedTrackBoundsAndImmediateChildren(testCase)
            % publishesFixedTrackBoundsAndImmediateChildren Match fixed tracks to realized child bounds.

            [document, handles, panel, grid, first, second, cleanup] = ...
                testCase.renderGrid([40 50], [60 70]);
            testCase.addTeardown(@() delete(cleanup));
            builder = macd.ui.GridLayoutOverlayDataBuilder();
            data = builder.build(document, handles, panel, grid.Id, second.Id, 7);

            firstIndex = find(string({data.children.id}) == first.Id, 1);
            secondIndex = find(string({data.children.id}) == second.Id, 1);
            testCase.verifyEqual(data.revision, 7);
            testCase.verifyEqual(string(data.activeGridId), grid.Id);
            testCase.verifyTrue(data.editable);
            testCase.verifyEqual(string({data.rowTracks.kind}), ["fixed", "fixed"]);
            testCase.verifyEqual(string({data.columnTracks.kind}), ["fixed", "fixed"]);
            testCase.verifyEqual(string(data.children(firstIndex).placementMode), "explicit");
            testCase.verifyTrue(data.children(secondIndex).selected);
            testCase.verifyEqual(data.children(secondIndex).rowStart, 2);
            testCase.verifyEqual(data.children(secondIndex).columnStart, 2);
            testCase.verifyEqual(data.children(firstIndex).bounds([2 4]), ...
                data.rowTracks(1).bounds([2 4]), "AbsTol", 1);
            testCase.verifyEqual(data.children(secondIndex).bounds([1 3]), ...
                data.columnTracks(2).bounds([1 3]), "AbsTol", 1);
        end
    end

    methods (Test)
        function alignsNestedFitTracksInAnOffsetParentCell(testCase)
            % alignsNestedFitTracksInAnOffsetParentCell Avoid adding nested grid coordinates twice.

            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("NestedFitGridApp", registry);
            outer = document.insertComponent(registry, "uigridlayout", document.RootComponentId);
            document.setProperty(outer.Id, "RowHeight", {180, "1x"});
            document.setProperty(outer.Id, "ColumnWidth", {230, "1x"});
            document.setProperty(outer.Id, "Padding", [13 17 19 23]);
            inner = document.insertComponent(registry, "uigridlayout", outer.Id);
            document.setProperty(inner.Id, "Layout.Row", 2);
            document.setProperty(inner.Id, "Layout.Column", 2);
            document.setProperty(inner.Id, "RowHeight", {"fit", "1x"});
            document.setProperty(inner.Id, "ColumnWidth", {"fit", "1x"});
            document.setProperty(inner.Id, "Padding", [5 7 11 13]);
            label = document.insertComponent(registry, "uilabel", inner.Id);
            document.setProperty(label.Id, "Text", "Nested fit label");
            button = document.insertComponent(registry, "uibutton", inner.Id);
            document.setProperty(button.Id, "Layout.Row", 2);
            document.setProperty(button.Id, "Layout.Column", 2);

            figure = uifigure("Visible", "on", "Position", [100 100 800 600]);
            cleanup = onCleanup(@() GridLayoutOverlayDataBuilderTest.deleteIfValid(figure));
            panel = uipanel(figure, "Position", [21 31 760 560]);
            renderer = macd.ui.PreviewRenderer(registry);
            [handles, diagnostics] = renderer.render(document, panel);
            testCase.verifyEmpty(diagnostics);
            GridLayoutOverlayDataBuilderTest.waitForLayout(handles(char(inner.Id)));
            builder = macd.ui.GridLayoutOverlayDataBuilder();
            data = builder.build( ...
                document, handles, panel, inner.Id, label.Id, 15);

            testCase.assertTrue(data.geometryAvailable, data.readOnlyReason);
            % Compare canvas boundaries with independent realized component rectangles.
            labelBounds = double(getpixelposition(handles(char(label.Id)), true));
            panelBounds = double(getpixelposition(panel, true));
            labelBounds(1:2) = labelBounds(1:2) - panelBounds(1:2);
            testCase.verifyEqual(data.columnTracks(1).bounds([1 3]), ...
                labelBounds([1 3]), "AbsTol", 1);
            testCase.verifyEqual(data.rowTracks(1).bounds([2 4]), ...
                labelBounds([2 4]), "AbsTol", 1);
            testCase.verifyEqual(data.innerBounds(1), labelBounds(1), "AbsTol", 1);
            testCase.verifyEqual(data.innerBounds(2) + data.innerBounds(4), ...
                labelBounds(2) + labelBounds(4), "AbsTol", 1);
            clear cleanup
        end

        function reconstructsFitTrackGeometryFromRealizedChildren(testCase)
            % reconstructsFitTrackGeometryFromRealizedChildren Align fit tracks with public child bounds.

            [document, handles, panel, grid, ~, second, cleanup] = ...
                testCase.renderGrid({'fit', '1x'}, {'1x', '1x'});
            testCase.addTeardown(@() delete(cleanup));
            builder = macd.ui.GridLayoutOverlayDataBuilder();
            data = builder.build(document, handles, panel, grid.Id, second.Id, 8);

            testCase.verifyTrue(data.editable);
            testCase.verifyTrue(data.geometryAvailable, data.readOnlyReason);
            testCase.verifyEqual(data.readOnlyReason, "");
            secondIndex = find(string({data.children.id}) == second.Id, 1);
            testCase.verifyEqual(data.children(secondIndex).bounds([2 4]), ...
                data.rowTracks(2).bounds([2 4]), "AbsTol", 1);
            testCase.verifyEqual(data.rowTracks(1).bounds(2) + ...
                data.rowTracks(1).bounds(4), data.innerBounds(2) + data.innerBounds(4), ...
                "AbsTol", 1);
        end

        function reconstructsFlexibleTrackRatiosWithPaddingAndSpacing(testCase)
            % reconstructsFlexibleTrackRatiosWithPaddingAndSpacing Preserve measured flexible proportions.

            [document, handles, panel, grid, ~, second, cleanup] = ...
                testCase.renderGrid({40, "1x"}, {"1x", "2x"});
            testCase.addTeardown(@() delete(cleanup));
            builder = macd.ui.GridLayoutOverlayDataBuilder();
            data = builder.build(document, handles, panel, grid.Id, second.Id, 12);

            testCase.verifyTrue(data.geometryAvailable, data.readOnlyReason);
            testCase.verifyEqual(string({data.columnTracks.kind}), ["flexible", "flexible"]);
            testCase.verifyEqual(data.columnTracks(2).bounds(3) / ...
                data.columnTracks(1).bounds(3), 2, "AbsTol", 0.02);
            testCase.verifyEqual(data.columnTracks(1).bounds(1), data.innerBounds(1), ...
                "AbsTol", 1);
        end

        function publishesSpanningChildAgainstMeasuredTrackBounds(testCase)
            % publishesSpanningChildAgainstMeasuredTrackBounds Preserve an explicit span without size inference.

            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("SpanningGridOverlayApp", registry);
            grid = document.insertComponent(registry, "uigridlayout", document.RootComponentId);
            document.setProperty(grid.Id, "RowHeight", {40, "1x"});
            document.setProperty(grid.Id, "ColumnWidth", {60, "1x"});
            document.setProperty(grid.Id, "RowSpacing", 8);
            document.setProperty(grid.Id, "ColumnSpacing", 9);
            document.setProperty(grid.Id, "Padding", [5 6 7 8]);
            child = document.insertComponent(registry, "uilabel", grid.Id);
            document.setProperty(child.Id, "Layout.Row", [1 2]);
            document.setProperty(child.Id, "Layout.Column", [1 2]);

            figure = uifigure("Visible", "on", "Position", [100 100 800 600]);
            cleanup = onCleanup(@() GridLayoutOverlayDataBuilderTest.deleteIfValid(figure));
            panel = uipanel(figure, "Position", [1 1 760 560]);
            renderer = macd.ui.PreviewRenderer(registry);
            [handles, diagnostics] = renderer.render(document, panel);
            testCase.verifyEmpty(diagnostics);
            GridLayoutOverlayDataBuilderTest.waitForLayout(handles(char(grid.Id)));

            builder = macd.ui.GridLayoutOverlayDataBuilder();
            data = builder.build(document, handles, panel, grid.Id, child.Id, 14);

            testCase.verifyTrue(data.geometryAvailable, data.readOnlyReason);
            testCase.verifyEqual(data.children(1).rowStart, 1);
            testCase.verifyEqual(data.children(1).rowEnd, 2);
            testCase.verifyEqual(data.children(1).columnStart, 1);
            testCase.verifyEqual(data.children(1).columnEnd, 2);
            testCase.verifyEqual(data.children(1).bounds(1), data.innerBounds(1), "AbsTol", 1);
            testCase.verifyEqual(data.children(1).bounds(2), data.innerBounds(2), "AbsTol", 1);
            clear cleanup
        end

        function reconstructsParsedCalculatorFitTracks(testCase)
            % reconstructsParsedCalculatorFitTracks Align parsed fit tracks with Safe Preview cells.

            testPath = mfilename("fullpath");
            projectRoot = fileparts(fileparts(fileparts(testPath)));
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.source.AppSourceParser.parseFile(fullfile(projectRoot, ...
                "tests", "fixtures", "SimpleCalculatorApp.m"), registry);
            grid = document.getComponentByName("GridLayout");
            figure = uifigure("Visible", "on", "Position", [100 100 800 600]);
            cleanup = onCleanup(@() GridLayoutOverlayDataBuilderTest.deleteIfValid(figure));
            panel = uipanel(figure, "Position", [1 1 760 560]);
            renderer = macd.ui.PreviewRenderer(registry);
            [handles, diagnostics] = renderer.render(document, panel);
            testCase.verifyEmpty(diagnostics);
            GridLayoutOverlayDataBuilderTest.waitForLayout(handles(char(grid.Id)));

            builder = macd.ui.GridLayoutOverlayDataBuilder();
            data = builder.build(document, handles, panel, grid.Id, grid.Id, 9);
            testCase.verifyTrue(data.geometryAvailable, data.readOnlyReason);
            testCase.verifyEqual(numel(data.rowTracks), 5);
            testCase.verifyEqual(numel(data.columnTracks), 2);
            testCase.verifyEqual(data.rowTracks(1).bounds(2) + ...
                data.rowTracks(1).bounds(4), data.innerBounds(2) + data.innerBounds(4), ...
                "AbsTol", 1);
            testCase.verifyEqual(data.columnTracks(1).bounds(1), data.innerBounds(1), ...
                "AbsTol", 1);
            testCase.verifyEqual(data.columnTracks(end).bounds(1) + ...
                data.columnTracks(end).bounds(3), data.innerBounds(1) + data.innerBounds(3), ...
                "AbsTol", 1);
            clear cleanup
        end

        function reconstructsParsedControlGalleryFitTracks(testCase)
            % reconstructsParsedControlGalleryFitTracks Include decorated control bounds in fit rows.

            testPath = mfilename("fullpath");
            projectRoot = fileparts(fileparts(fileparts(testPath)));
            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.source.AppSourceParser.parseFile(fullfile(projectRoot, ...
                "tests", "fixtures", "ControlGalleryApp.m"), registry);
            grid = document.getComponentByName("FormGrid");
            selected = document.getComponentByName("DueDatePicker");
            figure = uifigure("Visible", "on", "Position", [100 100 800 600]);
            cleanup = onCleanup(@() GridLayoutOverlayDataBuilderTest.deleteIfValid(figure));
            panel = uipanel(figure, "Position", [1 1 760 560]);
            renderer = macd.ui.PreviewRenderer(registry);
            [handles, diagnostics] = renderer.render(document, panel);
            testCase.verifyEmpty(diagnostics);
            GridLayoutOverlayDataBuilderTest.waitForLayout(handles(char(grid.Id)));

            builder = macd.ui.GridLayoutOverlayDataBuilder();
            data = builder.build(document, handles, panel, grid.Id, selected.Id, 10);

            testCase.verifyTrue(data.geometryAvailable, data.readOnlyReason);
            testCase.verifyTrue(data.editable, data.readOnlyReason);
            testCase.verifyEqual(numel(data.rowTracks), 8);
            testCase.verifyEqual(string({data.rowTracks.kind}), repmat("fit", 1, 8));
            slider = document.getComponentByName("IntensitySlider");
            sliderPreview = handles(char(slider.Id));
            testCase.verifyGreaterThan(data.rowTracks(4).bounds(4), ...
                double(sliderPreview.Position(4)) + 20);
            testCase.verifyEqual(data.rowTracks(4).bounds(4), ...
                double(sliderPreview.OuterPosition(4)), "AbsTol", 1);
            for row = [6 7]
                rowChildren = data.children([data.children.rowStart] == row & ...
                    [data.children.rowEnd] == row);
                lower = min(arrayfun(@(child) child.bounds(2), rowChildren));
                upper = max(arrayfun(@(child) child.bounds(2) + child.bounds(4), rowChildren));
                testCase.verifyEqual(data.rowTracks(row).bounds(4), upper - lower, "AbsTol", 1);
            end
            clear cleanup
        end

        function publishesCollapsedEmptyFitTrack(testCase)
            % publishesCollapsedEmptyFitTrack Keep an explicitly empty fit row addressable at zero height.

            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("CollapsedFitGridApp", registry);
            grid = document.insertComponent(registry, "uigridlayout", document.RootComponentId);
            document.setProperty(grid.Id, "RowHeight", {"fit", "1x"});
            document.setProperty(grid.Id, "ColumnWidth", {"1x"});
            child = document.insertComponent(registry, "uilabel", grid.Id);
            document.setProperty(child.Id, "Layout.Row", 2);
            document.setProperty(child.Id, "Layout.Column", 1);

            figure = uifigure("Visible", "on", "Position", [100 100 800 600]);
            cleanup = onCleanup(@() GridLayoutOverlayDataBuilderTest.deleteIfValid(figure));
            panel = uipanel(figure, "Position", [1 1 760 560]);
            renderer = macd.ui.PreviewRenderer(registry);
            [handles, diagnostics] = renderer.render(document, panel);
            testCase.verifyEmpty(diagnostics);
            GridLayoutOverlayDataBuilderTest.waitForLayout(handles(char(grid.Id)));

            builder = macd.ui.GridLayoutOverlayDataBuilder();
            data = builder.build(document, handles, panel, grid.Id, child.Id, 11);

            testCase.verifyTrue(data.geometryAvailable, data.readOnlyReason);
            testCase.verifyEqual(data.rowTracks(1).bounds(4), 0, "AbsTol", 1);
            testCase.verifyEqual(data.rowTracks(1).bounds(2), ...
                data.innerBounds(2) + data.innerBounds(4), "AbsTol", 1);
            changes = macd.model.GridChildPlacementPlanner.move( ...
                document, grid.Id, child.Id, 1, 1, 2, 1);
            document.applyGridLayoutEdit(grid.Id, changes);
            testCase.verifyEqual(child.getProperty("Layout.Row").LiteralValue, 1);
            clear cleanup
        end

        function publishesAdjacentCollapsedFitTracks(testCase)
            % publishesAdjacentCollapsedFitTracks Keep every adjacent empty fit track addressable.

            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("AdjacentCollapsedFitGridApp", registry);
            grid = document.insertComponent(registry, "uigridlayout", document.RootComponentId);
            document.setProperty(grid.Id, "RowHeight", {"fit", "fit", "1x"});
            document.setProperty(grid.Id, "ColumnWidth", {"fit", "fit", "1x"});
            child = document.insertComponent(registry, "uilabel", grid.Id);
            document.setProperty(child.Id, "Layout.Row", 3);
            document.setProperty(child.Id, "Layout.Column", 3);

            figure = uifigure("Visible", "on", "Position", [100 100 800 600]);
            cleanup = onCleanup(@() GridLayoutOverlayDataBuilderTest.deleteIfValid(figure));
            panel = uipanel(figure, "Position", [1 1 760 560]);
            renderer = macd.ui.PreviewRenderer(registry);
            [handles, diagnostics] = renderer.render(document, panel);
            testCase.verifyEmpty(diagnostics);
            GridLayoutOverlayDataBuilderTest.waitForLayout(handles(char(grid.Id)));

            builder = macd.ui.GridLayoutOverlayDataBuilder();
            data = builder.build(document, handles, panel, grid.Id, child.Id, 13);

            testCase.verifyTrue(data.geometryAvailable, data.readOnlyReason);
            testCase.verifyEqual(data.rowTracks(1).bounds(4), 0, "AbsTol", 1);
            testCase.verifyEqual(data.rowTracks(2).bounds(4), 0, "AbsTol", 1);
            testCase.verifyEqual(data.columnTracks(1).bounds(3), 0, "AbsTol", 1);
            testCase.verifyEqual(data.columnTracks(2).bounds(3), 0, "AbsTol", 1);
            changes = macd.model.GridChildPlacementPlanner.move( ...
                document, grid.Id, child.Id, 1, 1, 3, 3);
            document.applyGridLayoutEdit(grid.Id, changes);
            testCase.verifyEqual(child.getProperty("Layout.Row").LiteralValue, 1);
            testCase.verifyEqual(child.getProperty("Layout.Column").LiteralValue, 1);
            clear cleanup
        end
    end

    methods (Access = private)
        function [document, handles, panel, grid, first, second, cleanup] = ...
                renderGrid(testCase, rowHeight, columnWidth)
            % renderGrid Render one stable safe-preview grid with two immediate children.

            registry = macd.model.ComponentRegistry.createDefault();
            document = macd.model.NewAppFactory.createEmpty("GridOverlayApp", registry);
            grid = document.insertComponent(registry, "uigridlayout", document.RootComponentId);
            document.setProperty(grid.Id, "RowHeight", rowHeight);
            document.setProperty(grid.Id, "ColumnWidth", columnWidth);
            document.setProperty(grid.Id, "RowSpacing", 8);
            document.setProperty(grid.Id, "ColumnSpacing", 9);
            document.setProperty(grid.Id, "Padding", [5 6 7 8]);
            first = document.insertComponent(registry, "uilabel", grid.Id);
            second = document.insertComponent(registry, "uilabel", grid.Id);
            document.setProperty(second.Id, "Layout.Row", 2);
            document.setProperty(second.Id, "Layout.Column", 2);

            figure = uifigure("Visible", "on", "Position", [100 100 800 600]);
            cleanup = onCleanup(@() GridLayoutOverlayDataBuilderTest.deleteIfValid(figure));
            panel = uipanel(figure, "Position", [1 1 760 560]);
            renderer = macd.ui.PreviewRenderer(registry);
            [handles, diagnostics] = renderer.render(document, panel);
            testCase.verifyEmpty(diagnostics);
            GridLayoutOverlayDataBuilderTest.waitForLayout(handles(char(grid.Id)));
        end
    end

    methods (Static, Access = private)
        function waitForLayout(grid)
            % waitForLayout Wait for public GridLayout geometry to stabilize in the test figure.

            prior = zeros(1, 4);
            stableCount = 0;
            for index = 1:40
                drawnow;
                pause(0.05);
                current = double(grid.OuterPosition);
                if all(current(3:4) > 100) && isequal(current, prior)
                    stableCount = stableCount + 1;
                else
                    stableCount = 0;
                end
                if stableCount >= 2
                    return
                end
                prior = current;
            end
            error("macd:GridLayoutOverlayDataBuilderTest:UnstableLayout", ...
                "GridLayout geometry did not stabilize in the test figure.");
        end

        function deleteIfValid(value)
            % deleteIfValid Delete the editor-owned test figure when it remains valid.
            arguments (Input)
                value
            end

            if isvalid(value)
                delete(value);
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
