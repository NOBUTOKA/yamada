// Copyright (C) 2026 Nobuto Kaitoh
// SPDX-License-Identifier: GPL-3.0-or-later
// This file is part of yamada. See LICENSE for the license text.

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const html = fs.readFileSync(path.join(__dirname, '../resources/SourceDiffPreview.html'), 'utf8');
const context = vm.createContext({});
vm.runInContext(html.match(/<script>([\s\S]*?)<\/script>/)[1], context);
const align = (left, right) => Array.from(context.alignedRows(left, right),
  ({ oldLine, newLine, kind }) => [oldLine, newLine, kind]);

test('aligns common lines around additions, deletions, and replacements', () => {
  assert.deepEqual(align(
    ['start', 'deleted', 'middle', 'old value', 'end'],
    ['start', 'middle', 'new value', 'end', 'added']
  ), [
    [0, 0, ''],
    [1, null, 'deleted'],
    [2, 1, ''],
    [3, 2, 'modified'],
    [4, 3, ''],
    [null, 4, 'added']
  ]);
});

test('preserves repeated lines, whitespace, and a final newline', () => {
  const before = context.splitLines('x\r\n\tend\r\nx');
  const after = context.splitLines('x\nnew\n\tend\nx\n');
  assert.deepEqual(align(before, after), [
    [0, 0, ''],
    [null, 1, 'added'],
    [1, 2, ''],
    [2, 3, ''],
    [null, 4, 'added']
  ]);
  assert.deepEqual(align([' x'], ['x']), [[0, 0, 'modified']]);
});

test('handles identical, empty, and entirely replaced source', () => {
  assert.deepEqual(align(['same'], ['same']), [[0, 0, '']]);
  assert.deepEqual(align(context.splitLines(''), ['classdef App', 'end']),
    [[null, 0, 'added'], [null, 1, 'added']]);
  assert.deepEqual(align(['old', 'tail'], ['new']),
    [[0, 0, 'modified'], [1, null, 'deleted']]);
});
