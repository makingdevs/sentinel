const clamp = value => Math.max(0, Math.min(1, value))

export function videoRect(width, height, videoWidth, videoHeight) {
  const ratio = videoWidth > 0 && videoHeight > 0 ? videoWidth / videoHeight : width / height
  const w = Math.min(width, height * ratio)
  const h = w / ratio
  return {x: (width - w) / 2, y: (height - h) / 2, width: w, height: h}
}

export function moveLine(line, dx, dy) {
  dx = Math.max(-Math.min(line.x1, line.x2), Math.min(1 - Math.max(line.x1, line.x2), dx))
  dy = Math.max(-Math.min(line.y1, line.y2), Math.min(1 - Math.max(line.y1, line.y2), dy))
  return {x1: line.x1 + dx, y1: line.y1 + dy, x2: line.x2 + dx, y2: line.y2 + dy}
}

export const CountingLine = {
  mounted() {
    this.video = document.getElementById(this.el.dataset.videoId)
    this.svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
    this.svg.setAttribute("viewBox", "0 0 1000 1000")
    this.svg.setAttribute("preserveAspectRatio", "none")
    this.svg.style.cssText = "position:absolute;pointer-events:auto;touch-action:none;cursor:crosshair"
    this.svg.innerHTML = '<line data-part="line" stroke="#5eead4" stroke-width="5" vector-effect="non-scaling-stroke"/><circle data-part="start" r="12" fill="#5eead4" stroke="#020617" stroke-width="3"/><circle data-part="end" r="12" fill="#fbbf24" stroke="#020617" stroke-width="3"/>'
    this.el.append(this.svg)
    this.resize = () => {
      const rect = videoRect(this.el.clientWidth, this.el.clientHeight, this.video?.videoWidth, this.video?.videoHeight)
      Object.assign(this.svg.style, {left: `${rect.x}px`, top: `${rect.y}px`, width: `${rect.width}px`, height: `${rect.height}px`})
    }
    this.observer = new ResizeObserver(this.resize)
    this.observer.observe(this.el)
    this.video?.addEventListener("loadedmetadata", this.resize)
    this.down = event => {
      event.preventDefault()
      this.svg.setPointerCapture(event.pointerId)
      this.start = this.point(event)
      this.original = {...this.line}
      this.mode = event.target.dataset.part || "draw"
      if (this.mode === "draw") this.line = {x1: this.start.x, y1: this.start.y, x2: this.start.x, y2: this.start.y}
      this.paint()
    }
    this.move = event => {
      if (!this.mode) return
      const p = this.point(event)
      if (this.mode === "line") this.line = moveLine(this.original, p.x - this.start.x, p.y - this.start.y)
      else if (this.mode === "start") Object.assign(this.line, {x1: p.x, y1: p.y})
      else Object.assign(this.line, {x2: p.x, y2: p.y})
      this.paint()
    }
    this.up = event => {
      if (!this.mode) return
      this.move(event)
      this.mode = null
      this.pushEvent("line", {id: this.el.dataset.cameraId, line: this.line})
    }
    this.svg.addEventListener("pointerdown", this.down)
    this.svg.addEventListener("pointermove", this.move)
    this.svg.addEventListener("pointerup", this.up)
    this.svg.addEventListener("pointercancel", () => { this.mode = null })
    this.updated()
    this.resize()
  },
  point(event) {
    const r = this.svg.getBoundingClientRect()
    return {x: clamp((event.clientX - r.left) / r.width), y: clamp((event.clientY - r.top) / r.height)}
  },
  updated() {
    if (!this.mode) {
      this.line = Object.fromEntries(["x1", "y1", "x2", "y2"].map(key => [key, Number(this.el.dataset[key])]))
      this.paint()
    }
  },
  paint() {
    const l = this.line
    const segment = this.svg.querySelector("line")
    for (const key of ["x1", "y1", "x2", "y2"]) segment.setAttribute(key, l[key] * 1000)
    const start = this.svg.querySelector('[data-part="start"]')
    const end = this.svg.querySelector('[data-part="end"]')
    for (const [circle, x, y] of [[start, l.x1, l.y1], [end, l.x2, l.y2]]) {
      circle.setAttribute("cx", x * 1000)
      circle.setAttribute("cy", y * 1000)
    }
  },
  destroyed() {
    this.observer.disconnect()
    this.video?.removeEventListener("loadedmetadata", this.resize)
  },
}
