import { io } from "socket.io-client"

export function initSocket() {
  let siteName = window.site_name || "drive.localhost"

  // Do NOT statically import sites/common_site_config.json here (upstream
  // does): vite externalizes that bench-relative path, so production
  // browsers ESM-import /sites/common_site_config.json -> 404 -> the whole
  // module graph fails (white screen). And do NOT make this async: upstream
  // main.js does app.provide("socket", initSocket()) synchronously, so a
  // Promise here breaks every socket.on() consumer ("p.on is not a
  // function"). In production the socket rides nginx on the same origin
  // (no window.location.port -> no port suffix); in dev the bench default
  // is 9000, overridable via window.socketio_port.
  let default_port = window.socketio_port || "9000"
  let port = window.location.port ? `:${default_port}` : ""
  let protocol = port ? "http" : "https"
  let host = window.location.hostname

  let url = `${protocol}://${host}${port}/${siteName}`
  let socket = io(url, {
    withCredentials: true,
    reconnectionAttempts: 5,
  })
  socket.on("connect_error", (data) => {
    console.log(data)
  })
  return socket
}
