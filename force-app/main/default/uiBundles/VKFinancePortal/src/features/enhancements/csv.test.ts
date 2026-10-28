import { describe, expect, it } from 'vitest';
import {
  needsTransferReview,
  parseCsv,
  statementAmount,
  statementDate,
} from './csv';

describe('statement CSV boundaries', () => {
  it('preserves quoted delimiters, escaped quotes and multiline descriptions', () => {
    const csv =
      '\uFEFFDate,Description,Amount\r\n28/10/2026,"Shop, ""Central""\nMarket",-125.50\r\n';
    expect(parseCsv(csv)).toEqual({
      headers: ['Date', 'Description', 'Amount'],
      rows: [['28/10/2026', 'Shop, "Central"\nMarket', '-125.50']],
    });
  });
  it('supports semicolon and tab exports without mistaking quoted commas for separators', () => {
    expect(
      parseCsv('Date;Description;Amount\n2026-10-28;"One, two, three";125')
        .rows[0]
    ).toHaveLength(3);
    expect(parseCsv('Date\tAmount\n2026-10-28\t125').rows[0][1]).toBe('125');
  });
  it('rejects malformed quotes, ragged rows and ambiguous headers', () => {
    for (const csv of [
      'Date,Amount\n"broken,125',
      'Date,Amount\n28,10,125',
      'date,Date\n28,125',
      'Date,\n28,125',
      'Date,Amount\n"28"junk,125',
    ])
      expect(() => parseCsv(csv)).toThrow();
  });
  it('bounds file and row counts before a server request', () => {
    expect(() => parseCsv('x'.repeat(1_000_001))).toThrow(/1 MB/);
    expect(() =>
      parseCsv('Date,Amount\n' + '2026-10-28,1\n'.repeat(501))
    ).toThrow(/500/);
  });
});

describe('statement money and dates', () => {
  it('understands grouped amounts, DR/CR and debit parentheses', () => {
    expect(statementAmount('₹ 1,25,000.50 DR')).toBe(-125000.5);
    expect(statementAmount('(1,250.25)')).toBe(-1250.25);
    expect(statementAmount('125 CR')).toBe(125);
    expect(statementAmount('')).toBeUndefined();
    expect(() => statementAmount('12.345')).toThrow();
    expect(() => statementAmount('=1+2')).toThrow();
  });
  it('requires explicit ambiguous-date interpretation and rejects rollover dates', () => {
    expect(statementDate('01/02/2026', 'DMY')).toBe('2026-02-01');
    expect(statementDate('01/02/2026', 'MDY')).toBe('2026-01-02');
    expect(statementDate('2024-02-29', 'ISO')).toBe('2024-02-29');
    expect(() => statementDate('31/02/2026', 'DMY')).toThrow();
    expect(() => statementDate('28/10/26', 'DMY')).toThrow();
  });
  it('flags money movements that must not be counted as new income or expense', () => {
    for (const description of [
      'Card payment thank you',
      'Self transfer',
      'Loan payment',
      'Home EMI',
    ])
      expect(needsTransferReview(description)).toBe(true);
    expect(needsTransferReview('Groceries at Central Market')).toBe(false);
  });
});
