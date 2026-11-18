// kantan's module types. Each loads its `config` block, returning undefined
// when kantan would reject the module, and makes the state it shows from a
// sample of what it would read: a command's output, or a reading of the
// system such as the battery's level.
import bluetooth from "./bluetooth.js";
import clock from "./clock.js";
import command from "./command.js";
import drawer from "./drawer.js";
import focus from "./focus.js";
import icon from "./icon.js";
import power from "./power.js";
import text from "./text.js";
import volume from "./volume.js";
import waveform from "./waveform.js";
import wifi from "./wifi.js";
import workspace from "./workspace.js";

const implemented = { bluetooth, clock, command, drawer, focus, icon, power, text, volume, waveform, wifi, workspace };

export const MODULE_TYPES = Object.keys(implemented);

export const moduleType = type => (Object.hasOwn(implemented, type) ? implemented[type] : undefined);
