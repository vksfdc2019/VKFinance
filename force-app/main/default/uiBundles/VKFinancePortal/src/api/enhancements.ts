import { vkf } from './vkfClient';
import type { EntryInput } from './financeTypes';

export type Feature =
  'IMPORTS' | 'RECEIPTS' | 'REQUESTS' | 'GOALS' | 'INSTALL' | 'INSIGHTS';
export interface EnhancementSettings {
  enabled: Feature[];
  available: Feature[];
  canManage: boolean;
}
export interface Goal {
  id: string;
  title: string;
  target: number;
  progress: number;
  percent: number;
  accountId: string;
  accountName: string;
  targetDate?: string;
  color: string;
  monthlyNeeded?: number;
  canEdit: boolean;
}
export interface GoalInput {
  title: string;
  target: number;
  accountId?: string;
  targetDate?: string;
  includeExisting?: boolean;
  color?: string;
}
export interface SpendRequest {
  id: string;
  title: string;
  amount: number;
  childId: string;
  childName?: string;
  accountName: string;
  categoryName: string;
  status: 'Pending' | 'Approved' | 'Declined' | 'Cancelled' | 'Recorded';
  note?: string;
  decisionNote?: string;
  validUntil: string;
  expired: boolean;
  transactionId?: string;
  createdAt: string;
}
export interface SpendInput {
  title: string;
  amount: number;
  accountId: string;
  categoryId: string;
  note?: string;
  validUntil?: string;
}
export interface Receipt {
  id: string;
  fileName: string;
  mimeType: string;
  bytes: number;
  transactionId: string;
  createdAt: string;
  data?: string;
}
export interface ImportBatch {
  id: string;
  fileName: string;
  accountId: string;
  status:
    'Draft' | 'Processing' | 'Completed' | 'Partial' | 'Cancelled' | 'Archived';
  total: number;
  imported: number;
  duplicates: number;
  failed: number;
  error?: string;
  createdAt: string;
  rows?: {
    id: string;
    row: number;
    entry: EntryInput;
    status: string;
    error?: string;
    transactionId?: string;
  }[];
}
export interface Insight {
  key: string;
  kind: string;
  title: string;
  explanation: string;
  actual: number;
  baseline?: number;
  link: string;
  severity: string;
}

const root = '/enhancements';
const id = encodeURIComponent;
export const enhancementsApi = {
  settings: () => vkf<EnhancementSettings>('GET', `${root}/settings`),
  configure: (enabled: Feature[], currentPassword: string, code?: string) =>
    vkf<EnhancementSettings>('PATCH', `${root}/settings`, {
      enabled,
      currentPassword,
      code,
    }),
  goals: () => vkf<Goal[]>('GET', `${root}/goals`),
  saveGoal: (input: GoalInput, goalId?: string) =>
    vkf<Goal>(
      goalId ? 'PATCH' : 'POST',
      `${root}/goals${goalId ? '/' + id(goalId) : ''}`,
      input
    ),
  archiveGoal: (goalId: string) =>
    vkf<void>('DELETE', `${root}/goals/${id(goalId)}`),
  requests: () => vkf<SpendRequest[]>('GET', `${root}/requests`),
  request: (input: SpendInput) =>
    vkf<SpendRequest>('POST', `${root}/requests`, input),
  act: (
    requestId: string,
    action: 'approve' | 'decline' | 'cancel' | 'record',
    note?: string
  ) =>
    vkf<SpendRequest>('POST', `${root}/requests/${id(requestId)}/${action}`, {
      note,
    }),
  receipts: (transactionId: string) =>
    vkf<Receipt[]>('GET', `${root}/transactions/${id(transactionId)}/receipts`),
  upload: (
    transactionId: string,
    input: { fileName: string; mimeType: string; data: string }
  ) =>
    vkf<Receipt>(
      'POST',
      `${root}/transactions/${id(transactionId)}/receipts`,
      input
    ),
  photo: (receiptId: string) =>
    vkf<Receipt>('GET', `${root}/receipts/${id(receiptId)}`),
  removePhoto: (receiptId: string) =>
    vkf<void>('DELETE', `${root}/receipts/${id(receiptId)}`),
  imports: () => vkf<ImportBatch[]>('GET', `${root}/imports`),
  stage: (accountId: string, fileName: string, rows: EntryInput[]) =>
    vkf<ImportBatch>('POST', `${root}/imports`, { accountId, fileName, rows }),
  import: (batchId: string) =>
    vkf<ImportBatch>('GET', `${root}/imports/${id(batchId)}`),
  commit: (batchId: string) =>
    vkf<ImportBatch>('POST', `${root}/imports/${id(batchId)}/commit`, {}),
  cancelImport: (batchId: string) =>
    vkf<ImportBatch>('POST', `${root}/imports/${id(batchId)}/cancel`, {}),
  insights: () => vkf<Insight[]>('GET', `${root}/insights`),
  dismiss: (key: string, snooze: boolean) =>
    vkf<void>('POST', `${root}/insights/dismiss`, { key, snooze }),
};
