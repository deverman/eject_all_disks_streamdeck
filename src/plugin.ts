import streamDeck, { LogLevel } from "@elgato/streamdeck";

import { EjectAllDisks } from "./actions/eject-all-disks";

// Global error handlers to catch any unhandled errors
process.on("uncaughtException", (error) => {
	streamDeck.logger.error(`Uncaught exception: ${error.message}\n${error.stack}`);
});

process.on("unhandledRejection", (reason, promise) => {
	streamDeck.logger.error(`Unhandled rejection at: ${promise}, reason: ${reason}`);
});

// We can enable "trace" logging so that all messages between the Stream Deck, and the plugin are recorded. When storing sensitive information
streamDeck.logger.setLevel(LogLevel.TRACE);

streamDeck.logger.info("Eject All Disks plugin starting...");

// Create and register the eject action.
try {
	const ejectAction = new EjectAllDisks();
	streamDeck.actions.registerAction(ejectAction);
	streamDeck.logger.info("Action registered successfully");
} catch (error) {
	streamDeck.logger.error(`Error registering action: ${error}`);
}

// Log that we're starting the plugin
streamDeck.logger.info("Eject All Disks plugin connecting...");

// Finally, connect to the Stream Deck.
streamDeck.connect();
