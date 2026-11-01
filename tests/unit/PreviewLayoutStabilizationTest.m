classdef (TestTags = {'preview', 'ui'}) PreviewLayoutStabilizationTest < matlab.unittest.TestCase
    % PreviewLayoutStabilizationTest Verify request isolation and real R2024a fit-layout completion.
    properties (TestParameter)
        % Widget - Native asynchronous and nested-container geometry under test.
        Widget = {"table", "axes", "html", "tabs"}
    end
    methods (Test)
        function matchingReplyCompletesOnlyOnce(testCase)
            % matchingReplyCompletesOnlyOnce Reject stale tokens and retain the first matching response.
            reply = macd.ui.LayoutStabilizeReply("current");
            reply.accept(struct("token", "obsolete"));
            testCase.verifyFalse(reply.Done);
            reply.accept(struct("token", "current", "value", 1));
            reply.accept(struct("token", "current", "value", 2));
            reply.expire();
            testCase.verifyTrue(reply.Done);
            testCase.verifyEqual(reply.Data.value, 1);
        end

        function expiredReplyCannotBeReplaced(testCase)
            % expiredReplyCannotBeReplaced Ignore a native response that arrives after request expiry.
            reply = macd.ui.LayoutStabilizeReply("expired");
            reply.expire();
            expected = reply.Data;
            reply.accept(struct("token", "expired", "value", 1));
            testCase.verifyTrue(reply.Done);
            testCase.verifyEqual(reply.Data, expected);
            testCase.verifyTrue(isfield(expected, "error"));
        end

        function mixedWidgetLayoutsSettleBeforeMeasurement(testCase, Widget)
            % mixedWidgetLayoutsSettleBeforeMeasurement Check fit content, resize, and native asynchronous widgets.
            figure = uifigure("Visible", "on", "Position", [100 100 500 400]);
            cleanup = onCleanup(@() delete(figure));
            canvas = uipanel(figure, "BorderType", "none", "AutoResizeChildren", "off", ...
                "Position", [1 1 500 400]);
            grid = uigridlayout(canvas, [2 1], "RowHeight", {"fit", "1x"});
            label = uilabel(grid, "Text", "Initial");
            switch Widget
                case "table"
                    target = uitable(grid, "Data", ones(2, 3));
                case "axes"
                    target = uiaxes(grid);
                case "html"
                    target = uihtml(grid);
                case "tabs"
                    target = uitabgroup(grid);
                    uitab(target, "Title", "First");
                    tab = uitab(target, "Title", "Second");
                    panel = uipanel(tab, "Units", "normalized", "Position", [0.1 0.1 0.8 0.8]);
                    nested = uilabel(panel, "Position", [10 10 160 40]);
            end
            drawnow;
            canvas.Position(3:4) = [600 500];
            label.Text = ["A larger first line"; "Second line"];
            label.FontSize = 26;
            if Widget == "table", target.Data = ones(12, 5); end
            if Widget == "axes", target.FontSize = 24; ylabel(target, "Changed axis label"); end
            if Widget == "tabs", target.SelectedTab = tab; nested.FontSize = 24; end
            drawnow;
            macd.ui.waitForPreviewLayout(figure, grid);
            drawnow;
            immediate = [label.Position target.Position];
            if Widget == "tabs", immediate = [immediate getpixelposition(nested, true)]; end
            if isprop(target, "OuterPosition"), immediate = [immediate target.OuterPosition]; end
            pause(0.3); drawnow;
            later = [label.Position target.Position];
            if Widget == "tabs", later = [later getpixelposition(nested, true)]; end
            if isprop(target, "OuterPosition"), later = [later target.OuterPosition]; end
            testCase.verifyEqual(later, immediate, "AbsTol", 1e-8);
        end

        function fitLayoutCompletesWithoutImageCaptureOrPolling(testCase)
            % fitLayoutCompletesWithoutImageCaptureOrPolling Compare acknowledged geometry with a later independent read.
            figure = uifigure("Visible", "on", "Position", [100 100 500 400]);
            cleanup = onCleanup(@() delete(figure));
            grid = uigridlayout(figure, [2 1], "RowHeight", {"fit", "1x"});
            label = uilabel(grid, "Text", "Initial");
            uieditfield(grid, "numeric");
            drawnow;
            label.FontSize = 28;
            label.Text = ["First line"; "Second line"];
            drawnow;
            before = timerfindall();
            response = macd.ui.waitForPreviewLayout(figure, grid);
            drawnow;
            immediate = label.Position;
            pause(0.2); drawnow;
            testCase.verifyEqual(label.Position, immediate, "AbsTol", 1e-8);
            testCase.verifyNotEmpty(string(response.rootId));
            testCase.verifyEqual(numel(timerfindall()), numel(before));
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
