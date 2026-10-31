import { useEffect, useState } from "react";
import { CalendarRange } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Spinner } from "@/components/ui/spinner";
import { toast } from "@/components/ui/sonner";
import { FormErrors } from "@/components/forms";
import { familyApi } from "@/api/endpoints";
import { errorMessages } from "@/api/vkfClient";
import type { FamilySettings } from "@/api/types";
import { formatDate } from "@/lib/format";
import { useAuth } from "@/features/auth/AuthContext";

const DAYS = Array.from({ length: 31 }, (_, i) => i + 1);

function ordinal(n: number): string {
	const s = n % 100 >= 11 && n % 100 <= 13 ? "th" : (["th", "st", "nd", "rd"][n % 10] ?? "th");
	return `${n}${s}`;
}

/** When the family's month starts - the 1st, or payday. Only the Family Admin can change it. */
export function MonthStartCard() {
	const { refresh } = useAuth();
	const [settings, setSettings] = useState<FamilySettings>();
	const [day, setDay] = useState("1");
	const [errors, setErrors] = useState<string[]>([]);
	const [saving, setSaving] = useState(false);

	useEffect(() => {
		familyApi
			.settings()
			.then((s) => {
				setSettings(s);
				setDay(String(s.monthStartDay));
			})
			.catch((error: unknown) => setErrors(errorMessages(error)));
	}, []);

	async function save() {
		setSaving(true);
		setErrors([]);
		try {
			const saved = await familyApi.saveSettings({ monthStartDay: Number(day) });
			setSettings(saved);
			await refresh();
			toast.success(saved.monthStartDay === 1 ? "Months now follow the calendar" : `Months now start on the ${ordinal(saved.monthStartDay)}`);
		} catch (error) {
			setErrors(errorMessages(error));
		} finally {
			setSaving(false);
		}
	}

	const n = Number(day);
	const example = n === 1 ? "Each month runs from the 1st to the last day." : n > 15 ? `Salary credited on the ${ordinal(n)} counts towards the next month - e.g. November runs from ${ordinal(n)} October.` : `November runs from ${ordinal(n)} November to the day before the ${ordinal(n)} December.`;

	return (
		<Card>
			<CardHeader>
				<CardTitle className="flex items-center gap-2 text-base">
					<CalendarRange className="size-4" aria-hidden="true" />
					Family month
				</CardTitle>
				<CardDescription>
					Start the month on payday so this month&apos;s salary, budget and spending line up. Bank statements and tax reports still use calendar dates.
				</CardDescription>
			</CardHeader>
			<CardContent className="space-y-3">
				<div className="flex flex-wrap items-end gap-3">
					<div className="grid gap-1.5">
						<Label htmlFor="month-start">Month starts on</Label>
						<Select value={day} onValueChange={setDay} disabled={!settings?.canEdit}>
							<SelectTrigger id="month-start" className="w-44">
								<SelectValue />
							</SelectTrigger>
							<SelectContent>
								{DAYS.map((d) => (
									<SelectItem key={d} value={String(d)}>
										{d === 1 ? "1st (calendar month)" : `${ordinal(d)} of the month`}
									</SelectItem>
								))}
							</SelectContent>
						</Select>
					</div>
					{settings?.canEdit && (
						<Button onClick={() => void save()} disabled={saving || n === settings.monthStartDay}>
							{saving && <Spinner />}
							Save
						</Button>
					)}
				</div>
				<p className="text-xs text-slate-600 dark:text-slate-400">{example} Short months start on their last day.</p>
				{settings && (
					<p className="text-xs text-slate-500 dark:text-slate-400">
						This month: {formatDate(settings.current.startDate)} to {formatDate(settings.current.endDate)}
						{!settings.canEdit && " · only the Family Admin can change this"}
					</p>
				)}
				<FormErrors errors={errors} />
			</CardContent>
		</Card>
	);
}
