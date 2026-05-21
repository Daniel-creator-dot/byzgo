import { initializeApp } from "firebase/app";
import { getAuth, GoogleAuthProvider } from "firebase/auth";

/** Admin SPA (Vite). Mobile uses bytzgo-9bd89 via google-services.json + API token exchange. */
const firebaseConfig = {
  apiKey: "AIzaSyDzL9872ocLF9ykQMfbKMjww4zfENofe5U",
  authDomain: "bytzgo-72f1c.firebaseapp.com",
  projectId: "bytzgo-72f1c",
  storageBucket: "bytzgo-72f1c.firebasestorage.app",
  messagingSenderId: "1032098732502",
  appId: "1:1032098732502:web:f1c176dde9354a02dcec77",
  measurementId: "G-RHE4PB3S9K",
};

const app = initializeApp(firebaseConfig);
export const auth = getAuth(app);
export const googleProvider = new GoogleAuthProvider();
