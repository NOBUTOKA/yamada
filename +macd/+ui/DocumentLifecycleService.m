classdef DocumentLifecycleService < handle
    % DocumentLifecycleService Mediate editor document dialogs and file operations.
    %   This service keeps native prompts and filesystem access outside the editor's
    %   document-transition policy. Tests may supply callback replacements without
    %   constructing modal dialogs or writing project files.
    %
    %   Example:
    %       service = macd.ui.DocumentLifecycleService();

    properties (Access = private)
        RequestNewClassNameFcn function_handle
        RequestOpenPathFcn function_handle
        RequestSavePathFcn function_handle
        ConfirmUnsavedChangesFcn function_handle
        ConfirmReplaceFcn function_handle
        FileExistsFcn function_handle
        WriteSourceFcn function_handle
    end

    methods
        function obj = DocumentLifecycleService(callbacks)
            % DocumentLifecycleService Create native operations or install test callbacks.
            arguments (Input)
                callbacks struct = struct()
            end

            % Start from native behavior and replace only explicitly supplied seams.
            obj.RequestNewClassNameFcn = @macd.ui.DocumentLifecycleService.requestNativeClassName;
            obj.RequestOpenPathFcn = @macd.ui.DocumentLifecycleService.requestNativeOpenPath;
            obj.RequestSavePathFcn = @macd.ui.DocumentLifecycleService.requestNativeSavePath;
            obj.ConfirmUnsavedChangesFcn = @macd.ui.DocumentLifecycleService.confirmNativeUnsavedChanges;
            obj.ConfirmReplaceFcn = @macd.ui.DocumentLifecycleService.confirmNativeReplace;
            obj.FileExistsFcn = @isfile;
            obj.WriteSourceFcn = @macd.source.SourceWriter.write;
            obj.installCallbacks(callbacks);
        end

        function [accepted, className] = requestNewClassName(obj)
            % requestNewClassName Request one proposed class name.
            [accepted, className] = obj.RequestNewClassNameFcn();
            accepted = logical(accepted);
            className = string(className);
        end

        function [accepted, filePath] = requestOpenPath(obj)
            % requestOpenPath Request an existing AppBase source path.
            [accepted, filePath] = obj.RequestOpenPathFcn();
            accepted = logical(accepted);
            filePath = string(filePath);
        end

        function [accepted, filePath] = requestSavePath(obj, suggestedName)
            % requestSavePath Request a target path for Save As.
            arguments (Input)
                obj (1, 1) macd.ui.DocumentLifecycleService
                suggestedName (1, 1) string
            end

            [accepted, filePath] = obj.RequestSavePathFcn(suggestedName);
            accepted = logical(accepted);
            filePath = string(filePath);
        end

        function choice = confirmUnsavedChanges(obj)
            % confirmUnsavedChanges Ask whether to save, discard, or cancel a transition.
            choice = string(obj.ConfirmUnsavedChangesFcn());
        end

        function accepted = confirmReplace(obj, filePath)
            % confirmReplace Ask whether Save As may replace an existing target.
            arguments (Input)
                obj (1, 1) macd.ui.DocumentLifecycleService
                filePath (1, 1) string
            end

            accepted = logical(obj.ConfirmReplaceFcn(filePath));
        end

        function result = fileExists(obj, filePath)
            % fileExists Return whether a Save As target already exists.
            arguments (Input)
                obj (1, 1) macd.ui.DocumentLifecycleService
                filePath (1, 1) string
            end

            result = logical(obj.FileExistsFcn(filePath));
        end

        function writeSource(obj, filePath, source, lineEnding)
            % writeSource Write generated text through the configured filesystem seam.
            arguments (Input)
                obj (1, 1) macd.ui.DocumentLifecycleService
                filePath (1, 1) string
                source (1, 1) string
                lineEnding (1, 1) string
            end

            obj.WriteSourceFcn(filePath, source, lineEnding);
        end
    end

    methods (Access = private)
        function installCallbacks(obj, callbacks)
            % installCallbacks Replace documented callback seams supplied by a test.
            names = ["RequestNewClassNameFcn", "RequestOpenPathFcn", ...
                "RequestSavePathFcn", "ConfirmUnsavedChangesFcn", ...
                "ConfirmReplaceFcn", "FileExistsFcn", "WriteSourceFcn"];
            for index = 1:numel(names)
                name = names(index);
                if isfield(callbacks, name)
                    callback = callbacks.(name);
                    if ~isa(callback, "function_handle")
                        error("macd:DocumentLifecycleService:InvalidCallback", ...
                            "Callback ""%s"" must be a function handle.", name);
                    end
                    obj.(name) = callback;
                end
            end
        end
    end

    methods (Static, Access = private)
        function [accepted, className] = requestNativeClassName()
            % requestNativeClassName Show the native New-document class-name dialog.
            answer = inputdlg("MATLAB class name:", "New App", [1 50], {"UntitledApp"});
            accepted = ~isempty(answer);
            className = "";
            if accepted
                className = string(answer{1});
            end
        end

        function [accepted, filePath] = requestNativeOpenPath()
            % requestNativeOpenPath Show the native Open-file dialog.
            [fileName, folder] = uigetfile("*.m", "Open AppBase class");
            accepted = ~isequal(fileName, 0);
            filePath = "";
            if accepted
                filePath = string(fullfile(folder, fileName));
            end
        end

        function [accepted, filePath] = requestNativeSavePath(suggestedName)
            % requestNativeSavePath Show the native Save As target dialog.
            [fileName, folder] = uiputfile("*.m", "Save AppBase class", char(suggestedName));
            accepted = ~isequal(fileName, 0);
            filePath = "";
            if accepted
                filePath = string(fullfile(folder, fileName));
            end
        end

        function choice = confirmNativeUnsavedChanges()
            % confirmNativeUnsavedChanges Ask about a document-changing transition.
            choice = string(questdlg("Save changes before continuing?", ...
                "Unsaved Changes", "Save", "Discard", "Cancel", "Cancel"));
        end

        function accepted = confirmNativeReplace(filePath)
            % confirmNativeReplace Ask before replacing an existing Save As target.
            answer = questdlg("Replace existing file """ + filePath + """?", ...
                "Replace Existing File", "Replace", "Cancel", "Cancel");
            accepted = string(answer) == "Replace";
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
