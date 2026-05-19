import { io } from 'socket.io-client';
import { getApiBaseUrl } from './api';

export const socket = io(getApiBaseUrl(), {
  autoConnect: false,
});
