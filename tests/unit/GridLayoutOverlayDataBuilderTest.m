classdef GridLayoutOverlayDataBuilderTest < matlab.unittest.TestCase
    % GridLayoutOverlayDataBuilderTest Verify public-geometry grid overlay payloads.

    methods (Test)
        function publishesFixedTrackBoundsAndImmediateChildren(testCase)
            % publishesFixedTrackBoundsAndImmediateChildren Match fixed tracks to realized child bounds.

            [document, handles, panel, grid, first, second, cleanup] = ...
                testCase.renderGrid([40 50], [60 70]);
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
            clear cleanup
        end

        function locksFitTrackGeometryUntilItCanBeProved(testCase)
            % locksFitTrackGeometryUntilItCanBeProved Avoid misleading boundary interactions.

            [document, handles, panel, grid, ~, second, cleanup] = ...
                testCase.renderGrid({'fit', '1x'}, {'1x', '1x'});
            builder = macd.ui.GridLayoutOverlayDataBuilder();
            data = builder.build(document, handles, panel, grid.Id, second.Id, 8);

            testCase.verifyTrue(data.editable);
            testCase.verifyFalse(data.geometryAvailable);
            testCase.verifyTrue(contains(data.readOnlyReason, "Fit track boundaries are locked"));
            testCase.verifyEmpty(data.rowBoundaries);
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
