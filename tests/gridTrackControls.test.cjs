// Keep grid settings reachable outside the actual-size figure, including after shrinking it.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const html = fs.readFileSync(path.join(__dirname, '../resources/EditorInteractionOverlay.html'), 'utf8');
const context = {};
vm.createContext(context);
vm.runInContext(html.match(/<script>([\s\S]*?)<\/script>/)[1], context);
const openTrackPopover = context.openTrackPopover;
const controls = {children: [], clientWidth: 320, clientHeight: 240,
  appendChild(child) { this.children.push(child); }};
context.document = {
  getElementById: () => controls,
  createElement: () => ({style: {}, dataset: {}, attributes: {}, listeners: {},
    setAttribute(key, value) { this.attributes[key] = value; },
    addEventListener(name, listener) { this.listeners[name] = listener; }})
};
function grid(bounds) {
  const [x, y, width, height] = bounds;
  return {activeGridId: 'grid', outerBounds: bounds, innerBounds: bounds,
    editable: true, geometryAvailable: true, children: [],
    rowTracks: [y + height / 2, y].map((bottom, i) => ({index: i + 1,
      editable: true, bounds: [x, bottom, width, height / 2]})),
    columnTracks: [x, x + width / 2].map((left, i) => ({index: i + 1,
      editable: true, bounds: [left, y, width / 2, height]}))};
}
for (const scenario of [
  {width: 640, height: 480, bounds: [0, 0, 640, 480], surface: [-14, -14, 668, 508]},
  {width: 640, height: 480, bounds: [0, 50, 200, 180], surface: [-14, -14, 668, 508]},
  {width: 320, height: 240, bounds: [800, 600, 300, 200], surface: [0, 0, 1114, 814]}
]) {
  context.currentData = {width: scenario.width, height: scenario.height,
    surfaceBounds: scenario.surface};
  controls.children = [];
  const opened = [];
  context.openTrackPopover = (header, data, axis, track) => opened.push([axis, track.index]);
  context.renderGridEditor(grid(scenario.bounds));
  const headers = controls.children.filter(child => child.className === 'track-settings');
  assert.equal(headers.length, 4, 'both row and column settings must be present');
  for (const header of headers) {
    const left = Number.parseFloat(header.style.left);
    const top = Number.parseFloat(header.style.top);
    const [x, y, width, height] = scenario.surface;
    assert.ok(left >= x && left + 12 <= x + width);
    assert.ok(top >= scenario.height - y - height && top + 12 <= scenario.height - y);
    if (header.dataset.axis === 'row') {
      assert.equal(left, scenario.bounds[0] - 12);
    } else {
      assert.equal(top, scenario.height - scenario.bounds[1] - scenario.bounds[3] - 12);
    }
    header.listeners.click({stopPropagation() {}});
  }
  assert.deepEqual(opened, [['row', 1], ['row', 2], ['column', 1], ['column', 2]]);
}
// A popup for a stranded grid stays near its header instead of being clamped into the figure.
context.currentData = {width: 320, height: 240, surfaceBounds: [0, 0, 1114, 814]};
const popup = {offsetWidth: 244, offsetHeight: 200, style: {}};
context.placeTrackPopover({offsetLeft: 944, offsetTop: -572, offsetHeight: 12}, popup);
assert.ok(Number.parseFloat(popup.style.left) > 320);
assert.ok(Number.parseFloat(popup.style.top) < 0);
assert.ok(Number.parseFloat(popup.style.top) >= -570);

// Verify the available operations and emitted requests instead of source spellings.
function popupElement(tag) {
  return {tag, children: [], listeners: {}, style: {}, offsetWidth: 244, offsetHeight: 200,
    appendChild(child) {
      this.children.push(child);
      child.parent = this;
      if (child.selected) this.value = child.value;
    },
    addEventListener(name, listener) { this.listeners[name] = listener; },
    remove() { this.parent.children = this.parent.children.filter(child => child !== this); },
    focus() {}};
}
function descendants(element) {
  return [element, ...element.children.flatMap(descendants)];
}
const popupHost = popupElement('div');
context.document = {
  createElement: popupElement,
  getElementById: id => id === 'grid-controls' ? popupHost :
    descendants(popupHost).find(element => element.id === id)
};
const requests = [];
context.component = {sendEventToMATLAB(name, data) { requests.push({name, ...data}); }};
context.openTrackPopover = openTrackPopover;
for (const axis of ['row', 'column']) {
  const labels = axis === 'row' ?
    ['Insert Row Above', 'Insert Row Below', 'Delete Row', 'Cancel', 'Apply'] :
    ['Insert Column Left', 'Insert Column Right', 'Delete Column', 'Cancel', 'Apply'];
  for (const [buttonIndex, action, index] of [[0, 'insert-track', 2],
    [1, 'insert-track', 3], [2, 'delete-track', 2]]) {
    context.openTrackPopover({offsetLeft: 30, offsetTop: 20, offsetHeight: 12},
      {revision: 17, activeGridId: 'owned-grid'}, axis, {index: 2, kind: 'fixed', value: 50});
    const buttons = descendants(popupHost).filter(element => element.tag === 'button');
    assert.deepEqual(buttons.map(button => button.textContent), labels,
      'track controls offer insertion and deletion, without reordering commands');
    buttons[buttonIndex].listeners.click();
    assert.deepEqual(requests.at(-1), {name: 'GridAction', action, revision: 17,
      activeGridId: 'owned-grid', axis, index, fromIndex: 2, mode: 'fit', value: 0});
    assert.equal(popupHost.children.length, 0, 'an accepted action closes its popup');
  }
}
console.log('Grid settings outside the actual-size figure passed.');
