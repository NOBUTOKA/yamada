// Keep Delete local to Preview selection, excluding native HTML editors and drafts.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const html = fs.readFileSync(path.join(__dirname, '../resources/EditorInteractionOverlay.html'), 'utf8');
const context = {};
vm.createContext(context);
vm.runInContext(html.match(/<script>([\s\S]*?)<\/script>/)[1], context);
const sent = [];
context.component = {sendEventToMATLAB(name, data) { sent.push({name, data}); }};
context.currentData = {selectedComponentId: 'selected', gridEditor: {revision: 12}};
function key(target = {}, extra = {}) {
  return {key: 'Delete', target, preventDefault() {}, stopPropagation() {}, ...extra};
}
for (const tagName of ['INPUT', 'TEXTAREA', 'SELECT']) {
  context.deleteSelectionKey(key({tagName}));
}
context.deleteSelectionKey(key({isContentEditable: true}));
context.deleteSelectionKey(key({closest: () => ({})}));
for (const modifier of ['ctrlKey', 'metaKey', 'altKey']) {
  context.deleteSelectionKey(key({}, {[modifier]: true}));
}
context.gridGesture = {};
context.deleteSelectionKey(key());
context.gridGesture = null;
context.deleteSelectionKey(key({}, {key: 'Backspace'}));
assert.equal(sent.length, 0);
context.deleteSelectionKey(key({tagName: 'svg', closest: () => null}));
assert.equal(sent.length, 1);
assert.equal(sent[0].name, 'DeleteSelection');
assert.equal(sent[0].data.componentId, 'selected');
assert.equal(sent[0].data.revision, 12);
console.log('Preview Delete ignores editors, track popovers, modifiers and active gestures.');
