classdef LayoutStabilizeReply < handle
    % LayoutStabilizeReply Retain one layout response and ignore unrelated request tokens.
    %   The object provides an observable completion flag for a bounded waitfor.
    properties (SetObservable, SetAccess = private)
        % Done - Whether a matching response or the watchdog has completed this request.
        Done logical = false
    end
    properties (SetAccess = private)
        % Token - Exact request identifier required on accepted replies.
        Token string
        % Data - Matching JavaScript response or explicit timeout layouts.
        Data struct = struct()
    end
    methods
        function obj = LayoutStabilizeReply(token)
            % LayoutStabilizeReply Create the single-request completion sink.
            arguments (Input)
                token (1, 1) string
            end
            arguments (Output)
                obj (1, 1) macd.ui.LayoutStabilizeReply
            end
            obj.Token = token;
        end
        function accept(obj, data)
            % accept Publish only the first response carrying this request's token.
            arguments (Input)
                obj (1, 1) macd.ui.LayoutStabilizeReply
                data struct
            end
            if obj.Done || ~isfield(data, "token") || string(data.token) ~= obj.Token, return, end
            obj.Data = data;
            obj.Done = true;
        end
        function expire(obj)
            % expire Release the layout wait if the response never arrives.
            arguments (Input)
                obj (1, 1) macd.ui.LayoutStabilizeReply
            end
            if obj.Done, return, end
            obj.Data = struct("token", obj.Token, "error", "Layout acknowledgement timed out.");
            obj.Done = true;
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
