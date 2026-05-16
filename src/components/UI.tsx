import React from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { X, AlertCircle, CheckCircle2 } from 'lucide-react';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

interface ModalProps {
  isOpen: boolean;
  onClose: () => void;
  title: string;
  children: React.ReactNode;
  maxWidth?: string;
}

export const Modal: React.FC<ModalProps> = ({ isOpen, onClose, title, children, maxWidth = 'max-w-md' }) => {
  return (
    <AnimatePresence>
      {isOpen && (
        <>
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={onClose}
            className="fixed inset-0 bg-slate-900/40 backdrop-blur-sm z-[200]"
          />
          <motion.div
            initial={{ opacity: 0, scale: 0.9, y: 20 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.9, y: 20 }}
            className={cn(
              "fixed top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-full p-6 sm:p-8 bg-white rounded-[2.5rem] shadow-2xl z-[210] border border-slate-100",
              maxWidth
            )}
          >
            <div className="flex justify-between items-center mb-6">
              <h3 className="text-xl sm:text-2xl font-black italic tracking-tighter text-slate-800">{title}</h3>
              <button type="button" onClick={onClose} className="p-2 hover:bg-slate-100 rounded-xl transition-colors">
                <X size={20} />
              </button>
            </div>
            {children}
          </motion.div>
        </>
      )}
    </AnimatePresence>
  );
};

interface ConfirmationModalProps {
  isOpen: boolean;
  onClose: () => void;
  onConfirm: () => void;
  title: string;
  message: string;
  confirmLabel?: string;
  cancelLabel?: string;
  type?: 'danger' | 'success' | 'info';
}

export const ConfirmationModal: React.FC<ConfirmationModalProps> = ({
  isOpen,
  onClose,
  onConfirm,
  title,
  message,
  confirmLabel = 'Confirm',
  cancelLabel = 'Cancel',
  type = 'info'
}) => {
  return (
    <Modal isOpen={isOpen} onClose={onClose} title={title}>
      <div className="space-y-6">
        <div className="flex gap-4 items-start">
          <div className={cn(
            "w-12 h-12 rounded-2xl flex items-center justify-center shrink-0",
            type === 'danger' ? "bg-red-50 text-red-500" :
            type === 'success' ? "bg-brand-green/10 text-brand-green" :
            "bg-brand-blue/10 text-brand-blue"
          )}>
            {type === 'danger' ? <AlertCircle size={24} /> : 
             type === 'success' ? <CheckCircle2 size={24} /> : 
             <AlertCircle size={24} />}
          </div>
          <p className="text-slate-500 font-medium leading-relaxed">{message}</p>
        </div>
        <div className="flex flex-col sm:flex-row gap-3">
          <button
            type="button"
            onClick={onClose}
            className="flex-1 py-4 bg-slate-100 text-slate-500 rounded-2xl font-black uppercase tracking-widest text-xs hover:bg-slate-200 transition-all"
          >
            {cancelLabel}
          </button>
          <button
            type="button"
            onClick={() => {
              onConfirm();
              onClose();
            }}
            className={cn(
              "flex-1 py-4 text-white rounded-2xl font-black uppercase tracking-widest text-xs hover:scale-[1.02] active:scale-[0.98] transition-all shadow-lg",
              type === 'danger' ? "bg-red-500 shadow-red-500/20" :
              type === 'success' ? "bg-brand-green shadow-brand-green/20" :
              "bg-brand-blue shadow-brand-blue/20"
            )}
          >
            {confirmLabel}
          </button>
        </div>
      </div>
    </Modal>
  );
};

interface LoadingIndicatorProps {
  size?: 'sm' | 'md' | 'lg' | 'xl';
  className?: string;
  withText?: boolean;
  text?: string;
  variant?: 'blue' | 'white' | 'green';
}

export const LoadingIndicator: React.FC<LoadingIndicatorProps> = ({ 
  size = 'md', 
  className = '', 
  withText = false,
  text = 'Loading...',
  variant = 'blue'
}) => {
  const sizes = {
    sm: 'w-5 h-5 border-2',
    md: 'w-10 h-10 border-3',
    lg: 'w-16 h-16 border-4',
    xl: 'w-24 h-24 border-4'
  };

  const variants = {
    blue: 'border-brand-blue/20 border-t-brand-blue',
    white: 'border-white/20 border-t-white',
    green: 'border-brand-green/20 border-t-brand-green'
  };

  return (
    <div className={cn("flex flex-col items-center justify-center gap-4", className)}>
      <div 
        className={cn(
          "rounded-full animate-spin",
          variants[variant],
          sizes[size]
        )}
      />
      {withText && (
        <p className="text-[10px] font-black uppercase tracking-widest text-slate-400 animate-pulse">
          {text}
        </p>
      )}
    </div>
  );
};
