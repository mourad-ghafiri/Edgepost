// Monotonic ULID (https://github.com/ulid/spec): 48-bit ms timestamp + 80 bits of randomness,
// Crockford base32. Monotonic within an isolate, which matters because Date.now() does not
// advance during a Workers request until I/O happens.

const ENCODING = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
const RANDOM_BYTES = 10;

let lastTime = -1;
let lastRandom: Uint8Array = new Uint8Array(RANDOM_BYTES);

function encodeTime(time: number): string {
  let out = "";
  let t = time;
  for (let i = 0; i < 10; i++) {
    const mod = t % 32;
    out = ENCODING.charAt(mod) + out;
    t = (t - mod) / 32;
  }
  return out;
}

function encodeRandom(bytes: Uint8Array): string {
  let n = 0n;
  for (const b of bytes) n = (n << 8n) | BigInt(b);
  let out = "";
  for (let i = 0; i < 16; i++) {
    out = ENCODING.charAt(Number(n & 31n)) + out;
    n >>= 5n;
  }
  return out;
}

/** Adds one to an 80-bit big-endian number. Returns null on overflow. */
function increment(bytes: Uint8Array): Uint8Array | null {
  const next = bytes.slice();
  for (let i = next.length - 1; i >= 0; i--) {
    const v = next[i]!;
    if (v < 255) {
      next[i] = v + 1;
      return next;
    }
    next[i] = 0;
  }
  return null;
}

export function ulid(now: number = Date.now()): string {
  let time = Math.max(0, Math.floor(now));
  let random: Uint8Array | null = null;
  if (time <= lastTime) {
    time = lastTime;
    random = increment(lastRandom);
    if (random === null) {
      // Overflowed 80 bits within one millisecond: borrow the next millisecond.
      time = lastTime + 1;
    }
  }
  if (random === null) random = crypto.getRandomValues(new Uint8Array(RANDOM_BYTES));
  lastTime = time;
  lastRandom = random;
  return encodeTime(time) + encodeRandom(random);
}
