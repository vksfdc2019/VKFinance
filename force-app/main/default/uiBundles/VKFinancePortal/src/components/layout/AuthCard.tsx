import type { ReactNode } from "react";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { BrandMark } from "./BrandMark";

interface AuthCardProps {
	title: string;
	description?: ReactNode;
	children: ReactNode;
}

/** Centered card used by every signed-out page (sign in, reset, first password). */
export function AuthCard({ title, description, children }: AuthCardProps) {
	return (
		<main className="flex min-h-svh items-center justify-center bg-slate-50 dark:bg-slate-800/40 px-4 py-10">
			<title>{`${title} · VK Finance`}</title>
			<div className="w-full max-w-md">
				<div className="mb-6 flex justify-center">
					<BrandMark />
				</div>
				<Card>
					<CardHeader>
						<CardTitle className="text-xl">{title}</CardTitle>
						{description && <CardDescription>{description}</CardDescription>}
					</CardHeader>
					<CardContent>{children}</CardContent>
				</Card>
			</div>
		</main>
	);
}
