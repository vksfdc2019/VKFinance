import { format, formatDistanceToNow } from "date-fns";

export function formatDateTime(value?: string | null): string {
	return value ? format(new Date(value), "d MMM yyyy, h:mm a") : "—";
}

export function formatRelative(value?: string | null): string {
	return value ? `${formatDistanceToNow(new Date(value))} ago` : "Never";
}
