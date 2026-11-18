import { useState, useEffect } from "react";
import { latte, mocha, WORKSPACE_COLORS } from "../lib/theme.js";
import { I } from "./Icons.jsx";

function tokenize(...parts) {
  const tokens = [];
  for (const part of parts) {
    if (typeof part === "string") {
      for (const ch of part) {
        if (ch === "\n") tokens.push({ type: "break" });
        else tokens.push({ type: "char", ch });
      }
    } else {
      tokens.push(part);
    }
  }
  return tokens;
}

function LN(href, ...parts) {
  return tokenize(...parts).map(t => ({ ...t, href }));
}

const IC = (name, themeKey, opacity) => ({ type: "icon", name, themeKey, opacity });

const WORKSPACE_SCRIPTS = [
  /* 1 */ [
    { action: "type", tokens: tokenize("Welcome!"), speed: 80 },
    { action: "pause", ms: 2000 },
    { action: "clear", speed: 45 },
    { action: "pause", ms: 400 },
    { action: "type", tokens: tokenize(
      "Let's explore! Click around... I wonder what's on the other workspaces ",
      IC("point-filled", WORKSPACE_COLORS[0]), " ", IC("point-filled", WORKSPACE_COLORS[1], 0.4), " ", IC("point-filled", WORKSPACE_COLORS[2], 0.4),
    ), speed: 60 },
  ],
  /* 2 */ [
    { action: "type", tokens: tokenize("Try clicking the ", IC("box-align-right", "fg"), " icon to expand the drawer..."), speed: 50 },
  ],
  /* 3 */ [
      { action: "type", tokens: tokenize("What's in the Reminders list? ", IC("bell-filled", "maroon")), speed: 50 },
  ],
  /* 4 */ [
    { action: "type", tokens: tokenize("Hmm, let's see what's using up resources... ", IC("activity", "fg")), speed: 45 },
  ],
  /* 5 */ [
    { action: "type", tokens: tokenize("Time for a coffee break! ", IC("mug-filled", "rosewater")), speed: 50 },
  ],
  /* 6 */ [
    { action: "type", tokens: [
      ...tokenize("Ready to dive in?\n• "),
      ...LN("#install", "Install ", IC("app-window-filled")),
      ...tokenize("\n• "),
      ...LN("/docs/getting-started/", "Read the docs ", IC("book-filled")),
      ...tokenize("\n• "),
      ...LN("/builder/", "Build your bar ", IC("brush")),
    ], speed: 50 },
  ],
];

const CHAR_W = 7.5;
const ICON_W = 15;
const TERM_PAD = 28;
const PROMPT_W = 2 * CHAR_W;
const CURSOR_W = 8;
const MIN_TERM_W = 280;
const MAX_TERM_W = 360;
const LINE_H = 19;

function TerminalPane({ dark, themed, script, active, extraLines = 0 }) {
  const [displayed, setDisplayed] = useState([]);
  const [scriptIdx, setScriptIdx] = useState(0);
  const [tokenIdx, setTokenIdx] = useState(0);
  const [started, setStarted] = useState(false);
  const [done, setDone] = useState(false);
  const [cursorVisible, setCursorVisible] = useState(true);

  useEffect(() => {
    const id = setInterval(() => setCursorVisible(v => !v), 530);
    return () => clearInterval(id);
  }, []);

  useEffect(() => {
    if (active && !started) setStarted(true);
  }, [active, started]);

  useEffect(() => {
    if (!started || done) return;
    if (scriptIdx >= script.length) { setDone(true); return; }

    const step = script[scriptIdx];
    let timeout;

    switch (step.action) {
      case "type":
        if (tokenIdx < step.tokens.length) {
          timeout = setTimeout(() => {
            setDisplayed(d => [...d, step.tokens[tokenIdx]]);
            setTokenIdx(i => i + 1);
          }, step.speed || 60);
        } else {
          setTokenIdx(0);
          setScriptIdx(i => i + 1);
        }
        break;
      case "pause":
        timeout = setTimeout(() => setScriptIdx(i => i + 1), step.ms);
        break;
      case "clear":
        if (displayed.length > 0) {
          timeout = setTimeout(() => setDisplayed(d => d.slice(0, -1)), step.speed || 45);
        } else {
          setScriptIdx(i => i + 1);
        }
        break;
    }

    return () => clearTimeout(timeout);
  }, [started, done, scriptIdx, tokenIdx, displayed.length, script]);

  const textColor = dark ? "rgba(255,255,255,0.85)" : "rgba(0,0,0,0.8)";
  const promptColor = dark ? "#a6e3a1" : "#40a02b";
  const p = dark ? mocha : latte;
  const resolveColor = (key) => {
    if (!key) return textColor;
    if (themed) return key === "fg" ? p.fg : p[key] || textColor;
    return textColor;
  };

  const groups = [];
  let buf = "";
  let bufHref = undefined;
  const flushBuf = () => { if (buf) { groups.push({ type: "text", text: buf, href: bufHref }); buf = ""; } bufHref = undefined; };
  for (const token of displayed) {
    if (token.type === "break") {
      flushBuf();
      groups.push({ type: "break" });
    } else if (token.type === "char") {
      if (token.href !== bufHref) { flushBuf(); bufHref = token.href; }
      buf += token.ch;
    } else {
      flushBuf();
      groups.push(token);
    }
  }
  flushBuf();

  const linkColor = dark ? "rgba(140,170,255,0.9)" : "rgba(30,80,200,0.85)";

  const renderGroup = (g, key) => {
    if (g.type === "text") return <span key={key}>{g.text}</span>;
    return <I key={key} name={g.name} size={13} color={g.href ? linkColor : resolveColor(g.themeKey)}
      opacity={g.opacity != null ? g.opacity : 1}
      style={{ display: "inline-block", verticalAlign: "middle", margin: "0 1px" }} />;
  };

  const rendered = [];
  let gi = 0;
  while (gi < groups.length) {
    const g = groups[gi];
    if (g.type === "break") {
      rendered.push(<br key={`br-${gi}`} />);
      gi++;
    } else if (g.href) {
      const href = g.href;
      const linkItems = [];
      while (gi < groups.length && groups[gi].href === href) {
        linkItems.push(renderGroup(groups[gi], `l-${gi}`));
        gi++;
      }
      rendered.push(
        <a key={`a-${gi}`} href={href} style={{
          color: linkColor, textDecoration: "underline",
          textDecorationColor: dark ? "rgba(140,170,255,0.4)" : "rgba(30,80,200,0.3)",
          textUnderlineOffset: 2,
        }}>{linkItems}</a>
      );
    } else {
      rendered.push(renderGroup(g, gi));
      gi++;
    }
  }

  return (
    <div style={{
      padding: "10px 14px",
      fontFamily: "'SF Mono', Menlo, Monaco, monospace",
      fontSize: 12.5, lineHeight: 1.5, minHeight: 80 + extraLines * LINE_H,
    }}>
      <span style={{ color: promptColor }}>&#10095;</span>
      <span style={{ color: textColor }}>{" "}{rendered}</span>
      <span style={{
        display: "inline-block", width: 7, height: 15,
        background: textColor, marginLeft: 1, verticalAlign: "text-bottom",
        opacity: cursorVisible ? 0.8 : 0,
        transition: "opacity 0.08s",
      }} />
    </div>
  );
}

