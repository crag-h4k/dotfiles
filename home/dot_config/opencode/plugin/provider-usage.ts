import { Plugin } from "@opencode/plugin"
import { Rpc } from "@opencode/plugin/rpc"
import { LIMITS_RPC_SCHEMA } from "../v2-plugins/statusline/limits.mjs"
import { setupProviderUsage } from "../v2-plugins/statusline/usage-server.mjs"

export default Plugin.define({
  id: "dotfiles.provider-usage",
  async setup(ctx) {
    const registration = await setupProviderUsage(ctx, Rpc.define(LIMITS_RPC_SCHEMA))
    return () => registration.dispose()
  },
})
