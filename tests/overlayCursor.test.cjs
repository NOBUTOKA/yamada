// Check that absolute controls expose only usable resize directions to the overlay.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const html = fs.readFileSync(path.join(__dirname, '../resources/EditorInteractionOverlay.html'), 'utf8');
const context = {};
vm.createContext(context);
vm.runInContext(html.match(/<script>([\s\S]*?)<\/script>/)[1], context);
const handles = [];
context.currentData.height = 400;
context.document = {
  createElementNS: (_, name) => ({name, attributes: {},
    children: [], setAttribute(key, value) { this.attributes[key] = value; },
    appendChild(child) { this.children.push(child); }})
};
context.svg = {appendChild(handle) { handles.push(handle); }};

context.addHandles({id: 'button', selected: true, x: 10, y: 10, width: 90, height: 30});
assert.equal(handles.length, 8);
assert.deepEqual(handles.map(handle => handle.attributes['data-handle']).sort(),
  ['e', 'n', 'ne', 'nw', 's', 'se', 'sw', 'w']);
handles.length = 0;
context.addHandles({id: 'slider', selected: true, x: 10, y: 10, width: 90,
  height: 30, resizeConstraint: 'fixedHeight'});
assert.equal(handles.length, 6);
assert.ok(handles.every(handle => !['n', 's'].includes(handle.attributes['data-handle'])));
assert.ok(handles.every(handle => handle.attributes['data-resize-constraint'] === 'fixedHeight'));
assert.match(html, /\.silhouette \{[^}]*cursor: move;/);
assert.match(html, /\.handle\[data-handle="ne"\][^{]*\{ cursor: ne-resize; \}/);
assert.match(html, /data-resize-constraint="fixedHeight"\]\[data-handle="ne"\][\s\S]*\{ cursor: ew-resize; \}/);
handles.length = 0;
context.currentData = {width: 320, height: 240, rootId: 'root',
  rootSelected: false, rootEditable: true, rootSize: [340, 260]};
context.addRootHandles();
assert.deepEqual(handles.filter(handle => handle.attributes['data-handle'])
  .map(handle => handle.attributes['data-handle']).sort(),
['root-e', 'root-n', 'root-ne', 'root-nw', 'root-s', 'root-se', 'root-sw', 'root-w']);
assert.ok(handles.some(handle => handle.textContent === '340 × 260'));
handles.length = 0;
context.currentData.rootEditable = false;
context.addRootHandles();
assert.equal(handles.length, 0);
context.currentData.rootSelected = true;
context.addRootHandles();
assert.equal(handles.filter(handle => handle.attributes['data-handle']).length, 8);
handles.length = 0;
const sent = [];
context.component = {sendEventToMATLAB(name, data) { sent.push({name, data}); }};
context.svg.getBoundingClientRect = () => ({left: 0, top: 0, height: 240});
context.svg.setPointerCapture = () => {};
context.sendPointerEvent({type: 'pointerdown', pointerId: 1, clientX: 313,
  clientY: 7, target: {dataset: {componentId: 'root', handle: 'root-ne'}}});
assert.equal(sent[0].name, 'Pointer');
assert.equal(sent[0].data.componentId, 'root');
assert.equal(sent[0].data.handle, 'root-ne');
console.log('Absolute overlay move and resize cursors passed.');
