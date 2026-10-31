export interface CreditGroupSummary {
  id: string;
  name: string;
  issuer?: string;
  creditLimit: number;
  outstanding: number;
  available: number;
  utilisationPct: number;
  overLimit: number;
  activeCardCount: number;
  version: number;
}
export interface CreditGroup extends CreditGroupSummary {
  cardIds: string[];
  cards: {
    id: string;
    name: string;
    last4?: string;
    balance: number;
    status: 'Active' | 'Closed';
  }[];
}
export interface CreditOverview {
  canManage: boolean;
  groups: CreditGroup[];
  totals: {
    creditLimit?: number;
    outstanding: number;
    available?: number;
    facilities: number;
    restrictedCards: number;
    complete: boolean;
  };
}
export interface CreditGroupInput {
  name: string;
  issuer?: string | null;
  creditLimit: number;
  cardIds: string[];
  expectedVersion?: number;
}
