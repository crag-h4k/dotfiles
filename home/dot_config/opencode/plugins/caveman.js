// home/dot_config/opencode/plugins/caveman.js
import { readFile, lstat } from "node:fs/promises"
import { homedir } from "node:os"
import { join } from "node:path"
import { Plugin } from "@opencode/plugin"

export async function configure(ctx, home = homedir()) {
  const root = join(home, ".caveman/oc2")
  let config
  try {
    config = JSON.parse(await readFile(join(root, "settings.json"), "utf8"))
  } catch (error) {
    if (error.code === "ENOENT") return
    throw error
  }
  if (config.enabled === false) return
  if (config.enabled !== true) throw new Error("Caveman enabled must be a boolean")
  if (!/^[a-zA-Z0-9_-]+$/.test(config.provider)) throw new Error("Invalid Caveman provider ID")
  const base = new URL(config.url)
  if (!["http:", "https:"].includes(base.protocol) || base.username || base.password || base.search || base.hash) {
    throw new Error("Invalid private Caveman URL")
  }
  const keyPath = join(root, "proxy-token")
  const metadata = await lstat(keyPath)
  if (metadata.isSymbolicLink() || metadata.uid !== process.getuid() || (metadata.mode & 0o077)) throw new Error("Caveman token must be private and owned by you")
  const token = (await readFile(keyPath, "utf8")).trim()
  if (token.length < 16 || /\s/.test(token)) throw new Error("Invalid Caveman proxy token")
  const url = base.href.replace(/\/$/, "")
  const health = await fetch(`${url}/health/ready`, { signal: AbortSignal.timeout(5000), redirect: "error" })
  if (!health.ok) throw new Error("Caveman proxy is not ready")
  await health.body?.cancel()

  await ctx.session.hook("http.request", (event) => {
    const upstream = new URL(event.request.url)
    const route = upstream.pathname.match(/\/v1\/(responses|chat\/completions)$/)
    if (!route) return
    const target = new URL(`${url}/compat/${config.provider}/v1/${route[1]}${upstream.search}`)
    const request = new Request(target, event.request)
    request.headers.set("x-cave-api-key", token)
    event.request = request
  }, { providerID: config.provider })
}

export default Plugin.define({ id: "dotfiles.caveman", setup: configure })
