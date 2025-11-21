// Stream Deck Property Inspector basic functionality
// This file provides utility functions for Stream Deck property inspectors

/**
 * Registers the property inspector with Stream Deck
 * @param {string} inPort - The port to connect to
 * @param {string} inPropertyInspectorUUID - The UUID for the property inspector
 * @param {string} inRegisterEvent - The event to register with
 * @param {string} inInfo - Information about the action
 */
function connectElgatoStreamDeckSocket(inPort, inPropertyInspectorUUID, inRegisterEvent, inInfo) {
	// This function is called automatically by Stream Deck, don't rename it
	// It's the entry point for property inspector JavaScript

	// Store the registration info in case we need it
	if (typeof window.connectSocket === "function") {
		window.connectSocket(inPort, inPropertyInspectorUUID, inRegisterEvent, inInfo);
	} else {
		console.log("No connectSocket function found");
	}
}

/**
 * Utility function to save settings
 * @param {object} settings - The settings object to save
 * @param {object} websocket - The websocket connection
 * @param {string} context - The context of the action
 */
function saveSettings(settings, websocket, context) {
	if (websocket && websocket.readyState === 1) {
		const json = {
			event: "setSettings",
			context: context,
			payload: settings,
		};
		websocket.send(JSON.stringify(json));
	}
}

/**
 * Utility function to request global settings
 * @param {object} websocket - The websocket connection
 * @param {string} context - The context of the action
 */
function requestGlobalSettings(websocket, context) {
	if (websocket && websocket.readyState === 1) {
		const json = {
			event: "getGlobalSettings",
			context: context,
		};
		websocket.send(JSON.stringify(json));
	}
}

/**
 * Utility function to save global settings
 * @param {object} settings - The settings object to save
 * @param {object} websocket - The websocket connection
 * @param {string} context - The context of the action
 */
function saveGlobalSettings(settings, websocket, context) {
	if (websocket && websocket.readyState === 1) {
		const json = {
			event: "setGlobalSettings",
			context: context,
			payload: settings,
		};
		websocket.send(JSON.stringify(json));
	}
}

/**
 * Utility function to send data to plugin
 * @param {string} action - The action to perform
 * @param {object} data - The data to send
 * @param {object} websocket - The websocket connection
 * @param {string} context - The context of the action
 */
function sendToPlugin(action, data, websocket, context) {
	if (websocket && websocket.readyState === 1) {
		const json = {
			action: action,
			event: "sendToPlugin",
			context: context,
			payload: data,
		};
		websocket.send(JSON.stringify(json));
	}
}

// Export functions to global scope for use in HTML
window.saveSettings = saveSettings;
window.requestGlobalSettings = requestGlobalSettings;
window.saveGlobalSettings = saveGlobalSettings;
window.sendToPlugin = sendToPlugin;
