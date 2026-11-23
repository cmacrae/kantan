# Security

## Supported versions

Security fixes go into the latest release. Please update to it before reporting.

## Reporting a vulnerability

Please report vulnerabilities privately through [GitHub's private vulnerability reporting](https://github.com/cmacrae/kantan/security/advisories/new), not in a public issue.

A useful report says:

- what the vulnerability is and what an attacker could do with it
- how to reproduce it, with a minimal config or plugin if one is needed
- which kantan version and macOS version you found it on

Reports are read and answered as soon as possible. When the fix is released, its advisory is published and credits you by your GitHub username, unless you'd rather stay anonymous.

## Scope

kantan runs the commands and plugins your config names, with your permissions. A config or plugin you chose to run doing something harmful isn't a vulnerability in kantan. A config you download from a share link and run is one you chose. These are vulnerabilities:

- kantan doing something its config didn't ask for
- another app, website or user changing what kantan runs without your permission
- the builder page itself running something when you open a link in it
