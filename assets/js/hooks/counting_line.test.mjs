import test from "node:test"
import assert from "node:assert/strict"
import {videoRect, moveLine} from "./counting_line.mjs"

test("normalization uses video content, excluding letterbox/pillarbox", () => {
  assert.deepEqual(videoRect(1600, 900, 640, 480), {x: 200, y: 0, width: 1200, height: 900})
  assert.deepEqual(videoRect(100, 100, 200, 100), {x: 0, y: 25, width: 100, height: 50})
})

test("moving a line preserves shape and clamps both endpoints together", () => {
  const line = {x1: 0.1, y1: 0.5, x2: 0.9, y2: 0.5}
  const moved = moveLine(line, 0.5, -0.7)
  assert.ok(Math.abs(moved.x1 - 0.2) < 1e-10)
  assert.equal(moved.x2, 1)
  assert.equal(moved.y1, 0)
  assert.equal(moved.y2, 0)
  assert.deepEqual(line, {x1: 0.1, y1: 0.5, x2: 0.9, y2: 0.5})
})
