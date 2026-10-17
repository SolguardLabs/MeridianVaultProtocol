import { readFileSync } from "node:fs";
import { publicFiles } from "./tracked-files.mjs";

const forbidden = [
  { label: "challenge marker", pattern: /\bctf\b/iu },
  { label: "training marker", pattern: /laboratori/iu },
  { label: "private proof marker", pattern: /private[-_ ]proof/iu },
  { label: "private solution path", pattern: /solutions?[\\/]/iu },
];

const findings = [];
for (const file of publicFiles()) {
  if (file === "scripts/scan-public.mjs") continue;
  const content = readFileSync(file, "utf8");
  for (const rule of forbidden) {
    if (rule.pattern.test(content)) findings.push(`${file}: ${rule.label}`);
  }
}

if (findings.length > 0) {
  throw new Error(`Public surface scan failed:\n${findings.join("\n")}`);
}
process.stdout.write(`Public surface scan passed across ${publicFiles().length} text files.\n`);
