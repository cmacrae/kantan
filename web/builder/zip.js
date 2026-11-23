// A ZIP archive of text files, stored without compression, for downloading
// a config that is more than one file.

const CRC_TABLE = Array.from({ length: 256 }, (_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});

function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) crc = CRC_TABLE[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}

// `values` as little-endian fields, each `[value, bytes]`.
function fields(...values) {
  const out = [];
  for (const [value, size] of values) for (let i = 0; i < size; i++) out.push((value >>> (8 * i)) & 0xff);
  return out;
}

// Whether `path` names a file beneath the directory an archive is unpacked
// into: relative, with no part that is empty, `.` or `..`.
const within = path => !/[\\\u0000-\u001f\u007f]/.test(path) && path.split("/").every(part => part !== "" && part !== "." && part !== "..");

// The archive's bytes for `files`, each `{ path, text }`. Throws for a
// path that would unpack outside the archive's directory.
export function zip(files) {
  const encoder = new TextEncoder();
  const local = [], central = [];
  for (const { path, text } of files) {
    if (!within(path)) throw new Error(`An archive can't hold a file at the path ${JSON.stringify(path)}`);
    const name = encoder.encode(path), data = encoder.encode(text);
    // Version 2.0, names in UTF-8, stored, no timestamp
    const shared = [[20, 2], [0x0800, 2], [0, 2], [0, 2], [0x21, 2], [crc32(data), 4], [data.length, 4], [data.length, 4], [name.length, 2], [0, 2]];
    const offset = local.length;
    local.push(...fields([0x04034b50, 4], ...shared), ...name, ...data);
    central.push(...fields([0x02014b50, 4], [20, 2], ...shared, [0, 2], [0, 2], [0, 2], [0, 4], [offset, 4]), ...name);
  }
  const end = fields([0x06054b50, 4], [0, 2], [0, 2], [files.length, 2], [files.length, 2], [central.length, 4], [local.length, 4], [0, 2]);
  return Uint8Array.from([...local, ...central, ...end]);
}
