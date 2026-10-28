import { Link } from "react-router";
import { BrandMark } from "@/components/layout/BrandMark";

const SECTIONS: { title: string; body: string[] }[] = [
	{
		title: "What VK Finance stores",
		body: [
			"VK Finance is a private budgeting app for invited families. It stores what members enter: accounts, transactions, budgets, bills, loans, goals and receipt photos, plus sign-in records needed to keep accounts secure.",
			"Data is held in Salesforce. Passwords are stored only as salted hashes, two-step keys are encrypted, and each family can see only its own records.",
		],
	},
	{
		title: "Archive copies in Google Drive",
		body: [
			"Older records are archived each night. A copy is written to a private Google Drive owned by the app's operator, using Google's drive.file permission: the app can see only the folders and spreadsheets it creates, never other files in that Drive.",
			"Archive copies never include passwords, two-step keys, recovery codes or session tokens. They are not shared with anyone.",
		],
	},
	{
		title: "What we don't do",
		body: ["VK Finance has no advertising, doesn't sell or share data, and doesn't use data from Google services for anything other than storing the archive copy described above."],
	},
	{
		title: "Your choices",
		body: [
			"A Family Admin can ask for a family's data to be exported or deleted, including its archive copies. Removed members' sign-in records are deleted on the regular retention schedule.",
		],
	},
	{
		title: "Contact",
		body: ["Questions about privacy: vksfdc2019@gmail.com."],
	},
];

/** Public privacy notice; also the privacy policy URL on the Google OAuth consent screen. */
export default function PrivacyPage() {
	return (
		<main className="min-h-svh bg-slate-50 px-4 py-10">
			<title>Privacy · VK Finance</title>
			<article className="mx-auto max-w-2xl rounded-2xl bg-white p-6 shadow-sm ring-1 ring-slate-900/5 sm:p-10">
				<BrandMark />
				<h1 className="mt-6 text-2xl font-semibold tracking-tight text-slate-900">Privacy policy</h1>
				<p className="mt-1 text-sm text-slate-500">Last updated 28 October 2026</p>
				{SECTIONS.map((s) => (
					<section key={s.title} className="mt-6">
						<h2 className="text-base font-semibold text-slate-900">{s.title}</h2>
						{s.body.map((p) => (
							<p key={p} className="mt-2 text-sm leading-relaxed text-slate-700">
								{p}
							</p>
						))}
					</section>
				))}
				<p className="mt-8 text-sm">
					<Link to="/login" className="font-medium text-teal-700 hover:underline">
						Go to sign in
					</Link>
				</p>
			</article>
		</main>
	);
}
