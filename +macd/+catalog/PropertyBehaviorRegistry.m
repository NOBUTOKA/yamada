classdef PropertyBehaviorRegistry
    % PropertyBehaviorRegistry Validate symbolic property behavior identifiers.
    %   Catalog JSON names editor, validator, preview, and reset behaviors without
    %   carrying executable code. This class owns the finite allowlists used while
    %   loading the runtime component catalog; editor code may bind the same names
    %   to concrete adapters.

    methods (Static)
        function validateMetadata(metadata, context)
            % validateMetadata Reject unknown symbolic behavior identifiers.
            arguments (Input)
                metadata struct
                context (1, 1) string
            end

            % Validate each optional catalog behavior before model definitions exist.
            macd.catalog.PropertyBehaviorRegistry.validateIdentifier(metadata, "editor", ...
                ["literal", "text", "multilineText", "logical", "onOff", "enum", "number", ...
                "numericVector", "color", "stringList", "gridTrackList", "itemSelection", "filePath", ...
                "componentReference", "itemsData", "asset", "url", "dateTime", ...
                "tableData", "columnSettings", "structuredData", "numericMatrix", "readOnly"], context);
            macd.catalog.PropertyBehaviorRegistry.validateIdentifier(metadata, "validator", ...
                ["none", "matlabLiteral", "logical", "enum", "number", ...
                "numericVector", "normalizedRgb", "stringList", "filePath", ...
                "componentReference"], context);
            macd.catalog.PropertyBehaviorRegistry.validateIdentifier(metadata, "previewPolicy", ...
                ["apply", "adapt", "skip", "notRendered"], context);
            macd.catalog.PropertyBehaviorRegistry.validateIdentifier(metadata, "resetPolicy", ...
                ["remove", "retain", "structural"], context);
            macd.catalog.PropertyBehaviorRegistry.validateIdentifier(metadata, "auditDisposition", ...
                ["editable", "readOnly", "omitted"], context);
        end
    end

    methods (Static, Access = private)
        function validateIdentifier(metadata, fieldName, allowed, context)
            % validateIdentifier Check one optional symbolic field against its allowlist.
            arguments (Input)
                metadata struct
                fieldName (1, 1) string
                allowed (1, :) string
                context (1, 1) string
            end

            % Leave optional behavior metadata unconstrained when it is absent.
            key = char(fieldName);
            if ~isfield(metadata, key)
                return
            end
            value = string(metadata.(key));
            if ~isscalar(value) || ~any(allowed == value)
                error("macd:ComponentCatalogLoader:InvalidCatalog", ...
                    "%s.%s must be one of: %s.", context, fieldName, ...
                    strjoin(allowed, ", "));
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
