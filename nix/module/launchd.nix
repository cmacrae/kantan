# Shared launchd agent config for kantan, used by both the nix-darwin and
# home-manager modules. kantan's output is appended to
# ~/Library/Logs/kantan.log of the user running the agent.
{ package }:
{
  ProgramArguments = [
    "/bin/sh"
    "-c"
    ''exec ${package}/bin/kantan >>"$HOME/Library/Logs/kantan.log" 2>&1''
  ];
  KeepAlive = true;
  RunAtLoad = true;
  ProcessType = "Interactive";
}
