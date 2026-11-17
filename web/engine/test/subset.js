// Compares a result with what a shared case expects of it, as a subset:
// every key the expectation has must match, a list must match item for
// item, and `null` means the key is absent. Returns what differs, as a list
// of sentences.
export function mismatches(expected, actual, path = "result") {
  if (expected === null) {
    return actual === undefined || actual === null ? [] : [`${path} is ${JSON.stringify(actual)}, not absent`];
  }
  if (Array.isArray(expected)) {
    if (!Array.isArray(actual)) return [`${path} is ${JSON.stringify(actual)}, not a list`];
    if (actual.length !== expected.length) {
      return [`${path} has ${actual.length} items, not ${expected.length}: ${JSON.stringify(actual)}`];
    }
    return expected.flatMap((item, i) => mismatches(item, actual[i], `${path}[${i}]`));
  }
  if (typeof expected === "object") {
    if (actual === null || typeof actual !== "object" || Array.isArray(actual)) {
      return [`${path} is ${JSON.stringify(actual)}, not a mapping`];
    }
    return Object.entries(expected).flatMap(([key, value]) => mismatches(value, actual[key], `${path}.${key}`));
  }
  return expected === actual ? [] : [`${path} is ${JSON.stringify(actual)}, not ${JSON.stringify(expected)}`];
}
