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

// F2 remains exclusive to the hierarchy, including when Preview owns focus.
const beforeF2 = sent.length;
context.editorShortcutKey(key({key:'F2',ctrlKey:false}));
assert.equal(sent.length,beforeF2);
// All non-text editor shortcuts use the same guarded iframe bridge.
for (const [character, ctrlKey, action] of [['z',true,'Undo'],['r',true,'Redo'],['F5',false,'Reload']]) {
  const before = sent.length;
  context.editorShortcutKey(key({key:character,ctrlKey}, {tagName:'INPUT'}));
  assert.equal(sent.length, before);
  context.editorShortcutKey(key({key:character,ctrlKey}));
  assert.equal(sent.at(-1).name, 'Shortcut');
  assert.equal(sent.at(-1).data.action, action);
}
// Right-click resolves the hit component rather than the selected component.
context.currentData.rootId = 'root';
context.svg = {getBoundingClientRect() { return {left:10,top:20,height:300}; }};
let event = key({clientX:40,clientY:80}, {closest: selector => selector === '[data-component-id]' ? {dataset:{componentId:'unselected'}} : null});
context.previewContextMenu(event);
assert.equal(sent.at(-1).name, 'ContextMenu');
assert.equal(sent.at(-1).data.componentId, 'unselected');
assert.equal(sent.at(-1).data.x, 30);
assert.equal(sent.at(-1).data.y, 240);
const count = sent.length;
context.previewContextMenu(key({}, {tagName:'INPUT'}));
context.absoluteGesture = {};
context.previewContextMenu(event);
assert.equal(sent.length,count);
console.log('Preview editor keys and context targets preserve text editing and gesture ownership.');

const documentEvents = {};
let focused = 0;
context.document = {body:{focus(){focused++;}}, getElementById(){return {addEventListener(){}};},
  addEventListener(name, callback, capture){ if(capture)documentEvents[name]=callback; }};
context.render = () => {};
context.setup({Data:{},addEventListener(){}});
const rightClick = {target:{},button:2,stopPropagation(){this.stopped=true;}};
documentEvents.pointerdown(rightClick);
assert.equal(focused,1);
assert.equal(rightClick.stopped,true);
documentEvents.pointerdown({target:{tagName:'INPUT'}});
assert.equal(focused,1);
console.log('Pointer focus capture excludes editors and prevents right-click drag starts.');

// A simple click needs no asynchronous drag-source publication before Delete.
context.component = {sendEventToMATLAB(name,data){sent.push({name,data});}};
context.currentData = {width:300,height:200,rootId:'root',selectedComponentId:'selected',gridEditor:{revision:5}};
context.absoluteGesture = null;
context.gridGesture = null;
context.svg = {getBoundingClientRect(){return {left:0,top:0,height:200};},
  setPointerCapture(){},hasPointerCapture(){return true;},releasePointerCapture(){}};
const clickTarget = {dataset:{componentId:'selected'},classList:{contains(){return false;}}};
context.sendPointerEvent({type:'pointerdown',target:clickTarget,pointerId:1,clientX:20,clientY:40});
context.sendPointerEvent({type:'pointerup',target:clickTarget,pointerId:1,clientX:20,clientY:40});
assert.equal(context.absoluteGesture,null);
assert.equal(sent.at(-1).data.phase,'pointerup');
context.component = {sendEventToMATLAB(name,data){sent.push({name,data});}};
context.deleteSelectionKey(key({key:'Delete',ctrlKey:false}));
assert.equal(sent.at(-1).name,'DeleteSelection');
for (const character of ['n','o','s']) {
  context.editorShortcutKey(key({key:character}));
  assert.equal(sent.at(-1).name,'Accelerator');
  assert.equal(sent.at(-1).data.key,character.toUpperCase());
}
console.log('A completed click releases Delete and iframe file keys use native accelerator actions.');

// A real drag releases keyboard ownership both immediately and after delayed geometry arrives.
context.currentData.dragSource = {id:'selected',parentId:'root'};
context.currentData.reparentRevision = 1;
context.sendPointerEvent({type:'pointerdown',target:clickTarget,pointerId:2,clientX:20,clientY:40});
context.sendPointerEvent({type:'pointerup',target:clickTarget,pointerId:2,clientX:70,clientY:80});
assert.equal(context.absoluteGesture,null);
context.deleteSelectionKey(key({key:'Delete',ctrlKey:false}));
assert.equal(sent.at(-1).name,'DeleteSelection');
const savedSvg = context.svg;
const htmlEvents = {};
const htmlBridge = {Data:{width:300,height:200,rootId:'root',selectedComponentId:'selected',
  reparentRevision:1,gridEditor:{revision:6}},addEventListener(name,callback){htmlEvents[name]=callback;},
  sendEventToMATLAB(name,data){sent.push({name,data});}};
context.setup(htmlBridge);
context.svg = savedSvg;
context.sendPointerEvent({type:'pointerdown',target:clickTarget,pointerId:3,clientX:20,clientY:40});
context.sendPointerEvent({type:'pointerup',target:clickTarget,pointerId:3,clientX:70,clientY:80});
assert.ok(context.absoluteGesture.pendingPoint);
htmlBridge.Data = {...htmlBridge.Data,dragSource:{id:'selected',parentId:'root'},gridEditor:{revision:7}};
htmlEvents.DataChanged({});
assert.equal(context.absoluteGesture,null);
context.deleteSelectionKey(key({key:'Delete',ctrlKey:false}));
assert.equal(sent.at(-1).name,'DeleteSelection');
assert.equal(sent.at(-1).data.revision,7);
console.log('Delete works after real drags, including delayed drag-source publications.');
