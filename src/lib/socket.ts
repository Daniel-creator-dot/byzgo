import { io } from 'socket.io-client';
import { getApiBaseUrl } from './api';

export const socket = io(getApiBaseUrl(), {
  autoConnect: false,
  reconnection: true,
  reconnectionAttempts: Infinity,
  reconnectionDelay: 1000,
  reconnectionDelayMax: 5000,
  transports: ['websocket', 'polling'],
});
