classdef (TestTags = {'fast', 'model'}) CallbackModelTest < matlab.unittest.TestCase
    % CallbackModelTest Verify callback command rejection and default handler naming.
    %   These tests inspect authoritative model snapshots independently of the UI.

    methods (Test)
        % Guarantee: invalid, stale, or unsafe callback requests fail before any mutation.
        % Failure mode: a request for a missing component or callback or a repeated handler name is applied, or a rejected request still changes history.
        function rejectsRepeatedAndInvalidRequestsWithoutChangingState(testCase)
            % rejectsRepeatedAndInvalidRequestsWithoutChangingState Reject stale and unknown action targets before mutation.
            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("CallbackApp", registry);
            button = document.insertComponent(registry, "uibutton", document.RootComponentId);
            document.applyCallbackAction(button.Id, "ButtonPushedFcn", "New", registry, yamada.source.CallbackMethodTargets.defaultName(document, button.Id, "ButtonPushedFcn", registry));
            before = document.CallbackEdits;
            history = document.History;
            handler = document.History{end}.After(1).HandlerName;
            testCase.verifyError(@() document.applyCallbackAction(button.Id, "ButtonPushedFcn", "New", registry, handler), ...
                "yamada:DocumentModel:CallbackNameCollision");
            testCase.verifyError(@() document.applyCallbackAction("missing", "ButtonPushedFcn", "Disconnect", registry), ...
                "yamada:DocumentModel:UnsafeCallbackEdit");
            testCase.verifyError(@() document.applyCallbackAction(button.Id, "UnknownFcn", "New", registry, yamada.source.CallbackMethodTargets.defaultName(document, button.Id, "UnknownFcn", registry)), ...
                "yamada:DocumentModel:UnsafeCallbackEdit");
            testCase.verifyEqual(document.CallbackEdits, before);
            testCase.verifyEqual(document.History, history);
        end

        function generatedNamesAvoidSourceAndPendingCollisions(testCase)
            % generatedNamesAvoidSourceAndPendingCollisions Generate distinct valid names for multiple callback additions.
            % Guarantee: default handler names offered for New are valid and unique against source members and the class name.
            % Failure mode: a default name equals the class name or an existing handler, so accepting the prompt generates invalid source.
            registry = yamada.model.ComponentRegistry.createDefault();
            document = yamada.model.NewAppFactory.createEmpty("UIFigureSizeChanged", registry);
            root = document.RootComponentId;
            document.applyCallbackAction(root, "SizeChangedFcn", "New", registry, yamada.source.CallbackMethodTargets.defaultName(document, root, "SizeChangedFcn", registry));
            first = document.History{end}.After(1);
            testCase.verifyNotEqual(first.HandlerName, document.ClassName);
            testCase.verifyTrue(isvarname(first.HandlerName));
            document.applyCallbackAction(root, "CloseRequestFcn", "New", registry, yamada.source.CallbackMethodTargets.defaultName(document, root, "CloseRequestFcn", registry));
            testCase.verifyNotEqual(document.History{end}.After(1).HandlerName, first.HandlerName);
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
