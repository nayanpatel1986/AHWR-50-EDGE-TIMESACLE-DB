import { lazyWithRetry } from './lazyWithRetry';
export const RigOverview = lazyWithRetry(() => import('./components/RigOverview/RigOverview'), 'rig-overview');
export const RigConsoleOverview = lazyWithRetry(() => import('./components/RigOverview/RigConsoleOverview'), 'rig-console-overview');
export const WellControlDashboard = lazyWithRetry(() => import('./components/WellControl/WellControlDashboard'), 'well-control');
export const EdrDashboard = lazyWithRetry(() => import('./components/EDR/EdrDashboard'), 'edr');
export const FishingDashboard = lazyWithRetry(() => import('./components/Fishing/FishingDashboard'), 'fishing');
export const EquipmentHub = lazyWithRetry(() => import('./components/Dashboards/EquipmentHub'), 'equipment');
export const ActivityPage = lazyWithRetry(() => import('./components/Activity/ActivityPage'), 'activity');
export const AlarmsPage = lazyWithRetry(() => import('./components/Alarms/AlarmsPage'), 'alarms');
export const WorkoverPage = lazyWithRetry(() => import('./components/Workover/WorkoverPage'), 'workover');
export const ReportsPage = lazyWithRetry(() => import('./components/Reports/ReportsPage'), 'reports');
export const MaintenancePage = lazyWithRetry(() => import('./components/Maintenance/MaintenancePage'), 'maintenance');
export const EfficiencyPage = lazyWithRetry(() => import('./components/Efficiency/EfficiencyPage'), 'efficiency');
export const VariablesPage = lazyWithRetry(() => import('./components/Variables/VariablesPage'), 'variables');
export const EdgeSyncPage = lazyWithRetry(() => import('./components/Sync/EdgeSyncPage'), 'edge-sync');
export const OperationsPage = lazyWithRetry(() => import('./components/Operations/OperationsPage'), 'operations');
export const WellPage = lazyWithRetry(() => import('./components/Well/WellPage'), 'well');
export const SettingsPage = lazyWithRetry(() => import('./components/Settings/SettingsPage'), 'settings');

export const PRELOAD_ROUTES = [
    RigConsoleOverview,
    EdrDashboard,
    EquipmentHub,
    MaintenancePage,
    WellPage,
    EfficiencyPage,
    AlarmsPage,
    ActivityPage,
    WorkoverPage,
    WellControlDashboard,
    ReportsPage,
    VariablesPage,
    EdgeSyncPage,
    OperationsPage,
    FishingDashboard,
    RigOverview,
    SettingsPage
];

const routePages = {
    '/overview-classic': RigOverview,
    '/': RigConsoleOverview,
    '/wellcontrol': WellControlDashboard,
    '/edr': EdrDashboard,
    '/fishing': FishingDashboard,
    '/equipment': EquipmentHub,
    '/activity': ActivityPage,
    '/alarms': AlarmsPage,
    '/workover': WorkoverPage,
    '/reports': ReportsPage,
    '/maintenance': MaintenancePage,
    '/efficiency': EfficiencyPage,
    '/variables': VariablesPage,
    '/sync': EdgeSyncPage,
    '/operations': OperationsPage,
    '/well': WellPage,
    '/settings': SettingsPage,
};

export function preloadRoute(path) {
    return routePages[path]?.preload().catch(() => {});
}
