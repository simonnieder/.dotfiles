import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

type Preset = {
  provider: string;
  model: string;
  thinking: "medium" | "high" | "max";
  label: string;
};

const LUNA_HIGH: Preset = {
  provider: "openai-codex",
  model: "gpt-5.6-luna",
  thinking: "high",
  label: "Luna 5.6 · high",
};

const SOL_MEDIUM: Preset = {
  provider: "openai-codex",
  model: "gpt-5.6-sol",
  thinking: "medium",
  label: "Sol 5.6 · medium",
};

const DEEPSEEK_V4_FLASH_FREE: Preset = {
  provider: "opencode",
  model: "deepseek-v4-flash-free",
  thinking: "high",
  label: "DeepSeek V4 Flash · free",
};

const GLM_53_FLASH_MAX: Preset = {
  provider: "opencode-go",
  model: "glm-5.3-flash",
  thinking: "max",
  label: "GLM 5.3 Flash · max",
};

const PRESETS: readonly Preset[] = [
  LUNA_HIGH,
  SOL_MEDIUM,
  DEEPSEEK_V4_FLASH_FREE,
  GLM_53_FLASH_MAX,
];

export default function modelSwitcher(pi: ExtensionAPI) {
  let applying = false;

  async function apply(preset: Preset, ctx: ExtensionContext, notify = true) {
    const model = ctx.modelRegistry.find(preset.provider, preset.model);
    if (!model) {
      ctx.ui.notify(`Model unavailable: ${preset.provider}/${preset.model}`, "error");
      return;
    }

    applying = true;
    try {
      if (!(await pi.setModel(model))) {
        ctx.ui.notify(`No credentials for ${preset.label}`, "error");
        return;
      }
      pi.setThinkingLevel(preset.thinking);
      if (notify) ctx.ui.notify(`Switched to ${preset.label}`, "info");
    } finally {
      applying = false;
    }
  }

  pi.registerShortcut("ctrl+p", {
    description: "Switch model and apply its default thinking level",
    handler: (ctx) => {
      const currentIndex = PRESETS.findIndex(
        (preset) => preset.provider === ctx.model?.provider && preset.model === ctx.model?.id,
      );
      const next = PRESETS[(currentIndex + 1) % PRESETS.length];
      return apply(next, ctx);
    },
  });

  pi.on("session_start", async (_event, ctx) => {
    const preset = PRESETS.find(
      (candidate) => candidate.provider === ctx.model?.provider && candidate.model === ctx.model?.id,
    ) ?? SOL_MEDIUM;
    await apply(preset, ctx, false);
  });

  pi.on("model_select", async (event, ctx) => {
    if (applying) return;
    const preset = PRESETS.find(
      (candidate) => candidate.provider === event.model.provider && candidate.model === event.model.id,
    );
    if (preset) {
      pi.setThinkingLevel(preset.thinking);
    } else {
      await apply(SOL_MEDIUM, ctx);
    }
  });

}
