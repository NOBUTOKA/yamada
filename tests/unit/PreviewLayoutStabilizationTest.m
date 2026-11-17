classdef (TestTags = {'preview', 'ui'}) PreviewLayoutStabilizationTest < matlab.unittest.TestCase
    % PreviewLayoutStabilizationTest Verify request isolation and real fit-layout completion.
    %   Tests tagged desktop also run in the desktop profile, which a desktop
    %   MATLAB session starts to exercise the DivFigure route from R2025a.
    %   Tests that need that route assume a desktop session and verify that
    %   the wait reports it.
    properties (TestParameter)
        % Widget - Native asynchronous and nested-container geometry under test.
        Widget = {"table", "axes", "html", "tabs"}
        % WindowStyle - Desktop placement of the figure that renders the Preview.
        WindowStyle = {"normal", "docked"}
    end
    methods (Test)
        function matchingReplyCompletesOnlyOnce(testCase)
            % matchingReplyCompletesOnlyOnce Reject stale tokens and retain the first matching response.
            reply = yamada.ui.LayoutStabilizeReply("current");
            reply.accept(struct("token", "obsolete"));
            testCase.verifyFalse(reply.Done);
            reply.accept(struct("token", "current", "value", 1));
            reply.accept(struct("token", "current", "value", 2));
            reply.expire();
            testCase.verifyTrue(reply.Done);
            testCase.verifyFalse(reply.TimedOut);
            testCase.verifyEqual(reply.Data.value, 1);
        end

        function expiredReplyCannotBeReplaced(testCase)
            % expiredReplyCannotBeReplaced Ignore a native response that arrives after request expiry.
            reply = yamada.ui.LayoutStabilizeReply("expired");
            reply.expire();
            expected = reply.Data;
            reply.accept(struct("token", "expired", "value", 1));
            testCase.verifyTrue(reply.Done);
            testCase.verifyTrue(reply.TimedOut);
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
            yamada.ui.waitForPreviewLayout(figure, grid);
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
    end

    methods (Test, TestTags = {'desktop'})
        function repeatedWaitObservesResizeBurst(testCase)
            % repeatedWaitObservesResizeBurst Await a throttled trailing relayout in a later wait on one figure.
            %   A resize inside the Grid Layout throttle window defers the
            %   relayout to the trailing call, which only the quiet period
            %   observes; this fails when no container controller is hooked.
            figure = uifigure("Visible", "on", "Position", [100 100 500 400]);
            cleanup = onCleanup(@() delete(figure));
            canvas = uipanel(figure, "BorderType", "none", "AutoResizeChildren", "off", ...
                "Position", [1 1 500 400]);
            grid = uigridlayout(canvas, [2 1], "RowHeight", {"fit", "1x"});
            label = uilabel(grid, "Text", "Initial");
            target = uitabgroup(grid);
            uitab(target, "Title", "First");
            drawnow;
            first = yamada.ui.waitForPreviewLayout(figure, grid);
            testCase.verifyGreaterThan(first.hooked, 0);
            pause(0.5); drawnow;
            % The first resize opens the throttle window and the second lands inside it.
            canvas.Position(3:4) = [550 450];
            drawnow; pause(0.05);
            canvas.Position(3:4) = [600 500];
            label.FontSize = 26;
            drawnow;
            second = yamada.ui.waitForPreviewLayout(figure, grid);
            drawnow;
            immediate = [label.Position target.Position];
            pause(0.3); drawnow;
            testCase.verifyEqual([label.Position target.Position], immediate, "AbsTol", 1e-8);
            testCase.verifyGreaterThan(second.watched, 0);
            testCase.verifyTrue(second.quieted);
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
            response = yamada.ui.waitForPreviewLayout(figure, grid);
            drawnow;
            immediate = label.Position;
            pause(0.2); drawnow;
            testCase.verifyEqual(label.Position, immediate, "AbsTol", 1e-8);
            testCase.verifyTrue(response.framed);
            testCase.verifyEqual(numel(timerfindall()), numel(before));
        end

        function desktopRouteSettlesFigureAmongSameTitles(testCase, WindowStyle)
            % desktopRouteSettlesFigureAmongSameTitles Settle a docked or undocked DivFigure beside a same-titled one.
            %   The receiver locates the page by the figure channel, not by
            %   the title, so a decoy with the same Name must not be chosen.
            assumeDesktopRoute(testCase);
            decoy = uifigure("Visible", "on", "Name", "Yamada layout route", "Position", [80 80 300 200]);
            decoyCleanup = onCleanup(@() delete(decoy));
            uilabel(uigridlayout(decoy, [1 1]), "Text", "Decoy");
            figure = uifigure("Visible", "on", "Name", "Yamada layout route", "WindowStyle", WindowStyle);
            cleanup = onCleanup(@() delete(figure));
            if WindowStyle == "normal", figure.Position = [100 100 500 400]; end
            grid = uigridlayout(figure, [2 1], "RowHeight", {"fit", "1x"});
            label = uilabel(grid, "Text", "Initial");
            target = uitabgroup(grid);
            uitab(target, "Title", "First");
            drawnow;
            yamada.ui.waitForPreviewLayout(figure, grid);
            label.Text = ["A larger first line"; "Second line"];
            label.FontSize = 26;
            drawnow;
            response = yamada.ui.waitForPreviewLayout(figure, grid);
            drawnow;
            immediate = [label.Position target.Position];
            pause(0.3); drawnow;
            testCase.verifyEqual([label.Position target.Position], immediate, "AbsTol", 1e-8);
            testCase.verifyEqual(response.route, "desktop");
            testCase.verifyGreaterThan(response.watched, 0);
            testCase.verifyTrue(response.quieted);
            testCase.verifyTrue(response.framed);
            % The same-titled figure is settled in its own page as well.
            decoyResponse = yamada.ui.waitForPreviewLayout(decoy, decoy.Children(1));
            testCase.verifyGreaterThan(decoyResponse.watched, 0);
        end

        function desktopReceiverInstallsOncePerSession(testCase)
            % desktopReceiverInstallsOncePerSession Send later desktop requests without a new panel.
            assumeDesktopRoute(testCase);
            figure = uifigure("Visible", "on", "Position", [100 100 400 300]);
            cleanup = onCleanup(@() delete(figure));
            grid = uigridlayout(figure, [1 1]);
            uilabel(grid, "Text", "Label");
            drawnow;
            first = yamada.ui.waitForPreviewLayout(figure, grid);
            second = yamada.ui.waitForPreviewLayout(figure, grid);
            testCase.verifyEqual([first.route second.route], ["desktop" "desktop"]);
            testCase.verifyFalse(second.installed);
        end
    end
end

function assumeDesktopRoute(testCase)
% assumeDesktopRoute Skip unless uifigures in this session use the desktop DivFigure route.
arguments (Input)
    testCase (1, 1) matlab.unittest.TestCase
end
testCase.assumeFalse(batchStartupOptionUsed, "matlab -batch hosts uifigures in CEF windows.");
testCase.assumeFalse(isMATLABReleaseOlderThan("R2025a"), "The desktop hosts uifigures in CEF windows before R2025a.");
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
