import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';

export function middleware(request: NextRequest) {
  const isDashboard = request.nextUrl.pathname.startsWith('/dashboard');

  if (isDashboard) {
    // Check for Supabase session cookies
    const allCookies = request.cookies.getAll();
    const hasAuthCookie = allCookies.some(cookie => 
      cookie.name.includes('-auth-token') || 
      cookie.name.includes('supabase-auth-token') ||
      cookie.name.startsWith('sb-')
    );

    // If accessing dashboard and no auth cookie exists, redirect to login
    // Note: If client uses localStorage only, the client-side DashboardLayout verifies and guards the session
    if (!hasAuthCookie && request.cookies.get('sb_auth_state')?.value === 'unauthenticated') {
      return NextResponse.redirect(new URL('/login', request.url));
    }
  }

  return NextResponse.next();
}

export const config = {
  matcher: ['/dashboard/:path*'],
};
