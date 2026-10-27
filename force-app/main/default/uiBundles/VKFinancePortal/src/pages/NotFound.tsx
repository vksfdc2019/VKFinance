import { Link } from "react-router";
import { Button } from "@/components/ui/button";

export default function NotFound() {
	return (
		<div className="mx-auto max-w-md py-16 text-center">
			<title>Not found · VK Finance</title>
			<h1 className="mb-2 text-3xl font-semibold text-slate-900">Page not found</h1>
			<p className="mb-6 text-slate-600">That page doesn't exist or has moved.</p>
			<Button asChild>
				<Link to="/">Go to Home</Link>
			</Button>
		</div>
	);
}
