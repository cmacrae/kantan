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
.kb-stage-controls { display: flex; flex-wrap: wrap; gap: 6px 14px; align-items: center; justify-content: space-between; width: 100%; margin-top: 10px; color: var(--muted); }
.kb-stage-controls > div { display: flex; gap: 6px; align-items: center; flex-wrap: wrap; }

.kb-banner { max-width: 1500px; margin: 0 auto 10px; padding: 8px 12px; border-radius: 8px; border: 1px solid var(--warn); color: var(--warn); display: flex; gap: 8px; align-items: center; }
.kb-banner span { flex: 1; }

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
.kb-quick .kb-f { grid-template-columns: 84px minmax(0, 1fr); }
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
`;
