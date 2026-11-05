classdef InputChangeClock < handle
    % InputChangeClock Track semantic writes without retaining documents or records.
    %   Model owners share this acyclic revision token. Shared record ownership
    %   and untracked live values disable the fast path conservatively.
    properties (SetAccess = private)
        % Revision - Monotonically increasing semantic-write counter.
        Revision uint64 = uint64(0)
        % IsTracked - Whether all subsequent mutations can be observed locally.
        IsTracked logical = true
    end

    methods
        function touch(obj, value)
            % touch Record a semantic assignment and reject hidden mutable inputs.
            arguments (Input)
                obj (1, 1) yamada.model.InputChangeClock
                value
            end
            obj.Revision = obj.Revision + uint64(1);
            if obj.IsTracked && ~yamada.model.InputChangeClock.isValueData(value)
                obj.IsTracked = false;
            end
        end

        function disable(obj)
            % disable Require exact-value comparison after ownership becomes ambiguous.
            arguments (Input)
                obj (1, 1) yamada.model.InputChangeClock
            end
            obj.IsTracked = false;
        end
    end

    methods (Static)
        function safe = isValueData(value)
            % isValueData Recognize independent values without traversing live objects.
            arguments (Input)
                value
            end
            arguments (Output)
                safe (1, 1) logical
            end
            safe = true;
            if isstruct(value)
                names = fieldnames(value);
                for index = 1:numel(value)
                    for field = 1:numel(names)
                        if ~yamada.model.InputChangeClock.isValueData(value(index).(names{field}))
                            safe = false; return
                        end
                    end
                end
            elseif iscell(value)
                for index = 1:numel(value)
                    if ~yamada.model.InputChangeClock.isValueData(value{index})
                        safe = false; return
                    end
                end
            elseif isnumeric(value) || islogical(value) || ischar(value) || isstring(value) || ...
                    isa(value, "datetime") || isa(value, "duration") || ...
                    isa(value, "calendarDuration") || isa(value, "categorical")
                return
            elseif any(string(class(value)) == ["yamada.model.SourceSpan", ...
                    "yamada.model.UnknownSourceRegion", "yamada.model.Diagnostic", "yamada.model.CallbackEdit", ...
                    "yamada.source.CallbackMethodSignature"])
                return
            elseif any(string(class(value)) == ["yamada.model.PropertyState", ...
                    "yamada.model.PropertyDefinition", "yamada.model.PropertyApplicationPolicy", ...
                    "yamada.model.PropertySetting"])
                % Known value classes may themselves contain arbitrary input data.
                switch string(class(value))
                    case "yamada.model.PropertyState"
                        names = ["ExplicitValue", "RequestedValue", "EffectiveValue"];
                    case "yamada.model.PropertyDefinition"
                        names = ["DefaultValue", "Metadata", "ValueSchema", "Application"];
                    case "yamada.model.PropertyApplicationPolicy"
                        names = "InitialValue";
                    otherwise
                        names = "LiteralValue";
                end
                for index = 1:numel(value)
                    for field = 1:numel(names)
                        if ~yamada.model.InputChangeClock.isValueData(value(index).(names(field)))
                            safe = false; return
                        end
                    end
                end
            else
                safe = false;
            end
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
