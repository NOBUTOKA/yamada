classdef (TestTags = {'ui', 'parser'}) SourceParseProgressTest < matlab.unittest.TestCase
    % SourceParseProgressTest Verify parser notifications and editor ownership.
    %   Loading notifications must be indeterminate, close on all exits, and
    %   appear only in the editor registered for the parser's registry.
    properties (Access = private)
        Seen struct = struct("Title", {}, "Indeterminate", {}, "Cancelable", {})
    end
    methods (Test)
        function centralParserShowsAndClosesNotification(testCase)
            % centralParserShowsAndClosesNotification Cover valid and diagnostic-producing source loads.
            registry = yamada.model.ComponentRegistry.createDefault();
            parent = uifigure("Visible", "on", "Position", [100 100 320 200]); cleanup = onCleanup(@() delete(parent));
            display = yamada.source.SourceParseProgress(registry, parent);
            registrationCleanup = onCleanup(@() delete(display));
            listener = addlistener(display, "Started", @(~, ~) testCase.capture(display.Dialog)); %#ok<NASGU>
            root = fileparts(fileparts(mfilename("fullpath")));
            source = string(fileread(fullfile(root, "fixtures", "SmallPreviewFixtureApp.m")));
            yamada.source.AppSourceParser.parseText(source, registry);
            testCase.verifyEmpty(display.Dialog);
            [~, diagnostics] = yamada.source.AppSourceParser.parseText("invalid source", registry);
            testCase.verifyNotEmpty(diagnostics); testCase.verifyEmpty(display.Dialog);
            testCase.verifyNumElements(testCase.Seen, 2);
            testCase.verifyEqual(string({testCase.Seen.Title}), ["Loading", "Loading"]);
            testCase.verifyEqual(string({testCase.Seen.Indeterminate}), ["on", "on"]);
            testCase.verifyEqual(string({testCase.Seen.Cancelable}), ["off", "off"]);
        end

        function exceptionClosesNotificationAndRegistrationsAreIndependent(testCase)
            % exceptionClosesNotificationAndRegistrationsAreIndependent Release dialogs on errors without selecting another editor.
            first = yamada.model.ComponentRegistry.createDefault(); second = yamada.model.ComponentRegistry.createDefault();
            parent = uifigure("Visible", "on", "Position", [100 100 320 200]); cleanup = onCleanup(@() delete(parent));
            display = yamada.source.SourceParseProgress(first, parent);
            registrationCleanup = onCleanup(@() delete(display));
            testCase.verifyEmpty(yamada.source.SourceParseProgress.find(second));
            listener = addlistener(display, "Started", @(~, ~) delete(first)); %#ok<NASGU>
            root = fileparts(fileparts(mfilename("fullpath")));
            source = string(fileread(fullfile(root, "fixtures", "SmallPreviewFixtureApp.m")));
            thrown = false;
            try
                yamada.source.AppSourceParser.parseText(source, first);
            catch
                thrown = true;
            end
            testCase.verifyTrue(thrown); testCase.verifyEmpty(display.Dialog);
            delete(display);
            testCase.verifyEmpty(yamada.source.SourceParseProgress.find(second));
        end
    end
    methods (Access = private)
        function capture(obj, dialog)
            % capture Read notification state while the synchronous parser is active.
            arguments (Input)
                obj (1, 1) SourceParseProgressTest
                dialog (1, 1) matlab.ui.dialog.ProgressDialog
            end
            obj.Seen(end + 1) = struct("Title", string(dialog.Title), ...
                "Indeterminate", string(dialog.Indeterminate), "Cancelable", string(dialog.Cancelable));
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
