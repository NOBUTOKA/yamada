// Check the shipped nested grid hit targets without opening a MATLAB window.
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
    style: {}, dataset: {}, children: [], listeners: {},
    appendChild(child) { this.children.push(child); },
    addEventListener(name, callback) { this.listeners[name] = callback; }
  };
}

const controls = element();
controls.appendChild({className: 'grid-child'});
const sent = [];
let captured = false;
context.currentData.height = 400;
context.svg = {
  getBoundingClientRect: () => ({left: 0, top: 0, height: 400}),
  setPointerCapture() { captured = true; }
};
context.component = {sendEventToMATLAB(name, data) { sent.push({name, data}); }};
context.document = {
  getElementById: () => controls,
  createElement: element
};

context.renderNestedGridComponents([
  {id: 'outside', inGrid: false, x: 0, y: 0, width: 20, height: 20},
  {id: 'button', inGrid: true, selected: true, x: 50, y: 60, width: 90, height: 25}
]);
assert.equal(controls.children.length, 2);
const target = controls.children[1];
assert.equal(target.className, 'nested-grid-component');
assert.equal(target.dataset.componentId, 'button');
assert.equal(target.children.length, 8);

target.listeners.pointerdown({type: 'pointerdown', target, pointerId: 1, clientX: 55, clientY: 315});
assert.equal(captured, true);
assert.equal(sent[0].name, 'Pointer');
assert.equal(sent[0].data.componentId, 'button');
assert.equal(sent[0].data.handle, '');

const eastHandle = target.children.find(child => child.dataset.handle === 'e');
target.listeners.pointerdown({type: 'pointerdown', target: eastHandle, pointerId: 2,
  clientX: 140, clientY: 315});
assert.equal(sent[1].data.componentId, 'button');
assert.equal(sent[1].data.handle, 'e');
console.log('Nested grid component selection and resize targets passed.');
