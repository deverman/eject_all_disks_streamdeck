import streamDeck, {
	action,
	Action,
	DidReceiveSettingsEvent,
	JsonObject,
	JsonValue,
	KeyDownEvent,
	SendToPluginEvent,
	SingletonAction,
	Target,
	WillAppearEvent,
	WillDisappearEvent,
} from "@elgato/streamdeck";
import { exec } from "child_process";
import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";
import { promisify } from "util";

// Get __dirname equivalent for ES modules
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Types for Swift binary JSON output
interface VolumeInfo {
	name: string;
	path: string;
	bsdName?: string;
	isEjectable: boolean;
	isRemovable: boolean;
}

interface ListOutput {
	count: number;
	volumes: VolumeInfo[];
}

interface EjectResult {
	volume: string;
	success: boolean;
	error?: string;
	duration: number;
}

interface EjectOutput {
	totalCount: number;
	successCount: number;
	failedCount: number;
	results: EjectResult[];
	totalDuration: number;
}

/**
 * An action class that ejects all external disks when the button is pressed.
 */
@action({ UUID: "org.deverman.ejectalldisks.eject" })
export class EjectAllDisks extends SingletonAction {
	// Track timeouts for cleanup
	private timeouts: Set<NodeJS.Timeout> = new Set();

	// Track disk count monitoring intervals per action (keyed by action ID)
	private monitoringIntervals: Map<string, NodeJS.Timeout> = new Map();

	// Store current disk count per action (keyed by action ID)
	private diskCounts: Map<string, number> = new Map();

	// Cached path to the Swift binary
	private swiftBinaryPath: string | null = null;

	/**
	 * Gets the path to the Swift eject-disks binary
	 * @returns Path to the binary or null if not found
	 */
	private getSwiftBinaryPath(): string | null {
		if (this.swiftBinaryPath !== null) {
			return this.swiftBinaryPath;
		}

		streamDeck.logger.info(`Looking for Swift binary, __dirname: ${__dirname}, cwd: ${process.cwd()}`);

		// The binary is in the bin directory alongside plugin.js
		const possiblePaths = [
			path.join(__dirname, "eject-disks"),
			path.join(__dirname, "..", "bin", "eject-disks"),
			path.join(process.cwd(), "bin", "eject-disks"),
		];

		for (const binPath of possiblePaths) {
			streamDeck.logger.info(`Checking path: ${binPath}, exists: ${fs.existsSync(binPath)}`);
			if (fs.existsSync(binPath)) {
				this.swiftBinaryPath = binPath;
				streamDeck.logger.info(`Found Swift binary at: ${binPath}`);
				return binPath;
			}
		}

		streamDeck.logger.warn("Swift binary not found, will use fallback shell commands");
		return null;
	}

	/**
	 * Check if Swift binary is available
	 */
	private hasSwiftBinary(): boolean {
		return this.getSwiftBinaryPath() !== null;
	}

	// Cleanup timeouts
	private clearTimeouts(): void {
		this.timeouts.forEach((timeout) => clearTimeout(timeout));
		this.timeouts.clear();
	}

	// Cleanup monitoring interval for a specific action
	private stopMonitoring(actionId: string): void {
		const interval = this.monitoringIntervals.get(actionId);
		if (interval) {
			clearInterval(interval);
			this.monitoringIntervals.delete(actionId);
			this.diskCounts.delete(actionId);
		}
	}

	// Cleanup all monitoring intervals
	private stopAllMonitoring(): void {
		this.monitoringIntervals.forEach((interval) => clearInterval(interval));
		this.monitoringIntervals.clear();
		this.diskCounts.clear();
	}

