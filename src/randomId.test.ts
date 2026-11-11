import { describe, expect, it, vi } from "vitest";
import { randomId } from "./randomId";

const uuidV4 = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

describe("randomId", () => {
  it("uses crypto.randomUUID when the browser provides it", () => {
    const randomUUID = vi.fn(() => "11111111-2222-4333-8444-555555555555");
    vi.stubGlobal("crypto", { randomUUID, getRandomValues: undefined });
    expect(randomId()).toBe("11111111-2222-4333-8444-555555555555");
    expect(randomUUID).toHaveBeenCalledOnce();
  });

  // The console is opened over plain http on a LAN address, where
  // crypto.randomUUID is missing but getRandomValues still exists.
  it("builds a v4 UUID from getRandomValues in an insecure context", () => {
    const getRandomValues = vi.fn((bytes: Uint8Array) => {
      for (let index = 0; index < bytes.length; index += 1) bytes[index] = 0xff;
      return bytes;
    });
    vi.stubGlobal("crypto", { randomUUID: undefined, getRandomValues });
    expect(randomId()).toBe("ffffffff-ffff-4fff-bfff-ffffffffffff");
    expect(getRandomValues).toHaveBeenCalledOnce();
  });

  it("keeps producing distinct well-formed identifiers", () => {
    const seen = new Set<string>();
    for (let index = 0; index < 50; index += 1) {
      const id = randomId();
      expect(id).toMatch(uuidV4);
      seen.add(id);
    }
    expect(seen.size).toBe(50);
  });
});
