// kantan's template resolution: `{key}` placeholders filled from foreach
// scopes, a module's variables and the theme palette.

import { own } from "./values.js";

// Whether `key` has the shape of a variable's name: a letter or `_`, then
// letters, digits, `_`, `.` and `-`, all of them ASCII.
export const isName = key => /^[A-Za-z_][A-Za-z0-9_.-]*$/.test(key);

// What the `{` at `open` holds when the next brace after it is a `}`, as
// `{ key, end }` with `end` where that pair ends, or undefined.
function bracePair(template, open) {
  for (let i = open + 1; i < template.length; i++) {
    if (template[i] === "}") return { key: template.slice(open + 1, i), end: i + 1 };
    if (template[i] === "{") return undefined;
  }
  return undefined;
}

// `template` with each brace pair `fill` gives a value for replaced by
// that value. A brace it gives none for is left where it is, and what
// follows it is read on.
function filling(template, fill) {
  let result = "";
  for (let i = 0; i < template.length; i++) {
    const pair = template[i] === "{" ? bracePair(template, i) : undefined;
    const value = pair && fill(pair.key);
    if (value === undefined) {
      result += template[i];
    } else {
      result += value;
      i = pair.end - 1;
    }
  }
  return result;
}

const isThemeKey = key => key.startsWith("theme(") && key.endsWith(")");

// Whether `command` opens as a URL rather than running in a shell: a scheme
// followed by `:`, and no spaces.
export function isURLCommand(command) {
  return /^[a-z][a-z0-9+.-]*:/i.test(command) && !command.includes(" ");
}

// The characters a value keeps unencoded in a URL command: the ones a URL
// gives no meaning, so a value can't add a host, a port or a path segment.
const URL_VALUE_ALLOWED = /[A-Za-z0-9\-._~]/;

function percentEncode(value) {
  let result = "";
  for (const char of value) {
    if (URL_VALUE_ALLOWED.test(char)) result += char;
    else for (const byte of new TextEncoder().encode(char)) result += "%" + byte.toString(16).toUpperCase().padStart(2, "0");
  }
  return result;
}

// A resolver over a module's `variables` and `data` collections. `theme`
// resolves a `theme(name)` key to a colour, or returns undefined, and
// `scopes` are the foreach elements in scope, innermost last.
export function createResolver({ variables = {}, data = {}, theme = () => undefined, scopes = [] } = {}) {
  const lookup = key => {
    for (let i = scopes.length - 1; i >= 0; i--) {
      const scoped = own(scopes[i], key);
      if (scoped !== undefined) return scoped;
    }
    const variable = own(variables, key);
    if (variable !== undefined) return variable;
    return isThemeKey(key) ? theme(key) : undefined;
  };

  // The value of the variable `key`, or nothing when no variable has that
  // name. A value is used as it is, except that the `{theme(name)}`
  // templates within it resolve against the palette, and stay as written
  // when the palette lacks them.
  const valueOf = key => filling(lookup(key) ?? "", inner => (isThemeKey(inner) ? theme(inner) : undefined));

  // What the placeholder `{key}` comes to, or undefined when `{key}` isn't
  // one. A brace pair is a placeholder when a variable of that name exists,
  // or when what it holds has the shape of a name: one nothing defines
  // comes to nothing. Any other brace is text, and stays as written.
  const placeholderValue = key => (lookup(key) !== undefined || isName(key) ? valueOf(key) : undefined);

  const resolve = template => filling(template, placeholderValue);

  // `template` with each placeholder replaced by `encode(quote, value)`,
  // `quote` being the shell quote character it sits within, or null. A `$`
  // that would expand a bare or double-quoted placeholder's value is left
  // out.
  const substitute = (template, encode) => {
    let result = "";
    let quote = null;
    // Whether the last character is a `$` the shell would expand with what
    // follows: not escaped, and not the second of a `$$`.
    let expands = false;
    for (let i = 0; i < template.length; i++) {
      const char = template[i];
      const pair = char === "{" ? bracePair(template, i) : undefined;
      const value = pair && placeholderValue(pair.key);
      if (value !== undefined) {
        if (expands && quote !== "'") result = result.slice(0, -1);
        expands = false;
        result += encode(quote, value);
        i = pair.end - 1;
        continue;
      }
      result += char;
      expands = char === "$" && !expands;
      if (char === "\\" && quote !== "'" && i + 1 < template.length) {
        result += template[++i];
      } else if (char === "'" || char === '"') {
        quote = quote === null ? char : quote === char ? null : quote;
      }
    }
    return result;
  };

  return {
    variables,
    data,
    resolve,

    // A view command with its placeholders filled, each value quoted for
    // where it sits: bare, in single quotes or in double quotes. A `$`
    // straight before a bare or double-quoted placeholder is dropped. A
    // command that is one placeholder runs as that value, exactly as
    // written, and a URL command's values are percent-encoded. Braces that
    // aren't placeholders are the command's own, and stay as written.
    resolveCommand(template) {
      // The space kantan trims: spaces and tabs, and no line ends.
      const trimmed = template.replace(/^[\t\p{Zs}]+|[\t\p{Zs}]+$/gu, "");
      const sole = /^\{[^{}]*\}$/.test(trimmed) ? trimmed.slice(1, -1) : undefined;
      if (sole !== undefined && (lookup(sole) !== undefined || isName(sole))) return lookup(sole) ?? "";
      if (isURLCommand(trimmed)) return substitute(template, (_, value) => percentEncode(value));
      const single = value => value.replaceAll("'", "'\\''");
      return substitute(template, (quote, value) => {
        if (quote === "'") return single(value);
        if (quote === '"') return value.replace(/[\\"$`]/g, "\\$&");
        return value === "" ? "" : `'${single(value)}'`;
      });
    },

    // Whether `template` resolves to something other than nothing, `false`,
    // `0` or `no`, ignoring case and the space around it.
    resolveBool(template) {
      const resolved = resolve(template).toLowerCase().trim();
      return !["false", "0", "no", ""].includes(resolved);
    },

    // Whether the variable `condition` names is truthy: not empty, `0`,
    // `false` or `no`. A variable nothing defines is empty.
    truthy(condition) {
      const resolved = valueOf(condition).toLowerCase();
      return !["", "0", "false", "no"].includes(resolved);
    },

    // This resolver with `element` as the innermost foreach scope.
    scoped(element) {
      return createResolver({ variables, data, theme, scopes: [...scopes, element] });
    },
  };
}

// `template` as a plain tooltip shows it: `{value}`, `{icon}` and each
// variable filled in, and any other placeholder left as written. Each
// placeholder is filled once, with its value as it is: a placeholder
// within a value stays as written.
export function fillTooltip(template, { value, icon, variables = {} }) {
  return template.replace(/\{([^{}]*)\}/g, (placeholder, key) => {
    if (key === "value" && value !== undefined) return value;
    if (key === "icon" && icon !== undefined) return icon;
    return Object.hasOwn(variables, key) ? String(variables[key]) : placeholder;
  });
}
