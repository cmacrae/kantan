// Runs the shared cases in web/fixtures, which kantan's own tests run too.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import {
  createResolver, decodeJsonView, decodeYamlView, loadTheme, menuRows, parseOutput,
  resolveBar, resolveThemeTemplate, validateDocument,
} from "../index.js";
import { mismatches } from "./subset.js";

const fixtures = name => JSON.parse(readFileSync(new URL(`../../fixtures/${name}.json`, import.meta.url), "utf8"));
const check = (expected, actual) => assert.deepEqual(mismatches(expected, actual), []);

for (const group of fixtures("templates")) {
  test(`templates: ${group.name}`, () => {
    const { palette } = group;
    let resolver = createResolver({
      variables: group.variables ?? {},
      data: group.data ?? {},
      theme: key => (palette ? resolveThemeTemplate(`{${key}}`, palette) : `{${key}}`),
    });
    for (const scope of group.scopes ?? []) resolver = resolver.scoped(scope);
    for (const { expect, ...operation } of group.checks) {
      const [[kind, template]] = Object.entries(operation);
      const actual = {
        resolve: () => resolver.resolve(template),
        command: () => resolver.resolveCommand(template),
        bool: () => resolver.resolveBool(template),
        truthy: () => resolver.truthy(template),
      }[kind]();
      assert.equal(actual, expect, `${kind} ${JSON.stringify(template)}`);
    }
  });
}

for (const { name, themes, selection, expect } of fixtures("themes")) {
  test(`themes: ${name}`, () => check(expect, loadTheme(selection, themes) ?? null));
}

for (const { name, source, view, variables, data, expect } of fixtures("menus")) {
  test(`menus: ${name}`, () => {
    const node = source === "json" ? decodeJsonView(view).node : decodeYamlView(view);
    const state = parseOutput({ variables: variables ?? {}, data: data ?? {} }, "");
    const actual = node
      ? { rows: menuRows(node, createResolver({ variables: state.variables, data: state.data })) }
      : { rejected: true };
    check(expect, actual);
  });
}

for (const { name, document, checks } of [...fixtures("bars"), ...fixtures("modules")]) {
  test(`bars: ${name}`, () => {
    assert.deepEqual(validateDocument(document), []);
    for (const { expect, ...options } of checks) check(expect, resolveBar(document, options));
  });
}
