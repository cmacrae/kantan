// kantan's template resolution: `{key}` placeholders filled from foreach
// scopes, a module's variables and the theme palette.

// `template` with each `{key}` placeholder replaced by
// `replacement(key, placeholder)`. A `{` with no `}` after it is left alone.
function replacePlaceholders(template, replacement) {
  let result = "";
  let rest = template;
  for (;;) {
    const open = rest.indexOf("{");
    const close = open < 0 ? -1 : rest.indexOf("}", open + 1);
    if (close < 0) return result + rest;
    result += rest.slice(0, open) + replacement(rest.slice(open + 1, close), rest.slice(open, close + 1));
    rest = rest.slice(close + 1);
  }
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
      if (scopes[i][key] !== undefined) return scopes[i][key];
    }
    if (variables[key] !== undefined) return variables[key];
    return isThemeKey(key) ? theme(key) : undefined;
  };

  // A substituted value is used as it is, except that the `{theme(name)}`
  // templates within it resolve against the palette, and stay as written
  // when the palette lacks them.
  const resolve = template =>
    replacePlaceholders(template, key =>
      replacePlaceholders(lookup(key) ?? "", (inner, placeholder) =>
        isThemeKey(inner) ? theme(inner) ?? placeholder : placeholder));

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
      const close = char === "{" ? template.indexOf("}", i) : -1;
      if (close >= 0) {
        if (expands && quote !== "'") result = result.slice(0, -1);
        expands = false;
        result += encode(quote, resolve(template.slice(i, close + 1)));
        i = close;
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
    // written, and a URL command's values are percent-encoded.
    resolveCommand(template) {
      const trimmed = template.trim();
      if (/^\{[^{}]*\}$/.test(trimmed)) return lookup(trimmed.slice(1, -1)) ?? "";
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
      const resolved = resolve(`{${condition}}`).toLowerCase();
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
