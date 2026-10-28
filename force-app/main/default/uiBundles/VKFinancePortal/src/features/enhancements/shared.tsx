import type { SelectHTMLAttributes } from 'react';
import { cn } from '@/lib/utils';

export function NativeSelect({
  className,
  children,
  ...props
}: SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <select
      {...props}
      className={cn(
        'h-10 w-full rounded-lg border border-slate-200 bg-white px-3 text-sm text-slate-800 outline-none focus:border-teal-500 focus:ring-2 focus:ring-teal-100 disabled:opacity-60',
        className
      )}
    >
      {children}
    </select>
  );
}

export function Intro({
  eyebrow,
  title,
  description,
  children,
}: {
  eyebrow: string;
  title: string;
  description: string;
  children?: React.ReactNode;
}) {
  return (
    <div className="mb-7 flex flex-wrap items-end justify-between gap-4">
      <div>
        <p className="mb-2 text-xs font-semibold uppercase tracking-[.18em] text-teal-700">
          {eyebrow}
        </p>
        <h1 className="text-3xl font-semibold tracking-tight text-slate-900">
          {title}
        </h1>
        <p className="mt-2 max-w-2xl text-sm leading-relaxed text-slate-500">
          {description}
        </p>
      </div>
      {children}
    </div>
  );
}
