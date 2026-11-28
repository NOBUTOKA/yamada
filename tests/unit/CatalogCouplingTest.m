classdef (TestTags = {'fast', 'catalog'}) CatalogCouplingTest < matlab.unittest.TestCase
    % CatalogCouplingTest Verify child coupling capabilities across the committed release catalogs.
    %   The loader checks references on every load; this test checks the consistency rules
    %   of the generated catalogs once, because they change only when the ledger changes.

    methods (Test)
        function stateCouplingImpliesTopologyCoupling(testCase)
            % stateCouplingImpliesTopologyCoupling Require coupled membership wherever child state is coupled.
            % Guarantee: every container whose children resolve state together is also rechecked after child topology changes.
            % Failure mode: a ledger edit couples child state without topology, so moving or adding a child leaves stale group state.

            % Load each committed release catalog independently of the running release.
            folder = fullfile(fileparts(fileparts(fileparts(mfilename("fullpath")))), "resources", "component-catalog");
            entries = dir(fullfile(folder, "R*"));
            entries = entries([entries.isdir]);
            testCase.assertNotEmpty(entries);
            for entry = reshape(entries, 1, [])
                registry = yamada.catalog.ComponentCatalogLoader.load(string(fullfile(entry.folder, entry.name)));
                for id = registry.listVariantIds()
                    definition = registry.getById(id);
                    if ~definition.ChildStateCoupling, continue, end
                    testCase.verifyTrue(definition.ChildTopologyCoupling, ...
                        entry.name + " " + definition.Factory + " couples child state without child topology.");
                end
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
