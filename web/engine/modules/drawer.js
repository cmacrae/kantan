// The drawer module: folds the modules beside it away until it is clicked.
// Its sample is `{ open }`; without one, the drawer is closed.
import { plainState } from "../output.js";
import { str } from "../values.js";

export default {
  load(config) {
    return { showIcon: str(config?.icons?.show) ?? "box-align-right", hideIcon: str(config?.icons?.hide) ?? "box-align-left" };
  },

  state(loaded, sample) {
    const state = plainState("");
    state.open = sample?.open === true;
    state.icon = state.open ? loaded.hideIcon : loaded.showIcon;
    return state;
  },
};
