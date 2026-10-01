'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';

export function NavLink({ href, children }: { href: string; children: React.ReactNode }) {
  const pathname = usePathname();
  const active = href === '/' ? pathname === '/' : pathname.startsWith(href);
  return (
    <Link
      href={href}
      aria-current={active ? 'page' : undefined}
      className={`shrink-0 whitespace-nowrap rounded-md px-3 py-2 text-sm font-medium ${active ? 'bg-muted text-foreground' : 'text-muted-foreground hover:text-foreground'}`}
    >
      {children}
    </Link>
  );
}
