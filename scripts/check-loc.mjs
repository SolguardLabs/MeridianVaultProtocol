import { readFileSync } from "node:fs";
import { publicFiles } from "./tracked-files.mjs";

let nonblank = 0;
for (const file of publicFiles()) {
  nonblank += readFileSync(file, "utf8")
    .split(/\r?\n/u)
    .filter((line) => line.trim().length > 0).length;
}

const minimum = 5_500;
if (nonblank < minimum) {
  throw new Error(`Expected at least ${minimum} nonblank public lines, received ${nonblank}`);
}
process.stdout.write(`Public nonblank LOC: ${nonblank}\n`);
