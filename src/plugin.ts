import streamDeck, { LogLevel } from "@elgato/streamdeck";

import { EjectAllDisks } from "./actions/eject-all-disks";

// We can enable "trace" logging so that all messages between the Stream Deck, and the plugin are recorded. When storing sensitive information
streamDeck.logger.setLevel(LogLevel.TRACE);

// Create and register the eject action.
const ejectAction = new EjectAllDisks();
streamDeck.actions.registerAction(ejectAction);

// Log that we're starting the plugin
streamDeck.logger.info('Eject All Disks plugin initializing');

// Finally, connect to the Stream Deck.
streamDeck.connect();
