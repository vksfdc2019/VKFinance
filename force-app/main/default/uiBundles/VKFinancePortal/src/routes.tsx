import type { RouteObject } from 'react-router';
import Home from './pages/Home';
import NotFound from './pages/NotFound';
import Login from "./features/authentication/pages/Login";
import Register from "./features/authentication/pages/Register";
import ForgotPassword from "./features/authentication/pages/ForgotPassword";
import ResetPassword from "./features/authentication/pages/ResetPassword";
import Profile from "./features/authentication/pages/Profile";
import ChangePassword from "./features/authentication/pages/ChangePassword";
import PrivateRoute from "./features/authentication/layouts/privateRouteLayout";
import { ROUTES } from "./features/authentication/authenticationConfig";
import { Search as GlobalSearch, config } from "./features/search";
import TestChatPage from "./pages/TestChatPage";
import AuthAppLayout from "./features/authentication/layouts/AuthAppLayout";
import AccountObjectDetail from "./pages/AccountObjectDetailPage";

export const routes: RouteObject[] = [
  {
    path: "/",
    element: <AuthAppLayout />,
    children: [
      {
        index: true,
        element: <Home />,
        handle: { showInNavigation: true, label: "Home" }
      },
      {
        path: ROUTES.LOGIN.PATH,
        element: <Login />,
        handle: { showInNavigation: false, label: "Login", title: ROUTES.LOGIN.TITLE }
      },
      {
        path: ROUTES.REGISTER.PATH,
        element: <Register />,
        handle: { showInNavigation: false, title: ROUTES.REGISTER.TITLE }
      },
      {
        path: ROUTES.FORGOT_PASSWORD.PATH,
        element: <ForgotPassword />,
        handle: { showInNavigation: false, title: ROUTES.FORGOT_PASSWORD.TITLE }
      },
      {
        path: ROUTES.RESET_PASSWORD.PATH,
        element: <ResetPassword />,
        handle: { showInNavigation: false, title: ROUTES.RESET_PASSWORD.TITLE }
      },
      {
        element: <PrivateRoute />,
        children: [
          {
            path: ROUTES.PROFILE.PATH,
            element: <Profile />,
            handle: { showInNavigation: false, label: "Profile", title: ROUTES.PROFILE.TITLE }
          },
          {
            path: ROUTES.CHANGE_PASSWORD.PATH,
            element: <ChangePassword />,
            handle: { showInNavigation: false, title: ROUTES.CHANGE_PASSWORD.TITLE }
          }
        ]
      },
      {
        path: "search",
        element: (
					<GlobalSearch
						config={config}
						title="Search"
						searchPlaceholder="Search accounts, contacts, opportunities, and content..."
					/>
				),
        handle: { showInNavigation: true, label: "Search" }
      },
      {
        path: "test-chat",
        element: <TestChatPage />,
        handle: { showInNavigation: true, label: "Test Chat" }
      },
      {
        path: "accounts/:recordId",
        element: <AccountObjectDetail />
      },
      {
        path: '*',
        element: <NotFound />
      }
    ]
  }
];
