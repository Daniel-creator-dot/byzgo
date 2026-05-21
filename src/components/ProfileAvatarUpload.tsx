import { useRef, useState } from 'react';
import axios from 'axios';
import { Camera } from 'lucide-react';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

type Props = {
  name: string;
  avatarUrl?: string;
  onUpdated: (user: Record<string, unknown>, token: string) => void;
  onError?: (message: string) => void;
  className?: string;
  size?: 'md' | 'lg';
};

export function ProfileAvatarUpload({
  name,
  avatarUrl,
  onUpdated,
  onError,
  className,
  size = 'lg',
}: Props) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [uploading, setUploading] = useState(false);
  const dim = size === 'lg' ? 'w-20 h-20 sm:w-24 sm:h-24' : 'w-16 h-16';
  const textSize = size === 'lg' ? 'text-2xl sm:text-3xl' : 'text-xl';

  const upload = async (file: File) => {
    setUploading(true);
    try {
      const formData = new FormData();
      formData.append('image', file);
      const up = await axios.post('/api/upload', formData, {
        headers: { 'Content-Type': 'multipart/form-data' },
      });
      const res = await axios.patch('/api/auth/profile', { avatar_url: up.data.url });
      onUpdated(res.data.user, res.data.token);
    } catch (err: unknown) {
      const msg =
        (err as { response?: { data?: { message?: string } } })?.response?.data?.message ||
        'Failed to upload photo';
      onError?.(msg);
    } finally {
      setUploading(false);
    }
  };

  return (
    <div className={cn('relative inline-flex shrink-0', className)}>
      <button
        type="button"
        disabled={uploading}
        onClick={() => inputRef.current?.click()}
        className={cn(
          dim,
          'rounded-2xl sm:rounded-3xl overflow-hidden border-2 border-brand-blue/30 shadow-lg relative group focus:outline-none focus:ring-4 focus:ring-brand-blue/20'
        )}
        aria-label="Change profile photo"
      >
        {avatarUrl ? (
          <img src={avatarUrl} alt="" className="w-full h-full object-cover" />
        ) : (
          <span
            className={cn(
              'w-full h-full flex items-center justify-center bg-brand-blue text-white font-black italic',
              textSize
            )}
          >
            {name[0]?.toUpperCase() || '?'}
          </span>
        )}
        <span className="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center">
          <Camera size={22} className="text-white" />
        </span>
        {uploading && (
          <span className="absolute inset-0 bg-black/50 flex items-center justify-center text-[10px] font-black uppercase text-white">
            Uploading…
          </span>
        )}
      </button>
      <input
        ref={inputRef}
        type="file"
        accept="image/*"
        className="hidden"
        onChange={(e) => {
          const file = e.target.files?.[0];
          if (file) void upload(file);
          e.target.value = '';
        }}
      />
    </div>
  );
}
