# Checks that every relative link in a built mdBook resolves to a page, and
# that each link's fragment names an element on that page.
import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit


class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = set()
        self.links = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if "id" in attrs:
            self.ids.add(attrs["id"])
        if tag == "a" and attrs.get("href"):
            self.links.append(attrs["href"])


def parse(path):
    page = Page()
    page.feed(path.read_text())
    return page


book = Path(sys.argv[1]).resolve()
pages = {}
broken = []
# The print page repeats every chapter with its links rewritten.
for html in sorted(p for p in book.rglob("*.html") if p.name != "print.html"):
    for href in pages.setdefault(html, parse(html)).links:
        url = urlsplit(href)
        if url.scheme or url.netloc or href.startswith("/"):
            if href.startswith("/"):
                broken.append(f"{html.relative_to(book)}: {href} is absolute")
            continue
        target = (html.parent / unquote(url.path)).resolve() if url.path else html
        if target.is_dir():
            target = target / "index.html"
        if not target.is_file():
            broken.append(f"{html.relative_to(book)}: {href} has no page")
            continue
        if url.fragment and target.suffix == ".html":
            ids = pages.setdefault(target, parse(target)).ids
            if unquote(url.fragment) not in ids:
                broken.append(f"{html.relative_to(book)}: {href} has no such anchor")

print("\n".join(broken))
sys.exit(1 if broken else 0)