	override onWillDisappear(ev: WillDisappearEvent): void {
		this.clearTimeouts();
		this.stopMonitoring(ev.action.id);
	}
	/**
	 * Gets the list of ejectible external volumes using Swift binary (fast)
	 * Falls back to shell commands if Swift binary is not available
	 * @returns Promise that resolves to array of volume names
	 */
	private async getEjectibleVolumes(): Promise<string[]> {
		const execPromise = promisify(exec);
		const binaryPath = this.getSwiftBinaryPath();

		// Try Swift binary first (faster, more accurate)
		if (binaryPath) {
			try {
				const { stdout } = await execPromise(`"${binaryPath}" list`, {
					shell: "/bin/bash",
					timeout: 5000,
				});

				const output: ListOutput = JSON.parse(stdout);
				return output.volumes.map((v) => v.name);
			} catch (error) {
				streamDeck.logger.warn(`Swift binary failed, falling back to shell: ${error}`);
				// Fall through to shell fallback
			}
		}

		// Fallback to shell commands
		try {
			const { stdout } = await execPromise(
				`ls /Volumes/ 2>/dev/null | grep -Ev "^(Macintosh HD|\\..*|com\\.apple\\..*|Backups of .*)$"`,
				{ shell: "/bin/bash" },
			);

			const volumes = stdout
				.trim()
				.split("\n")
				.filter((line) => line.length > 0);
			return volumes;
		} catch (error) {
			streamDeck.logger.info(`No ejectible volumes found or error: ${error}`);
			return [];
		}
	}

	/**
	 * Gets the count of ejectible external volumes
	 * Uses Swift binary's count command for fastest response
	 * @returns Promise that resolves to the number of ejectible volumes
	 */
	private async getDiskCount(): Promise<number> {
		const execPromise = promisify(exec);
		const binaryPath = this.getSwiftBinaryPath();

		// Try Swift binary's count command (fastest)
		if (binaryPath) {
			try {
				const { stdout } = await execPromise(`"${binaryPath}" count`, {
					shell: "/bin/bash",
					timeout: 3000,
				});

				return parseInt(stdout.trim(), 10) || 0;
			} catch (error) {
				// Fall through to getEjectibleVolumes
			}
		}

		// Fallback
		const volumes = await this.getEjectibleVolumes();
		return volumes.length;
	}

	/**
	 * Creates the normal eject icon SVG with disk count
	 * @param count The number of disks to display
	 * @returns SVG string for the normal eject icon
	 */
	private createNormalSvg(count: number = 0): string {
		return `<svg width="144" height="144" viewBox="0 0 144 144" xmlns="http://www.w3.org/2000/svg">
      <!-- Dark background circle for better text contrast -->
      <circle cx="72" cy="72" r="65" fill="#222222" opacity="0.6"/>
      <g fill="#FF9F0A">
        <!-- Triangle shape pointing upward -->
        <path d="M72 36L112 90H32L72 36Z" stroke="#000000" stroke-width="2"/>
        <!-- Horizontal line beneath the triangle -->
        <rect x="32" y="100" width="80" height="10" rx="2" stroke="#000000" stroke-width="2"/>
      </g>
      <!-- Disk count badge -->
      ${
				count > 0
					? `
      <g>
        <circle cx="110" cy="34" r="20" fill="#FF3B30" stroke="#000000" stroke-width="2"/>
        <text x="110" y="42" text-anchor="middle" font-family="Arial, sans-serif" font-size="24" font-weight="bold" fill="#FFFFFF">${count}</text>
      </g>
      `
					: ""
			}
    </svg>`;
	}

	/**
	 * Creates the ejecting icon SVG with animation
	 * @returns SVG string for the ejecting icon
	 */
	private createEjectingSvg(): string {
		return `<svg width="144" height="144" viewBox="0 0 144 144" xmlns="http://www.w3.org/2000/svg">
      <!-- Dark background circle for better text contrast -->
      <circle cx="72" cy="72" r="65" fill="#222222" opacity="0.7"/>
      <g fill="#FFCC00">
        <!-- Triangle shape pointing upward with animation effect -->
        <path d="M72 36L112 90H32L72 36Z" stroke="#000000" stroke-width="2">
          <animate attributeName="opacity" values="0.7;1;0.7" dur="1s" repeatCount="indefinite" />
        </path>
        <!-- Horizontal line beneath the triangle -->
        <rect x="32" y="100" width="80" height="10" rx="2" stroke="#000000" stroke-width="2"/>
      </g>
    </svg>`;
	}

