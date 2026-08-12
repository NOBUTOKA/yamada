classdef Diagnostic
    % Diagnostic Describe one model, parsing, validation, or generation issue.
    %   This value class carries severity, user-facing text, and optional model
    %   and source locations. It does not decide whether an operation proceeds.

    properties (SetAccess = private)
        % Code - Stable machine-readable diagnostic identifier.
        Code string = ""
        % Severity - Diagnostic level: info, warning, or error.
        Severity string = "warning"
        % Message - User-facing explanation of the issue.
        Message string = ""
        % ComponentId - Optional stable identity of the related component.
        ComponentId string = ""
        % SourceSpan - Optional macd.model.SourceSpan associated with the issue.
        SourceSpan macd.model.SourceSpan = macd.model.SourceSpan.empty
    end

    methods
        function obj = Diagnostic(code, severity, message, componentId, sourceSpan)
            % Diagnostic Create a structured diagnostic for a model location.
            arguments (Input)
                code string = ""
                severity string = "warning"
                message string = ""
                componentId string = ""
                sourceSpan macd.model.SourceSpan = macd.model.SourceSpan.empty
            end
            arguments (Output)
                obj (1, 1) macd.model.Diagnostic
            end

            % Preserve property defaults for the no-input constructor.
            if nargin == 0
                return
            end

            % Normalize the required diagnostic fields.
            severity = string(validatestring(severity, ["info", "warning", "error"]));
            obj.Code = code;
            obj.Severity = severity;
            obj.Message = message;

            % Attach optional model and source locations when supplied.
            if nargin >= 4
                obj.ComponentId = componentId;
            end
            if nargin >= 5
                obj.SourceSpan = sourceSpan;
            end
        end

        function result = isError(obj)
            % isError Return true when this diagnostic blocks generation.
            arguments (Input)
                obj (1, 1) macd.model.Diagnostic
            end
            arguments (Output)
                result (1, 1) logical
            end

            result = obj.Severity == "error";
        end
    end
end

%{
Copyright (C) 2026 Nobuto Kaitoh

This file is part of MatlabAppClassDesigner.

MatlabAppClassDesigner is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

MatlabAppClassDesigner is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with MatlabAppClassDesigner. If not, see <https://www.gnu.org/licenses/>.
%}
