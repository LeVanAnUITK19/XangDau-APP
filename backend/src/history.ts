export type HistoryPriceRecord = {
  effectiveAt?: Date | string | null;
  effectiveDate?: string | null;
  observedAt?: Date | string | null;
};

function validDate(value: Date | string | null | undefined): Date | null {
  if (!value) return null;
  const date = value instanceof Date ? value : new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

export function historyDate(record: HistoryPriceRecord): Date | null {
  if (record.effectiveAt) {
    const effectiveAt = validDate(record.effectiveAt);
    if (effectiveAt) return effectiveAt;
  }

  if (record.effectiveDate) {
    const dateOnly = /^\d{4}-\d{2}-\d{2}$/.test(record.effectiveDate)
      ? `${record.effectiveDate}T00:00:00.000Z`
      : record.effectiveDate;
    const effectiveDate = validDate(dateOnly);
    if (effectiveDate) return effectiveDate;
  }

  return validDate(record.observedAt);
}

export function selectHistoryWindow<T extends HistoryPriceRecord>(
  records: readonly T[],
  from: Date,
): { records: T[]; dates: Date[] } {
  const dated = records
    .flatMap((record) => {
      const date = historyDate(record);
      return date ? [{ record, date }] : [];
    })
    .sort((a, b) => a.date.getTime() - b.date.getTime());

  const carry = dated.filter(({ date }) => date < from).at(-1);
  const inWindow = dated.filter(({ date }) => date >= from);
  const selected = [...(carry ? [carry] : []), ...inWindow];

  return {
    records: selected.map(({ record }) => record),
    dates: selected.map(({ date }) => date),
  };
}