	/**
	 * Creates the success icon SVG
	 * @returns SVG string for the success icon
	 */
	private createSuccessSvg(): string {
		return `<svg width="144" height="144" viewBox="0 0 144 144" xmlns="http://www.w3.org/2000/svg">
      <!-- Dark background circle for better text contrast -->
      <circle cx="72" cy="72" r="65" fill="#222222" opacity="0.7"/>
      <g fill="#34C759">
        <!-- Triangle shape pointing upward -->
        <path d="M72 36L112 90H32L72 36Z" stroke="#000000" stroke-width="2"/>
        <!-- Horizontal line beneath the triangle -->
        <rect x="32" y="100" width="80" height="10" rx="2" stroke="#000000" stroke-width="2"/>
        <!-- Checkmark -->
        <path d="M52 72L67 87L92 57" stroke="#FFFFFF" stroke-width="6" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
      </g>
    </svg>`;
	}

	/**
	 * Creates the error icon SVG
	 * @returns SVG string for the error icon
	 */
	private createErrorSvg(): string {
		return `<svg width="144" height="144" viewBox="0 0 144 144" xmlns="http://www.w3.org/2000/svg">
      <!-- Dark background circle for better text contrast -->
      <circle cx="72" cy="72" r="65" fill="#222222" opacity="0.8"/>
      <g fill="#FF3B30">
        <!-- Triangle shape pointing upward -->
        <path d="M72 36L112 90H32L72 36Z" stroke="#000000" stroke-width="2"/>
        <!-- Horizontal line beneath the triangle -->
        <rect x="32" y="100" width="80" height="10" rx="2" stroke="#000000" stroke-width="2"/>
        <!-- X mark -->
        <path d="M60 60L84 84M84 60L60 84" stroke="#FFFFFF" stroke-width="6" stroke-linecap="round"/>
      </g>
    </svg>`;
	}

	/**
	 * Handle messages from the property inspector
	 */
	override onSendToPlugin(ev: SendToPluginEvent<JsonValue, JsonObject>): void | Promise<void> {
		const payload = ev.payload as Record<string, unknown>;

		// Check if we received a showTitle setting change
		if (payload && typeof payload === "object" && "showTitle" in payload) {
			const showTitle = Boolean(payload.showTitle);
			const settings = { showTitle: showTitle };

			// Log for debugging
			streamDeck.logger.info(`Received showTitle setting: ${settings.showTitle}`);

			// Apply title change immediately
			(ev.action as any).setTitle(showTitle ? "Eject All\nDisks" : "", {
				target: Target.HardwareAndSoftware,
			});

			// Save the settings without waiting
			ev.action.setSettings(settings);

			return Promise.resolve();
		}
	}

	/**
	 * Called when settings are changed in the property inspector
	 */
	override onDidReceiveSettings(ev: DidReceiveSettingsEvent): void | Promise<void> {
		// Get settings and apply immediately
		const settings = ev.payload.settings as EjectSettings;

		// Log for debugging
		streamDeck.logger.info(`Settings received: ${JSON.stringify(settings)}`);

		// Get the show title setting (default to true if not set)
		const showTitle = settings?.showTitle !== false;

		// Update title immediately
		return (ev.action as any).setTitle(showTitle ? "Eject All\nDisks" : "", {
			target: Target.HardwareAndSoftware,
		});
	}

	/**
	 * Refreshes settings from storage and applies them
	 */
	private async refreshSettings(action: Action): Promise<void> {
		try {
			// Force get the latest settings from Stream Deck
			const latestSettings = (await action.getSettings()) as EjectSettings;
			streamDeck.logger.info(`Refreshed settings: ${JSON.stringify(latestSettings)}`);

			// Apply settings immediately
			return this.updateTitleFromSettings(action, latestSettings);
		} catch (err) {
			streamDeck.logger.error(`Error refreshing settings: ${err}`);
		}
	}

