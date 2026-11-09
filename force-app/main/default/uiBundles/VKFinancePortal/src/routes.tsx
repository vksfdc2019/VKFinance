import { lazy } from "react";
import { Outlet, type RouteObject } from "react-router";
import { Toaster } from "./components/ui/sonner";
import AppLayout from "./components/layout/AppLayout";
import { AuthProvider } from "./features/auth/AuthContext";
import { ThemeProvider } from "./theme/ThemeProvider";
import { PublicOnly, RequireAuth, RequirePermission } from "./features/auth/RouteGuards";
import LoginPage from "./features/auth/pages/LoginPage";
import FirstLoginPage from "./features/auth/pages/FirstLoginPage";
import ForgotPasswordPage from "./features/auth/pages/ForgotPasswordPage";
import ResetPasswordPage from "./features/auth/pages/ResetPasswordPage";
import HomePage from "./pages/Home";
import NotFound from "./pages/NotFound";
import PrivacyPage from "./pages/PrivacyPage";

// Pages beyond the overview load on demand, so signing in downloads less.
const MembersPage = lazy(() => import("./features/family/MembersPage"));
const TransactionsPage = lazy(() => import("./features/transactions/TransactionsPage"));
const AccountsPage = lazy(() => import("./features/accounts/AccountsPage"));
const BudgetsPage = lazy(() => import("./features/budgets/BudgetsPage"));
const CategoriesPage = lazy(() => import("./features/categories/CategoriesPage"));
const ProfilePage = lazy(() => import("./features/profile/ProfilePage"));
const BillsPage = lazy(() => import("./features/commitments/BillsPage"));
const LoansPage = lazy(() => import("./features/commitments/LoansPage"));
const RecurringPage = lazy(() => import("./features/commitments/RecurringPage"));
const ReportsPage = lazy(() => import("./features/reports/ReportsPage"));
const ReportView = lazy(() => import("./features/reports/ReportView"));
const HelpPage = lazy(() => import("./features/help/HelpPage"));
const EnhancementsLayout = lazy(() => import("./features/enhancements/EnhancementsLayout"));
const EnhancementsHome = lazy(() => import("./features/enhancements/EnhancementsLayout").then(m => ({ default: m.EnhancementsHome })));
const ImportsPage = lazy(() => import("./features/enhancements/ImportsPage"));
const ReceiptsPage = lazy(() => import("./features/enhancements/ReceiptsPage"));
const RequestsPage = lazy(() => import("./features/enhancements/RequestsPage"));
const GoalsPage = lazy(() => import("./features/enhancements/GoalsPage"));
const InstallPage = lazy(() => import("./features/enhancements/InstallPage"));
const InsightsPage = lazy(() => import("./features/enhancements/InsightsPage"));
const ArchivePage = lazy(() => import("./features/archive/ArchivePage"));
const AppearancePage = lazy(() => import("./features/appearance/AppearancePage"));
const PositionPage = lazy(() => import("./features/position/PositionPage"));
const AnalyticsPage = lazy(() => import("./features/analytics/AnalyticsPage"));
const SavingsPage = lazy(() => import("./features/savings/SavingsPage"));


function Root() {
	return (
		<AuthProvider>
			<ThemeProvider>
				<Outlet />
				<Toaster />
			</ThemeProvider>
		</AuthProvider>
	);
}

export const routes: RouteObject[] = [
	{
		element: <Root />,
		children: [
			{
				element: <PublicOnly />,
				children: [
					{ path: "/login", element: <LoginPage /> },
					{ path: "/forgot-password", element: <ForgotPasswordPage /> },
				],
			},
			// Reachable signed in or out: the link comes from an email.
			{ path: "/reset-password", element: <ResetPasswordPage /> },
			{ path: "/first-login", element: <FirstLoginPage /> },
			// Public: linked from the Google consent screen.
			{ path: "/privacy", element: <PrivacyPage /> },
			{
				element: <RequireAuth />,
				children: [
					{
						element: <AppLayout />,
						children: [
							{ index: true, element: <HomePage /> },
							{ path: "/profile", element: <ProfilePage /> },
							{ path: "/appearance", element: <AppearancePage /> },
							{ path: "/help", element: <HelpPage /> },
							{
								element: <RequirePermission permission="ENHANCEMENTS:READ" />,
								children: [{ path: "/enhancements", element: <EnhancementsLayout />, children: [
									{ index: true, element: <EnhancementsHome /> },
									{ path: "imports", element: <ImportsPage /> },
									{ path: "receipts", element: <ReceiptsPage /> },
									{ path: "requests", element: <RequestsPage /> },
									{ path: "goals", element: <GoalsPage /> },
									{ path: "install", element: <InstallPage /> },
									{ path: "insights", element: <InsightsPage /> },
								] }],
							},
							{
								element: <RequirePermission permission="DASHBOARD:READ" />,
								children: [
									{ path: "/position", element: <PositionPage /> },
									{ path: "/analytics", element: <AnalyticsPage /> },
								],
							},
							{
								element: <RequirePermission permission="TRANSACTIONS:READ" />,
								children: [
									{ path: "/transactions", element: <TransactionsPage /> },
									{ path: "/archive", element: <ArchivePage /> },
								],
							},
							{
								element: <RequirePermission permission="ACCOUNTS:READ" />,
								children: [
									{ path: "/accounts", element: <AccountsPage /> },
									{ path: "/savings", element: <SavingsPage /> },
								],
							},
							{
								element: <RequirePermission permission="BUDGETS:READ" />,
								children: [{ path: "/budgets", element: <BudgetsPage /> }],
							},
							{
								element: <RequirePermission permission="CATEGORIES:CREATE" />,
								children: [{ path: "/categories", element: <CategoriesPage /> }],
							},
							{
								element: <RequirePermission permission="MEMBERS:CREATE" />,
								children: [{ path: "/family", element: <MembersPage /> }],
							},
							{
								element: <RequirePermission permission="BILLS:READ" />,
								children: [{ path: "/bills", element: <BillsPage /> }],
							},
							{
								element: <RequirePermission permission="LOANS:READ" />,
								children: [{ path: "/loans", element: <LoansPage /> }],
							},
							{
								element: <RequirePermission permission="RECURRING:READ" />,
								children: [{ path: "/recurring", element: <RecurringPage /> }],
							},
							{
								element: <RequirePermission permission="REPORTS:READ" />,
								children: [
									{ path: "/reports", element: <ReportsPage /> },
									{ path: "/reports/:type", element: <ReportView /> },
								],
							},
							{ path: "*", element: <NotFound /> },
						],
					},
				],
			},
		],
	},
];
