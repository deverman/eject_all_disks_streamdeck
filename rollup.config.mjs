import commonjs from "@rollup/plugin-commonjs";
import nodeResolve from "@rollup/plugin-node-resolve";
import terser from "@rollup/plugin-terser";
import typescript from "@rollup/plugin-typescript";
import { execSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import url from "node:url";

const isWatching = !!process.env.ROLLUP_WATCH;
const sdPlugin = "org.deverman.ejectalldisks.sdPlugin";

/**
 * @type {import('rollup').RollupOptions}
 */
const config = {
	input: "src/plugin.ts",
	output: {
		file: `${sdPlugin}/bin/plugin.js`,
		sourcemap: isWatching,
		sourcemapPathTransform: (relativeSourcePath, sourcemapPath) => {
			return url.pathToFileURL(path.resolve(path.dirname(sourcemapPath), relativeSourcePath)).href;
		},
	},
	plugins: [
		{
			name: "watch-externals",
			buildStart: function () {
				this.addWatchFile(`${sdPlugin}/manifest.json`);
			},
		},
		{
			name: "build-swift",
			buildStart: function () {
				// Only build Swift on macOS
				if (process.platform !== "darwin") {
					console.log("Skipping Swift build (not on macOS)");
					return;
				}

				const swiftSrc = "swift/EjectDisks.swift";
				const outputBin = `${sdPlugin}/bin/eject-disks`;

				// Check if Swift source exists
				if (!fs.existsSync(swiftSrc)) {
					console.log("Swift source not found, skipping Swift build");
					return;
				}

				// Check if rebuild is needed (source newer than binary)
				if (fs.existsSync(outputBin)) {
					const srcStat = fs.statSync(swiftSrc);
					const binStat = fs.statSync(outputBin);
					if (srcStat.mtime <= binStat.mtime) {
						console.log("Swift binary is up to date");
						return;
					}
				}

				console.log("Building Swift disk ejection tool...");
				try {
					execSync("bash scripts/build-swift.sh", {
						stdio: "inherit",
						cwd: process.cwd(),
					});
					console.log("Swift build completed successfully");
				} catch (error) {
					console.error("Swift build failed:", error.message);
					// Don't fail the build - the plugin has a shell fallback
				}
			},
		},
		typescript({
			mapRoot: isWatching ? "./" : undefined,
		}),
		nodeResolve({
			browser: false,
			exportConditions: ["node"],
			preferBuiltins: true,
		}),
		commonjs(),
		!isWatching && terser(),
		{
			name: "emit-module-package-file",
			generateBundle() {
				this.emitFile({ fileName: "package.json", source: `{ "type": "module" }`, type: "asset" });
			},
		},
	],
};

export default config;
