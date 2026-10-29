function observations = ProbeCatalogSetterAccess(releaseDirectory, targets)
% ProbeCatalogSetterAccess Read native setter metadata for owned catalog fixtures.
%   With no targets, inspect every unresolved ledger entry. Explicit targets
%   containing componentId and path make a recorded audit reproducible after
%   the ledger has been corrected. User app source and callbacks are not run.
arguments (Input)
    releaseDirectory (1, 1) string
    targets (1, :) struct = struct.empty(1, 0)
end
arguments (Output)
    observations (1, :) struct
end

% Discover requested public-documentation entries before constructing controls.
files = dir(fullfile(releaseDirectory, "components", "*.json"));
ledgers = struct();
for file = reshape(files, 1, [])
    ledger = jsondecode(fileread(fullfile(file.folder, file.name)));
    ledgers.(matlab.lang.makeValidName(ledger.id)) = ledger;
end
if isempty(targets)
    targets = struct("componentId", {}, "path", {});
    for name = string(fieldnames(ledgers))'
        ledger = ledgers.(name);
        for index = 1:numel(ledger.properties)
            property = ledger.properties(index);
            if iscell(property), property = property{1}; end
            if string(property.runtimeSetAccess) == "unresolved"
                targets(end + 1) = struct("componentId", string(ledger.id), ...
                    "path", string(property.path)); %#ok<AGROW>
            end
        end
    end
end
observations = struct("componentId", {}, "path", {}, "runtimeSetAccess", {}, ...
    "nativeSetAccess", {}, "metadataClass", {}, "errorId", {});

% One owned fixture per variant exposes instance metadata, including dynamic properties.
figure = uifigure(Visible="off");
cleanup = onCleanup(@() delete(figure));
ids = unique(string({targets.componentId}), "stable");
for id = ids
    ledger = ledgers.(matlab.lang.makeValidName(id));
    arguments = ledger.creationArguments;
    if ~iscell(arguments), arguments = num2cell(arguments); end
    target = feval(string(ledger.factory), figure, arguments{:});
    entries = targets(string({targets.componentId}) == id);
    for entry = entries
        observation = struct("componentId", id, "path", string(entry.path), ...
            "runtimeSetAccess", "unresolved", "nativeSetAccess", "", ...
            "metadataClass", "", "errorId", "");
        try
            property = findprop(target, string(entry.path));
            if ~isscalar(property)
                error("yamada:SetterAccess:MissingProperty", "Native property metadata is unavailable.");
            end
            observation.metadataClass = string(class(property));
            access = property.SetAccess;
            if ischar(access) || isstring(access)
                observation.nativeSetAccess = string(access);
                if observation.nativeSetAccess == "public"
                    observation.runtimeSetAccess = "public";
                elseif any(observation.nativeSetAccess == ["private", "protected", "immutable"])
                    observation.runtimeSetAccess = "restricted";
                end
            elseif iscell(access) || isa(access, "meta.class")
                observation.nativeSetAccess = "class-restricted";
                observation.runtimeSetAccess = "restricted";
            end
        catch exception
            observation.errorId = string(exception.identifier);
        end
        observations(end + 1) = observation; %#ok<AGROW>
    end
    delete(target);
end
clear cleanup
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
