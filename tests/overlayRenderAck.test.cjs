// Rendering acknowledgements are opt-in, versioned, and do not publish stale work.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const html = fs.readFileSync(path.join(__dirname, '../resources/EditorInteractionOverlay.html'), 'utf8');
const frames = [];
const events = [];
const layer = {style: {}, innerHTML: ''};
const context = {document: {getElementById() { return layer; }},
  requestAnimationFrame(callback) { frames.push(callback); }};
vm.createContext(context);
vm.runInContext(html.match(/<script>([\s\S]*?)<\/script>/)[1], context);
context.svg = {setAttribute() {}, appendChild() {}, innerHTML: ''};
context.component = {sendEventToMATLAB(name, data) { events.push({name, revision: data.revision}); }};
for (const name of ['closeTrackPopover', 'renderTabControls', 'renderGridSelectionTargets',
  'renderGridEditor', 'renderNestedGridComponents', 'renderGridPlacement', 'addRootHandles']) {
  context[name] = () => {};
}
context.currentData = {width: 100, height: 100, components: [], gridEditor: {revision: 7}};
context.render();
assert.equal(frames.length, 0);
context.currentData.measureRender = true;
context.render();
frames.shift()();
assert.equal(events.length, 0);
frames.shift()();
assert.deepEqual(events, [{name: 'Rendered', revision: 7}]);
context.render();
frames.shift()();
context.currentData.gridEditor.revision = 8;
frames.shift()();
assert.equal(events.length, 1);
console.log('Opt-in HTML rendering acknowledgements reject obsolete revisions.');
