import { Moon, Sun } from "lucide-react";
import { Button } from "@/components/ui/button";
import { toast } from "@/components/ui/sonner";
import { errorMessages } from "@/api/vkfClient";
import { cn } from "@/lib/utils";
import { useTheme } from "@/theme/ThemeProvider";

/** One-tap light/dark switch. Saves the choice; "Match device" lives on the Appearance page. */
export function ModeToggle({ className }: { className?: string }) {
	const { isDark, setMode } = useTheme();
	const next = isDark ? "light" : "dark";

	async function toggle() {
		try {
			await setMode(next);
		} catch (error) {
			toast.error(errorMessages(error)[0] ?? "Couldn't save your theme.");
		}
	}

	return (
		<Button
			variant="ghost"
			size="icon"
			className={cn("rounded-full", className)}
			aria-label={isDark ? "Switch to light mode" : "Switch to dark mode"}
			title={isDark ? "Light mode" : "Dark mode"}
			onClick={() => void toggle()}
		>
			{isDark ? <Sun className="vk-pop" /> : <Moon className="vk-pop" />}
		</Button>
	);
}
