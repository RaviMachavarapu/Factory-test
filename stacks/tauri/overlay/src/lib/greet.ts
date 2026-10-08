// __NAME__ — tauri stack pack overlay (REQ-303/304).
export function greeting(name: string): string {
  const trimmed = name.trim();
  return trimmed.length > 0 ? `Hello, ${trimmed}!` : "Hello, friend!";
}
