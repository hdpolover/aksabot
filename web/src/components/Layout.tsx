import { Outlet, NavLink, useNavigate } from 'react-router-dom';
import { Home, MessageSquare, Brain, Settings, LogOut } from 'lucide-react';
import { useConnectionStore } from '../store/connectionStore';

const NAV_ITEMS = [
  { to: '/',          icon: Home,          label: 'Home',      end: true },
  { to: '/history',   icon: MessageSquare, label: 'History' },
  { to: '/memories',  icon: Brain,         label: 'Memories' },
  { to: '/settings',  icon: Settings,      label: 'Settings' },
];

export default function Layout() {
  const status = useConnectionStore((s) => s.status);
  const disconnect = useConnectionStore((s) => s.disconnect);
  const navigate = useNavigate();

  function handleSignOut() {
    disconnect();
    localStorage.removeItem('aksa-jwt');
    navigate('/login');
  }

  const dot =
    status === 'connected'
      ? 'bg-emerald-400'
      : status === 'connecting'
        ? 'bg-yellow-400 animate-pulse'
        : 'bg-red-500';

  return (
    <div className="flex h-full">
      {/* ── Sidebar (desktop) ── */}
      <aside className="hidden md:flex flex-col w-[220px] flex-shrink-0 bg-[#12121c] border-r border-[#2a2a40] h-full fixed left-0 top-0 z-30">
        {/* Logo */}
        <div className="flex items-center gap-3 px-5 py-5 border-b border-[#2a2a40]">
          <div className="relative flex-shrink-0">
            <div className="w-8 h-8 rounded-full bg-[#00e5ff]/10 border border-[#00e5ff]/30 flex items-center justify-center">
              <span className="text-[#00e5ff] text-xs font-bold">A</span>
            </div>
            <span className={`absolute -bottom-0.5 -right-0.5 w-2.5 h-2.5 rounded-full border-2 border-[#12121c] ${dot}`} />
          </div>
          <div className="min-w-0">
            <p className="text-sm font-semibold text-gray-100 leading-none">Aksa</p>
            <p className="text-[11px] text-gray-500 mt-0.5 capitalize">{status}</p>
          </div>
        </div>

        {/* Nav */}
        <nav className="flex-1 py-3 px-2 space-y-0.5">
          {NAV_ITEMS.map(({ to, icon: Icon, label, end }) => (
            <NavLink
              key={to}
              to={to}
              end={end}
              className={({ isActive }) =>
                `flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm transition-colors ${
                  isActive
                    ? 'bg-[#00e5ff]/10 text-[#00e5ff]'
                    : 'text-gray-400 hover:text-gray-100 hover:bg-[#1a1a28]'
                }`
              }
            >
              <Icon size={18} />
              {label}
            </NavLink>
          ))}
        </nav>

        {/* Sign out */}
        <div className="p-2 border-t border-[#2a2a40]">
          <button
            onClick={handleSignOut}
            className="w-full flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm text-gray-500 hover:text-red-400 hover:bg-red-500/10 transition-colors"
          >
            <LogOut size={18} />
            Sign out
          </button>
        </div>
      </aside>

      {/* ── Main content ── */}
      <main className="flex-1 flex flex-col min-h-0 md:ml-[220px] pb-16 md:pb-0 overflow-hidden">
        <Outlet />
      </main>

      {/* ── Bottom nav (mobile) ── */}
      <nav className="md:hidden fixed bottom-0 left-0 right-0 z-30 bg-[#12121c] border-t border-[#2a2a40] flex items-stretch h-16">
        {NAV_ITEMS.map(({ to, icon: Icon, label, end }) => (
          <NavLink
            key={to}
            to={to}
            end={end}
            className={({ isActive }) =>
              `flex-1 flex flex-col items-center justify-center gap-0.5 text-[10px] font-medium transition-colors ${
                isActive ? 'text-[#00e5ff]' : 'text-gray-500 hover:text-gray-300'
              }`
            }
          >
            <Icon size={20} />
            {label}
          </NavLink>
        ))}

        {/* WS status dot on mobile */}
        <div className="absolute top-1.5 right-2">
          <span className={`block w-2 h-2 rounded-full ${dot}`} />
        </div>
      </nav>
    </div>
  );
}
