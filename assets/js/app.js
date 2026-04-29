// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/share_circle"
import topbar from "../vendor/topbar"

// Manages browser push notification subscription.
// Attach with phx-hook="PushNotifications" data-vapid-key="<base64url key>".
const PushNotifications = {
  async mounted() {
    const vapidKey = this.el.dataset.vapidKey
    if (!vapidKey || !("serviceWorker" in navigator) || !("PushManager" in window)) return

    // Check existing subscription and notify LiveView
    try {
      const reg = await navigator.serviceWorker.ready
      const existing = await reg.pushManager.getSubscription()
      if (existing) this.pushEvent("push_already_subscribed", {})
    } catch (_) {}

    // Wire the subscribe button (present only when not yet subscribed)
    const btn = this.el.querySelector("[data-push-subscribe]")
    if (btn) btn.addEventListener("click", () => this._subscribe(vapidKey))
  },

  updated() {
    // Re-wire after LiveView re-renders (button may have re-appeared).
    // Replace the node to drop any previous listeners before adding a new one.
    const vapidKey = this.el.dataset.vapidKey
    const btn = this.el.querySelector("[data-push-subscribe]")
    if (btn && vapidKey) {
      const fresh = btn.cloneNode(true)
      btn.replaceWith(fresh)
      fresh.addEventListener("click", () => this._subscribe(vapidKey))
    }
  },

  async _subscribe(vapidKey) {
    try {
      const permission = await Notification.requestPermission()
      if (permission !== "granted") return

      const reg = await navigator.serviceWorker.ready
      const sub = await reg.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(vapidKey)
      })
      const json = sub.toJSON()
      this.pushEvent("push_subscribed", {
        endpoint: json.endpoint,
        p256dh_key: json.keys.p256dh,
        auth_key: json.keys.auth
      })
    } catch (err) {
      console.error("Push subscribe failed:", err)
    }
  }
}

function urlBase64ToUint8Array(base64String) {
  const padding = "=".repeat((4 - base64String.length % 4) % 4)
  const base64 = (base64String + padding).replace(/-/g, "+").replace(/_/g, "/")
  const raw = window.atob(base64)
  return Uint8Array.from([...raw].map(c => c.charCodeAt(0)))
}

// Scrolls a container to the bottom on mount and whenever new content is added.
// Attach with phx-hook="ScrollBottom" on the scrollable container.
const ScrollBottom = {
  mounted() { this.scrollToBottom() },
  updated() {
    // Only scroll if already near the bottom (within 200px) to avoid
    // hijacking scroll position when the user is reading older messages.
    const el = this.el
    const nearBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 200
    if (nearBottom) this.scrollToBottom()
  },
  scrollToBottom() {
    this.el.scrollTop = this.el.scrollHeight
  }
}

// External uploader: PUTs directly to a presigned URL (local-blob or S3)
const Uploaders = {
  PresignedPut: function(entries, onViewError) {
    entries.forEach(entry => {
      const {url, headers} = entry.meta
      const xhr = new XMLHttpRequest()
      onViewError(() => xhr.abort())
      // Only signal 100% (done) after the server confirms receipt (onload).
      // The upload progress event fires when bytes leave the client, which can
      // race ahead of the server actually writing the file to storage.
      xhr.onload = () => (xhr.status >= 200 && xhr.status < 300) ? entry.progress(100) : entry.error()
      xhr.onerror = () => entry.error()
      xhr.upload.addEventListener("progress", e => {
        if (e.lengthComputable) entry.progress(Math.min(Math.round((e.loaded / e.total) * 100), 99))
      })
      xhr.open("PUT", url, true)
      if (headers) Object.entries(headers).forEach(([k, v]) => xhr.setRequestHeader(k, v))
      xhr.send(entry.file)
    })
  }
}

// Submits the closest form when Ctrl+Enter or Cmd+Enter is pressed.
// Attach with phx-hook="CtrlEnterSubmit" on a textarea or input.
const CtrlEnterSubmit = {
  mounted() {
    this.handler = (e) => {
      if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) {
        e.preventDefault()
        this.el.closest("form")?.requestSubmit()
      }
    }
    this.el.addEventListener("keydown", this.handler)
  },
  destroyed() {
    this.el.removeEventListener("keydown", this.handler)
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ScrollBottom, PushNotifications, CtrlEnterSubmit},
  uploaders: Uploaders,
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

window.addEventListener("phx:clear-message-input", () => {
  const el = document.getElementById("message-input")
  if (el) { el.value = ""; el.focus() }
})

if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("/sw.js").catch(err => console.error("SW registration failed:", err))
}

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