	/**
	 * Updates the button title based on the current settings
	 */
	private async updateTitleFromSettings(action: Action, settings?: EjectSettings): Promise<void> {
		// Default to showing title if setting is not explicitly false
		const showTitle = settings?.showTitle !== false;

		// Log what we're doing
		streamDeck.logger.info(`Updating title, showTitle=${showTitle}`);

		try {
			// Use target both hardware and software to ensure it's updated properly
			await (action as any).setTitle(showTitle ? "Eject All\nDisks" : "", {
				target: Target.HardwareAndSoftware,
			});
		} catch (err) {
			streamDeck.logger.error(`Error setting title: ${err}`);
		}
	}

	/**
	 * Updates the disk count display for a specific action
	 */
	private async updateDiskCount(action: Action): Promise<void> {
		try {
			const newCount = await this.getDiskCount();
			const currentCount = this.diskCounts.get(action.id) ?? -1;

			// Only update if the count has changed
			if (newCount !== currentCount) {
				this.diskCounts.set(action.id, newCount);
				streamDeck.logger.info(`Disk count changed to: ${newCount} for action ${action.id}`);

				// Update the icon with the new count
				await (action as any).setImage(`data:image/svg+xml,${encodeURIComponent(this.createNormalSvg(newCount))}`, {
					target: Target.HardwareAndSoftware,
				});
			}
		} catch (error) {
			streamDeck.logger.error(`Error in updateDiskCount: ${error}`);
		}
	}

	/**
	 * Starts monitoring disk count for a specific action
	 */
	private async startMonitoring(action: Action): Promise<void> {
		try {
			// Stop any existing monitoring for this specific action
			this.stopMonitoring(action.id);

			// Initial count update
			await this.updateDiskCount(action);

			// Check disk count every 3 seconds
			const interval = setInterval(async () => {
				try {
					await this.updateDiskCount(action);
				} catch (error) {
					streamDeck.logger.error(`Error in monitoring interval: ${error}`);
				}
			}, 3000);

			this.monitoringIntervals.set(action.id, interval);
		} catch (error) {
			streamDeck.logger.error(`Error in startMonitoring: ${error}`);
		}
	}

	/**
	 * When the action appears on screen
	 */
	override async onWillAppear(ev: WillAppearEvent): Promise<void> {
		try {
			streamDeck.logger.info("onWillAppear called");

			// Get the settings or initialize default
			const settings = (ev.payload.settings as EjectSettings) || {};

			// If showTitle is undefined, initialize it to true
			if (settings.showTitle === undefined) {
				settings.showTitle = true;
				await ev.action.setSettings(settings);
				streamDeck.logger.info(`Initialized settings with showTitle=true`);
			}

			// Get the show title value (default to true)
			const showTitle = settings.showTitle !== false;

			// Update title immediately
			await (ev.action as any).setTitle(showTitle ? "Eject All\nDisks" : "", {
				target: Target.HardwareAndSoftware,
			});

			streamDeck.logger.info("About to start monitoring");

			// Start monitoring disk count
			await this.startMonitoring(ev.action);

			streamDeck.logger.info("Monitoring started successfully");
		} catch (error) {
			streamDeck.logger.error(`Error in onWillAppear: ${error}`);
		}
	}

