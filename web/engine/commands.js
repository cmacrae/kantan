// The commands a click somewhere on a module, or in the menu or popup it
// opens, can run, read from the module the engine resolved.

// The command a check runs when clicked: the one that ticks it, or the one
// that unticks it once it's ticked.
export const checkCommand = check => (check.checked ? check.uncheckedCommand ?? check.command : check.command);

function viewCommands(nodes) {
  return nodes.flatMap(node => [
    node.type === "check" ? checkCommand(node) : node.command,
    ...viewCommands(node.children ?? []),
  ]);
}

export function moduleCommands(module) {
  const { click } = module;
  const commands =
    click?.type === "toggle" ? [click.command]
    : click?.type === "menu" ? click.rows.map(row => (row.type === "check" ? checkCommand(row) : row.command))
    : click?.type === "popup" ? viewCommands(click.view)
    : [];
  return commands.filter(command => typeof command === "string" && command !== "");
}
