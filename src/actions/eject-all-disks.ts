import streamDeck, {
  action,
  DidReceiveSettingsEvent,
  KeyDownEvent,
  SingletonAction,
  WillAppearEvent,
  Action,
  SendToPluginEvent,
  Target,
  JsonValue,
  JsonObject,
} from "@elgato/streamdeck";
import { exec } from "child_process";
import { promisify } from "util";

/**
 * An action class that ejects all external disks when the button is pressed.
 */
@action({ UUID: "org.deverman.ejectalldisks.eject" })
export class EjectAllDisks extends SingletonAction {
  // Track timeouts for cleanup
  private timeouts: Set<NodeJS.Timeout> = new Set();

  // Track disk count monitoring interval
  private monitoringInterval: NodeJS.Timeout | null = null;

  // Store current disk count
  private currentDiskCount: number = 0;

  // Cleanup timeouts
  private clearTimeouts(): void {
    this.timeouts.forEach(timeout => clearTimeout(timeout));
    this.timeouts.clear();
  }

  // Cleanup monitoring interval
  private stopMonitoring(): void {
    if (this.monitoringInterval) {
      clearInterval(this.monitoringInterval);
      this.monitoringInterval = null;
    }
  }

  override onWillDisappear(): void {
    this.clearTimeouts();
    this.stopMonitoring();
  }
  /**
   * Gets the list of ejectible external volumes (what user sees in Finder)
   * Excludes: Macintosh HD, hidden volumes, Time Machine, simulators, network mounts
   * @returns Promise that resolves to array of volume names
   */
  private async getEjectibleVolumes(): Promise<string[]> {
    try {
      const execPromise = promisify(exec);

      // List volumes and filter out system/hidden volumes
      // Excludes:
      // - Macintosh HD (internal drive)
      // - Hidden volumes (starting with .)
      // - Time Machine volumes (com.apple.TimeMachine*, Backups of *)
      // - We also check if it's a local mount (not network)
      const { stdout } = await execPromise(
        `ls /Volumes/ 2>/dev/null | grep -Ev "^(Macintosh HD|\\..*|com\\.apple\\..*|Backups of .*)$"`,
        { shell: '/bin/bash' }
      );

      const volumes = stdout.trim().split('\n').filter(line => line.length > 0);
      return volumes;
    } catch (error) {
      // grep returns exit code 1 if no matches found, which is not an error
      streamDeck.logger.info(`No ejectible volumes found or error: ${error}`);
      return [];
    }
  }

  /**
   * Gets the count of ejectible external volumes
   * @returns Promise that resolves to the number of ejectible volumes
   */
  private async getDiskCount(): Promise<number> {
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
      ${count > 0 ? `
      <g>
        <circle cx="110" cy="34" r="20" fill="#FF3B30" stroke="#000000" stroke-width="2"/>
        <text x="110" y="42" text-anchor="middle" font-family="Arial, sans-serif" font-size="24" font-weight="bold" fill="#FFFFFF">${count}</text>
      </g>
      ` : ''}
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
    if (payload && typeof payload === 'object' && 'showTitle' in payload) {
      const showTitle = Boolean(payload.showTitle);
      const settings = { showTitle: showTitle };
      
      // Log for debugging
      streamDeck.logger.info(`Received showTitle setting: ${settings.showTitle}`);
      
      // Apply title change immediately
      (ev.action as any).setTitle(showTitle ? "Eject All\nDisks" : "", { 
        target: Target.HardwareAndSoftware 
      });
      
      // Save the settings without waiting
      ev.action.setSettings(settings);
      
      return Promise.resolve();
    }
  }

  /**
   * Called when settings are changed in the property inspector
   */
  override onDidReceiveSettings(
    ev: DidReceiveSettingsEvent
  ): void | Promise<void> {
    // Get settings and apply immediately
    const settings = ev.payload.settings as EjectSettings;
    
    // Log for debugging
    streamDeck.logger.info(`Settings received: ${JSON.stringify(settings)}`);
    
    // Get the show title setting (default to true if not set)
    const showTitle = settings?.showTitle !== false;
    
    // Update title immediately
    return (ev.action as any).setTitle(showTitle ? "Eject All\nDisks" : "", { 
      target: Target.HardwareAndSoftware 
    });
  }

