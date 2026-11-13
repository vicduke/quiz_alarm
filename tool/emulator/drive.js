// Drives the mini emulator from the command line (needs Node + Playwright).
// The app keeps its data between runs in tool/emulator/.profile.
//
//   node tool/emulator/drive.js [--url URL] [--fresh] step step ...
//
// Steps:
//   tap:Text        tap the button / tab / item whose label contains Text
//   tapxy:200,300   tap a point (phone is 412 x 892)
//   type:Text       type into the focused field
//   key:Enter       press a key
//   scroll:600      scroll down by that many pixels (negative = up)
//   wait:1500       wait in milliseconds
//   shot:name.png   save a screenshot
//   reload          restart the app (like killing and reopening it)
//   text            print the labels currently on screen
//   solve           answer the question on screen correctly (built-in bank only)
//   fail            answer the question on screen wrongly
//
// Example:
//   node tool/emulator/drive.js "tap:Question Banks" wait:500 shot:bank.png
const path = require('path');
const fs = require('fs');
const { chromium } = require('playwright');

(async () => {
  const args = process.argv.slice(2);
  let url = 'http://localhost:8090/';
  const profile = path.join(__dirname, '.profile');
  const steps = [];
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--url') url = args[++i];
    else if (args[i] === '--fresh') fs.rmSync(profile, { recursive: true, force: true });
    else steps.push(args[i]);
  }

  const ctx = await chromium.launchPersistentContext(profile, {
    viewport: { width: 412, height: 892 },
    deviceScaleFactor: 2,
    args: ['--autoplay-policy=no-user-gesture-required'],
  });
  const page = ctx.pages()[0] || (await ctx.newPage());
  if (process.env.EMU_LOG) page.on('console', (m) => console.log('LOG:', m.text().slice(0, 300)));
  page.on('pageerror', (e) => console.log('PAGE ERROR:', String(e).slice(0, 400)));

  // Flutter draws on a canvas; switching accessibility on gives us a DOM
  // tree with every label, so elements can be found by their text.
  const open = async () => {
    await page.goto(url);
    await page.waitForSelector('flt-semantics-placeholder', { state: 'attached', timeout: 60000 });
    await page.evaluate(() => document.querySelector('flt-semantics-placeholder').click());
    await page.waitForTimeout(1200);
  };
  const labels = () =>
    page.evaluate(() =>
      [...document.querySelectorAll('flt-semantics')]
        .map((e) => (e.getAttribute('aria-label') || (e.children.length ? '' : e.textContent) || '').trim())
        .filter(Boolean));

  // Answers of the bundled question banks, for the solve / fail steps.
  const bank = [];
  const bankDir = path.join(__dirname, '..', '..', 'assets', 'question_banks');
  for (const f of fs.readdirSync(bankDir).filter((f) => f.endsWith('.json'))) {
    for (const t of JSON.parse(fs.readFileSync(path.join(bankDir, f), 'utf8')).topics) {
      bank.push(...t.questions);
    }
  }
  const currentQuestion = async () => {
    const all = await page.evaluate(() =>
      [...document.querySelectorAll('flt-semantics')]
        .map((e) => (e.getAttribute('aria-label') || '') + ' ' + e.textContent).join(' '));
    return bank.find((q) => all.includes(q.text));
  };
  const tapLabel = async (text) => {
    const box = await page.evaluate((want) => {
      const hit = [...document.querySelectorAll('flt-semantics')].find((e) =>
        e.children.length === 0 &&
        (e.getAttribute('aria-label') || e.textContent || '').trim() === want &&
        e.getBoundingClientRect().width > 2);
      if (!hit) return null;
      const r = hit.getBoundingClientRect();
      return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
    }, text);
    if (box) await page.mouse.click(box.x, box.y);
    return !!box;
  };

  await open();
  for (const step of steps) {
    const [cmd, ...rest] = step.split(':');
    const arg = rest.join(':');
    if (cmd === 'tap') {
      const box = await page.evaluate((text) => {
        const want = text.toLowerCase();
        const all = [...document.querySelectorAll('flt-semantics')];
        const label = (e) => (e.getAttribute('aria-label') || e.textContent || '').trim().toLowerCase();
        // Prefer an exact label, then the smallest element on screen
        // (wrappers repeat the text of the buttons inside them).
        const area = (e) => { const r = e.getBoundingClientRect(); return r.width * r.height; };
        const visible = (e) => { const r = e.getBoundingClientRect(); return r.width > 2 && r.height > 2; };
        const hits = all.filter((e) => visible(e) && label(e).includes(want));
        hits.sort((a, b) =>
          (label(a) === want ? 0 : 1) - (label(b) === want ? 0 : 1) ||
          area(a) - area(b));
        if (!hits.length) return null;
        const r = hits[0].getBoundingClientRect();
        return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
      }, arg);
      if (!box) {
        console.log(`tap: nothing on screen contains "${arg}". On screen:`, await labels());
        process.exitCode = 1;
        break;
      }
      await page.mouse.click(box.x, box.y);
      await page.waitForTimeout(700);
    } else if (cmd === 'tapxy') {
      const [x, y] = arg.split(',').map(Number);
      await page.mouse.click(x, y);
      await page.waitForTimeout(700);
    } else if (cmd === 'type') {
      await page.keyboard.type(arg, { delay: 15 });
    } else if (cmd === 'key') {
      await page.keyboard.press(arg);
      await page.waitForTimeout(500);
    } else if (cmd === 'scroll') {
      await page.mouse.move(206, 450);
      await page.mouse.wheel(0, Number(arg));
      await page.waitForTimeout(600);
    } else if (cmd === 'wait') {
      await page.waitForTimeout(Number(arg));
    } else if (cmd === 'shot') {
      await page.screenshot({ path: arg });
      console.log('saved', arg);
    } else if (cmd === 'solve' || cmd === 'fail') {
      const q = await currentQuestion();
      if (!q) {
        console.log(`${cmd}: no built-in question found on screen`);
        process.exitCode = 1;
        break;
      }
      const right = cmd === 'solve';
      if (q.type === 'mcq') {
        await tapLabel(right ? q.answer : q.options.find((o) => o !== q.answer));
      } else {
        // Put the cursor in the answer field first (it is not always focused).
        const field = await page.evaluate(() => {
          const e = document.querySelector('flt-semantics input, flt-semantics textarea, flt-semantics[role="textbox"], input.flt-text-editing, textarea.flt-text-editing');
          if (!e) return null;
          const r = e.getBoundingClientRect();
          return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
        });
        if (field) {
          await page.mouse.click(field.x, field.y);
          await page.waitForTimeout(300);
        }
        await page.keyboard.type(right ? q.answer : 'wrong answer', { delay: 15 });
        await page.keyboard.press('Enter');
      }
      console.log(`${cmd}: ${q.text} -> ${right ? q.answer : '(wrong)'}`);
      await page.waitForTimeout(1500);
    } else if (cmd === 'reload') {
      await open();
    } else if (cmd === 'text') {
      console.log(await labels());
    } else {
      console.log('unknown step:', step);
    }
  }
  await ctx.close();
})();
