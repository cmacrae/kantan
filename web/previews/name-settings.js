// Prints a module's settings with each colour and icon its plugin's
// schema describes replaced by its name, for the plugin's generator to
// print its states from.
//
// usage: name-settings.js <settings.schema.json> <module-config.schema.json> <settings as JSON>
import { readFileSync } from "node:fs";
import { bundleSchema, nameSettings } from "../builder/settings.js";

const [schemaPath, sharedPath, settings] = process.argv.slice(2);
const read = path => JSON.parse(readFileSync(path, "utf8"));
process.stdout.write(JSON.stringify(nameSettings(JSON.parse(settings), bundleSchema(read(schemaPath), read(sharedPath)))));
