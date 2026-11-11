# Copyright (C) 2026 Nobuto Kaitoh
# SPDX-License-Identifier: GPL-3.0-or-later
# This file is part of yamada. See LICENSE for the license text.

from pathlib import Path
import json,hashlib,shutil
root=Path(__file__).resolve().parents[2];base=root/'testResults/performance/source-strategy-20261031';base.mkdir(parents=True,exist_ok=True)
s=(root/'yamada.m').read_text()
s=s.replace('''                app.Document.setPropertyBatch(component.Id, transaction.changes(), app.Registry);''','''                experiment = getappdata(app.UIFigure, "SourceStrategyExperiment");
                requested = transaction.changes();
                assert(isscalar(requested), "Prototype handles one Inspector property per operation.");
                experiment.edit(component.Name, string(requested.Path), requested.Value);''',1)
s=s.replace('''            app.Document.validatePropertyCommit(app.Registry);
            app.refreshViews(yamada.ui.RefreshRequest("properties", component.Id, string({changes.Path})));''','''            app.Document.Diagnostics = yamada.validation.ModelValidator.validate(app.Document, app.Registry, component.Name);
            app.refreshViews(yamada.ui.RefreshRequest("properties", component.Id, string({changes.Path})));''',1)
needle='''            completed = false;
            % Missing or unconfirmed targets'''
replacement='''            completed = false;
            experiment = getappdata(app.UIFigure, "SourceStrategyExperiment");
            assert(~isempty(experiment), "This detached editor build requires the experiment harness.");
            path = string(getappdata(app.UIFigure, "SourceStrategySavePath"));
            checkpoint = experiment.save(path);
            app.SavedSourceText = checkpoint.SourceText;
            app.updateSaveState(app.Document.Diagnostics);
            app.refreshTitle();
            app.setStatus("Saved experimental source.");
            completed = true;
            return
            % Missing or unconfirmed targets'''
assert needle in s;s=s.replace(needle,replacement,1)
# Keep the production Save body out of the detached experimental function.
a=s.index('            return\n            % Missing or unconfirmed targets');b=s.index('\n        function icon = refreshToolIcon',a)
s=s[:a]+'''        end
'''+s[b:]
variants={}
for mode in ['deferred','eager']:
 folder=base/'variants'/mode;folder.mkdir(parents=True,exist_ok=True)
 shutil.copytree(root/'resources',folder/'resources',dirs_exist_ok=True)
 p=folder/'yamada.m';p.write_bytes(s.replace('\n','\r\n').encode())
 variants[mode]={'root':str(folder),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
(base/'variants.json').write_text(json.dumps(variants),encoding='utf-8')
print('Built detached UI variants with shared Inspector/Preview and strategy-specific source engines.')

# Create paired fixtures from preserved project-owned 200-control sources.
operations=[]
for index in range(1,101):
    field=(index+1)//2 if index%2 else 201-index//2
    path=['Value','Tooltip','FontSize','Tooltip'][(index-1)%4]
    value=1000+index if path=='Value' else (10+index if path=='FontSize' else "変更後のヒント ' "+str(index)+'x'*(index%13))
    operations.append({'name':'Field'+str(field),'path':path,'value':value,'existing':index%4 in [1,2]})
fixtures={}
for layout in ['absolute','flatgrid','nestedgrid']:
    original=root/'tests/fixtures/performance/sourceStrategy'/layout/'UpdateDistributionFixture.m'
    if not original.exists():
        raise FileNotFoundError('Preserved scale fixture is required: '+str(original))
    lines=[]
    for line in original.read_text(encoding='utf-8').splitlines():
        lines.append(line)
        for operation in operations:
            if operation['existing'] and line.lstrip().startswith('app.'+operation['name']+' = uieditfield('):
                literal="'old'" if operation['path']=='Tooltip' else '9'
                lines.append('            app.'+operation['name']+'.'+operation['path']+' = '+literal+';')
    output=base/(layout+'-fixture.m')
    output.write_bytes(('\r\n'.join(lines)+'\r\n').encode('utf-8'))
    fixtures[layout]={'path':str(output),'sha256':hashlib.sha256(output.read_bytes()).hexdigest()}
(base/'fixtures.json').write_text(json.dumps(fixtures),encoding='utf-8')
(base/'operations.json').write_text(json.dumps(operations,ensure_ascii=False),encoding='utf-8')
# Freeze source hashes after successful verification and before timed sessions.
import subprocess
paths=set()
for flags in [[],['--others','--exclude-standard']]:
    paths.update(subprocess.check_output(['git','ls-files',*flags,'--','*.m','*.html','*.json','*.py','*.ps1'],cwd=root,text=True).splitlines())
manifest={'root':str(root),'revision':subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),
          'sources':[{'path':path,'sha256':hashlib.sha256((root/path).read_bytes()).hexdigest()} for path in sorted(paths)],
          'variants':variants,'fixtures':fixtures,'operationsSha256':hashlib.sha256((base/'operations.json').read_bytes()).hexdigest()}
(base/'inputs.json').write_text(json.dumps(manifest),encoding='utf-8')
