// Exercise the shipped overlay functions without requiring a MATLAB window.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const html = fs.readFileSync(path.join(__dirname, '../resources/EditorInteractionOverlay.html'), 'utf8');
const context = {};
vm.createContext(context);
vm.runInContext(html.match(/<script>([\s\S]*?)<\/script>/)[1], context);
context.currentData.height = 400;
context.document = {
  getElementById: () => ({getBoundingClientRect: () => ({left: 0, top: 0, height: 400}), appendChild() {}}),
  createElement: () => ({style: {}}),
  addEventListener() {}
};
const data = {
  editable: true, geometryAvailable: true,
  rowTracks: [300, 190, 80].map((y, i) => ({index: i + 1, bounds: [0, y, 320, 100]})),
  columnTracks: [0, 110, 220].map((x, i) => ({index: i + 1, bounds: [x, 80, 100, 320]}))
};
const child = {editable: true, rowStart: 1, rowEnd: 2, columnStart: 1, columnEnd: 2};
function start(kind, x, y) {
  context.gridGesture = null;
  context.beginGridChildGesture({clientX: x, clientY: 400 - y, preventDefault() {}, stopPropagation() {}}, data, child, kind);
  assert.ok(context.gridGesture, `${kind} must start on a handle outside a cell`);
  return context.gridGesture;
}
// Both sides of a handle and a handle centered in a perpendicular gap must start.
for (const x of [208, 210, 212]) start('right', x, 295);
start('bottom', 105, 188);
for (const [kind, axis, field, origin, outward] of [
  ['right', 'x', 'columnEnd', [212, 295], 1],
  ['bottom', 'y', 'rowEnd', [105, 188], -1]
]) {
  const gesture = start(kind, ...origin);
  for (const direction of [-1, 1]) {
    const point = {x: origin[0], y: origin[1]};
    point[axis] += direction * outward * 54;
    assert.equal(context.candidateGridSpan(gesture, point)[field], 2);
    point[axis] += direction * outward * 2;
    assert.equal(context.candidateGridSpan(gesture, point)[field], 2 + direction);
  }
}
const corner = start('bottom-right', 212, 188);
assert.equal(context.candidateGridSpan(corner, {x: 268, y: 132}).columnEnd, 3);
assert.equal(context.candidateGridSpan(corner, {x: 268, y: 132}).rowEnd, 3);
const innerChild = {...child, rowStart: 2, rowEnd: 3, columnStart: 2, columnEnd: 3};
for (const [kind, axis, field, outward] of [
  ['left', 'x', 'columnStart', -1], ['top', 'y', 'rowStart', 1]
]) {
  const gesture = {data, child: innerChild, kind, startPoint: {x: 108, y: 292}};
  for (const direction of [-1, 1]) {
    const point = {...gesture.startPoint};
    point[axis] += direction * outward * 54;
    assert.equal(context.candidateGridSpan(gesture, point)[field], 2);
    point[axis] += direction * outward * 2;
    assert.equal(context.candidateGridSpan(gesture, point)[field], 2 - direction);
  }
}
console.log('Grid resize gestures: gap starts, symmetric thresholds and corner resizing passed.');
