import { createHash } from "node:crypto";
import { spawn } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const hooksDir = resolve(root, "hooks");

type HookPayload = {
  assistant_response?: string;
  cwd: string;
  prompt?: string;
  session_id: string;
};

function sessionID(ctx: ExtensionContext): string {
  const raw = ctx.sessionManager.getSessionId() ?? "unknown";
  return createHash("sha256").update(raw).digest("hex");
}

function payload(ctx: ExtensionContext, extra: Partial<HookPayload> = {}): HookPayload {
  return { cwd: ctx.cwd, session_id: sessionID(ctx), ...extra };
}

async function runHook(name: string, input: HookPayload): Promise<string> {
  return new Promise((resolveOutput) => {
    const child = spawn("bash", [resolve(hooksDir, name)], {
      cwd: root,
      env: {
        ...process.env,
        AI_AGENTS_SKILLS_ROOT: root,
        PRIME_AGENT_ROOT: root,
      },
      stdio: ["pipe", "pipe", "ignore"],
    });
    const output: Buffer[] = [];

    child.stdout.on("data", (chunk: Buffer) => output.push(chunk));
    child.once("error", () => resolveOutput(""));
    child.once("close", () => resolveOutput(Buffer.concat(output).toString("utf8")));
    child.stdin.end(JSON.stringify(input));
  });
}

function hookContext(output: string): string {
  try {
    const parsed = JSON.parse(output) as {
      hookSpecificOutput?: { additionalContext?: unknown };
    };
    const context = parsed.hookSpecificOutput?.additionalContext;
    return typeof context === "string" ? context : "";
  } catch {
    return "";
  }
}

function textFromMessage(message: unknown): string {
  if (!message || typeof message !== "object") return "";
  const candidate = message as { content?: unknown; role?: unknown };
  if (candidate.role !== "assistant") return "";
  if (typeof candidate.content === "string") return candidate.content;
  if (!Array.isArray(candidate.content)) return "";

  return candidate.content
    .flatMap((block) => {
      if (!block || typeof block !== "object") return [];
      const value = block as { text?: unknown; type?: unknown };
      return value.type === "text" && typeof value.text === "string" ? [value.text] : [];
    })
    .join("\n");
}

function lastAssistantResponse(messages: unknown[]): string {
  for (let index = messages.length - 1; index >= 0; index -= 1) {
    const text = textFromMessage(messages[index]);
    if (text) return text;
  }
  return "";
}

/**
 * Prime Agent adapter for the shared skills tree.
 *
 * Prime Agent does not have Claude's Notification/PermissionRequest hooks, so
 * delayed "needs attention" notices intentionally degrade. The shared task-start,
 * cancellation, completion, abbreviation, and model-tier behavior is preserved.
 */
export default function (pi: ExtensionAPI): void {
  let sessionContext = "";
  let contextDelivered = false;

  pi.on("session_start", async (_event, ctx) => {
    const input = payload(ctx);
    const outputs = await Promise.all([
      runHook("abbr-inject.sh", input),
      runHook("model-tiers-inject.sh", input),
    ]);
    sessionContext = outputs.map(hookContext).filter(Boolean).join("\n\n");
    contextDelivered = false;
  });

  pi.on("before_agent_start", async (event, ctx) => {
    await runHook("tg-prompt-start.sh", payload(ctx, { prompt: event.prompt }));
    if (!sessionContext || contextDelivered) return;
    contextDelivered = true;
    return {
      message: {
        customType: "ai-agents-skills:session-context",
        content: sessionContext,
        display: false,
      },
    };
  });

  pi.on("tool_execution_start", async (_event, ctx) => {
    await runHook("tg-cancel-pending.sh", payload(ctx));
  });

  pi.on("agent_end", async (event, ctx) => {
    await runHook(
      "tg-on-stop.sh",
      payload(ctx, { assistant_response: lastAssistantResponse(event.messages) }),
    );
  });

  pi.on("session_shutdown", async (_event, ctx) => {
    await runHook("tg-cancel-pending.sh", payload(ctx));
  });
}
