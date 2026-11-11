import { afterEach, describe, expect, it, vi } from "vitest";
import { copyText } from "./copyText";

describe("copyText", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it("prefers the async clipboard when the context is secure", async () => {
    const writeText = vi.fn(async () => {});
    vi.stubGlobal("navigator", { clipboard: { writeText } });
    await copyText("secret");
    expect(writeText).toHaveBeenCalledWith("secret");
  });

  // navigator.clipboard is missing over plain http on a LAN address, so the
  // console falls back to a hidden textarea plus execCommand.
  it("falls back to execCommand when the clipboard API is absent", async () => {
    vi.stubGlobal("navigator", {});
    const execCommand = vi.fn(() => true);
    const original = document.execCommand;
    document.execCommand = execCommand;
    try {
      await copyText("secret");
    } finally {
      document.execCommand = original;
    }
    expect(execCommand).toHaveBeenCalledWith("copy");
    expect(document.querySelector("textarea")).toBeNull();
  });

  it("surfaces a readable error when every copy path fails", async () => {
    vi.stubGlobal("navigator", {});
    const original = document.execCommand;
    document.execCommand = () => false;
    try {
      await expect(copyText("secret")).rejects.toThrow("复制失败");
    } finally {
      document.execCommand = original;
    }
    expect(document.querySelector("textarea")).toBeNull();
  });
});
