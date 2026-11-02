/** Shape of GET /vkf/v1/dashboard/analytics: each family month's money split, daily spending and top payees. */

export interface MonthFlow {
	month: string;
	periodStart: string;
	periodEnd: string;
	income: number;
	/** Everyday spending: expenses less refunds, without bills or loan interest. */
	spending: number;
	bills: number;
	/** EMI principal and interest. */
	emis: number;
	saved: number;
	savingsRate?: number;
}

export interface Analytics {
	month: string;
	periodStart: string;
	periodEnd: string;
	currencyCode?: string;
	memberId?: string;
	members: { id: string; name: string }[];
	/** Oldest first, ending with the selected month. */
	series: MonthFlow[];
	current: MonthFlow;
	days: { day: string; amount: number }[];
	payees: { name: string; amount: number; count: number }[];
}
