import { execFileSync } from "node:child_process";
import { extname } from "node:path";

const binaryExtensions = new Set([
  ".png",
  ".jpg",
  ".jpeg",
  ".gif",
  ".webp",
  ".ico",
  ".pdf",
  ".zip",
  ".gz",
  ".tgz",
]);

export function publicFiles() {
  const output = execFileSync("git", ["ls-files", "-co", "--exclude-standard", "-z"]);
  return [...new Set(output.toString("utf8").split("\0").filter(Boolean))].filter(
    (file) => !binaryExtensions.has(extname(file).toLowerCase()),
  );
}
