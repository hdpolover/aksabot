import { Navigate } from 'react-router-dom';
import type { ReactNode } from 'react';

export default function ProtectedRoute({ children }: { children: ReactNode }) {
  const jwt = localStorage.getItem('aksa-jwt');
  if (!jwt) return <Navigate to="/login" replace />;
  return <>{children}</>;
}
