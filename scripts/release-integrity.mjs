import { existsSync, readFileSync, statSync } from "node:fs";

const pkg = JSON.parse(readFileSync("package.json", "utf8"));
const required = [
  "README.md",
  "SECURITY.md",
  "CHANGELOG.md",
  "CONTRIBUTING.md",
  "assets/banner.png",
  "docs/arquitectura.md",
  "docs/modelo-economico.md",
  "docs/riesgo-y-capital.md",
  "docs/operacion.md",
  "docs/integracion.md",
];

if (pkg.version !== "1.0.0") throw new Error(`Unexpected package version: ${pkg.version}`);
for (const path of required) {
  if (!existsSync(path) || statSync(path).size === 0)
    throw new Error(`Missing release asset: ${path}`);
}

const readme = readFileSync("README.md", "utf8");
const workflow = readFileSync(".github/workflows/ci.yml", "utf8");
if (!readme.includes("![MeridianVaultProtocol](./assets/banner.png)")) {
  throw new Error("README banner reference is missing");
}
for (const marker of ["production", "release/**", "v*", "windows-latest", "ubuntu-latest"]) {
  if (!workflow.includes(marker)) throw new Error(`CI workflow marker missing: ${marker}`);
}
process.stdout.write("Release integrity: Production 1.0.0 ready.\n");
