import axios from 'axios';

const phone = process.argv[2] || '0247904675';
const message = process.argv[3] || 'BytzGo SMS test message.';

const apiKey = process.env.SMS_API_KEY || 'INTEK_0E3012.cb48045dfaa3384211cdcbf82516d36fff101a23da78f1dd';
const baseUrl = (process.env.SMS_BASE_URL || 'https://www.inteksms.top/api/v1').replace(/\/$/, '');
const senderId = process.env.SMS_SENDER_ID || 'bytzee';

let formattedPhone = phone.trim().replace(/\s+/g, '');
if (formattedPhone.startsWith('0')) formattedPhone = '233' + formattedPhone.slice(1);
else if (!formattedPhone.startsWith('233') && formattedPhone.length === 9) formattedPhone = '233' + formattedPhone;

const headers = {
  Authorization: `Bearer ${apiKey}`,
  apikey: apiKey,
  'Content-Type': 'application/json',
};

const res = await axios.post(`${baseUrl}/messages/send`, {
  recipients: [formattedPhone],
  message,
  sender: senderId,
}, { headers, timeout: 15000 });

console.log('Sent to', formattedPhone);
console.log(JSON.stringify(res.data, null, 2));
