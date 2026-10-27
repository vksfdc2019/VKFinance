import { Outlet, type RouteObject } from "react-router";
import { Toaster } from "./components/ui/sonner";
import AppLayout from "./components/layout/AppLayout";
import { AuthProvider } from "./features/auth/AuthContext";
import { PublicOnly, RequireAuth, RequirePermission } from "./features/auth/RouteGuards";
import LoginPage from "./features/auth/pages/LoginPage";
import FirstLoginPage from "./features/auth/pages/FirstLoginPage";
import ForgotPasswordPage from "./features/auth/pages/ForgotPasswordPage";
import ResetPasswordPage from "./features/auth/pages/ResetPasswordPage";
import MembersPage from "./features/family/MembersPage";
import ProfilePage from "./features/profile/ProfilePage";
import HomePage from "./pages/Home";
import NotFound from "./pages/NotFound";

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
								element: <RequirePermission permission="MEMBERS:CREATE" />,
								children: [{ path: "/family", element: <MembersPage /> }],
							},
							{ path: "*", element: <NotFound /> },
						],
					},
				],
			},
		],
	},
];
