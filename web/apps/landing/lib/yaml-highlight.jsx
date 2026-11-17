export function highlightYaml(code, colors) {
  return code.split('\n').map((line, i, arr) => {
    const nl = i < arr.length - 1 ? '\n' : '';
    if (!line.trim()) return nl;
    if (line.trimStart().startsWith('#')) {
      return <span key={i} style={{ color: colors.comment }}>{line}{nl}</span>;
    }
    const m = line.match(/^(\s*(?:- )?)([\w][\w.-]*)(:\s?)(.*)/);
    if (m) {
      const [, prefix, key, colon, val] = m;
      let valColor = colors.value;
      if (val.startsWith('"') || val.startsWith("'")) valColor = colors.string;
      else if (/^(true|false)$/i.test(val)) valColor = colors.bool;
      else if (/^\d+$/.test(val)) valColor = colors.number;
      return <span key={i}>
        <span style={{ color: colors.punct }}>{prefix}</span>
        <span style={{ color: colors.key }}>{key}</span>
        <span style={{ color: colors.punct }}>{colon}</span>
        {val && <span style={{ color: valColor }}>{val}</span>}
        {nl}
      </span>;
    }
    const listM = line.match(/^(\s*)(- )(.*)/);
    if (listM) {
      const valColor = listM[3].startsWith('"') ? colors.string : colors.value;
      return <span key={i}>
        <span>{listM[1]}</span>
        <span style={{ color: colors.punct }}>{listM[2]}</span>
        <span style={{ color: valColor }}>{listM[3]}</span>
        {nl}
      </span>;
    }
    return <span key={i} style={{ color: colors.value }}>{line}{nl}</span>;
  });
}
