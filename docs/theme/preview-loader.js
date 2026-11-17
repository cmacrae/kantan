// Starts the plugin previews on a page that holds one, so the other pages
// don't load the script that draws them. The previews, their icons and the
// script sit in the book's preview directory.
if (document.querySelector(".kantan-preview")) {
  const base = `${path_to_root}preview/`;
  const icons = Object.assign(document.createElement("link"), { rel: "stylesheet", href: `${base}icons.css` });
  const script = Object.assign(document.createElement("script"), { src: `${base}main.js` });
  script.dataset.base = base;
  document.head.append(icons, script);
}
