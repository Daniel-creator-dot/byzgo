import { io } from 'socket.io-client';

const isProd = import.meta.env.PROD;
const URL = isProd ? window.location.origin : 'http://localhost:3000';

export const socket = io(URL, {
  autoConnect: false,
});