  /**
   * Refreshes settings from storage and applies them
   */
  private async refreshSettings(action: Action): Promise<void> {
    try {
      // Force get the latest settings from Stream Deck
      const latestSettings = await action.getSettings() as EjectSettings;
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
        target: Target.HardwareAndSoftware 
      });
    } catch (err) {
      streamDeck.logger.error(`Error setting title: ${err}`);
    }
  }
  
  /**
   * Updates the disk count display
   */
  private async updateDiskCount(action: Action): Promise<void> {
    const newCount = await this.getDiskCount();

    // Only update if the count has changed
    if (newCount !== this.currentDiskCount) {
      this.currentDiskCount = newCount;
      streamDeck.logger.info(`Disk count changed to: ${newCount}`);

      // Update the icon with the new count
      await (action as any).setImage(`data:image/svg+xml,${encodeURIComponent(this.createNormalSvg(newCount))}`, {
        target: Target.HardwareAndSoftware
      });
    }
  }

  /**
   * Starts monitoring disk count
   */
  private async startMonitoring(action: Action): Promise<void> {
    // Stop any existing monitoring
    this.stopMonitoring();

    // Initial count update
    await this.updateDiskCount(action);

    // Check disk count every 3 seconds
    this.monitoringInterval = setInterval(async () => {
      await this.updateDiskCount(action);
    }, 3000);
  }

  /**
   * When the action appears on screen
   */
  override async onWillAppear(
    ev: WillAppearEvent,
  ): Promise<void> {
    // Get the settings or initialize default
    const settings = ev.payload.settings as EjectSettings || {};

    // If showTitle is undefined, initialize it to true
    if (settings.showTitle === undefined) {
      settings.showTitle = true;
      ev.action.setSettings(settings);
      streamDeck.logger.info(`Initialized settings with showTitle=true`);
    }

    // Get the show title value (default to true)
    const showTitle = settings.showTitle !== false;

    // Update title immediately
    await (ev.action as any).setTitle(showTitle ? "Eject All\nDisks" : "", {
      target: Target.HardwareAndSoftware
    });

    // Start monitoring disk count
    await this.startMonitoring(ev.action);
  }

  /**
   * When the key is pressed
   */
  override async onKeyDown(ev: KeyDownEvent): Promise<void> {
    streamDeck.logger.info("Ejecting disks...");
    
    // Set the ejecting icon
    await ev.action.setImage(`data:image/svg+xml,${encodeURIComponent(this.createEjectingSvg())}`, {
      target: Target.HardwareAndSoftware
    });
    
    // Get current settings for title display
    const settings = await ev.action.getSettings() as EjectSettings;
    const showTitle = settings?.showTitle !== false;
    
    // Show ejecting status
    await (ev.action as any).setTitle(showTitle ? "Ejecting..." : "", {
      target: Target.HardwareAndSoftware
    });
    
    try {
      const execPromise = promisify(exec);

      // Get the list of ejectible volumes first
      const volumes = await this.getEjectibleVolumes();

      if (volumes.length === 0) {
        streamDeck.logger.info("No volumes to eject");
        // Show success since there's nothing to eject
        await ev.action.setImage(`data:image/svg+xml,${encodeURIComponent(this.createSuccessSvg())}`, {
          target: Target.HardwareAndSoftware
        });
        await (ev.action as any).setTitle(showTitle ? "No Disks" : "", {
          target: Target.HardwareAndSoftware
        });
        await ev.action.showOk();

        const timeout = setTimeout(async () => {
          await this.updateDiskCount(ev.action);
          const finalSettings = await ev.action.getSettings() as EjectSettings;
          const showFinalTitle = finalSettings?.showTitle !== false;
          await (ev.action as any).setTitle(showFinalTitle ? "Eject All\nDisks" : "", {
            target: Target.HardwareAndSoftware
          });
          this.timeouts.delete(timeout);
        }, 2000);
        this.timeouts.add(timeout);
        return;
      }

      // Script to eject each volume by name
      // Uses diskutil eject which safely unmounts and ejects the volume
      const volumeList = volumes.map(v => `"${v.replace(/"/g, '\\"')}"`).join(' ');
      const script = `
        results=""
        errors=""
        for volume in ${volumeList}; do
          # Check if volume still exists before ejecting
          if [ -d "/Volumes/$volume" ]; then
            output=$(diskutil eject "/Volumes/$volume" 2>&1)
            if [ $? -eq 0 ]; then
              results="$results$output\\n"
            else
              errors="$errors$output\\n"
            fi
          fi
        done
        if [ -n "$errors" ]; then
          echo "$errors" >&2
        fi
        echo "$results"
      `;

      const { stdout, stderr } = await execPromise(script, { shell: '/bin/bash' });
      
      if (stderr) {
        streamDeck.logger.error(`Error ejecting disks: ${stderr}`);
        
        // Show error icon
        await ev.action.setImage(`data:image/svg+xml,${encodeURIComponent(this.createErrorSvg())}`, {
          target: Target.HardwareAndSoftware
        });
        
        // Get latest settings to check if we should show title
        const currentSettings = await ev.action.getSettings() as EjectSettings;
        const shouldShowTitle = currentSettings?.showTitle !== false;
        
        // Show error message
        await (ev.action as any).setTitle(shouldShowTitle ? "Error!" : "", {
          target: Target.HardwareAndSoftware
        });
        await ev.action.showAlert();
        
        // Reset title and image after 2 seconds
        const timeout = setTimeout(async () => {
          // Update disk count (will be 0 or less after ejecting)
          await this.updateDiskCount(ev.action);

          // Get latest settings again in case they changed
          const finalSettings = await ev.action.getSettings() as EjectSettings;
          const showFinalTitle = finalSettings?.showTitle !== false;

          await (ev.action as any).setTitle(showFinalTitle ? "Eject All\nDisks" : "", {
            target: Target.HardwareAndSoftware
          });

          this.timeouts.delete(timeout);
        }, 2000);
        this.timeouts.add(timeout);
      } else {
        streamDeck.logger.info(`Disks ejected: ${stdout}`);
        
        // Show success icon
        await ev.action.setImage(`data:image/svg+xml,${encodeURIComponent(this.createSuccessSvg())}`, {
          target: Target.HardwareAndSoftware
        });
        
        // Get latest settings to check if we should show title
        const currentSettings = await ev.action.getSettings() as EjectSettings;
        const shouldShowTitle = currentSettings?.showTitle !== false;
        
        // Show success message
        await (ev.action as any).setTitle(shouldShowTitle ? "Ejected!" : "", {
          target: Target.HardwareAndSoftware
        });
        await ev.action.showOk();
        
        // Reset title and image after 2 seconds
        const timeout = setTimeout(async () => {
          // Update disk count (will be 0 or less after ejecting)
          await this.updateDiskCount(ev.action);

          // Get latest settings again in case they changed
          const finalSettings = await ev.action.getSettings() as EjectSettings;
          const showFinalTitle = finalSettings?.showTitle !== false;

          await (ev.action as any).setTitle(showFinalTitle ? "Eject All\nDisks" : "", {
            target: Target.HardwareAndSoftware
          });

          this.timeouts.delete(timeout);
        }, 2000);
        this.timeouts.add(timeout);
      }
    } catch (error) {
      streamDeck.logger.error(`Exception: ${error}`);
      
      // Show error icon for exceptions
      await ev.action.setImage(`data:image/svg+xml,${encodeURIComponent(this.createErrorSvg())}`, {
        target: Target.HardwareAndSoftware
      });
          
      // Get latest settings to check if we should show title
      const errorSettings = await ev.action.getSettings() as EjectSettings;
      const showErrorTitle = errorSettings?.showTitle !== false;
        
      await (ev.action as any).setTitle(showErrorTitle ? "Failed!" : "", {
        target: Target.HardwareAndSoftware
      });
      await ev.action.showAlert();
      
      // Reset title and image after 2 seconds
      const timeout = setTimeout(async () => {
        // Update disk count
        await this.updateDiskCount(ev.action);

        // Get latest settings to check if we should show title
        const finalSettings = await ev.action.getSettings() as EjectSettings;
        const showFinalTitle = finalSettings?.showTitle !== false;

        await (ev.action as any).setTitle(showFinalTitle ? "Eject All\nDisks" : "", {
          target: Target.HardwareAndSoftware
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