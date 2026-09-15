import { existsSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const source = resolve(root, 'assets/brand/app-icon.png');
const icons = new Map();

for (const [density, size] of [
  ['mdpi', 48], ['hdpi', 72], ['xhdpi', 96], ['xxhdpi', 144], ['xxxhdpi', 192],
]) {
  const path = resolve(root, `android/app/src/main/res/mipmap-${density}/ic_launcher.png`);
  if (existsSync(dirname(path))) icons.set(path, size);
}

for (const [destination, size] of icons) {
  execFileSync('ffmpeg', [
    '-hide_banner', '-loglevel', 'error', '-y', '-i', source,
    '-vf', `scale=${size}:${size}:flags=lanczos`, '-frames:v', '1', destination,
  ], { stdio: 'inherit' });
}

console.log(`Updated ${icons.size} launcher images from assets/brand/app-icon.png.`);
