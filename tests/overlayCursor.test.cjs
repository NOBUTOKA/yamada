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
    setAttribute(key, value) { this.attributes[key] = value; }})
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
console.log('Absolute overlay move and resize cursors passed.');
