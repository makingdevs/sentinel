// The player owns only its ignored container. Replacing the container runs
// destroyed() so changing one camera never reinitializes its neighbours.
export function createHlsPlayer(Hls, schedule = setTimeout, cancel = clearTimeout) {
  return {
    mounted() {
      this.video = this.el.querySelector("video")
      this.status = this.el.querySelector("[data-player-status]")
      this.disposed = false
      this.retryTimer = null
      this.listeners = []
      const listen = (name, callback) => {
        this.video.addEventListener(name, callback)
        this.listeners.push([name, callback])
      }
      this.setStatus = message => {
        this.status.textContent = message
        this.status.hidden = !message
      }
      listen("playing", () => this.setStatus(""))
      listen("waiting", () => this.setStatus("Cargando video…"))
      listen("stalled", () => this.setStatus("Esperando datos de la cámara…"))
      listen("error", () => this.retry())
      this.video.muted = true
      this.open()
    },

    open() {
      if (this.disposed) return
      this.setStatus("Conectando con la cámara…")
      const source = this.el.dataset.source
      if (Hls.isSupported()) {
        this.hls = new Hls({manifestLoadingMaxRetry: 2, levelLoadingMaxRetry: 2})
        this.hls.on(Hls.Events.ERROR, (_event, data) => {
          if (["manifestIncompatibleCodecsError", "bufferAddCodecError"].includes(data.details)) {
            this.setStatus("El códec de esta cámara no es compatible con el navegador. Configura una salida H.264.")
            this.hls.destroy()
            this.hls = null
          } else if (data.fatal) {
            this.retry()
          }
        })
        this.hls.loadSource(source)
        this.hls.attachMedia(this.video)
      } else if (this.video.canPlayType("application/vnd.apple.mpegurl")) {
        this.video.src = source
      } else {
        this.setStatus("Este navegador no admite la reproducción HLS.")
        return
      }
      this.play()
    },

    play() {
      const promise = this.video.play()
      if (promise?.catch) promise.catch(() => {
        if (!this.disposed && this.retryTimer === null) this.setStatus("Pulsa reproducir para iniciar el video.")
      })
    },

    retry() {
      if (this.disposed || this.retryTimer !== null) return
      this.setStatus("No se recibe video. Reintentando…")
      this.retryTimer = schedule(() => {
        this.retryTimer = null
        this.open()
      }, 3000)
      if (this.hls) { this.hls.destroy(); this.hls = null }
      this.video.pause()
      this.video.removeAttribute("src")
      this.video.load()
    },

    destroyed() {
      this.disposed = true
      if (this.retryTimer !== null) cancel(this.retryTimer)
      this.listeners.forEach(([name, callback]) => this.video.removeEventListener(name, callback))
      if (this.hls) this.hls.destroy()
      this.video.pause()
      this.video.removeAttribute("src")
      this.video.load()
    },
  }
}
