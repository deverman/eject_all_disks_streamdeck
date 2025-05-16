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

  // Cleanup timeouts
  private clearTimeouts(): void {
    this.timeouts.forEach(timeout => clearTimeout(timeout));
    this.timeouts.clear();
  }

  override onWillDisappear(): void {
    this.clearTimeouts();
  }
  /**
   * Creates the normal eject icon SVG
   * @returns SVG string for the normal eject icon
   */
  private createNormalSvg(): string {
    return `<svg width="144" height="144" viewBox="0 0 144 144" xmlns="http://www.w3.org/2000/svg">
      <!-- Dark background circle for better text contrast -->
      <circle cx="72" cy="72" r="65" fill="#222222" opacity="0.6"/>
      <g fill="#FF9F0A">
        <!-- Triangle shape pointing upward -->
        <path d="M72 36L112 90H32L72 36Z" stroke="#000000" stroke-width="2"/>
        <!-- Horizontal line beneath the triangle -->
        <rect x="32" y="100" width="80" height="10" rx="2" stroke="#000000" stroke-width="2"/>
      </g>
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
   * When the action appears on screen
   */
  override onWillAppear(
    ev: WillAppearEvent,
  ): void | Promise<void> {
    // Set the image using the normal eject icon
    ev.action.setImage(`data:image/svg+xml,${encodeURIComponent(this.createNormalSvg())}`, {
      target: Target.HardwareAndSoftware
    });
    
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
    return (ev.action as any).setTitle(showTitle ? "Eject All\nDisks" : "", { 
      target: Target.HardwareAndSoftware 
    });
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
      
      // Script to eject all external disks
      const script = `
        IFS=$'\n'
        disks=$(diskutil list external | grep -o -E '/dev/disk[0-9]+')
        for disk in $disks; do
          # Validate disk path format for security
          if [[ "$disk" =~ ^/dev/disk[0-9]+$ ]]; then
            diskutil unmountDisk "$disk"
          else
            echo "Invalid disk path: $disk" >&2
          fi
        done
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
          await ev.action.setImage(`data:image/svg+xml,${encodeURIComponent(this.createNormalSvg())}`, {
            target: Target.HardwareAndSoftware
          });
          
          // Get latest settings again in case they changed
          const finalSettings = await ev.action.getSettings() as EjectSettings;
          const showFinalTitle = finalSettings?.showTitle !== false;
          
          await (ev.action as any).setTitle(showFinalTitle ? "Eject All\nDisks" : "", {
            target: Target.HardwareAndSoftware
          });
        }, 2000);
        this.timeouts.add(timeout);
        this.timeouts.add(timeout);
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
          await ev.action.setImage(`data:image/svg+xml,${encodeURIComponent(this.createNormalSvg())}`, {
            target: Target.HardwareAndSoftware
          });
          
          // Get latest settings again in case they changed
          const finalSettings = await ev.action.getSettings() as EjectSettings;
          const showFinalTitle = finalSettings?.showTitle !== false;
          
          await (ev.action as any).setTitle(showFinalTitle ? "Eject All\nDisks" : "", {
            target: Target.HardwareAndSoftware
          });
        }, 2000);
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
        await ev.action.setImage(`data:image/svg+xml,${encodeURIComponent(this.createNormalSvg())}`, {
          target: Target.HardwareAndSoftware
        });
        
        // Get latest settings to check if we should show title
        const finalSettings = await ev.action.getSettings() as EjectSettings;
        const showFinalTitle = finalSettings?.showTitle !== false;
        
        await (ev.action as any).setTitle(showFinalTitle ? "Eject All\nDisks" : "", {
          target: Target.HardwareAndSoftware
        });
      }, 2000);
    }
  }
}

/**
 * Settings for {@link EjectAllDisks}.
 */
type EjectSettings = {
  showTitle?: boolean; // Whether to show the title on the button
};