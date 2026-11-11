// Copyright (C) 2026 Nobuto Kaitoh
// SPDX-License-Identifier: GPL-3.0-or-later
// This file is part of yamada. See LICENSE for the license text.

// Exercise cross-container target geometry, overlap, clipped spans, commit and cancellation.
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
const body = {appendChild(node) { node.parentNode = body; }};
context.document = {body, createElement() { return {style: {}, remove() { this.parentNode = null; }}; },
  removeEventListener() {}, querySelectorAll() { return []; }};
context.svg = {getBoundingClientRect: () => ({left: 0, top: 0, height: 300}),
  setPointerCapture() {}, hasPointerCapture: () => false, releasePointerCapture() {}};
const source = {id: 'child', parentId: 'left', bounds: [10, 10, 50, 20], rowSpan: 1, columnSpan: 1};
const right = {id: 'right', name: 'Right', bounds: [220, 0, 200, 300], origin: [222, 2], depth: 1, enabled: true, grid: {}};
context.currentData = {width: 500, height: 300, rootId: 'root', reparentRevision: 4, gridEditor: {revision: 9},
  dragSource: source, reparentTargets: [
    {id: 'root', name: 'Root', bounds: [0, 0, 500, 300], origin: [0, 0], depth: 0, enabled: true, grid: {}},
    {id: 'left', name: 'Left', bounds: [0, 0, 200, 300], origin: [2, 2], depth: 1, enabled: true, grid: {}}, right]};
const gesture = {id: 'child', startPoint: {x: 15, y: 15}, modelRevision: 4};
let candidate = context.dropCandidate(gesture, {x: 250, y: 50});
assert.equal(candidate.parentId, 'right');
assert.deepEqual(Array.from(candidate.targetPosition), [23, 43, 50, 20]);
assert.equal(context.dropCandidate(gesture, {x: 30, y: 30}), null);
right.grid = {geometryAvailable: true, innerBounds: right.bounds,
  rowTracks: [{index: 1, bounds: [220, 150, 200, 150]}, {index: 2, bounds: [220, 0, 200, 150]}],
  columnTracks: [{index: 1, bounds: [220, 0, 100, 300]}, {index: 2, bounds: [320, 0, 100, 300]}], children: []};
candidate = context.dropCandidate(gesture, {x: 350, y: 200});
assert.equal(candidate.enabled, true);
assert.deepEqual(Array.from(candidate.targetCell), [1, 2]);
assert.deepEqual(Array.from(candidate.bounds), [320, 150, 100, 150]);
right.grid.children = [{id: 'other', rowStart: 1, rowEnd: 1, columnStart: 2, columnEnd: 2}];
const overlapping = context.dropCandidate(gesture, {x: 350, y: 200});
assert.equal(overlapping.enabled, true);
assert.deepEqual(Array.from(overlapping.targetCell), [1, 2]);
context.sendReparent('child', overlapping, 4);
assert.equal(sent.pop().data.parentId, 'right');
right.grid.children = [];
source.rowSpan = 2;
source.columnSpan = 2;
const clipped = context.dropCandidate(gesture, {x: 350, y: 50});
assert.equal(clipped.enabled, true);
assert.deepEqual(Array.from(clipped.targetCell), [2, 2]);
assert.deepEqual(Array.from(clipped.bounds), [320, 0, 100, 150]);
right.enabled = false;
const disabled = context.dropCandidate(gesture, {x: 350, y: 50});
assert.equal(disabled.enabled, false);
context.sendReparent('child', disabled, 4);
assert.equal(sent.pop().data.parentId, '');
right.enabled = true;
right.grid.geometryAvailable = false;
assert.equal(context.dropCandidate(gesture, {x: 350, y: 50}).enabled, false);
right.grid.geometryAvailable = true;
source.rowSpan = 1;
source.columnSpan = 1;
function gridGesture() { return {child: {id: 'child'}, draft: {parentNode: null}, reparent: candidate, modelRevision: 4}; }
context.gridGesture = gridGesture();
context.finishGridChildGesture(false);
assert.equal(sent.length, 0);
context.gridGesture = gridGesture();
context.finishGridChildGesture(true);
assert.equal(sent.length, 1);
assert.equal(sent[0].name, 'Reparent');
assert.equal(sent[0].data.parentId, 'right');
assert.equal(sent[0].data.modelRevision, 4);
sent.length = 0;
context.sendReparent('child', candidate, 2);
assert.equal(sent.pop().data.modelRevision, 2);
right.grid = {};
const event = (type, x, y, dataset = {}) => ({type, clientX: x, clientY: 300 - y, pointerId: 1, target: {dataset}});
context.sendPointerEvent(event('pointerdown', 15, 15, {componentId: 'child'}));
context.sendPointerEvent(event('pointermove', 250, 50));
context.sendPointerEvent(event('pointercancel', 250, 50));
assert.equal(context.absoluteGesture, null);
assert.equal(sent[sent.length - 1].data.phase, 'pointercancel');
assert.equal(sent.filter(item => item.name === 'Reparent').length, 0);
sent.length = 0;
context.sendPointerEvent(event('pointerdown', 15, 15, {componentId: 'child'}));
context.sendPointerEvent(event('pointerup', 250, 50));
assert.equal(sent[sent.length - 1].name, 'Reparent');
assert.deepEqual(Array.from(sent[sent.length - 1].data.targetPosition), [23, 43, 50, 20]);
console.log('Cross-container drop geometry, overlap, clipped spans, versioning and cancellation passed.');

// The documented DataChanged contract supplies data on htmlComponent, not on the event.
const listeners = {};
const bridge = {Data: {width: 640, height: 480},
  addEventListener(name, fn) { listeners[name] = fn; }, sendEventToMATLAB() {}};
context.document.addEventListener = () => {};
context.document.getElementById = () => context.svg;
context.svg.addEventListener = () => {};
const frames = [];
context.render = () => frames.push(context.currentData.width);
context.setup(bridge);
assert.equal(frames[0], 640);
bridge.Data = {width: 800, height: 600};
listeners.DataChanged({Data: {width: 1}});
assert.equal(frames[1], 800);
console.log('Initial and changed uihtml data render through the documented component Data contract.');
