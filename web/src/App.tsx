import { Routes, Route, useLocation, Navigate } from 'react-router-dom'
import { useState, useEffect, lazy, Suspense } from 'react'
import LandingPage from './pages/LandingPage'
import EventDiscovery from './pages/EventDiscovery'
import { RaceCenter } from './components/RaceCenter'
import VehiclePage from './pages/VehiclePage'
import TeamLogin from './pages/TeamLogin'
import TeamDashboard from './pages/TeamDashboard'
import ProductionDashboard from './pages/ProductionDashboard'
import ProductionEventPicker from './pages/ProductionEventPicker'
import ControlRoom from './pages/ControlRoom'
import AdminDashboard from './pages/admin/AdminDashboard'
import AdminLogin from './pages/admin/AdminLogin'
import EventCreate from './pages/admin/EventCreate'
import EventDetail from './pages/admin/EventDetail'
import BottomNav from './components/common/BottomNav'
import AppLoading from './components/common/AppLoading'
import NotFound from './components/common/NotFound'
import ErrorBoundary from './components/common/ErrorBoundary'

// Dev-only component showcase (lazy loaded)
const ComponentShowcase = lazy(() => import('./pages/ComponentShowcase'))

const API_BASE = import.meta.env.VITE_API_URL || '/api/v1'

/**
 * Protected Route wrapper for admin pages.
 * Checks authentication status and redirects to login if needed.
 */
function ProtectedAdminRoute({ children }: { children: React.ReactNode }) {
  const location = useLocation()
  const [authState, setAuthState] = useState<'loading' | 'authenticated' | 'unauthenticated'>('loading')

  useEffect(() => {
    checkAuth()
  }, [])

  async function checkAuth() {
    try {
      // Get token from localStorage as backup
      const token = localStorage.getItem('admin_token')
      const headers: HeadersInit = {}
      if (token) {
        headers['Authorization'] = `Bearer ${token}`
      }

      const response = await fetch(`${API_BASE}/admin/auth/status`, {
        credentials: 'include',
        headers,
      })

      if (response.ok) {
        // Verify response is JSON before parsing (handles 502 returning HTML)
        const contentType = response.headers.get('content-type')
        if (!contentType || !contentType.includes('application/json')) {
          console.warn('Auth status returned non-JSON response, allowing access')
          setAuthState('authenticated')
          return
        }

        const data = await response.json()
        // If no auth required OR already authenticated, allow access
        if (!data.auth_required || data.authenticated) {
          setAuthState('authenticated')
        } else {
          setAuthState('unauthenticated')
        }
      } else {
        // For 5xx errors, allow access (server issue, not auth issue)
        if (response.status >= 500) {
          console.warn(`Auth status returned ${response.status}, allowing access`)
          setAuthState('authenticated')
        } else {
          setAuthState('unauthenticated')
        }
      }
    } catch (err) {
      console.error('Auth check failed:', err)
      // On error, try to show the page anyway (might be network issue)
      setAuthState('authenticated')
    }
  }

  if (authState === 'loading') {
    return <AppLoading message="Verifying access..." />
  }

  if (authState === 'unauthenticated') {
    // Redirect to login, preserving the intended destination
    return <Navigate to="/admin/login" state={{ from: location.pathname }} replace />
  }

  return <>{children}</>
}

function App() {
  const location = useLocation()

  // Show bottom nav only on event discovery page
  // RaceCenter (/events/:eventId) has its own TabBar, so hide the global BottomNav
  // Hide on admin/production/team dashboards
  const isEventDiscovery = location.pathname === '/events'
  const isVehiclePage = /^\/events\/[^/]+\/vehicles\//.test(location.pathname)
  const showBottomNav = isEventDiscovery || isVehiclePage

  return (
    <ErrorBoundary>
      <div className="h-full flex flex-col bg-neutral-950">
        <Routes>
        {/* Landing Page - public, role-neutral */}
        <Route path="/" element={<LandingPage />} />

        {/* Admin Login - public route */}
        <Route path="/admin/login" element={<AdminLogin />} />

        {/* Admin / Organizer routes - Protected */}
        <Route path="/admin" element={
          <ProtectedAdminRoute>
            <AdminDashboard />
          </ProtectedAdminRoute>
        } />
        <Route path="/admin/events/new" element={
          <ProtectedAdminRoute>
            <EventCreate />
          </ProtectedAdminRoute>
        } />
        <Route path="/admin/events/:eventId" element={
          <ProtectedAdminRoute>
            <EventDetail />
          </ProtectedAdminRoute>
        } />
        <Route path="/admin/events/:eventId/vehicles" element={
          <ProtectedAdminRoute>
            <EventDetail />
          </ProtectedAdminRoute>
        } />

        {/* Fan routes - public */}
        {/* FIXED: P1-2 - Added event discovery page for mobile fans */}
        <Route path="/events" element={<EventDiscovery />} />
        <Route path="/events/:eventId" element={<RaceCenter />} />
        <Route path="/events/:eventId/vehicles/:vehicleId" element={<VehiclePage />} />

        {/* Team routes */}
        <Route path="/team/login" element={<TeamLogin />} />
        <Route path="/team/dashboard" element={<TeamDashboard />} />

        {/* Production Director routes */}
        <Route path="/production" element={<ProductionEventPicker />} />
        <Route path="/production/events/:eventId" element={<ControlRoom />} />
        {/* Legacy route - keep for backwards compatibility */}
        <Route path="/events/:eventId/production" element={<ProductionDashboard />} />

        {/* Dev-only component showcase */}
        {import.meta.env.DEV && (
          <Route
            path="/dev/components"
            element={
              <Suspense fallback={<AppLoading message="Loading components..." />}>
                <ComponentShowcase />
              </Suspense>
            }
          />
        )}

        {/* 404 catch-all route */}
        <Route path="*" element={<NotFound />} />
      </Routes>

        {/* Mobile Bottom Navigation - only on fan event pages */}
        {showBottomNav && <BottomNav />}
      </div>
    </ErrorBoundary>
  )
}

export default App
