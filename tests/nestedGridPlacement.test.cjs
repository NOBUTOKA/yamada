// Exercise nested grid placement through the shipped frame and pointer listeners.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const html = fs.readFileSync(path.join(__dirname, '../resources/EditorInteractionOverlay.html'), 'utf8');
const context = {};
vm.createContext(context);
vm.runInContext(html.match(/<script>([\s\S]*?)<\/script>/)[1], context);

function element() {
  return {
    style: {}, dataset: {}, children: [], listeners: {}, parentNode: null,
    appendChild(child) { this.children.push(child); child.parentNode = this; },
    addEventListener(name, listener) { this.listeners[name] = listener; },
    remove() { this.parentNode.children = this.parentNode.children.filter(child => child !== this); }
  };
}
const controls = element();
const documentListeners = {};
const sent = [];
context.document = {
  getElementById: id => id === 'overlay' ? context.svg : controls, createElement: element,
  addEventListener(name, listener) { documentListeners[name] = listener; },
  removeEventListener(name) { delete documentListeners[name]; },
  querySelectorAll: () => []
};
context.component = {sendEventToMATLAB(name, data) { sent.push({name, data}); }};
context.currentData = {width: 400, height: 400, surfaceBounds: [-14, -14, 428, 428]};
context.svg = {getBoundingClientRect: () => ({left: 60, top: 80, height: 428})};
function pointer(x, y) {
  return {clientX: 60 + x + 14, clientY: 80 + 414 - y,
    preventDefault() {}, stopPropagation() {}};
}
const child = {id: 'inner', selected: true, editable: true, bounds: [0, 210, 190, 190],
  rowStart: 1, rowEnd: 1, columnStart: 1, columnEnd: 1};
const parent = {activeGridId: 'outer', revision: 7, editable: true, geometryAvailable: true,
  children: [child],
  rowTracks: [{index: 1, bounds: [0, 210, 400, 190]}, {index: 2, bounds: [0, 0, 400, 200]}],
  columnTracks: [{index: 1, bounds: [0, 0, 190, 400]}, {index: 2, bounds: [200, 0, 200, 400]}]};

context.renderGridPlacement(parent);
const frame = controls.children[0];
assert.equal(frame.dataset.componentId, 'inner');
assert.equal(frame.children.length, 12);
assert.match(html, /\.grid-child\.selected\.editable\.grid-placement\s*\{[^}]*pointer-events:\s*none/);
const leftEdge = frame.children.find(item => item.className === 'grid-move-edge left');
// A border just outside the cell must start and commit in the parent, with scroll offsets applied.
leftEdge.listeners.pointerdown(pointer(-2, 300));
assert.ok(context.gridGesture);
documentListeners.pointerup(pointer(250, 100));
assert.equal(sent.length, 1);
assert.equal(sent[0].name, 'GridAction');
assert.equal(sent[0].data.action, 'move-child');
assert.equal(sent[0].data.activeGridId, 'outer');
assert.equal(sent[0].data.childId, 'inner');
assert.equal(sent[0].data.rowStart, 2);
assert.equal(sent[0].data.columnStart, 2);

const corner = frame.children.find(item => item.className === 'grid-span-handle bottom-right');
corner.listeners.pointerdown(pointer(193, 207));
documentListeners.pointerup(pointer(300, 100));
assert.equal(sent[1].data.action, 'resize-span');
assert.equal(sent[1].data.rowEnd, 2);
assert.equal(sent[1].data.columnEnd, 2);

// The nested grid's empty background also starts a move, while Escape leaves the model unchanged.
context.renderGridSelectionTargets([{id: 'inner', gridId: 'outer', x: 0, y: 210,
  width: 190, height: 190}], {activeGridId: 'inner'}, parent);
const target = controls.children.at(-1);
assert.equal(target.style.cursor, 'move');
target.listeners.pointerdown(pointer(50, 300));
assert.ok(context.gridGesture);
documentListeners.keydown({key: 'Escape', preventDefault() {}});
assert.equal(context.gridGesture, null);
assert.equal(sent.length, 2);

const priorCount = controls.children.length;
context.renderGridPlacement({...parent, geometryAvailable: false});
context.renderGridPlacement({...parent, children: [{...child, selected: false}]});
assert.equal(controls.children.length, priorCount);
console.log('Nested grid parent moves, span resizing, cancellation and scrolled coordinates passed.');
