// Formats a moment as kantan's clock does: with a date pattern of the kind
// macOS takes (`HH:mm`, `EEE d MMM`, text in 'quotes'), in which `do` is
// the day of the month with its English ordinal suffix.

// Stands in for the ordinal suffix until the day is known.
const ORDINAL = "";

// The English ordinal suffix for a day of the month.
export function ordinalSuffix(day) {
  if (day % 100 >= 11 && day % 100 <= 13) return "th";
  return { 1: "st", 2: "nd", 3: "rd" }[day % 10] ?? "th";
}

// A pattern as a list of fields: `{ letter, count }` for a run of one
// pattern letter, `{ text }` for anything written out. An unquoted lone `d`
// before a lone `o` is the day followed by the ordinal marker.
function fields(pattern) {
  const chars = [...pattern];
  const result = [];
  const text = value => {
    const last = result.at(-1);
    if (last?.text !== undefined) last.text += value;
    else result.push({ text: value });
  };
  let quoted = false;
  for (let i = 0; i < chars.length;) {
    const c = chars[i];
    if (c === "'") {
      // Two quotes are one written out, in or out of quoted text.
      if (chars[i + 1] === "'") {
        text("'");
        i += 2;
      } else {
        quoted = !quoted;
        i += 1;
      }
    } else if (!quoted && /[A-Za-z]/.test(c)) {
      let end = i;
      while (end < chars.length && chars[end] === c) end += 1;
      if (c === "d" && end - i === 1 && chars[end] === "o" && chars[end + 1] !== "o") {
        result.push({ letter: "d", count: 1 });
        text(ORDINAL);
        i = end + 1;
      } else {
        result.push({ letter: c, count: end - i });
        i = end;
      }
    } else {
      text(c);
      i += 1;
    }
  }
  return result;
}

const WIDTHS = { 3: "short", 4: "long", 5: "narrow" };

// `time`, milliseconds since 1970, written in `pattern`. `timezone` is an
// IANA name and `locale` a locale's, each the system's when left out or
// unknown. Returns `{ text }`, or `{ unsupported }` naming a pattern field
// this can't write.
export function formatDate(time, pattern, { timezone, locale } = {}) {
  const date = new Date(time);
  const tag = locale?.replace(/_/g, "-");
  const format = options => {
    const attempts = [[tag, timezone], [tag, undefined], [undefined, timezone], [undefined, undefined]];
    for (const [locales, timeZone] of attempts) {
      try {
        return new Intl.DateTimeFormat(locales, { calendar: "gregory", numberingSystem: "latn", timeZone, ...options });
      } catch {
        // An unknown locale or time zone falls back to the system's.
      }
    }
    return new Intl.DateTimeFormat();
  };
  const part = (options, type) => format(options).formatToParts(date).find(p => p.type === type)?.value ?? "";

  // The moment's numbers on the wall clock of the time zone.
  const wall = Object.fromEntries(
    format({ year: "numeric", month: "numeric", day: "numeric", hour: "numeric", minute: "numeric", second: "numeric", hourCycle: "h23" })
      .formatToParts(date).map(p => [p.type, Number(p.value)]));
  const offsetMinutes = Math.round(
    (Date.UTC(wall.year, wall.month - 1, wall.day, wall.hour, wall.minute, wall.second) - Math.floor(time / 1000) * 1000) / 60000);
  const pad = (value, count) => String(value).padStart(count, "0");
  const offset = separator => {
    const minutes = Math.abs(offsetMinutes);
    return `${offsetMinutes < 0 ? "-" : "+"}${pad(Math.trunc(minutes / 60), 2)}${separator}${pad(minutes % 60, 2)}`;
  };

  const write = ({ letter, count }) => {
    switch (letter) {
      case "y":
        return count === 2 ? pad(wall.year % 100, 2) : pad(wall.year, count);
      // A month within a date takes the form a locale writes beside a
      // day, and `L` the form it writes alone.
      case "M":
        if (count <= 2) return pad(wall.month, count);
        return WIDTHS[count] && part({ month: WIDTHS[count], day: "numeric" }, "month");
      case "L":
        if (count <= 2) return pad(wall.month, count);
        return WIDTHS[count] && part({ month: WIDTHS[count] }, "month");
      case "d":
        return count <= 2 ? pad(wall.day, count) : undefined;
      case "E":
        if (count <= 3) return part({ weekday: "short", day: "numeric", month: "long" }, "weekday");
        return WIDTHS[count] && part({ weekday: WIDTHS[count], day: "numeric", month: "long" }, "weekday");
      case "a":
        return count === 1 ? part({ hour: "numeric", hourCycle: "h12" }, "dayPeriod") : undefined;
      case "H":
        return count <= 2 ? pad(wall.hour, count) : undefined;
      case "h":
        return count <= 2 ? pad(wall.hour % 12 || 12, count) : undefined;
      case "K":
        return count <= 2 ? pad(wall.hour % 12, count) : undefined;
      case "k":
        return count <= 2 ? pad(wall.hour || 24, count) : undefined;
      case "m":
        return count <= 2 ? pad(wall.minute, count) : undefined;
      case "s":
        return count <= 2 ? pad(wall.second, count) : undefined;
      case "S":
        return pad(((time % 1000) + 1000) % 1000, 3).padEnd(count, "0").slice(0, count);
      case "G":
        return count <= 3 ? part({ era: "short" }, "era") : undefined;
      case "z":
        return count <= 3 ? part({ timeZoneName: "short" }, "timeZoneName")
          : count === 4 ? part({ timeZoneName: "long" }, "timeZoneName") : undefined;
      case "Z":
        if (count <= 3) return offset("");
        if (count === 4) return offsetMinutes === 0 ? "GMT" : `GMT${offset(":")}`;
        return count === 5 ? (offsetMinutes === 0 ? "Z" : offset(":")) : undefined;
      default:
        return undefined;
    }
  };

  let text = "";
  for (const field of fields(pattern)) {
    const written = field.text ?? write(field);
    if (written === undefined) return { unsupported: field.letter.repeat(field.count) };
    text += written;
  }
  return { text: text.replaceAll(ORDINAL, ordinalSuffix(wall.day)) };
}
