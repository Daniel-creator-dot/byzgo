import { useEffect, useState } from 'react';
import axios from 'axios';

type AppUpdateConfig = {
  enabled: boolean;
  title: string;
  message: string;
  min_version: string;
  min_build: number;
  ios_url: string;
  android_url: string;
  force: boolean;
  id: string;
};

const DISMISS_KEY = 'bytzgo_app_update_dismissed';

export function AppUpdateNotice() {
  const [notice, setNotice] = useState<AppUpdateConfig | null>(null);
  const [open, setOpen] = useState(false);

  useEffect(() => {
    let cancelled = false;
    axios
      .get<AppUpdateConfig>('/api/config/app-update')
      .then((res) => {
        if (cancelled) return;
        const data = res.data;
        if (!data?.enabled || !String(data.message || '').trim()) return;
        try {
          if (!data.force && localStorage.getItem(DISMISS_KEY) === data.id) return;
        } catch {
          /* ignore */
        }
        setNotice(data);
        setOpen(true);
      })
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, []);

  if (!open || !notice) return null;

  const dismiss = () => {
    if (notice.force) return;
    try {
      localStorage.setItem(DISMISS_KEY, notice.id);
    } catch {
      /* ignore */
    }
    setOpen(false);
  };

  return (
    <div className="fixed inset-0 z-[10000] flex items-end sm:items-center justify-center bg-black/60 p-4">
      <div className="w-full max-w-md rounded-3xl bg-slate-900 border border-slate-700 p-5 shadow-2xl">
        <p className="text-[10px] font-black uppercase tracking-widest text-brand-green mb-2">
          App update
        </p>
        <h2 className="text-xl font-black text-white tracking-tight mb-2">{notice.title}</h2>
        <p className="text-sm text-slate-300 font-medium leading-relaxed whitespace-pre-wrap">
          {notice.message}
        </p>
        <div className="mt-5 flex flex-col sm:flex-row gap-2">
          <a
            href={notice.ios_url}
            target="_blank"
            rel="noreferrer"
            className="flex-1 text-center py-3 rounded-xl bg-brand-blue text-white text-xs font-black uppercase tracking-widest"
          >
            Update iPhone
          </a>
          <a
            href={notice.android_url}
            target="_blank"
            rel="noreferrer"
            className="flex-1 text-center py-3 rounded-xl bg-slate-800 text-white text-xs font-black uppercase tracking-widest border border-slate-600"
          >
            Update Android
          </a>
        </div>
        {!notice.force && (
          <button
            type="button"
            onClick={dismiss}
            className="w-full mt-3 py-2 text-[11px] font-black uppercase tracking-widest text-slate-500"
          >
            Later
          </button>
        )}
      </div>
    </div>
  );
}