	/**
	 * When the key is pressed
	 */
	override async onKeyDown(ev: KeyDownEvent): Promise<void> {
		streamDeck.logger.info("Ejecting disks...");

		// Set the ejecting icon
		await ev.action.setImage(`data:image/svg+xml,${encodeURIComponent(this.createEjectingSvg())}`, {
			target: Target.HardwareAndSoftware,
		});

		// Get current settings for title display
		const settings = (await ev.action.getSettings()) as EjectSettings;
		const showTitle = settings?.showTitle !== false;

		// Show ejecting status
		await (ev.action as any).setTitle(showTitle ? "Ejecting..." : "", {
			target: Target.HardwareAndSoftware,
		});

		try {
			const execPromise = promisify(exec);

			// Get the list of ejectible volumes first
			const volumes = await this.getEjectibleVolumes();

			if (volumes.length === 0) {
				streamDeck.logger.info("No volumes to eject");
				// Show success since there's nothing to eject
				await ev.action.setImage(`data:image/svg+xml,${encodeURIComponent(this.createSuccessSvg())}`, {
					target: Target.HardwareAndSoftware,
				});
				await (ev.action as any).setTitle(showTitle ? "No Disks" : "", {
					target: Target.HardwareAndSoftware,
				});
				await ev.action.showOk();

				const timeout = setTimeout(async () => {
					await this.updateDiskCount(ev.action);
					const finalSettings = (await ev.action.getSettings()) as EjectSettings;
					const showFinalTitle = finalSettings?.showTitle !== false;
					await (ev.action as any).setTitle(showFinalTitle ? "Eject All\nDisks" : "", {
						target: Target.HardwareAndSoftware,
					});
					this.timeouts.delete(timeout);
				}, 2000);
				this.timeouts.add(timeout);
				return;
			}

			// Use Swift binary for fast parallel ejection with native APIs
			const binaryPath = this.getSwiftBinaryPath();
			let ejectResult: EjectOutput | null = null;
			let ejectError: string | null = null;

			if (binaryPath) {
				// Use Swift binary (fastest - uses DiskArbitration framework)
				try {
					const { stdout } = await execPromise(`"${binaryPath}" eject`, {
						shell: "/bin/bash",
						timeout: 30000, // 30 second timeout for ejection
					});

					ejectResult = JSON.parse(stdout) as EjectOutput;
					streamDeck.logger.info(
						`Swift eject completed: ${ejectResult.successCount}/${ejectResult.totalCount} in ${ejectResult.totalDuration.toFixed(2)}s`,
					);

					// Check for failures
					if (ejectResult.failedCount > 0) {
						const failures = ejectResult.results
							.filter((r) => !r.success)
							.map((r) => `${r.volume}: ${r.error}`)
							.join(", ");
						ejectError = failures;
					}
				} catch (error) {
					streamDeck.logger.warn(`Swift binary eject failed, falling back to shell: ${error}`);
					// Fall through to shell fallback
				}
			}

			// Fallback to shell script if Swift binary not available or failed
			if (!ejectResult) {
				const volumeList = volumes.map((v) => `"${v.replace(/"/g, '\\"')}"`).join(" ");
				const script = `
          tmpdir=$(mktemp -d)
          trap "rm -rf $tmpdir" EXIT
          pids=""
          i=0
          for volume in ${volumeList}; do
            (
              if [ -d "/Volumes/$volume" ]; then
                output=$(diskutil eject "/Volumes/$volume" 2>&1)
                if [ $? -eq 0 ]; then
                  echo "$output" > "$tmpdir/success_$i"
                else
                  echo "$output" > "$tmpdir/error_$i"
                fi
              fi
            ) &
            pids="$pids $!"
            i=$((i + 1))
          done
          wait $pids
          results=""
          errors=""
          for f in "$tmpdir"/success_*; do
            [ -f "$f" ] && results="$results$(cat "$f")\\n"
          done
          for f in "$tmpdir"/error_*; do
            [ -f "$f" ] && errors="$errors$(cat "$f")\\n"
          done
          if [ -n "$errors" ]; then
            echo "$errors" >&2
          fi
          echo "$results"
        `;

				const { stdout, stderr } = await execPromise(script, { shell: "/bin/bash" });

				if (stderr) {
					ejectError = stderr;
				}

				// Create a mock EjectOutput for consistent handling
				ejectResult = {
					totalCount: volumes.length,
					successCount: stderr ? 0 : volumes.length,
					failedCount: stderr ? volumes.length : 0,
					results: [],
					totalDuration: 0,
				};

				streamDeck.logger.info(`Shell eject completed: ${stdout}`);
			}

			// Handle results
			if (ejectError) {
				streamDeck.logger.error(`Error ejecting disks: ${ejectError}`);

				// Show error icon
				await ev.action.setImage(`data:image/svg+xml,${encodeURIComponent(this.createErrorSvg())}`, {
					target: Target.HardwareAndSoftware,
				});

				// Get latest settings to check if we should show title
				const currentSettings = (await ev.action.getSettings()) as EjectSettings;
				const shouldShowTitle = currentSettings?.showTitle !== false;

				// Show error message
				await (ev.action as any).setTitle(shouldShowTitle ? "Error!" : "", {
					target: Target.HardwareAndSoftware,
				});
				await ev.action.showAlert();

				// Reset title and image after 2 seconds
				const timeout = setTimeout(async () => {
					await this.updateDiskCount(ev.action);
					const finalSettings = (await ev.action.getSettings()) as EjectSettings;
					const showFinalTitle = finalSettings?.showTitle !== false;
					await (ev.action as any).setTitle(showFinalTitle ? "Eject All\nDisks" : "", {
						target: Target.HardwareAndSoftware,
					});
					this.timeouts.delete(timeout);
				}, 2000);
				this.timeouts.add(timeout);
			} else {
				streamDeck.logger.info(`All disks ejected successfully`);

				// Show success icon
				await ev.action.setImage(`data:image/svg+xml,${encodeURIComponent(this.createSuccessSvg())}`, {
					target: Target.HardwareAndSoftware,
				});

				// Get latest settings to check if we should show title
				const currentSettings = (await ev.action.getSettings()) as EjectSettings;
				const shouldShowTitle = currentSettings?.showTitle !== false;

				// Show success message
				await (ev.action as any).setTitle(shouldShowTitle ? "Ejected!" : "", {
					target: Target.HardwareAndSoftware,
				});
				await ev.action.showOk();

				// Reset title and image after 2 seconds
				const timeout = setTimeout(async () => {
					await this.updateDiskCount(ev.action);
					const finalSettings = (await ev.action.getSettings()) as EjectSettings;
					const showFinalTitle = finalSettings?.showTitle !== false;
					await (ev.action as any).setTitle(showFinalTitle ? "Eject All\nDisks" : "", {
						target: Target.HardwareAndSoftware,
					});
					this.timeouts.delete(timeout);
				}, 2000);
				this.timeouts.add(timeout);
			}
		} catch (error) {
			streamDeck.logger.error(`Exception: ${error}`);

			// Show error icon for exceptions
			await ev.action.setImage(`data:image/svg+xml,${encodeURIComponent(this.createErrorSvg())}`, {
				target: Target.HardwareAndSoftware,
			});

			// Get latest settings to check if we should show title
			const errorSettings = (await ev.action.getSettings()) as EjectSettings;
			const showErrorTitle = errorSettings?.showTitle !== false;

			await (ev.action as any).setTitle(showErrorTitle ? "Failed!" : "", {
				target: Target.HardwareAndSoftware,
			});
			await ev.action.showAlert();

			// Reset title and image after 2 seconds
			const timeout = setTimeout(async () => {
				// Update disk count
				await this.updateDiskCount(ev.action);

				// Get latest settings to check if we should show title
				const finalSettings = (await ev.action.getSettings()) as EjectSettings;
				const showFinalTitle = finalSettings?.showTitle !== false;

				await (ev.action as any).setTitle(showFinalTitle ? "Eject All\nDisks" : "", {
					target: Target.HardwareAndSoftware,
				});

				this.timeouts.delete(timeout);
			}, 2000);
			this.timeouts.add(timeout);
		}
	}
}

/**
 * Settings for {@link EjectAllDisks}.
 */
type EjectSettings = {
	showTitle?: boolean; // Whether to show the title on the button
};
