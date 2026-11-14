import { useState, useEffect, useCallback, useRef } from "react";
import { latte, mocha, SPACES, WORKSPACE_COLORS } from "../lib/theme.js";
import { I, ICON_SCALE } from "./Icons.jsx";
import { WorkspaceTerminals } from "./Terminal.jsx";

function M({ children, style, onClick, tip, padOuter = true }) {
  const [hov, setHov] = useState(false);
  return (
    <div
      style={{
        display: "flex", alignItems: "center",
        padding: padOuter ? "0 10px" : 0,
        gap: 5, whiteSpace: "nowrap", height: 33, boxSizing: "border-box",
        cursor: onClick ? "pointer" : "default", position: "relative",
        ...style,
      }}
      onClick={onClick}
      onMouseEnter={() => setHov(true)}
      onMouseLeave={() => setHov(false)}
    >
      {children}
      {tip && hov && (
        <div style={{
          position: "absolute", top: 35, left: "50%", transform: "translateX(-50%)",
          padding: "5px 10px", borderRadius: 6, fontSize: 11, fontWeight: 400,
          whiteSpace: "nowrap", zIndex: 200, pointerEvents: "none",
          backdropFilter: "blur(20px)", WebkitBackdropFilter: "blur(20px)",
          background: "var(--tip-bg)", color: "var(--fg)",
          boxShadow: "0 2px 12px rgba(0,0,0,0.2)", letterSpacing: 0,
        }}>{tip}</div>
      )}
    </div>
  );
}

function WiFi({ color, size = 15 }) {
  const scale = ICON_SCALE["wifi"] || 1.0;
  const s = Math.round(size * scale);
  return (
    <span style={{ position: "relative", display: "inline-flex", alignItems: "center", justifyContent: "center", width: s, height: s, flexShrink: 0 }}>
      <span style={{ position: "absolute", inset: 0, display: "flex", alignItems: "center", justifyContent: "center" }}>
        <I name="wifi" size={size} color={color} opacity={0.15} />
      </span>
      <I name="wifi" size={size} color={color} />
    </span>
  );
}

