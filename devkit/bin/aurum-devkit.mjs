#!/usr/bin/env node
// aurum-devkit render [--target DIR] [--profile local|prod] [--dest PATH]
//
// The installed form of tools/render-devkit (#819). The renderer is Python
// 3 and its standard library, shipped beside this file and run as it is, so
// a product renders the same bytes from the package as from a checkout of
// aurum-alpha/workflows. --target defaults to the working directory, which
// is where a product's devkit.json sits.
import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const usage = "usage: aurum-devkit render [--target DIR] [--profile local|prod] [--dest PATH]";
const [command, ...args] = process.argv.slice(2);

if (command === undefined || command === "-h" || command === "--help") {
  console.log(usage);
  process.exit(command === undefined ? 2 : 0);
}
if (command !== "render") {
  console.error(`aurum-devkit: unknown command ${command}\n${usage}`);
  process.exit(2);
}

const renderer = join(dirname(fileURLToPath(import.meta.url)), "render-devkit");
const withTarget = args.includes("--target") ? args : ["--target", ".", ...args];
const run = spawnSync("python3", [renderer, ...withTarget], { stdio: "inherit" });

if (run.error) {
  console.error(`aurum-devkit: python3 could not be run (${run.error.message}). The renderer needs Python 3.`);
  process.exit(2);
}
process.exit(run.status ?? 2);
