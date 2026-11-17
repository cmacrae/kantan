// The bar's modules where they're drawn, for picking one to edit, moving
// it, or adding another beside it.
import { useState } from "react";
import { BUILT_INS } from "../../builder/catalog.js";
import { Button, Ic, useBuilder } from "./ui.jsx";

// `modules` are the modules' configs, and `sections` where the bar draws
// them: each a `title`, the `items` it holds as indexes into `modules`,
// the `placement` a module dropped on it takes, a `note`, and `fixed` when
// its modules can't be moved. `accepted` are the names of the modules
// kantan would load, and `selected` the index of the one being edited.
// `onAdd(placement)` asks for a module to be added to a section.
export function ModuleList({ modules, sections, accepted, selected, onSelect, onPlace, onPlaceIn, onAdd }) {
  const { icons } = useBuilder();
  const [dragged, setDragged] = useState();
  const [over, setOver] = useState();
  const end = () => { setDragged(undefined); setOver(undefined); };

  const item = (section, index, position) => {
    const module = modules[index];
    const up = section.items[position - 1], down = section.items[position + 1];
    const drop = section.fixed ? {} : {
      onDragOver: event => { event.preventDefault(); setOver(index); },
      onDragLeave: () => setOver(current => (current === index ? undefined : current)),
      onDrop: event => { event.preventDefault(); if (dragged !== undefined) onPlace(dragged, index, false); end(); },
    };
    return (
      <li key={index} className={`kb-item ${selected === index ? "on" : ""} ${over === index && dragged !== index ? "over" : ""}`}
        draggable={!section.fixed} onClick={() => onSelect(index)} onDragEnd={end} {...drop}
        onDragStart={event => { setDragged(index); event.dataTransfer.effectAllowed = "move"; event.dataTransfer.setData("text/plain", String(index)); }}>
        <span className="kb-glyph"><Ic name={icons(module?.icon ?? "") ? module.icon : BUILT_INS[module?.type]?.icon ?? "puzzle"} size={16} /></span>
        <span className="name">{module?.name ?? "(no name)"}</span>
        {!accepted.has(module?.name) && <span className="tag out" title="kantan would leave this module out">left out</span>}
        {!section.fixed && (
          <span className="moves">
            <Button kind="plain" icon="chevron-up" aria-label={`Move ${module?.name} earlier`} disabled={up === undefined}
              onClick={event => { event.stopPropagation(); onPlace(index, up, false); }} />
            <Button kind="plain" icon="chevron-down" aria-label={`Move ${module?.name} later`} disabled={down === undefined}
              onClick={event => { event.stopPropagation(); onPlace(index, down, true); }} />
          </span>
        )}
      </li>
    );
  };

  return (
    <>
      <h2><span>Modules</span></h2>
      <ul className="kb-list">
        {sections.map(section => {
          const target = section.placement !== undefined && dragged !== undefined;
          return (
            <li key={section.title}>
              <h3 className={over === section.title ? "over" : ""}
                onDragOver={target ? event => { event.preventDefault(); setOver(section.title); } : undefined}
                onDragLeave={() => setOver(current => (current === section.title ? undefined : current))}
                onDrop={target ? event => { event.preventDefault(); onPlaceIn(dragged, section.placement, false); end(); } : undefined}>
                <span>{section.title}</span>
                {section.placement !== undefined && (
                  <Button kind="plain" icon="plus" aria-label={`Add a module to ${section.title}`} onClick={() => onAdd(section.placement)}>Add</Button>
                )}
              </h3>
              {section.note && <div className="kb-note" style={{ padding: "0 6px 4px" }}>{section.note}</div>}
              <ul>{section.items.map((index, position) => item(section, index, position))}</ul>
            </li>
          );
        })}
      </ul>
    </>
  );
}
