# Shared launchd agent config for kantan, used by both the nix-darwin and
# home-manager modules.
{ package }:
{
  ProgramArguments = [ "${package}/bin/kantan" ];
  KeepAlive = true;
  RunAtLoad = true;
  ProcessType = "Interactive";
}