function computeTerminalInfo(script) {
  let allTokens = [];
  for (const step of script) {
    if (step.action === "type") allTokens = [...allTokens, ...step.tokens];
    else if (step.action === "clear") allTokens = [];
  }

  const lines = [[]];
  for (const t of allTokens) {
    if (t.type === "break") lines.push([]);
    else lines[lines.length - 1].push(t);
  }

  let maxLineW = 0;
  for (let li = 0; li < lines.length; li++) {
    let w = li === 0 ? PROMPT_W : 0;
    for (const t of lines[li]) w += t.type === "char" ? CHAR_W : ICON_W;
    if (w > maxLineW) maxLineW = w;
  }

  const ideal = Math.ceil(TERM_PAD + maxLineW + CURSOR_W);
  const width = Math.max(MIN_TERM_W, Math.min(ideal, MAX_TERM_W));

  const contentArea = width - TERM_PAD - CURSOR_W;
  let totalLines = 0;
  for (let li = 0; li < lines.length; li++) {
    let w = li === 0 ? PROMPT_W : 0;
    for (const t of lines[li]) w += t.type === "char" ? CHAR_W : ICON_W;
    totalLines += Math.max(1, Math.ceil(w / contentArea));
  }

  return { width, extraLines: totalLines - 1 };
}

const TERMINAL_INFO = WORKSPACE_SCRIPTS.map(computeTerminalInfo);

export function WorkspaceTerminals({ dark, themed, activeSpace }) {
  const titleBarBg = dark ? "rgba(40,40,48,0.95)" : "rgba(232,232,236,0.95)";
  const bodyBg = dark ? "rgba(30,30,36,0.92)" : "rgba(248,248,250,0.92)";
  const titleColor = dark ? "rgba(255,255,255,0.5)" : "rgba(0,0,0,0.45)";
  const shadow = dark
    ? "0 -2px 24px rgba(0,0,0,0.4), 0 0 0 0.5px rgba(255,255,255,0.08)"
    : "0 -2px 24px rgba(0,0,0,0.1), 0 0 0 0.5px rgba(0,0,0,0.12)";

  return (
    <>
      {WORKSPACE_SCRIPTS.map((script, i) => {
        const offset = (i - activeSpace) * 700;
        const { width, extraLines } = TERMINAL_INFO[i];
        return (
          <div key={i} style={{
            position: "absolute", bottom: -30, left: "50%",
            transform: `translateX(calc(-50% + ${offset}px))`,
            transition: "transform 0.3s cubic-bezier(0.4, 0, 0.2, 1)",
            width, borderRadius: "10px 10px 0 0",
            boxShadow: shadow, overflow: "hidden", zIndex: 1,
          }}>
            <div style={{
              height: 28, display: "flex", alignItems: "center",
              padding: "0 10px", gap: 6, background: titleBarBg,
            }}>
              <div style={{ width: 10, height: 10, borderRadius: "50%", background: "#ff5f57" }} />
              <div style={{ width: 10, height: 10, borderRadius: "50%", background: "#febc2e" }} />
              <div style={{ width: 10, height: 10, borderRadius: "50%", background: "#28c840" }} />
              <span style={{
                flex: 1, textAlign: "center", fontSize: 11, fontWeight: 500,
                color: titleColor, marginRight: 48,
              }}>Terminal</span>
            </div>
            <div style={{ background: bodyBg }}>
              <TerminalPane dark={dark} themed={themed} script={script} active={i === activeSpace} extraLines={extraLines} />
            </div>
          </div>
        );
      })}
    </>
  );
}
