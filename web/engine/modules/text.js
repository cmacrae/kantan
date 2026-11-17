// The text module: shows its `value`.
import { plainState } from "../output.js";
import { str } from "../values.js";

export default {
  load(config) {
    const value = str(config?.value);
    return value === undefined ? undefined : { value };
  },
  state: loaded => plainState(loaded.value),
};
