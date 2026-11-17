// Picks one of Tabler's icons by searching their names.
import { useMemo, useState } from "react";
import { Ic, Modal, useBuilder } from "./ui.jsx";

// As many icons as are drawn at once. A search narrows them down.
const SHOWN = 240;

export function IconPicker({ value, onPick, onClose }) {
  const { iconNames } = useBuilder();
  const [query, setQuery] = useState("");
  const [filled, setFilled] = useState(value.endsWith("-filled"));
  const matches = useMemo(() => {
    const words = query.toLowerCase().split(/\s+/).filter(Boolean);
    return iconNames.filter(name => name.endsWith("-filled") === filled && words.every(word => name.includes(word)));
  }, [iconNames, query, filled]);

  return (
    <Modal title="Pick an icon" onClose={onClose}>
      <div className="kb-row">
        <input type="text" autoFocus placeholder="Search icons by name" aria-label="Search icons" value={query} spellCheck={false}
          onChange={event => setQuery(event.target.value)} />
        <label className="kb-row" style={{ flex: "0 0 auto" }}>
          <input type="checkbox" checked={filled} onChange={event => setFilled(event.target.checked)} />
          <span>Filled</span>
        </label>
      </div>
      <div className="kb-icons">
        {matches.slice(0, SHOWN).map(name => (
          <button key={name} type="button" title={name} aria-label={name} aria-pressed={name === value} onClick={() => onPick(name)}>
            <Ic name={name} size={22} />
          </button>
        ))}
      </div>
      <div className="kb-note">
        {iconNames.length === 0 ? "Loading the icons…"
          : matches.length === 0 ? "No icon has that name."
          : matches.length > SHOWN ? `Showing ${SHOWN} of ${matches.length}. Search to narrow them down.`
          : `${matches.length} icons`}
      </div>
    </Modal>
  );
}
