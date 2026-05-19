import { useCallback, useEffect, useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import {
  Bell,
  Download,
  MapPin,
  Navigation,
  Share,
  Smartphone,
  ChevronRight,
  CheckCircle2,
  AlertCircle,
} from 'lucide-react';
import axios from 'axios';
import { Role } from '../types';
import { LoadingIndicator } from './UI';
import {
  isStandalonePwa,
  isIos,
  isAndroid,
  markSetupComplete,
  requestDeviceLocation,
  roleNeedsLocation,
  roleNeedsNotifications,
} from '../lib/deviceSetup';
import { requestNotificationPermission, subscribeRiderPush } from '../lib/pushNotifications';

type InstallPromptEvent = Event & {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>;
};

type Step = 'install' | 'location' | 'notifications' | 'done';

interface AuthUserShape {
  id: string;
  role: Role;
  lat?: number;
  lng?: number;
}

interface InstallPermissionsOnboardingProps {
  open: boolean;
  role: Role;
  user: AuthUserShape;
  onComplete: (userPatch?: { lat: number; lng: number }) => void;
  onUserRefresh?: (user: AuthUserShape, token: string) => void;
}

export function InstallPermissionsOnboarding({
  open,
  role,
  user,
  onComplete,
  onUserRefresh,
}: InstallPermissionsOnboardingProps) {
  const [step, setStep] = useState<Step>('install');
  const [installPrompt, setInstallPrompt] = useState<InstallPromptEvent | null>(null);
  const [installing, setInstalling] = useState(false);
  const [locationLoading, setLocationLoading] = useState(false);
  const [locationError, setLocationError] = useState('');
  const [notificationLoading, setNotificationLoading] = useState(false);
  const [notificationError, setNotificationError] = useState('');
  const [locationDone, setLocationDone] = useState(false);
  const [notificationsDone, setNotificationsDone] = useState(false);

  const needsLocation = roleNeedsLocation(role);
  const needsNotifications = roleNeedsNotifications(role);
  const installed = isStandalonePwa();

  const resolveInitialStep = useCallback((): Step => {
    if (!installed && !isIos()) return 'install';
    if (isIos() && !installed) return 'install';
    if (needsLocation) return 'location';
    if (needsNotifications) return 'notifications';
    return 'done';
  }, [installed, needsLocation, needsNotifications]);

  useEffect(() => {
    if (!open) return;
    setStep(resolveInitialStep());
    setLocationError('');
    setNotificationError('');
    setLocationDone(localStorage.getItem('bytzgo_location_ok') === '1');
    setNotificationsDone(Notification.permission === 'granted');
  }, [open, resolveInitialStep]);

  const finish = useCallback(() => {
    markSetupComplete(role, { installSkipped: !isStandalonePwa() });
    onComplete();
  }, [role, onComplete]);

  useEffect(() => {
    const onBip = (e: Event) => {
      e.preventDefault();
      setInstallPrompt(e as InstallPromptEvent);
    };
    window.addEventListener('beforeinstallprompt', onBip);
    return () => window.removeEventListener('beforeinstallprompt', onBip);
  }, []);

  useEffect(() => {
    const onInstalled = () => {
      setInstallPrompt(null);
      if (needsLocation) setStep('location');
      else if (needsNotifications) setStep('notifications');
      else finish();
    };
    window.addEventListener('appinstalled', onInstalled);
    return () => window.removeEventListener('appinstalled', onInstalled);
  }, [needsLocation, needsNotifications, finish]);

  const goNextAfterInstall = () => {
    if (needsLocation) setStep('location');
    else if (needsNotifications) setStep('notifications');
    else finish();
  };

  const handleInstall = async () => {
    if (!installPrompt) {
      goNextAfterInstall();
      return;
    }
    setInstalling(true);
    try {
      await installPrompt.prompt();
      const { outcome } = await installPrompt.userChoice;
      if (outcome === 'accepted') return;
    } catch {
      /* user dismissed */
    } finally {
      setInstalling(false);
      setInstallPrompt(null);
      goNextAfterInstall();
    }
  };

  const handleEnableLocation = async () => {
    setLocationLoading(true);
    setLocationError('');
    const pos = await requestDeviceLocation();
    setLocationLoading(false);
    if (!pos) {
      setLocationError('Location was blocked or unavailable. Allow location in your browser or device settings so maps and delivery work.');
      return;
    }
    setLocationDone(true);
    const { latitude: lat, longitude: lng } = pos.coords;
    try {
      const res = await axios.patch('/api/auth/profile', { lat, lng });
      onUserRefresh?.(res.data.user, res.data.token);
      localStorage.setItem('user', JSON.stringify(res.data.user));
      localStorage.setItem('token', res.data.token);
    } catch {
      /* still proceed — maps can use live GPS */
    }
    if (needsNotifications) setStep('notifications');
    else finish();
  };

  const handleEnableNotifications = async () => {
    setNotificationLoading(true);
    setNotificationError('');
    const permission = await requestNotificationPermission();
    if (permission !== 'granted') {
      setNotificationLoading(false);
      setNotificationError(
        'Notifications are off. Enable them in browser settings to get ride requests and order alerts when the app is in the background.'
      );
      return;
    }
    if (role === 'rider') {
      try {
        await subscribeRiderPush();
      } catch {
        setNotificationLoading(false);
        setNotificationError('Could not register for push alerts. Try again after you go Online.');
        return;
      }
    }
    setNotificationLoading(false);
    setNotificationsDone(true);
    finish();
  };

  const skipInstall = () => goNextAfterInstall();

  if (!open || role === 'admin') return null;

  const stepIndex =
    step === 'install' ? 0 : step === 'location' ? 1 : step === 'notifications' ? 2 : 3;
  const totalSteps =
    (installed || step === 'location' || step === 'notifications' || step === 'done'
      ? 0
      : 1) +
    (needsLocation ? 1 : 0) +
    (needsNotifications ? 1 : 0);
  const progress =
    totalSteps > 0 ? Math.min(100, ((stepIndex + (step === 'done' ? 1 : 0.5)) / totalSteps) * 100) : 100;

  return (
    <AnimatePresence>
      {open && (
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          className="fixed inset-0 z-[25000] flex items-end sm:items-center justify-center bg-slate-950/80 backdrop-blur-md p-0 sm:p-4"
        >
          <motion.div
            initial={{ y: '100%' }}
            animate={{ y: 0 }}
            exit={{ y: '100%' }}
            transition={{ type: 'spring', damping: 28, stiffness: 320 }}
            className="w-full max-w-lg bg-white rounded-t-[2.5rem] sm:rounded-[2.5rem] shadow-2xl overflow-hidden max-h-[92vh] flex flex-col"
          >
            <motion.div
              className="h-1 bg-brand-green"
              initial={{ width: 0 }}
              animate={{ width: `${progress}%` }}
            />

            <motion.div className="p-6 sm:p-8 overflow-y-auto flex-1">
              {step === 'install' && (
                <div className="space-y-6">
                  <motion.div
                    className="w-16 h-16 rounded-2xl bg-brand-blue/10 flex items-center justify-center mx-auto"
                    animate={{ scale: [1, 1.05, 1] }}
                    transition={{ duration: 2, repeat: Infinity }}
                  >
                    <Download className="text-brand-blue" size={32} />
                  </motion.div>
                  <div className="text-center space-y-2">
                    <p className="text-[10px] font-black uppercase tracking-[0.25em] text-brand-green">
                      Step 1 · Install app
                    </p>
                    <h2 className="text-2xl font-black tracking-tight text-slate-900">
                      Install BytzGo on your device
                    </h2>
                    <p className="text-sm text-slate-500 font-medium leading-relaxed">
                      Install the app for the best experience on{' '}
                      {isIos() ? 'iPhone/iPad' : isAndroid() ? 'Android' : 'your phone or computer'}.
                      Next we&apos;ll ask for maps and notifications.
                    </p>
                  </div>

                  {isIos() && !installed && (
                    <div className="bg-slate-50 border border-slate-100 rounded-2xl p-5 space-y-3 text-sm">
                      <p className="font-black text-slate-800 uppercase tracking-widest text-[10px]">
                        iPhone / iPad
                      </p>
                      <ol className="space-y-2 text-slate-600 font-medium list-decimal list-inside">
                        <li className="flex items-start gap-2">
                          <Share size={16} className="text-brand-blue shrink-0 mt-0.5" />
                          Tap <strong>Share</strong> in Safari
                        </li>
                        <li>
                          Choose <strong>Add to Home Screen</strong>
                        </li>
                        <li>
                          Open BytzGo from your home screen, then continue setup
                        </li>
                      </ol>
                    </div>
                  )}

                  {!isIos() && installPrompt && (
                    <button
                      type="button"
                      disabled={installing}
                      onClick={handleInstall}
                      className="w-full py-4 bg-brand-blue text-white rounded-2xl font-black uppercase tracking-widest text-xs flex items-center justify-center gap-2"
                    >
                      {installing ? <LoadingIndicator size="sm" /> : <Smartphone size={18} />}
                      {installing ? 'Installing…' : 'Install BytzGo'}
                    </button>
                  )}

                  {!isIos() && !installPrompt && !installed && (
                    <p className="text-center text-xs text-slate-400 font-medium px-4">
                      Use Chrome or Edge, or open the browser menu and choose &quot;Install app&quot; / &quot;Add to Home screen&quot;.
                    </p>
                  )}

                  <div className="flex flex-col gap-2">
                    <button
                      type="button"
                      onClick={skipInstall}
                      className="w-full py-4 bg-slate-900 text-white rounded-2xl font-black uppercase tracking-widest text-xs flex items-center justify-center gap-2"
                    >
                      {installed ? 'Continue setup' : 'Continue in browser'}
                      <ChevronRight size={18} />
                    </button>
                    {!installed && (
                      <p className="text-[10px] text-center text-slate-400 font-medium">
                        You can install later — we&apos;ll still ask for maps &amp; notifications.
                      </p>
                    )}
                  </div>
                </div>
              )}

              {step === 'location' && needsLocation && (
                <motion.div className="space-y-6" initial={{ opacity: 0, x: 20 }} animate={{ opacity: 1, x: 0 }}>
                  <div className="w-16 h-16 rounded-2xl bg-brand-green/10 flex items-center justify-center mx-auto">
                    <MapPin className="text-brand-green" size={32} />
                  </div>
                  <div className="text-center space-y-2">
                    <p className="text-[10px] font-black uppercase tracking-[0.25em] text-brand-green">
                      {installed ? 'Step 1' : 'Step 2'} · Maps &amp; location
                    </p>
                    <h2 className="text-2xl font-black tracking-tight text-slate-900">
                      Allow location for maps
                    </h2>
                    <p className="text-sm text-slate-500 font-medium leading-relaxed">
                      {role === 'rider'
                        ? 'BytzGo uses your location for live maps, navigation, and matching you to nearby rides.'
                        : 'We use your location to show delivery on the map, calculate fees, and find riders near you.'}
                    </p>
                  </div>
                  <div className="flex items-center gap-3 p-4 rounded-2xl bg-brand-blue/5 border border-brand-blue/10">
                    <Navigation className="text-brand-blue shrink-0" size={22} />
                    <p className="text-xs font-bold text-slate-600">
                      When prompted, tap <strong>Allow</strong> so Google Maps can work in the app.
                    </p>
                  </div>
                  {locationError && (
                    <div className="flex gap-2 p-3 rounded-xl bg-amber-50 border border-amber-100 text-amber-800 text-xs font-medium">
                      <AlertCircle size={16} className="shrink-0" />
                      {locationError}
                    </div>
                  )}
                  {locationDone && (
                    <motion.div
                      className="flex items-center gap-2 text-brand-green text-sm font-black uppercase tracking-widest justify-center"
                      initial={{ scale: 0.9 }}
                      animate={{ scale: 1 }}
                    >
                      <CheckCircle2 size={18} /> Location enabled
                    </motion.div>
                  )}
                  <button
                    type="button"
                    disabled={locationLoading}
                    onClick={handleEnableLocation}
                    className="w-full py-4 bg-brand-green text-white rounded-2xl font-black uppercase tracking-widest text-xs flex items-center justify-center gap-2"
                  >
                    {locationLoading ? <LoadingIndicator size="sm" /> : <MapPin size={18} />}
                    {locationLoading ? 'Requesting…' : 'Allow location & maps'}
                  </button>
                  <button
                    type="button"
                    onClick={() => {
                      if (needsNotifications) setStep('notifications');
                      else finish();
                    }}
                    className="w-full py-3 text-slate-400 font-black uppercase tracking-widest text-[10px]"
                  >
                    Skip for now
                  </button>
                </motion.div>
              )}

              {step === 'notifications' && needsNotifications && (
                <motion.div className="space-y-6" initial={{ opacity: 0, x: 20 }} animate={{ opacity: 1, x: 0 }}>
                  <div className="w-16 h-16 rounded-2xl bg-amber-500/10 flex items-center justify-center mx-auto">
                    <Bell className="text-amber-600" size={32} />
                  </div>
                  <motion.div
                    className="text-center space-y-2"
                    animate={{ opacity: [1, 0.85, 1] }}
                    transition={{ duration: 2, repeat: Infinity }}
                  >
                    <p className="text-[10px] font-black uppercase tracking-[0.25em] text-brand-green">
                      Final step · Notifications
                    </p>
                    <h2 className="text-2xl font-black tracking-tight text-slate-900">
                      Allow notifications
                    </h2>
                    <p className="text-sm text-slate-500 font-medium leading-relaxed">
                      {role === 'rider'
                        ? 'Get incoming ride calls and alerts even when the app is in the background or your screen is locked.'
                        : role === 'vendor'
                          ? 'Get notified instantly when customers place new orders.'
                          : 'Get updates when your order is picked up, on the way, or delivered.'}
                    </p>
                  </motion.div>
                  {notificationError && (
                    <motion.div className="flex gap-2 p-3 rounded-xl bg-red-50 border border-red-100 text-red-700 text-xs font-medium">
                      <AlertCircle size={16} className="shrink-0" />
                      {notificationError}
                    </motion.div>
                  )}
                  {notificationsDone && (
                    <div className="flex items-center gap-2 text-brand-green text-sm font-black uppercase tracking-widest justify-center">
                      <CheckCircle2 size={18} /> Notifications enabled
                    </div>
                  )}
                  <button
                    type="button"
                    disabled={notificationLoading}
                    onClick={handleEnableNotifications}
                    className="w-full py-4 bg-slate-900 text-white rounded-2xl font-black uppercase tracking-widest text-xs flex items-center justify-center gap-2"
                  >
                    {notificationLoading ? <LoadingIndicator size="sm" /> : <Bell size={18} />}
                    {notificationLoading ? 'Enabling…' : 'Allow notifications'}
                  </button>
                  <button
                    type="button"
                    onClick={finish}
                    className="w-full py-3 text-slate-400 font-black uppercase tracking-widest text-[10px]"
                  >
                    Skip for now
                  </button>
                </motion.div>
              )}
            </motion.div>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}
