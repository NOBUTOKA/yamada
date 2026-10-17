// Preserve live controls and event revisions while rejecting older publications.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
class Element {
  constructor() { this.children = []; this.style = {}; this.dataset = {}; this.attributes = {}; this.listeners = {}; }
  set innerHTML(value) { assert.equal(value, ''); this.children.forEach(child => { child.parent = null; }); this.children = []; }
  setAttribute(key, value) { this.attributes[key] = value; }
  get classList() { return {contains: name => String(this.attributes.class || '').split(' ').includes(name),
    toggle: (name, enabled) => { const values = new Set(String(this.attributes.class || '').split(' ').filter(Boolean));
      enabled ? values.add(name) : values.delete(name); this.attributes.class = [...values].join(' '); }}; }
  addEventListener(name, callback) { this.listeners[name] = callback; }
  appendChild(child) { child.remove(); this.children.push(child); child.parent = this; return child; }
  insertBefore(child, reference) { child.remove(); const index = this.children.indexOf(reference);
    this.children.splice(index < 0 ? this.children.length : index, 0, child); child.parent = this; }
  remove() { if (this.parent) { this.parent.children.splice(this.parent.children.indexOf(this), 1); this.parent = null; } }
  replaceWith(child) { const parent = this.parent; const index = parent.children.indexOf(this);
    this.remove(); parent.children.splice(index, 0, child); child.parent = parent; }
}
const layers = Object.fromEntries(['overlay', 'tab-controls', 'grid-controls'].map(id => [id, new Element()]));
const context = {document: {getElementById: id => layers[id], createElement: () => new Element(),
  createElementNS: () => new Element(), addEventListener() {} }};
vm.createContext(context);
const html = fs.readFileSync(path.join(__dirname, '../resources/EditorInteractionOverlay.html'), 'utf8');
vm.runInContext(html.match(/<script>([\s\S]*?)<\/script>/)[1], context);
const data = {width: 300, height: 200, rootId: 'root', surfaceBounds: [-14, -14, 328, 228],
  components: [{id: 'a', x: 10, y: 10, width: 50, height: 20, selected: false},
    {id: 'b', x: 70, y: 10, width: 50, height: 20, selected: false}],
  gridEditor: {revision: 1, activeGridId: 'grid', outerBounds: [0, 0, 300, 200],
    innerBounds: [0, 0, 300, 200], editable: true, geometryAvailable: true,
    rowTracks: [{index: 1, bounds: [0, 0, 300, 200], editable: true}], columnTracks: [],
    children: [{id: 'a', bounds: [10, 10, 50, 20], selected: false, editable: true}]}};
const listeners = {};
const component = {Data: structuredClone(data), addEventListener(name, callback) { listeners[name] = callback; }};
context.setup(component);
component.Data = structuredClone(data);
component.Data.gridEditor.revision = 0;
listeners.DataChanged({});
assert.equal(context.currentData.gridEditor.revision, 1, 'initial setup also establishes the accepted revision');
const outline = context.outlineNodes.get('a').node;
const header = context.gridTrackHost.children.find(node => node.className === 'track-settings');
let opened;
context.openTrackPopover = (_, grid) => { opened = grid.revision; };
component.Data = structuredClone(data);
component.Data.gridEditor.revision = 2;
component.Data.components[0].selected = true;
component.Data.gridEditor.children[0].selected = true;
listeners.DataChanged({});
assert.equal(context.outlineNodes.get('a').node, outline);
assert.equal(outline.classList.contains('selected'), true);
assert.equal(context.gridTrackHost.children.find(node => node.className === 'track-settings'), header);
header.listeners.click({stopPropagation() {}});
assert.equal(opened, 2, 'retained event closures use the latest accepted revision');
component.Data = structuredClone(data); // An obsolete native publication must not replace newer selection.
listeners.DataChanged({});
assert.equal(context.currentData.gridEditor.revision, 2);
assert.equal(outline.classList.contains('selected'), true);
component.Data = structuredClone(context.currentData);
component.Data.gridEditor.revision = 3;
component.Data.components[0].width = 60;
component.Data.components.pop();
listeners.DataChanged({});
assert.notEqual(context.outlineNodes.get('a').node, outline);
assert.equal(context.outlineNodes.has('b'), false);
assert.equal(outline.parent, null);
console.log('Diff rendering preserves controls, updates bindings, removes nodes, and rejects stale publications.');
