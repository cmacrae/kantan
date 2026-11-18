// The builder's own look, in the site's colours for either appearance.
export const STYLES = `
.kb {
  --bg: #faf9f5; --fg: #191918; --muted: rgba(25,25,24,0.58); --faint: rgba(25,25,24,0.4);
  --line: rgba(25,25,24,0.12); --panel: #ffffff; --field: #ffffff; --code: #eeeee8;
  --accent: #c4593a; --accent-fg: #ffffff; --warn: #a15c00; --hover: rgba(25,25,24,0.05);
  --yaml-string: #40a02b; --yaml-number: #d76a00;
  min-height: 100vh; background: var(--bg); color: var(--fg);
  font: 13px/1.45 -apple-system, BlinkMacSystemFont, 'Helvetica Neue', Helvetica, sans-serif;
}
@media (prefers-color-scheme: dark) {
  .kb {
    --bg: #141413; --fg: #e8e6dc; --muted: rgba(232,230,220,0.62); --faint: rgba(232,230,220,0.42);
    --line: rgba(232,230,220,0.14); --panel: #1c1c1b; --field: #242423; --code: #1c1c1b;
    --accent: #d97757; --accent-fg: #141413; --warn: #e0a458; --hover: rgba(232,230,220,0.07);
    --yaml-string: #a6e3a1; --yaml-number: #fab387;
    color-scheme: dark;
  }
}
.kb a { color: inherit; }
.kb button, .kb input, .kb select, .kb textarea { font: inherit; color: inherit; }
.kb-top { display: flex; align-items: center; gap: 8px 16px; flex-wrap: wrap; padding: 14px 20px; max-width: 1500px; margin: 0 auto; }
.kb-brand { display: flex; align-items: baseline; gap: 8px; text-decoration: none; margin-right: auto; }
.kb-brand b { font: 400 26px/1 'Single Day', sans-serif; }
.kb-brand span { color: var(--muted); font: 400 22px/1 'Single Day', sans-serif; }
.kb-actions { display: flex; align-items: center; gap: 6px; flex-wrap: wrap; }

.kb-btn {
  display: inline-flex; align-items: center; gap: 6px; padding: 5px 10px; border-radius: 6px;
  border: 1px solid var(--line); background: var(--panel); cursor: pointer; white-space: nowrap; text-decoration: none;
}
.kb-btn:hover { background: var(--hover); }
.kb-btn:disabled { opacity: 0.45; cursor: default; }
.kb-btn.primary { background: var(--accent); border-color: var(--accent); color: var(--accent-fg); font-weight: 600; }
.kb-btn.plain { border-color: transparent; background: none; padding: 4px 6px; }
.kb-btn.plain:hover { background: var(--hover); }
.kb-btn.on { border-color: var(--accent); color: var(--accent); }
.kb-ic { display: inline-block; line-height: 1; flex-shrink: 0; }

.kb-col { display: flex; flex-direction: column; gap: 14px; min-width: 0; }
.kb-barcard { display: flex; align-items: center; gap: 10px; padding: 10px 12px; cursor: pointer; text-align: left; width: 100%; }
.kb-barcard.on { border-color: var(--accent); }
.kb-barcard > span:last-child { display: flex; flex-direction: column; }
.kb-barcard > span:last-child > span { color: var(--muted); font-size: 12px; }
.kb-stage { position: sticky; top: 0; z-index: 20; background: var(--bg); padding: 4px 20px 12px; }
.kb-stage-inner { max-width: 1500px; margin: 0 auto; }
.kb-desk { position: relative; width: 100%; min-width: max-content; border-radius: 10px; box-shadow: 0 6px 30px rgba(0,0,0,0.14), 0 1px 4px rgba(0,0,0,0.08); }
.kb-desk-paper { position: absolute; inset: 0; border-radius: 10px; }
.kb-desk-room { position: relative; height: 84px; }
.kb-hint { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; padding: 0 20px; text-align: center; font-size: 13px; pointer-events: none; user-select: none; transition: opacity 0.6s ease; }
.kb-hint.gone { opacity: 0; }
.kb-stage-controls { display: flex; flex-wrap: wrap; gap: 6px 14px; align-items: center; justify-content: space-between; width: 100%; margin-top: 10px; color: var(--muted); }
.kb-stage-controls > div { display: flex; gap: 6px; align-items: center; flex-wrap: wrap; }

.kb-banner { max-width: 1500px; margin: 0 auto 10px; padding: 8px 12px; border-radius: 8px; border: 1px solid var(--warn); color: var(--warn); display: flex; gap: 8px; align-items: center; }
.kb-banner span { flex: 1; }
.kb-banner.note { border-color: var(--line); color: var(--muted); }

.kb-tabs { display: none; gap: 4px; padding: 0 20px 10px; }
.kb-tabs button { flex: 1; justify-content: center; }
.kb-panes { display: grid; grid-template-columns: 270px minmax(360px, 1fr) minmax(320px, 440px); gap: 14px; padding: 4px 20px 40px; max-width: 1500px; margin: 0 auto; align-items: start; }
.kb-pane { background: var(--panel); border: 1px solid var(--line); border-radius: 10px; min-width: 0; }
.kb-pane > h2 { display: flex; align-items: center; gap: 8px; font-size: 13px; font-weight: 600; text-align: left; padding: 10px 12px; border-bottom: 1px solid var(--line); }
.kb-pane > h2 > span:not(.kb-ic) { flex: 1; min-width: 0; text-align: left; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.kb-body { padding: 12px; }
@media (max-width: 1080px) {
  .kb-top { padding: 10px 12px; }
  .kb-stage { padding: 4px 12px 10px; }
  .kb-tabs { display: flex; padding: 0 12px 10px; }
  .kb-panes { display: block; padding: 0 12px 32px; }
  .kb-panes > * { display: none; }
  .kb-panes > .on { display: block; }
  .kb-panes > .kb-col.on { display: flex; }
  .kb-stage-inner { overflow-x: auto; }
  .kb-desk-room { height: 150px; }
}

.kb-list, .kb-list ul { list-style: none; }
.kb-list { padding: 6px; }
.kb-list h3.over { color: var(--accent); box-shadow: 0 2px 0 var(--accent); }
.kb-list h3 { font-size: 11px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.04em; color: var(--faint); padding: 8px 6px 4px; }
.kb-item { display: flex; align-items: center; gap: 8px; padding: 5px 6px; border-radius: 6px; cursor: pointer; border: 1px solid transparent; }
.kb-item:hover { background: var(--hover); }
.kb-item.on { border-color: var(--accent); background: var(--hover); }
.kb-item.over { box-shadow: 0 -2px 0 var(--accent); }
.kb-item .name { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.kb-item .tag { font-size: 11px; color: var(--faint); white-space: nowrap; }
.kb-item .out { color: var(--warn); }
.kb-item .moves { display: none; }
.kb-item:hover .moves, .kb-item.on .moves { display: flex; }
.kb-item:hover .tag:not(.out), .kb-item.on .tag:not(.out) { display: none; }
.kb-glyph { width: 20px; text-align: center; flex-shrink: 0; }

.kb-subtabs { display: flex; gap: 2px; padding: 8px 12px 0; border-bottom: 1px solid var(--line); }
.kb-subtabs button { background: none; border: none; padding: 6px 10px; cursor: pointer; color: var(--muted); border-bottom: 2px solid transparent; margin-bottom: -1px; }
.kb-subtabs button[aria-selected="true"] { color: var(--fg); border-bottom-color: var(--accent); font-weight: 600; }

.kb-f { display: grid; grid-template-columns: minmax(90px, 150px) minmax(0, 1fr); gap: 4px 10px; align-items: center; padding: 4px 0; }
.kb-f > .label { color: var(--muted); overflow-wrap: anywhere; }
.kb-f > .label[title] { cursor: help; }
.kb-f.wide { grid-template-columns: minmax(0, 1fr); }
.kb-row { display: flex; gap: 6px; align-items: center; min-width: 0; }
.kb-row > input[type="text"], .kb-row > input[type="number"], .kb-row > select, .kb-row > textarea { flex: 1; min-width: 0; }
.kb input[type="text"], .kb input[type="number"], .kb input[type="url"], .kb select, .kb textarea {
  background: var(--field); border: 1px solid var(--line); border-radius: 6px; padding: 4px 7px; min-width: 0; width: 100%;
}
.kb textarea { font: 12px/1.5 'SF Mono', Menlo, Monaco, monospace; resize: vertical; min-height: 64px; tab-size: 2; }
.kb input:focus-visible, .kb select:focus-visible, .kb textarea:focus-visible, .kb button:focus-visible { outline: 2px solid var(--accent); outline-offset: 1px; }
.kb input[type="range"] { flex: 1; min-width: 0; accent-color: var(--accent); }
.kb input[type="checkbox"] { accent-color: var(--accent); width: 15px; height: 15px; }
.kb-problem { color: var(--warn); font-size: 12px; padding: 2px 0; }
.kb-note { color: var(--muted); font-size: 12px; padding: 4px 0; }
.kb-group { border: 1px solid var(--line); border-radius: 8px; margin: 8px 0; }
.kb-group > summary { padding: 6px 10px; cursor: pointer; font-weight: 600; list-style-position: inside; }
.kb-group > summary .set { color: var(--accent); font-weight: 400; font-size: 11px; margin-left: 6px; }
.kb-group > div { padding: 2px 10px 8px; }
.kb-swatch { width: 24px; height: 24px; border-radius: 6px; border: 1px solid var(--line); flex-shrink: 0; position: relative; overflow: hidden; }
.kb-swatch input { position: absolute; inset: -6px; width: 40px; height: 40px; opacity: 0; cursor: pointer; }
.kb-iconbtn { width: 30px; height: 28px; display: inline-flex; align-items: center; justify-content: center; border: 1px solid var(--line); border-radius: 6px; background: var(--field); cursor: pointer; flex-shrink: 0; }

.kb-chips { display: flex; flex-wrap: wrap; gap: 6px; padding: 2px 0 8px; }
.kb-chip { padding: 3px 10px; border-radius: 999px; border: 1px solid var(--line); background: none; cursor: pointer; }
.kb-chip[aria-pressed="true"] { border-color: var(--accent); color: var(--accent); font-weight: 600; }

.kb-code { margin: 0; padding: 12px 14px; background: var(--code); font: 12px/1.6 'SF Mono', Menlo, Monaco, monospace; overflow: auto; max-height: 70vh; border-radius: 0 0 10px 10px; }
.kb-file { display: flex; align-items: center; gap: 8px; padding: 6px 12px; border-top: 1px solid var(--line); color: var(--muted); font: 12px 'SF Mono', Menlo, Monaco, monospace; }
.kb-file > button:first-child { flex: 1; min-width: 0; display: flex; align-items: center; gap: 6px; padding: 2px 0; background: none; border: none; cursor: pointer; text-align: left; font: inherit; }
.kb .kb-file > button:first-child { color: var(--muted); }
.kb .kb-file > button:first-child:hover { color: var(--fg); }
.kb-file > button:first-child > span:last-child { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.kb-file + .kb-code { border-radius: 0; max-height: none; }

.kb-shade { position: fixed; inset: 0; z-index: 1000; background: rgba(0,0,0,0.4); display: flex; align-items: flex-start; justify-content: center; padding: 6vh 12px 12px; overflow: auto; }
.kb-modal { background: var(--panel); color: var(--fg); border-radius: 12px; border: 1px solid var(--line); width: min(640px, 100%); box-shadow: 0 20px 80px rgba(0,0,0,0.35); }
.kb-modal > h2 { display: flex; align-items: center; text-align: left; padding: 12px 14px; font-size: 14px; border-bottom: 1px solid var(--line); }
.kb-modal > h2 span { flex: 1; }
.kb-modal > div { padding: 14px; }
.kb-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 6px; }
.kb-card { display: flex; align-items: center; gap: 8px; padding: 8px 10px; border: 1px solid var(--line); border-radius: 8px; background: none; cursor: pointer; text-align: left; }
.kb-card:hover { border-color: var(--accent); }
.kb-icons { display: grid; grid-template-columns: repeat(auto-fill, minmax(44px, 1fr)); gap: 4px; max-height: 50vh; overflow: auto; margin-top: 10px; }
.kb-icons button { height: 44px; border: 1px solid transparent; border-radius: 8px; background: none; cursor: pointer; }
.kb-icons button:hover, .kb-icons button[aria-pressed="true"] { border-color: var(--accent); background: var(--hover); }
.kb-h { font-size: 11px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.04em; color: var(--faint); margin: 12px 0 6px; }
.kb-h:first-child { margin-top: 0; }
.kb-theme { display: inline-flex; flex-direction: column; gap: 4px; padding: 4px; border: 1.5px solid transparent; border-radius: 10px; background: none; cursor: pointer; text-align: left; }
.kb-theme:hover { background: var(--hover); }
.kb-theme[aria-pressed="true"] { border-color: var(--accent); }
.kb-theme .face { display: flex; flex-direction: column; justify-content: space-between; width: 104px; height: 58px; padding: 7px 8px; border-radius: 7px; border: 1px solid var(--line); }
.kb-theme .face b { font-size: 15px; line-height: 1; }
.kb-theme .dots { display: flex; gap: 3px; }
.kb-theme .dots i { width: 10px; height: 10px; border-radius: 50%; }
.kb-theme .name { font-size: 12px; padding: 0 2px; }
.kb-theme-row { margin: 6px 0 10px; }
.kb-theme-mode { font-weight: 600; padding: 2px 0 4px; }
.kb-theme-set { display: flex; flex-wrap: wrap; gap: 4px; }
.kb-shot { display: flex; align-items: center; justify-content: center; min-height: 120px; border: 1px solid var(--line); border-radius: 8px; background: var(--code); overflow: hidden; }
.kb-shot img { display: block; max-width: 100%; height: auto; }
.kb .kb-problem .kb-btn { color: var(--fg); }
.kb-gallery { display: grid; grid-template-columns: repeat(auto-fill, minmax(118px, 1fr)); gap: 2px; max-height: 300px; overflow: auto; padding: 4px; border: 1px solid var(--line); border-radius: 8px; }
.kb-gallery .kb-theme .name { max-width: 104px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.kb-gallery .kb-theme:disabled { cursor: default; }
.kb-gallery .kb-theme { position: relative; }
.kb-theme .pills { position: absolute; top: 8px; right: 8px; display: flex; gap: 3px; }
.kb-theme .pills i { font-style: normal; font-size: 10px; font-weight: 600; line-height: 1; padding: 3px 6px; border-radius: 999px; background: var(--accent); color: var(--accent-fg); text-transform: capitalize; }
.kb-slots { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 8px; }
.kb-slotcard { display: flex; align-items: center; border: 1.5px solid var(--line); border-radius: 10px; }
.kb-slotcard.on { border-color: var(--accent); }
.kb-slotcard > button:first-child { flex: 1; min-width: 0; display: flex; align-items: center; gap: 10px; padding: 6px; background: none; border: none; border-radius: 9px; cursor: pointer; text-align: left; }
.kb-slotcard .face { display: flex; flex-direction: column; justify-content: space-between; flex-shrink: 0; width: 84px; height: 46px; padding: 6px 7px; border-radius: 7px; border: 1px solid var(--line); }
.kb-slotcard .face b { font-size: 13px; line-height: 1; }
.kb-slotcard .dots { display: flex; gap: 3px; }
.kb-slotcard .dots i { width: 8px; height: 8px; border-radius: 50%; }
.kb-slotcard > button > span:last-child { display: flex; flex-direction: column; min-width: 0; }
.kb-slotcard > button > span:last-child > span { color: var(--muted); font-size: 12px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.kb-themes { list-style: none; margin-bottom: 8px; }
.kb-themes li { display: flex; align-items: center; gap: 8px; padding: 2px 0; }
.kb-themes li > span:first-child { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.kb-themes .tag { font-size: 11px; color: var(--faint); white-space: nowrap; }
.kb-tc { display: grid; grid-template-columns: minmax(70px, 150px) minmax(0, 1fr) auto; gap: 4px 8px; align-items: start; padding: 3px 0; }
.kb-note code, .kb-problem code { font-family: 'SF Mono', Menlo, Monaco, monospace; font-size: 11.5px; }

.kb-quick { position: absolute; z-index: 400; background: var(--panel); color: var(--fg); border: 1px solid var(--line); border-radius: 12px; padding: 10px 12px; box-shadow: 0 12px 40px rgba(0,0,0,0.25); }
.kb-quick .arrow { position: absolute; top: -7px; width: 12px; height: 12px; margin-left: -6px; background: var(--panel); border: 1px solid var(--line); border-right: none; border-bottom: none; transform: rotate(45deg); }
.kb-quick .head { display: flex; align-items: baseline; gap: 8px; padding-bottom: 4px; }
.kb-quick .head span { flex: 1; color: var(--muted); font-size: 12px; }
.kb-quick .kb-f { grid-template-columns: 104px minmax(0, 1fr); }
.kb-quick .foot { display: flex; justify-content: space-between; gap: 8px; margin-top: 8px; padding-top: 8px; border-top: 1px solid var(--line); }
.kb-swatch.inherited { opacity: 0.55; }
.kb-colors { position: relative; flex: 0 0 auto; }
.kb-colors > button { display: flex; align-items: center; gap: 6px; width: 124px; padding: 4px 7px; background: var(--field); border: 1px solid var(--line); border-radius: 6px; cursor: pointer; }
.kb-colors > button > span { flex: 1; text-align: left; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.kb-colors .unset { color: var(--muted); }
.kb-colors .dot { width: 11px; height: 11px; border-radius: 50%; flex-shrink: 0; border: 1px solid var(--line); }
.kb-colors ul { position: absolute; right: 0; top: calc(100% + 4px); z-index: 500; width: 170px; max-height: 260px; overflow: auto; list-style: none; padding: 4px; background: var(--panel); border: 1px solid var(--line); border-radius: 8px; box-shadow: 0 10px 30px rgba(0,0,0,0.25); }
.kb-colors li button { display: flex; align-items: center; gap: 8px; width: 100%; padding: 4px 6px; background: none; border: none; border-radius: 5px; cursor: pointer; text-align: left; }
.kb-colors li button:hover, .kb-colors li[aria-selected="true"] button { background: var(--hover); }

.kb-slot { position: absolute; z-index: 5; top: 4px; border-radius: 7px; pointer-events: none; display: flex; align-items: center; justify-content: center; border: none; padding: 0; }
.kb-slot.add { pointer-events: auto; cursor: pointer; }
.kb-list h3 { display: flex; align-items: center; }
.kb-list h3 > span { flex: 1; }
.kb-list h3 .kb-btn { text-transform: none; letter-spacing: 0; font-weight: 400; color: var(--muted); padding: 1px 6px; }
.kb-notice { position: absolute; z-index: 6; left: 50%; transform: translateX(-50%); width: 330px; display: flex; gap: 10px; align-items: flex-start; padding: 9px 12px; border-radius: 12px; font: 12px/1.4 -apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif; white-space: normal; text-align: left; color: #1d1d1f; background: rgba(246,246,246,0.92); backdrop-filter: blur(20px); -webkit-backdrop-filter: blur(20px); box-shadow: 0 8px 28px rgba(0,0,0,0.28), 0 0 0 0.5px rgba(0,0,0,0.12); }
.kb-notice .kb-ic { color: #e0900a; margin-top: 1px; }
.kb-notice b { display: block; font-size: 13px; }
.kb-notice .arrow { position: absolute; top: -5px; left: 50%; width: 10px; height: 10px; margin-left: -5px; background: inherit; transform: rotate(45deg); border-radius: 2px 0 0 0; }
.kb-tip { position: relative; }
.kb-tip:hover::after, .kb-tip:focus-visible::after { content: attr(data-tip); position: absolute; left: 0; top: calc(100% + 6px); z-index: 30; width: max-content; max-width: min(320px, 80vw); padding: 6px 9px; border-radius: 7px; background: var(--fg); color: var(--bg); font-size: 12px; font-weight: 400; line-height: 1.4; text-align: left; white-space: normal; pointer-events: none; box-shadow: 0 6px 20px rgba(0,0,0,0.25); }
.kb-keyhint { font-size: 12px; color: var(--faint); white-space: nowrap; }
.kb kbd { display: inline-block; padding: 1px 6px; margin: 0 3px; border: 1px solid var(--line); border-bottom-width: 2px; border-radius: 5px; background: var(--panel); color: var(--muted); font: 11px/1.5 -apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif; }
@media (hover: none) { .kb-keyhint, .kb-fold kbd { display: none; } }
.kb-fold { display: flex; flex-direction: column; align-items: center; margin: 2px auto -6px; padding: 0 28px 2px; background: none; border: none; border-radius: 8px; cursor: pointer; color: var(--faint); line-height: 0; }
.kb .kb-fold { color: var(--faint); }
.kb .kb-fold:hover, .kb .kb-fold:hover > span:first-child { color: var(--fg); }
.kb .kb-fold:focus-visible { outline: none; color: var(--fg); }
.kb [hidden] { display: none !important; }
.kb-fold > span:first-child:not(.kb-ic) { font-size: 12px; line-height: 1.4; color: var(--faint); }
.kb ::placeholder { color: var(--faint); opacity: 1; }
.kb-tree { padding: 0; margin: 4px 0 8px; border: 1px solid var(--line); border-radius: 8px; max-height: 320px; overflow: auto; }
.kb-tree .kb-item { border-radius: 0; padding-top: 4px; padding-bottom: 4px; }
.kb-tree .kb-item.into { box-shadow: inset 0 0 0 1.5px var(--accent); }
.kb-tree .name { font-weight: 400; }
.kb-tree .name b { font-weight: 600; }
.kb-tree .name i { color: var(--faint); font-style: normal; }
.kb-tree .kb-item .moves .kb-btn { padding: 1px 4px; }
.kb-nodepicker .head { display: flex; align-items: center; justify-content: space-between; margin-bottom: 6px; }
.kb-nodegrid { display: grid; grid-template-columns: repeat(auto-fill, minmax(190px, 1fr)); gap: 6px; }
.kb-nodegrid > button { display: flex; align-items: flex-start; gap: 8px; padding: 8px 10px; border: 1px solid var(--line); border-radius: 8px; background: none; cursor: pointer; text-align: left; }
.kb-nodegrid > button:hover { border-color: var(--accent); background: var(--hover); }
.kb-nodegrid > button > .kb-ic { margin-top: 2px; flex-shrink: 0; }
.kb-nodegrid > button > span { display: flex; flex-direction: column; gap: 1px; min-width: 0; }
.kb-nodegrid > button > span > span { color: var(--muted); font-size: 12px; line-height: 1.35; }
.kb-seg { display: inline-flex; border: 1px solid var(--line); border-radius: 8px; padding: 2px; gap: 2px; background: var(--field); }
.kb-seg > button { display: inline-flex; align-items: center; gap: 5px; padding: 4px 11px; border: none; border-radius: 6px; background: none; cursor: pointer; white-space: nowrap; }
.kb .kb-seg > button { color: var(--muted); }
.kb .kb-seg > button[aria-pressed="true"] { background: var(--accent); color: var(--accent-fg); font-weight: 600; }
.kb-viewshade { padding: 3vh 2vw; align-items: stretch; overflow: hidden; }
.kb-view { display: flex; flex-direction: column; width: min(1500px, 100%); height: 94vh; background: var(--panel); color: var(--fg); border: 1px solid var(--line); border-radius: 14px; box-shadow: 0 20px 80px rgba(0,0,0,0.4); overflow: hidden; }
.kb-view-top { display: flex; align-items: center; gap: 12px; padding: 10px 14px; border-bottom: 1px solid var(--line); flex-wrap: wrap; }
.kb-view-top .title { display: flex; align-items: center; gap: 7px; font-size: 14px; }
.kb-view-top .title > span { color: var(--muted); }
.kb-view-top .grow { flex: 1; }
.kb-view-split { flex: 1; min-height: 0; display: grid; grid-template-columns: var(--split) 9px minmax(0, 1fr); }
.kb-view-stage { display: flex; flex-direction: column; gap: 8px; padding: 14px; min-width: 0; min-height: 0; overflow: auto; background: var(--bg); }
.kb-view-desk { position: relative; flex: 1 0 auto; min-height: 320px; border-radius: 10px; box-shadow: 0 6px 30px rgba(0,0,0,0.14), 0 1px 4px rgba(0,0,0,0.08); }
.kb-view-desk .empty { position: absolute; left: 0; right: 0; top: 46%; padding: 0 18px; text-align: center; color: rgba(255,255,255,0.75); font-size: 12.5px; text-shadow: 0 1px 3px rgba(0,0,0,0.5); }
.kb-shared { max-width: 900px; margin: 0 auto; padding: 4px 20px 48px; display: flex; flex-direction: column; gap: 14px; }
.kb-shared h1 { margin: 0; font-size: 20px; font-weight: 600; }
.kb-shared-desk { position: relative; min-height: 120px; border-radius: 10px; box-shadow: 0 6px 30px rgba(0,0,0,0.14), 0 1px 4px rgba(0,0,0,0.08); }
.kb-shared-desk .empty { position: absolute; left: 0; right: 0; top: 58%; text-align: center; color: rgba(255,255,255,0.75); font-size: 12.5px; text-shadow: 0 1px 3px rgba(0,0,0,0.5); }
.kb-shared-under { display: flex; align-items: center; gap: 8px 16px; flex-wrap: wrap; }
.kb-shared-under .kb-chips { padding: 0; }
.kb-shared-under > .kb-btn { margin-left: auto; }
.kb-shared .kb-code { max-height: none; }
.kb-view-under { display: flex; align-items: center; justify-content: space-between; gap: 8px; flex-wrap: wrap; }
.kb-view-under .kb-chips { padding: 0; }
.kb-view-grip { cursor: col-resize; background: var(--line); background-clip: content-box; padding: 0 4px; touch-action: none; }
.kb-view-grip:hover, .kb-view-grip:focus-visible { background-color: var(--accent); outline: none; }
.kb-view-work { display: flex; flex-direction: column; min-width: 0; min-height: 0; }
.kb-view-bar { display: flex; align-items: flex-end; justify-content: space-between; gap: 12px; flex-wrap: wrap; border-bottom: 1px solid var(--line); padding-right: 14px; }
.kb-view-bar .kb-subtabs { border-bottom: none; }
.kb-view-from { display: flex; align-items: center; gap: 8px; padding: 6px 0; color: var(--muted); font-size: 12px; }
.kb-view-notes { padding: 8px 14px 0; }
.kb-view-notes:empty { display: none; }
.kb-tagdemo { color: var(--warn); font-size: 11px; }
.kb-view-design { flex: 1; min-height: 0; display: grid; grid-template-columns: minmax(240px, 2fr) minmax(280px, 3fr); }
.kb-view-layers, .kb-view-inspect { padding: 10px 14px 14px; overflow: auto; min-height: 0; }
.kb-view-layers { border-right: 1px solid var(--line); }
.kb-view-layers .kb-tree { max-height: none; }
.kb-view-head { display: flex; align-items: center; justify-content: space-between; gap: 8px; min-height: 30px; }
.kb-view-head .kb-h { margin: 0; }
.kb-view-head code { color: var(--faint); font: 11.5px 'SF Mono', Menlo, Monaco, monospace; }
.kb-view-foot { margin-top: 16px; padding-top: 10px; border-top: 1px solid var(--line); }
.kb-view-start { padding: 22px 14px; max-width: 900px; overflow: auto; }
.kb-view-start .chips { display: flex; flex-wrap: wrap; gap: 6px; color: var(--muted); font: 11.5px 'SF Mono', Menlo, Monaco, monospace; }
.kb-startgrid { display: grid; grid-template-columns: repeat(auto-fill, minmax(250px, 1fr)); gap: 10px; margin-top: 12px; align-items: stretch; }
.kb-startgrid > button { display: flex; flex-direction: column; gap: 8px; padding: 8px; border: 1px solid var(--line); border-radius: 10px; background: none; cursor: pointer; text-align: left; }
.kb-startgrid > button:hover { border-color: var(--accent); background: var(--hover); }
.kb-startgrid > button > span { display: flex; flex-direction: column; gap: 1px; padding: 0 2px 2px; }
.kb-startgrid > button > span > span { color: var(--muted); font-size: 12px; line-height: 1.35; }
.kb-thumb { height: 150px; overflow: hidden; border-radius: 7px; background: var(--code); display: flex; align-items: flex-start; justify-content: center; padding: 10px; pointer-events: none; }
.kb-thumb > div { zoom: 0.7; flex-shrink: 0; }
.kb-view-start h3 { font-size: 15px; margin-bottom: 2px; }
.kb-view-start .kb-nodegrid { margin-top: 10px; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); }
.kb-handoff { flex: 1; min-height: 0; overflow: auto; padding: 10px 14px 14px; }
.kb-handoff a { color: var(--accent); }
.kb-snippet { border: 1px solid var(--line); border-radius: 10px; margin-top: 10px; overflow: hidden; }
.kb-snippet > header { display: flex; align-items: flex-start; gap: 10px; padding: 9px 10px; border-bottom: 1px solid var(--line); }
.kb-snippet .step { flex-shrink: 0; width: 22px; height: 22px; border-radius: 50%; background: var(--accent); color: var(--accent-fg); font-weight: 700; font-size: 12px; display: flex; align-items: center; justify-content: center; }
.kb-snippet > header > span:nth-child(2) { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 2px; }
.kb-snippet > header > span:nth-child(2) > span { color: var(--muted); font-size: 12px; line-height: 1.45; }
.kb-snippet code { font: 11.5px 'SF Mono', Menlo, Monaco, monospace; }
.kb-snippet label { white-space: nowrap; }
.kb-snippet pre { margin: 0; padding: 10px 12px; max-height: 300px; overflow: auto; background: var(--code); font: 12px/1.5 'SF Mono', Menlo, Monaco, monospace; white-space: pre; }
@media (max-width: 860px) {
  .kb-viewshade { padding: 0; }
  .kb-view { height: 100vh; border-radius: 0; }
  .kb-view-split { display: flex; flex-direction: column; overflow: auto; }
  .kb-view-stage { flex: 0 0 auto; overflow: visible; }
  .kb-view-desk { min-height: 240px; }
  .kb-view-grip { display: none; }
  .kb-view-work { flex: 0 0 auto; }
  .kb-view-design { display: block; }
  .kb-view-layers { border-right: none; border-bottom: 1px solid var(--line); }
  .kb-view-layers, .kb-view-inspect, .kb-handoff { overflow: visible; }
}
.kb-cards { display: flex; flex-wrap: wrap; gap: 8px; padding: 6px 0; }
.kb-key { display: block; color: var(--faint); font: 10.5px/1.3 'SF Mono', Menlo, Monaco, monospace; overflow-wrap: anywhere; }
.kb-group > summary .kb-key { display: inline; margin-left: 8px; font-weight: 400; }
.kb-sec { padding: 12px 0 10px; border-top: 1px solid var(--line); }
.kb-sec > h3 { display: flex; align-items: baseline; gap: 7px; font-size: 13px; margin-bottom: 6px; }
.kb-sec > h3 > .kb-ic { align-self: center; color: var(--accent); }
.kb-sec > h3 > span:last-child { color: var(--muted); font-weight: 400; font-size: 12px; }
.kb-more { border-top: 1px solid var(--line); padding-top: 10px; }
.kb-more > summary { display: flex; align-items: baseline; gap: 7px; cursor: pointer; list-style: none; padding: 2px 0; }
.kb-more > summary::-webkit-details-marker { display: none; }
.kb-more > summary::after { content: "Show"; margin-left: auto; color: var(--accent); font-size: 12px; }
.kb-more[open] > summary::after { content: "Hide"; }
.kb-more > summary > .kb-ic { align-self: center; color: var(--faint); }
.kb-more > summary > span { color: var(--muted); font-size: 12px; }
.kb-more > div { padding-top: 8px; }
.kb-preview { --tint: rgba(64,120,220,0.09); --tint-line: rgba(64,120,220,0.4); --tint-fg: #2f62c9; margin-bottom: 12px; border: 1px dashed var(--tint-line); border-radius: 9px; background: var(--tint); }
@media (prefers-color-scheme: dark) { .kb-preview { --tint: rgba(110,160,255,0.09); --tint-line: rgba(110,160,255,0.42); --tint-fg: #8fb6ff; } }
.kb-preview > .head { display: flex; align-items: center; flex-wrap: wrap; gap: 6px 8px; padding: 7px 9px; }
.kb-preview > .head .kb-chips { flex: 1 1 auto; padding: 0; align-items: center; }
.kb-preview > .head > .kb-btn { margin-left: auto; }
.kb-preview > .body { padding: 2px 10px 10px; border-top: 1px dashed var(--tint-line); }
.kb-preview .badge { padding: 1px 7px; border-radius: 999px; border: 1px solid var(--tint-line); color: var(--tint-fg); font-size: 10.5px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.04em; white-space: nowrap; cursor: help; }
.kb .kb-preview .kb-chip[aria-pressed="true"] { border-color: var(--tint-fg); color: var(--tint-fg); }
.kb-quick .kb-preview { margin: 8px 0 0; }
.kb-opts { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 6px; }
.kb-opts > button { display: flex; align-items: flex-start; gap: 8px; padding: 8px 10px; border: 1.5px solid var(--line); border-radius: 9px; background: none; cursor: pointer; text-align: left; }
.kb-opts > button:hover { background: var(--hover); }
.kb-opts > button[aria-pressed="true"] { border-color: var(--accent); }
.kb .kb-opts > button[aria-pressed="true"] > .kb-ic { color: var(--accent); }
.kb-opts > button > .kb-ic { margin-top: 1px; }
.kb-opts > button > span { display: flex; flex-direction: column; gap: 1px; min-width: 0; }
.kb-opts > button > span > span { color: var(--muted); font-size: 12px; line-height: 1.35; }
.kb-addgrid { display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 8px; }
@media (max-width: 520px) {
  .kb-f { grid-template-columns: minmax(76px, 104px) minmax(0, 1fr); }
  .kb-colors > button { width: 92px; }
}
.kb-addcard { display: flex; flex-direction: column; gap: 6px; padding: 6px; border: 1px solid var(--line); border-radius: 10px; background: none; cursor: pointer; text-align: left; min-width: 0; }
.kb-addcard:hover { border-color: var(--accent); background: var(--hover); }
.kb-addcard .strip { display: block; border-radius: 6px; overflow: hidden; pointer-events: none; }
.kb-addcard > span:last-child { display: flex; flex-direction: column; gap: 1px; padding: 0 3px 2px; min-width: 0; }
.kb-addcard > span:last-child > span { color: var(--muted); font-size: 12px; line-height: 1.35; }
.kb-own { display: flex; align-items: center; flex-wrap: wrap; gap: 8px 12px; padding: 9px 12px; margin-bottom: 4px; border: 1px solid var(--accent); border-radius: 9px; }
.kb-own > .kb-ic { color: var(--accent); }
.kb-own > span:not(.kb-ic) { flex: 1 1 260px; color: var(--muted); font-size: 12px; }
.kb-own > span > b { display: block; color: var(--fg); font-size: 13px; }
.kb-link { background: none; border: none; padding: 0; cursor: pointer; text-decoration: underline; font: inherit; }
.kb .kb-link { color: var(--accent); }
.kb-view-under .kb-preview { flex: 1 1 auto; margin: 0; }
.kb-vars.kb-preview > .body { border-top: 1px dashed var(--tint-line); }
.kb-listed { margin: 8px 0; padding: 8px; border: 1px solid var(--line); border-radius: 8px; background: var(--panel); }
.kb-listed .table { display: grid; gap: 4px; align-items: center; margin: 4px 0; overflow-x: auto; }
.kb-listed .field input { font: 11.5px 'SF Mono', Menlo, Monaco, monospace; font-weight: 600; background: none; }
.kb-valchips { display: flex; flex-wrap: wrap; gap: 5px; padding: 2px 0 4px; max-height: 92px; overflow: auto; }
.kb-valchips > button { display: inline-flex; align-items: baseline; gap: 6px; max-width: 100%; padding: 2px 8px; border: 1px solid var(--line); border-radius: 6px; background: none; cursor: pointer; font-size: 12px; }
.kb-valchips > button:hover { border-color: var(--accent); }
.kb-valchips code { font: 11.5px 'SF Mono', Menlo, Monaco, monospace; }
.kb-valchips > button > span { color: var(--muted); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; max-width: 140px; }
.kb-vars { margin-top: 14px; }
.kb-vars .chips { display: flex; flex-wrap: wrap; gap: 5px; padding: 2px 0 6px; }
.kb-vars .chips > span { display: inline-flex; align-items: baseline; gap: 6px; max-width: 100%; padding: 2px 8px; border: 1px solid var(--line); border-radius: 6px; font-size: 12px; }
.kb-vars .chips > span > span { color: var(--muted); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; max-width: 140px; }
.kb-vars .kb-f { grid-template-columns: minmax(70px, 110px) minmax(0, 1fr); }
.kb-vars .chips > button { display: inline-flex; align-items: baseline; gap: 6px; max-width: 100%; padding: 2px 8px; border: 1px solid var(--line); border-radius: 6px; background: none; cursor: pointer; font-size: 12px; }
.kb-vars .chips > button:hover { border-color: var(--accent); }
.kb-vars .chips > button > span { color: var(--muted); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; max-width: 140px; }
.kb-vars code { font-family: 'SF Mono', Menlo, Monaco, monospace; font-size: 11.5px; }
`;
