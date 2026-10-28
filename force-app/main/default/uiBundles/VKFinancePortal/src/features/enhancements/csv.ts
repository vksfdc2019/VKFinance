/** Strict bounded CSV parser: quoted delimiters/newlines, escaped quotes and UTF-8 BOM. */
export function parseCsv(source: string): {
  headers: string[];
  rows: string[][];
} {
  if (source.length > 1_000_000)
    throw new Error('Use a CSV file smaller than 1 MB.');
  source = source.replace(/^\uFEFF/, '');
  const firstLine = source.split(/\r?\n/, 1)[0];
  // Count separators outside quoted cells so a quoted address does not pick the delimiter.
  const score = (delimiter: string) => {
    let quoted = false,
      count = 0;
    for (let i = 0; i < firstLine.length; i++) {
      if (firstLine[i] === '"') {
        if (quoted && firstLine[i + 1] === '"') i++;
        else quoted = !quoted;
      } else if (!quoted && firstLine[i] === delimiter) count++;
    }
    return count;
  };
  const delimiter = [',', ';', '\t'].sort((a, b) => score(b) - score(a))[0];
  const records: string[][] = [];
  let record: string[] = [],
    cell = '',
    quoted = false,
    endedQuote = false;
  const saveCell = () => {
    record.push(cell.trim());
    cell = '';
    endedQuote = false;
  };
  const saveRecord = () => {
    saveCell();
    if (record.some(Boolean)) records.push(record);
    record = [];
    if (records.length > 501)
      throw new Error(
        'Import up to 500 rows at a time. Split a larger statement into smaller CSV files.'
      );
  };
  for (let i = 0; i < source.length; i++) {
    const ch = source[i];
    if (quoted) {
      if (ch === '"') {
        if (source[i + 1] === '"') {
          cell += '"';
          i++;
        } else {
          quoted = false;
          endedQuote = true;
        }
      } else cell += ch;
    } else if (ch === delimiter) saveCell();
    else if (ch === '\r' || ch === '\n') {
      if (ch === '\r' && source[i + 1] === '\n') i++;
      saveRecord();
    } else if (ch === '"') {
      if (cell.trim() || endedQuote)
        throw new Error(
          'A CSV quote is misplaced. Export the statement again.'
        );
      cell = '';
      quoted = true;
    } else if (endedQuote && ch.trim())
      throw new Error('Unexpected text after a quoted CSV cell.');
    else if (!endedQuote) cell += ch;
  }
  if (quoted) throw new Error('The CSV has an unclosed quoted cell.');
  if (cell || record.length) saveRecord();
  if (records.length < 2)
    throw new Error('The CSV needs a header and at least one transaction.');
  const headers = records.shift()!;
  if (
    headers.length < 2 ||
    headers.length > 40 ||
    headers.some(h => !h) ||
    new Set(headers.map(h => h.toLowerCase())).size !== headers.length
  )
    throw new Error('Use 2–40 uniquely named columns, without blank headers.');
  if (records.some(r => r.length !== headers.length))
    throw new Error(
      'Some rows have a different number of columns. Check the CSV before importing.'
    );
  return { headers, rows: records };
}

export function statementAmount(value: string): number | undefined {
  let text = value.trim().replace(/[₹$£€\s,]/g, '');
  if (!text || text === '-') return undefined;
  const negative = /^\(.*\)$/.test(text) || /DR$/i.test(text);
  text = text.replace(/^\((.*)\)$/, '$1').replace(/(?:CR|DR)$/i, '');
  if (!/^[+-]?\d+(?:\.\d{1,2})?$/.test(text))
    throw new Error(`Invalid amount: ${value}`);
  const amount = Number(text) * (negative ? -1 : 1);
  if (!Number.isFinite(amount) || Math.abs(amount) > 9_999_999_999.99)
    throw new Error('Amount is outside the supported range.');
  return amount;
}

export function statementDate(
  value: string,
  format: 'DMY' | 'MDY' | 'ISO'
): string {
  const parts = value.trim().split(/[./-]/);
  if (parts.length !== 3 || parts.some(p => !/^\d+$/.test(p)))
    throw new Error('Use numeric dates matching the selected date format.');
  const [year, month, day] =
    format === 'ISO'
      ? parts.map(Number)
      : [
          Number(parts[2]),
          Number(parts[format === 'DMY' ? 1 : 0]),
          Number(parts[format === 'DMY' ? 0 : 1]),
        ];
  if (year < 2000 || year > 2100)
    throw new Error('Use a four-digit year from 2000 onward.');
  const date = new Date(Date.UTC(year, month - 1, day));
  if (
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day
  )
    throw new Error('This date does not exist.');
  return `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
}

export function needsTransferReview(description: string): boolean {
  return /\b(transfer|card\s*(payment|repayment)|payment\s*(received|thank\s*you)|self\s*transfer|emi|loan\s*payment)\b/i.test(
    description
  );
}
