/** TechPlay 専用 */

import { loginWithPlaywright, fillAndSubmit } from './utils.js';

export const SITE_NAME = 'techplay';

export const config = {
  loginUrl:  process.env.TECHPLAY_LOGIN_URL  || 'https://techplay.jp/signin',
  mypage:    process.env.TECHPLAY_URL        || 'https://techplay.jp/',
  createUrl: process.env.TECHPLAY_CREATE_URL || 'https://techplay.jp/event/create',
  email:     process.env.TECHPLAY_EMAIL,
  password:  process.env.TECHPLAY_PASSWORD,
  emailSel:  'input[name="email"]',
  passSel:   'input[name="password"]',
};

export async function post(page, content, _eventFields, log) {
  const cfg = config;
  await loginWithPlaywright(page, cfg, SITE_NAME, log);
  await fillAndSubmit(page, cfg, SITE_NAME, content, log);
}
