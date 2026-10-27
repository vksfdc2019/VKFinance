import { lazy } from "react";
import { Outlet, type RouteObject } from "react-router";
import { Toaster } from "./components/ui/sonner";
import AppLayout from "./components/layout/AppLayout";
import { AuthProvider } from "./features/auth/AuthContext";
import { PublicOnly, RequireAuth, RequirePermission } from "./features/auth/RouteGuards";
import LoginPage from "./features/auth/pages/LoginPage";
import FirstLoginPage from "./features/auth/pages/FirstLoginPage";
import ForgotPasswordPage from "./features/auth/pages/ForgotPasswordPage";
import ResetPasswordPage from "./features/auth/pages/ResetPasswordPage";
import HomePage from "./pages/Home";
import NotFound from "./pages/NotFound";

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

function Root() {
	return (
		<AuthProvider>
			<Outlet />
			<Toaster />
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
			{
				element: <RequireAuth />,
				children: [
					{
						element: <AppLayout />,
						children: [
							{ index: true, element: <HomePage /> },
							{ path: "/profile", element: <ProfilePage /> },
							{
								element: <RequirePermission permission="TRANSACTIONS:READ" />,
								children: [{ path: "/transactions", element: <TransactionsPage /> }],
							},
							{
								element: <RequirePermission permission="ACCOUNTS:READ" />,
								children: [{ path: "/accounts", element: <AccountsPage /> }],
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
							{ path: "*", element: <NotFound /> },
						],
					},
				],
			},
		],
	},
];
