classdef SourceParseProgress < handle
    % SourceParseProgress Associate whole-source parsing with its editor window.
    %   Registrations are owned and released by editor instances. Standalone
    %   model/parser callers create no UI. The parser owns dialog creation.

    properties (SetAccess = private)
        % Parent - Editor figure that owns the current parsing notification.
        Parent matlab.ui.Figure
        % Dialog - Active whole-source parsing dialog, empty outside parsing.
        Dialog matlab.ui.dialog.ProgressDialog = matlab.ui.dialog.ProgressDialog.empty
    end
    properties (Access = private)
        Registry yamada.model.ComponentRegistry
    end
    events
        % Started - A whole-source parse has opened its visible notification.
        Started
        % Finished - The notification has closed after success or failure.
        Finished
    end
    methods
        function obj = SourceParseProgress(registry, parent)
            % SourceParseProgress Register the editor parent for one capability registry.
            arguments (Input)
                registry (1, 1) yamada.model.ComponentRegistry
                parent (1, 1) matlab.ui.Figure
            end
            obj.Registry = registry; obj.Parent = parent;
            yamada.source.SourceParseProgress.registrations("add", obj);
        end

        function delete(obj)
            % delete Release the notification and registration without closing the editor.
            obj.finish(obj.Dialog);
            yamada.source.SourceParseProgress.registrations("remove", obj);
        end

        function finish(obj, dialog)
            % finish Close only the matching parser-owned notification, including error cleanup.
            arguments (Input)
                obj (1, 1) yamada.source.SourceParseProgress
                dialog matlab.ui.dialog.ProgressDialog
            end
            if isempty(dialog), return, end
            if ~isempty(obj.Dialog) && isequal(obj.Dialog, dialog)
                obj.Dialog = matlab.ui.dialog.ProgressDialog.empty;
                if isvalid(dialog), close(dialog); end
                notify(obj, "Finished");
            end
        end
    end
    methods (Access = ?yamada.source.AppSourceParser)
        function start(obj, dialog)
            % start Publish the central parser notification before yielding to native rendering.
            arguments (Input)
                obj (1, 1) yamada.source.SourceParseProgress
                dialog (1, 1) matlab.ui.dialog.ProgressDialog
            end
            obj.Dialog = dialog; notify(obj, "Started");
        end
    end
    methods (Static)
        function registration = find(registry)
            % find Resolve only the editor whose registry is used by this parse.
            arguments (Input)
                registry (1, 1) yamada.model.ComponentRegistry
            end
            arguments (Output)
                registration yamada.source.SourceParseProgress
            end
            registration = yamada.source.SourceParseProgress.empty;
            for item = yamada.source.SourceParseProgress.registrations("read")
                if isvalid(item) && isvalid(item.Parent) && isvalid(item.Registry) && item.Registry == registry
                    registration = item; return
                end
            end
        end
    end
    methods (Static, Access = private)
        function list = registrations(action, registration)
            % registrations Keep editor-owned registrations separate from model and source state.
            arguments (Input)
                action (1, 1) string
                registration yamada.source.SourceParseProgress = yamada.source.SourceParseProgress.empty
            end
            arguments (Output)
                list yamada.source.SourceParseProgress
            end
            persistent entries
            if isempty(entries), entries = yamada.source.SourceParseProgress.empty; end
            entries = entries(isvalid(entries));
            if action == "add", entries(end + 1) = registration;
            elseif action == "remove", entries(entries == registration) = []; end
            list = entries;
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
