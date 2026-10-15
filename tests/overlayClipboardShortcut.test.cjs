const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const html = fs.readFileSync(require('node:path').join(__dirname, '../resources/EditorInteractionOverlay.html'), 'utf8');
const context = {};
vm.createContext(context);
vm.runInContext(html.match(/<script>([\s\S]*?)<\/script>/)[1], context);
const sent = [];
context.component = {sendEventToMATLAB(name, data) { sent.push({name, data}); }};
context.currentData = {selectedComponentId: 'selected', gridEditor: {revision: 12}};
function key(extra = {}, target = {}) {
  return {key: 'v', ctrlKey: true, target, preventDefault() {this.prevented = true;}, stopPropagation() {}, ...extra};
}
for (const tagName of ['INPUT', 'TEXTAREA', 'SELECT']) context.clipboardSelectionKey(key({}, {tagName}));
context.clipboardSelectionKey(key({}, {isContentEditable: true}));
context.clipboardSelectionKey(key({}, {closest: () => ({})}));
for (const extra of [{ctrlKey:false}, {altKey:true}, {shiftKey:true}, {repeat:true}, {key:'z'}]) context.clipboardSelectionKey(key(extra));
context.gridGesture = {};
context.clipboardSelectionKey(key());
context.gridGesture = null;
context.absoluteGesture = {};
context.clipboardSelectionKey(key());
context.absoluteGesture = null;
assert.equal(sent.length, 0);
for (const [character, action] of [['c','Copy'], ['x','Cut'], ['v','Paste']]) {
  const event = key({key: character});
  context.clipboardSelectionKey(event);
  assert.equal(event.prevented, true);
  assert.equal(sent.at(-1).name, 'Clipboard');
  assert.equal(sent.at(-1).data.action, action);
  assert.equal(sent.at(-1).data.componentId, 'selected');
  assert.equal(sent.at(-1).data.revision, 12);
}
context.clipboardSelectionKey(key({ctrlKey:false,metaKey:true,key:'V'}));
assert.equal(sent.at(-1).data.action, 'Paste');
assert.equal(sent.length, 4);
console.log('Preview clipboard shortcuts forward commands and preserve text and gesture ownership.');
