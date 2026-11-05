classdef (TestTags = {'preview', 'ui'}) TextPreviewReuseTest < matlab.unittest.TestCase
    % TextPreviewReuseTest Verify local text commits retain native rendering and fresh fit geometry.
    %   Independent full renders must agree after text grows and shrinks across
    %   absolute, single-grid, and nested-grid layouts.
    methods (Test)
        function localTextGrowthMatchesFreshRendering(testCase)
            % localTextGrowthMatchesFreshRendering Compare retained controls with complete native reconstruction.
            registry = yamada.model.ComponentRegistry.createDefault();
            for layout = ["absolute", "flat", "nested"]
                [document, label] = TextPreviewReuseTest.fixture(registry, layout);
                document.setProperty(label.Id, "Text", "Baseline", registry);
                document.validatePropertyCommit(registry);
                figure = uifigure(Visible="on", Position=[100 100 900 700]);
                cleanup = onCleanup(@() delete(figure));
                left = uipanel(figure, Position=[1 1 440 680]);
                right = uipanel(figure, Position=[451 1 440 680]);
                renderer = yamada.ui.PreviewRenderer(registry);
                referenceRenderer = yamada.ui.PreviewRenderer(registry);
                [handles, diagnostics] = renderer.render(document, left);
                testCase.assertEmpty(diagnostics);
                original = handles(char(label.Id));
                TextPreviewReuseTest.settle(original);
                initialHeight = original.Position(4);
                values = {["First line", "Second line", "Third line"], "Short again"};
                for index = 1:numel(values)
                    % The already validated owner is edited through the production model path.
                    document.setPropertyBatch(label.Id, ...
                        yamada.model.PropertyTransaction.singleChange("Text", values{index}), registry);
                    document.validatePropertyCommit(registry);
                    [applied, diagnostics, geometry] = renderer.synchronize(document, handles, ...
                        yamada.ui.RefreshRequest("properties", label.Id, "Text"));
                    testCase.verifyTrue(applied, layout);
                    testCase.verifyEmpty(diagnostics);
                    testCase.verifyEqual(geometry, layout ~= "absolute");
                    original = handles(char(label.Id));
                    reference = referenceRenderer.render(document, right);
                    TextPreviewReuseTest.settle(original);
                    TextPreviewReuseTest.settle(reference(char(label.Id)));
                    testCase.verifyEqual(reshape(string(original.Text), [], 1), ...
                        reshape(string(values{index}), [], 1));
                    testCase.verifyEqual(original.Position, reference(char(label.Id)).Position, "AbsTol", 1);
                    if layout ~= "absolute" && index == 1
                        testCase.verifyGreaterThan(original.Position(4), initialHeight);
                    end
                    if layout ~= "absolute" && index == 2
                        testCase.verifyEqual(original.Position(4), initialHeight, "AbsTol", 1);
                    end
                end
                clear cleanup
            end
        end
    end

    methods (Static, Access = private)
        function [document, label] = fixture(registry, layout)
            % fixture Parse one owned label under the requested fit-layout depth.
            arguments (Input)
                registry (1, 1) yamada.model.ComponentRegistry
                layout (1, 1) string
            end
            arguments (Output)
                document (1, 1) yamada.model.DocumentModel
                label (1, 1) yamada.model.ComponentRecord
            end
            document = yamada.model.NewAppFactory.createEmpty("TextGeometryFixture", registry);
            parent = document.RootComponentId;
            if layout == "nested"
                outer = document.insertComponent(registry, "uigridlayout", parent);
                outer.setProperty("RowHeight", {"1x"});
                outer.setProperty("ColumnWidth", {"1x"});
                parent = outer.Id;
            end
            if layout ~= "absolute"
                grid = document.insertComponent(registry, "uigridlayout", parent);
                grid.setProperty("RowHeight", {"fit", "1x"});
                grid.setProperty("ColumnWidth", {"1x"});
                parent = grid.Id;
            end
            label = document.insertComponent(registry, "uilabel", parent);
            label.setProperty("Text", "Original");
            name = label.Name;
            source = yamada.source.NewAppGenerator(registry).generate(document);
            document = yamada.source.AppSourceParser.parseText(source, registry);
            label = document.getComponentByName(name);
        end

        function settle(target)
            % settle Wait for several stable native geometry observations with a bounded deadline.
            arguments (Input)
                target (1, 1) matlab.ui.control.Label
            end
            started = tic;
            previous = double(target.Position);
            stable = 0;
            while toc(started) < 5
                drawnow; pause(0.04); drawnow;
                current = double(target.Position);
                if all(abs(current - previous) < 0.1)
                    stable = stable + 1;
                else
                    stable = 0;
                end
                if stable >= 4, return, end
                previous = current;
            end
            error("yamada:TextPreviewReuseTest:UnsettledGeometry", "Text layout did not settle.");
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
