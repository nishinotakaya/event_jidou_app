/** Peatix 専用 */

import { loginWithPlaywright, fillAndSubmit } from './utils.js';

export const SITE_NAME = 'Peatix';

export const config = {
  loginUrl:  process.env.PEATIX_LOGIN_URL  || 'https://peatix.com/signin',
  mypage:    process.env.PEATIX_URL        || 'https://peatix.com/',
  createUrl: process.env.PEATIX_CREATE_URL || 'https://peatix.com/group/16510066/event/create',
  email:     process.env.PEATIX_EMAIL,
  password:  process.env.PEATIX_PASSWORD,
  emailSel:  'input[name="email"]',
  passSel:   'input[name="password"]',
};

export async function post(page, content, _eventFields, log) {
  const cfg = config;
  await loginWithPlaywright(page, cfg, SITE_NAME, log);
  await fillAndSubmit(page, cfg, SITE_NAME, content, log);
}
