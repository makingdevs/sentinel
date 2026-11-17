import test from "node:test"
import assert from "node:assert/strict"
import {createHlsPlayer} from "./hls_player.mjs"

function mount({supported = true, native = true} = {}) {
  const instances = []
  class FakeHls {
    static Events = {ERROR: "error"}
    static isSupported() { return supported }
    constructor() { this.destroyed = false; instances.push(this) }
    on(_event, callback) { this.onError = callback }
    loadSource(source) { this.source = source }
    attachMedia(video) { this.video = video }
    destroy() { this.destroyed = true }
  }
  const video = new EventTarget()
  Object.assign(video, {
    play: () => Promise.resolve(), pause: () => {}, load: () => {},
    removeAttribute(name) { delete this[name] },
    canPlayType: () => native ? "maybe" : "",
  })
  const status = {textContent: "", hidden: false}
  const timers = new Map()
  let nextTimer = 1
  const hook = Object.assign(createHlsPlayer(FakeHls,
    callback => { const id = nextTimer++; timers.set(id, callback); return id },
    id => timers.delete(id)), {
    el: {dataset: {source: "/hls/division-1/secundaria/index.m3u8"}, querySelector: selector => selector === "video" ? video : status},
  })
  hook.mounted()
  return {hook, video, status, instances, timers}
}

test("players initialize independently and destroying one frees only its resources", () => {
  const first = mount(), second = mount()
  assert.equal(first.instances[0].source, "/hls/division-1/secundaria/index.m3u8")
  assert.equal(first.video.muted, true)
  first.video.dispatchEvent(new Event("playing"))
  assert.equal(first.status.hidden, true)
  first.hook.destroyed()
  assert.equal(first.instances[0].destroyed, true)
  assert.equal(second.instances[0].destroyed, false)
  first.video.dispatchEvent(new Event("waiting"))
  assert.equal(first.status.hidden, true) // listeners were removed
  second.hook.destroyed()
})

test("fatal errors retry once and removing a player cancels the pending retry", () => {
  const player = mount()
  player.instances[0].onError("error", {fatal: true})
  player.hook.retry()
  assert.equal(player.instances[0].destroyed, true)
  assert.equal(player.timers.size, 1)
  const callback = [...player.timers.values()][0]
  player.timers.clear()
  callback()
  assert.equal(player.instances.length, 2)
  player.instances[1].onError("error", {fatal: true})
  player.hook.destroyed()
  assert.equal(player.timers.size, 0)
})

test("native HLS fallback retries initial failures and releases its source on removal", () => {
  const player = mount({supported: false})
  assert.equal(player.video.src, "/hls/division-1/secundaria/index.m3u8")
  player.video.dispatchEvent(new Event("error"))
  assert.equal(player.timers.size, 1)
  player.hook.destroyed()
  assert.equal(player.video.src, undefined)
  assert.equal(player.timers.size, 0)
})

test("unsupported browsers show a useful message", () => {
  const player = mount({supported: false, native: false})
  assert.match(player.status.textContent, /no admite/)
  assert.equal(player.timers.size, 0)
  player.hook.destroyed()
})


test("incompatible codec errors explain the H264 requirement without a retry loop", () => {
  const player = mount()
  player.instances[0].onError("error", {fatal: true, details: "manifestIncompatibleCodecsError"})
  assert.match(player.status.textContent, /H.264/)
  assert.equal(player.instances[0].destroyed, true)
  assert.equal(player.timers.size, 0)
  player.hook.destroyed()
})