// `children` replace the terminals on the desktop below the bar, and `clock`
// stops the clock at a fixed time.
export default function KantanBarMock({ themed, dark, children, clock, desktopHeight = 200, maxWidth = "60vw" }) {
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [caffeineActive, setCaffeineActive] = useState(false);
  const [remindersOpen, setRemindersOpen] = useState(false);
  const [sysmonOpen, setSysmonOpen] = useState(false);
  const [reminders, setReminders] = useState([
    { id: 0, text: "Dentist", done: false },
    { id: 1, text: "Haircut", done: false },
    { id: 2, text: "Run 5k", done: false },
  ]);
  const pending = reminders.filter(r => !r.done);
  const remindersRef = useRef(null);
  const sysmonRef = useRef(null);
  const [time, setTime] = useState(() => clock ?? fmt(new Date()));

  function fmt(d) {
    return `${String(d.getHours()).padStart(2,"0")}:${String(d.getMinutes()).padStart(2,"0")}`;
  }

  useEffect(() => {
    if (clock) return;
    const id = setInterval(() => setTime(fmt(new Date())), 5000);
    return () => clearInterval(id);
  }, [clock]);

  useEffect(() => {
    if (!remindersOpen) return;
    function handleClick(e) {
      if (remindersRef.current && !remindersRef.current.contains(e.target)) {
        setRemindersOpen(false);
      }
    }
    document.addEventListener("mousedown", handleClick);
    return () => document.removeEventListener("mousedown", handleClick);
  }, [remindersOpen]);

  useEffect(() => {
    if (!sysmonOpen) return;
    function handleClick(e) {
      if (sysmonRef.current && !sysmonRef.current.contains(e.target)) {
        setSysmonOpen(false);
      }
    }
    document.addEventListener("mousedown", handleClick);
    return () => document.removeEventListener("mousedown", handleClick);
  }, [sysmonOpen]);

  const isTheme = themed;
  const isDark = dark;
  const p = isDark ? mocha : latte;

  const fg = isTheme ? p.fg : isDark ? "rgba(255,255,255,0.92)" : "rgba(0,0,0,0.85)";
  const bg = isTheme ? p.bg : isDark ? "rgba(28,28,32,0.68)" : "rgba(253,253,255,0.68)";
  const tipBg = isTheme
    ? isDark ? "rgba(30,30,46,0.9)" : "rgba(239,241,245,0.9)"
    : isDark ? "rgba(42,42,48,0.9)" : "rgba(255,255,255,0.9)";
  const blur = isTheme ? "none" : "blur(24px) saturate(1.5)";

  const c = useCallback((key) => isTheme ? p[key] : fg, [isTheme, p, fg]);

  const wallpaper = isDark
    ? "radial-gradient(ellipse at 25% 25%, #1e3a5f 0%, #132740 35%, #162447 60%, #1a1a2e 100%)"
    : "linear-gradient(150deg, #91bdd6 0%, #6fa3c2 25%, #5d90ac 50%, #7fafc8 70%, #b0d4e6 100%)";

  const cssVars = { "--fg": fg, "--tip-bg": tipBg };

  const [activeSpace, setActiveSpace] = useState(0);

  return (
    <>
      {/* Desktop frame */}
      <div style={{
        // Grows past 60vw rather than letting the bar spill out of it.
        width: "100%", maxWidth, minWidth: "max-content", borderRadius: 10,
        boxShadow: dark
          ? "0 16px 64px rgba(0,0,0,0.55), 0 2px 6px rgba(0,0,0,0.3)"
          : "0 8px 40px rgba(0,0,0,0.12), 0 2px 6px rgba(0,0,0,0.06)",
        position: "relative",
        fontFamily: "'Helvetica Neue', Helvetica, sans-serif",
      }}>
        {/* Wallpaper */}
        <div style={{ position: "absolute", inset: 0, background: wallpaper, zIndex: 0, borderRadius: 10, overflow: "hidden" }} />

        {/* BAR */}
        <div style={{
          height: 33, display: "flex", alignItems: "center",
          position: "relative", zIndex: 1,
          fontSize: 13, fontWeight: 400, color: fg,
          background: bg, backdropFilter: blur, WebkitBackdropFilter: blur,
          borderRadius: "10px 10px 0 0", overflow: "visible",
          ...cssVars,
        }}>

          {/* LEFT: Workspace dots */}
          <M padOuter>
            <div style={{ display: "flex", gap: 6, alignItems: "center" }}>
              {Array.from({ length: SPACES }).map((_, i) => {
                const dotColor = isTheme ? p[WORKSPACE_COLORS[i % WORKSPACE_COLORS.length]] : fg;
                return (
                  <div key={i} onClick={() => setActiveSpace(i)}
                    style={{ cursor: "pointer", display: "flex", alignItems: "center" }}>
                    <I name="point-filled" size={13} color={dotColor}
                      opacity={i === activeSpace ? 1 : 0.4} />
                  </div>
                );
              })}
            </div>
          </M>

          {/* Spacer */}
          <div style={{ flex: 1 }} />

          {/* RIGHT: Drawer content (animated) */}
          <div style={{
            display: "flex", alignItems: "center",
            maxWidth: drawerOpen ? 500 : 0,
            opacity: drawerOpen ? 1 : 0,
            transition: "max-width 0.28s cubic-bezier(0.4,0,0.2,1), opacity 0.18s ease",
            overflow: drawerOpen ? "visible" : "hidden",
          }}>
            {/* System Monitor */}
            <div ref={sysmonRef} style={{ position: "relative" }}>
              <M onClick={() => { setSysmonOpen(o => !o); setRemindersOpen(false); }}
                tip={!sysmonOpen ? "CPU 29% \u00b7 Mem 58% \u00b7 Temp 46\u00b0C" : undefined}>
                <I name="activity" size={14} color={c("fg")} />
                <span style={{ color: c("fg") }}>29%</span>
              </M>

              {sysmonOpen && (
                <div style={{
                  position: "absolute", top: 37, left: 0, zIndex: 300,
                  width: 300, borderRadius: 10, padding: "5px 0",
                  backdropFilter: "blur(50px) saturate(1.6)",
                  WebkitBackdropFilter: "blur(50px) saturate(1.6)",
                  background: isTheme
                    ? isDark ? "rgba(40,40,55,0.97)" : "rgba(244,245,249,0.97)"
                    : isDark ? "rgba(50,50,56,0.97)" : "rgba(255,255,255,0.97)",
                  boxShadow: "0 8px 32px rgba(0,0,0,0.22), 0 0 0 0.5px " + (isDark ? "rgba(255,255,255,0.08)" : "rgba(0,0,0,0.08)"),
                  color: fg, fontSize: 13,
                  fontFamily: "'Helvetica Neue', Helvetica, sans-serif",
                }}>
                  <div style={{ padding: "4px 16px 2px", fontWeight: 600, fontSize: 13 }}>
                    Overview
                  </div>

                  {[
                    { icon: "cpu", label: "CPU", value: "29%" },
                    { icon: "script", label: "Memory", value: "13.4/24 GB" },
                    { icon: "device-floppy", label: "Disk", value: "379/460 GB" },
                    { icon: "thermometer", label: "Thermal", value: "Nominal" },
                    { icon: "clock", label: "Uptime", value: "1d 0h" },
                    { icon: "graph", label: "Load", value: "2.45 2.49 2.53" },
                  ].map(({ icon, label, value }) => (
                    <div key={label} style={{
                      display: "flex", alignItems: "center",
                      minHeight: 22, padding: "2px 16px",
                    }}>
                      <I name={icon} size={13} color={fg} style={{ marginRight: 4 }} />
                      <span>{label}</span>
                      <span style={{ flex: 1, minWidth: 16 }} />
                      <span style={{ opacity: 0.5 }}>{value}</span>
                    </div>
                  ))}

                  <div style={{
                    height: 1, margin: "4px 12px",
                    background: isDark ? "rgba(255,255,255,0.1)" : "rgba(0,0,0,0.08)",
                  }} />

                  <div style={{ padding: "4px 16px 2px", fontWeight: 600, fontSize: 13 }}>
                    Top Processes
                  </div>

                  {[
                    ["WindowServer", "44.2%"],
                    ["Emacs", "16.0%"],
                    ["Finder", "13.2%"],
                    ["Arc", "11.7%"],
                    ["tccd", "11.0%"],
                  ].map(([name, pct]) => (
                    <div key={name} style={{
                      display: "flex", alignItems: "center",
                      minHeight: 22, padding: "2px 16px",
                    }}>
                      <span>{name}</span>
                      <span style={{ flex: 1, minWidth: 16 }} />
                      <span style={{ opacity: 0.5 }}>{pct}</span>
                    </div>
                  ))}

                  <div style={{
                    height: 1, margin: "4px 12px",
                    background: isDark ? "rgba(255,255,255,0.1)" : "rgba(0,0,0,0.08)",
                  }} />

                  <div style={{
                    display: "flex", alignItems: "center",
                    minHeight: 22, padding: "2px 16px", cursor: "default",
                  }}>
                    <I name="dashboard" size={13} color={fg} style={{ marginRight: 4 }} />
                    <span>Activity Monitor</span>
                  </div>
                </div>
              )}
            </div>

            {/* Reminders, hidden like the plugin once nothing is incomplete */}
            {pending.length > 0 && (
            <div ref={remindersRef} style={{ position: "relative", margin: "0 10px", flexShrink: 0 }}>
              <div
                onClick={() => { setRemindersOpen(o => !o); setSysmonOpen(false); }}
                style={{
                  display: "flex", alignItems: "center", gap: 5, cursor: "pointer",
                  background: isTheme ? p.shape : isDark ? "rgba(255,255,255,0.1)" : "rgba(0,0,0,0.06)",
                  borderRadius: 4, padding: "3px 6px",
                }}
              >
                <I name="bell-filled" size={14} color={c("maroon")} />
                <span style={{ color: fg, whiteSpace: "nowrap" }}>{pending[0].text}</span>
              </div>

              {remindersOpen && (
                <div style={{
                  position: "absolute", top: 37, left: 0, zIndex: 300,
                  width: 280, borderRadius: 10,
                  padding: "5px 0",
                  backdropFilter: "blur(50px) saturate(1.6)",
                  WebkitBackdropFilter: "blur(50px) saturate(1.6)",
                  background: isTheme
                    ? isDark ? "rgba(40,40,55,0.97)" : "rgba(244,245,249,0.97)"
                    : isDark ? "rgba(50,50,56,0.97)" : "rgba(255,255,255,0.97)",
                  boxShadow: "0 8px 32px rgba(0,0,0,0.22), 0 0 0 0.5px " + (isDark ? "rgba(255,255,255,0.08)" : "rgba(0,0,0,0.08)"),
                  color: fg,
                  fontSize: 13,
                  fontFamily: "'Helvetica Neue', Helvetica, sans-serif",
                }}>
                  {pending.map(r => (
                    <div
                      key={r.id}
                      onClick={() => setReminders(rs => rs.map(x => x.id === r.id ? { ...x, done: !x.done } : x))}
                      style={{
                        display: "flex", alignItems: "center", gap: 8,
                        minHeight: 26, padding: "3px 12px", cursor: "default",
                        borderRadius: 5, margin: "1px 5px",
                      }}
                    >
                      <svg viewBox="0 0 20 20" width={15} height={15} style={{ flexShrink: 0 }}>
                        <circle cx="10" cy="10" r="7.5" fill="none" stroke="currentColor" strokeWidth="1.4" />
                      </svg>
                      <span>{r.text}</span>
                    </div>
                  ))}
                  {reminders.filter(r => r.done).map(r => (
                    <div
                      key={r.id}
                      onClick={() => setReminders(rs => rs.map(x => x.id === r.id ? { ...x, done: !x.done } : x))}
                      style={{
                        display: "flex", alignItems: "center", gap: 8,
                        minHeight: 26, padding: "3px 12px", cursor: "default",
                        opacity: 0.4, borderRadius: 5, margin: "1px 5px",
                      }}
                    >
                      <svg viewBox="0 0 20 20" width={15} height={15} style={{ flexShrink: 0 }}>
                        <circle cx="10" cy="10" r="7.5" fill="currentColor" opacity="0.2" />
                        <circle cx="10" cy="10" r="7.5" fill="none" stroke="currentColor" strokeWidth="1.4" />
                        <path d="M6.5 10.5l2 2l5 -5" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
                      </svg>
                      <span style={{ textDecoration: "line-through" }}>{r.text}</span>
                    </div>
                  ))}
                  <div style={{
                    height: 1, margin: "4px 12px",
                    background: isDark ? "rgba(255,255,255,0.1)" : "rgba(0,0,0,0.08)",
                  }} />
                  <div
                    style={{
                      display: "flex", alignItems: "center", gap: 6,
                      minHeight: 26, padding: "3px 12px", cursor: "default",
                      borderRadius: 5, margin: "1px 5px",
                    }}
                  >
                    <I name="list-check" size={14} color="currentColor" />
                    <span>Reminders</span>
                  </div>
                </div>
              )}
            </div>
            )}
          </div>

          {/* Drawer toggle */}
          <M onClick={() => { setDrawerOpen(d => !d); setRemindersOpen(false); setSysmonOpen(false); }}
            tip={drawerOpen ? "Collapse drawer" : "Expand drawer"}>
            <I name={drawerOpen ? "box-align-left" : "box-align-right"}
              size={14} color={c("overlay0")} />
          </M>

          {/* Always visible */}

          <M tip={caffeineActive ? "Caffeine: Active" : "Caffeine: Inactive"}
            onClick={() => setCaffeineActive(a => !a)}
            style={{ opacity: caffeineActive ? 1 : 0.4 }}>
            <I name="mug-filled" size={14} color={c("rosewater")} />
          </M>

          <M tip="Focus: Do Not Disturb">
            <I name="brain" size={14} color={c("pink")} />
          </M>

          <M tip="Bluetooth: Connected">
            <I name="bluetooth" size={14} color={c("blue")} />
          </M>

          <M tip="Volume: 64%">
            <I name="volume" size={14} color={c("lavender")} />
          </M>

          <M tip="WiFi: Home Network">
            <WiFi color={c("sky")} />
          </M>

          <M tip="Battery: 78%">
            <I name="battery-3-filled" size={14} color={c("subtext1")} />
          </M>

          <M tip="Control Centre">
            <I name="adjustments-horizontal-filled" size={14} color={c("mauve")} />
          </M>

          <M>
            <span style={{
              color: c("flamingo"),
              fontVariantNumeric: "tabular-nums",
              fontWeight: 400,
            }}>{time}</span>
          </M>
        </div>

        {/* Desktop peek */}
        <div style={{ height: desktopHeight, position: "relative", zIndex: 0, borderRadius: "0 0 10px 10px", overflow: "hidden", background: wallpaper }}>
          {children ?? <WorkspaceTerminals dark={dark} themed={isTheme} activeSpace={activeSpace} />}
        </div>
      </div>
    </>
  );
}
