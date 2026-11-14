// Adds a version picker to the docs' menu bar, and a notice to pages of an
// older release pointing at the latest docs. The site build lists each
// release's docs in versions.json beside this script.
(async function () {
  const root = new URL(".", document.currentScript.src).pathname;
  let versions;
  try {
    versions = await (await fetch(root + "versions.json")).json();
  } catch {
    return;
  }

  // The version whose path is the longest prefix of this page's
  const page = location.pathname;
  const current = versions
    .filter(v => page.startsWith(v.path))
    .sort((a, b) => b.path.length - a.path.length)[0];
  if (!current) return;
  const relative = page.slice(current.path.length);
  const latest = versions.find(v => v.latest);

  // The same page in another version, or that version's first page when it
  // has no such page.
  async function samePage(version) {
    const target = version.path + relative;
    try {
      const response = await fetch(target, { method: "HEAD" });
      if (response.ok) return target;
    } catch {}
    return version.path;
  }

  const style = document.createElement("style");
  style.textContent = `
    .version-picker {
      appearance: none; -webkit-appearance: none;
      background: none; color: var(--icons);
      border: 1px solid var(--theme-popup-border); border-radius: 6px;
      font: inherit; font-size: 13px; line-height: 1.2;
      padding: 3px 8px; margin: 0 6px; cursor: pointer;
      vertical-align: middle;
    }
    .version-picker:hover, .version-picker:focus { color: var(--icons-hover); }
    .version-notice {
      background: var(--quote-bg); border: 1px solid var(--quote-border);
      border-radius: 8px; padding: 10px 14px; margin: 16px 0 0;
      font-size: 0.9em;
    }
  `;
  document.head.appendChild(style);

  const picker = document.createElement("select");
  picker.className = "version-picker";
  picker.title = "Documentation version";
  picker.setAttribute("aria-label", "Documentation version");
  for (const version of versions) {
    const option = document.createElement("option");
    option.value = version.path;
    option.textContent = version.latest ? `${version.version} (latest)` : version.version;
    option.selected = version === current;
    picker.appendChild(option);
  }
  picker.addEventListener("change", async () => {
    const version = versions.find(v => v.path === picker.value);
    location.href = await samePage(version);
  });
  document.querySelector(".right-buttons")?.prepend(picker);

  if (latest && current !== latest) {
    const notice = document.createElement("p");
    notice.className = "version-notice";
    notice.append(`These docs are for kantan ${current.version}. `);
    const link = document.createElement("a");
    link.textContent = `Read the docs for ${latest.version}`;
    link.href = latest.path;
    samePage(latest).then(href => { link.href = href; });
    notice.append(link, ".");
    document.querySelector("#mdbook-content main")?.prepend(notice);
  }
})();
