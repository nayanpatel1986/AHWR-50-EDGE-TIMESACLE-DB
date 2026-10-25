import { Suspense, useEffect } from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import Layout from './components/Layout/Layout';
import { RigOverview, RigConsoleOverview, WellControlDashboard, EdrDashboard, FishingDashboard, EquipmentHub, ActivityPage, AlarmsPage, WorkoverPage, ReportsPage, MaintenancePage, EfficiencyPage, VariablesPage, EdgeSyncPage, OperationsPage, WellPage, SettingsPage, PRELOAD_ROUTES } from './routePages';

import { ThemeModeProvider } from './context/ThemeModeContext';
import { AuthProvider } from './context/AuthContext';
import { AlarmProvider } from './context/AlarmContext';
import Login from './components/Auth/Login';
import ProtectedRoute from './components/Auth/ProtectedRoute';
import RoleRoute from './components/Auth/RoleRoute';
import { useAuth } from './context/AuthContext';

import { ErrorBoundary } from './components/ErrorBoundary';

const screen = (Component) => (
    <ErrorBoundary>
        <Suspense fallback={<div style={{ padding: 24, color: '#94a3b8' }}>Loading...</div>}>
            <Component />
        </Suspense>
    </ErrorBoundary>
);

function RoutePreloader() {
    const { token } = useAuth();
    useEffect(() => {
        if (!token) return undefined;
        let cancelled = false;
        let timer;
        let index = 0;
        const preloadNext = () => {
            if (cancelled || index >= PRELOAD_ROUTES.length) return;
            const batch = PRELOAD_ROUTES.slice(index, index + 2);
            index += batch.length;
            Promise.allSettled(batch.map(Component => Component.preload())).then(() => {
                if (!cancelled) timer = setTimeout(preloadNext, 100);
            });
        };
        // Warm pages in small batches so downloads and module evaluation leave
        // room for the page the operator is currently opening.
        timer = setTimeout(preloadNext, 300);
        return () => { cancelled = true; clearTimeout(timer); };
    }, [token]);
    return null;
}

function App() {
    return (
        <ThemeModeProvider>
            <AuthProvider>
                <RoutePreloader />
                <AlarmProvider>
                    <BrowserRouter>
                        <Routes>
                            <Route path="/login" element={<Login />} />

                            <Route element={<ProtectedRoute />}>
                                <Route path="/" element={<Layout />}>
                                <Route index element={screen(RigConsoleOverview)} />
                                <Route path="overview-classic" element={screen(RigOverview)} />
                                <Route path="engine" element={<Navigate to="/equipment" replace />} />
                                <Route path="wellcontrol" element={screen(WellControlDashboard)} />
                                <Route path="fishing" element={screen(FishingDashboard)} />
                                <Route path="edr" element={screen(EdrDashboard)} />
                                <Route path="equipment" element={screen(EquipmentHub)} />
                                <Route path="activity" element={screen(ActivityPage)} />
                                <Route path="alarms" element={screen(AlarmsPage)} />
                                <Route path="operations" element={screen(OperationsPage)} />
                                <Route path="well" element={screen(WellPage)} />
                                <Route path="workover" element={screen(WorkoverPage)} />
                                <Route path="reports" element={screen(ReportsPage)} />
                                <Route path="maintenance" element={screen(MaintenancePage)} />
                                <Route path="efficiency" element={screen(EfficiencyPage)} />
                                <Route path="variables" element={screen(VariablesPage)} />
                                <Route path="sync" element={screen(EdgeSyncPage)} />
                                <Route element={<RoleRoute allow={['admin']} />}>
                                    <Route path="settings" element={screen(SettingsPage)} />
                                </Route>
                                <Route path="admin" element={<Navigate to="/settings" replace />} />
                                <Route path="*" element={screen(RigOverview)} />
                                </Route>
                            </Route>
                        </Routes>
                    </BrowserRouter>
                </AlarmProvider>
            </AuthProvider>
        </ThemeModeProvider>
    );
}

export default App;
