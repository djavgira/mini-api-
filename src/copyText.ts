// navigator.clipboard is only defined in secure contexts (https / localhost).
// Over plain http on a LAN address the console must still be able to copy, so
// fall back to a hidden textarea plus execCommand, which works in insecure
// contexts as long as the call happens inside a user gesture.
export async function copyText(text: string): Promise<void> {
  const clipboard = globalThis.navigator?.clipboard;
  if (typeof clipboard?.writeText === "function") {
    try {
      await clipboard.writeText(text);
      return;
    } catch {
      // Permission or focus problems fall through to the legacy path.
    }
  }
  const area = document.createElement("textarea");
  area.value = text;
  area.setAttribute("readonly", "");
  area.style.position = "fixed";
  area.style.top = "-1000px";
  area.style.opacity = "0";
  document.body.appendChild(area);
  try {
    area.select();
    area.setSelectionRange(0, area.value.length);
    if (!document.execCommand("copy")) throw new Error("复制失败，请手动选择文本复制。");
  } finally {
    document.body.removeChild(area);
  }
}
