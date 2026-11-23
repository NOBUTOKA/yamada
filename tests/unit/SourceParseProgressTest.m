classdef (TestTags = {'ui', 'parser'}) SourceParseProgressTest < matlab.unittest.TestCase
    % SourceParseProgressTest Verify parser notifications and editor ownership.
    %   Loading notifications close on all exits and
    %   appear only in the editor registered for the parser's registry.
    properties (Access = private)
        StartedCount double = 0
    end
    methods (Test)
        % Guarantee: every parse closes its progress notification, including on diagnostics and errors, and registrations stay per editor.
        % Failure mode: an exception path leaves a modal notification open or one editor's registration is reused by another.
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
            testCase.verifyEqual(testCase.StartedCount, 2);
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
            % capture Count notifications while the synchronous parser is active.
            arguments (Input)
                obj (1, 1) SourceParseProgressTest
                dialog (1, 1) matlab.ui.dialog.ProgressDialog
            end
            obj.assertTrue(isvalid(dialog));
            obj.StartedCount = obj.StartedCount + 1;
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
