import { spawnSync } from "node:child_process";

function run(command, args) {
  process.stdout.write(`==> ${command} ${args.join(" ")}\n`);
  const result = spawnSync(command, args, { stdio: "inherit", shell: false });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}

if (process.platform === "win32") {
  run("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "scripts/ci.ps1"]);
} else {
  run("bash", ["scripts/ci.sh"]);
}

run(process.execPath, [
  "node_modules/prettier/bin/prettier.cjs",
  "--check",
  "--config",
  ".prettierrc",
  "--ignore-path",
  ".prettierignore",
  "**/*.md",
  ".github/**/*.yml",
  "scripts/**/*.mjs",
  "*.json",
]);
run(process.execPath, ["scripts/check-loc.mjs"]);
run(process.execPath, ["scripts/scan-public.mjs"]);
run(process.execPath, ["scripts/release-integrity.mjs"]);
