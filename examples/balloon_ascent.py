# Demo for the run page and the live-updating runs list: a simulated balloon
# ascent that prints one telemetry line per second, then a numpy summary and a
# line on stderr. Output appears when the run finishes; the clock ticks meanwhile.
import sys
import time
import numpy as np

DURATION = 25  # seconds; set to 150 to watch the two-minute limit kill it
rng = np.random.default_rng(42)

print("pyrun live demo: simulated balloon ascent")
print(f"started {time.strftime('%H:%M:%S')} UTC, running {DURATION}s")
print(f"{'t(s)':>5} {'alt(m)':>9} {'temp(C)':>8} {'press(hPa)':>11} {'v(m/s)':>7}")

alt = 0.0
log = []
t0 = time.time()
for t in range(1, DURATION + 1):
    v = 5.0 + rng.normal(0, 0.4)  # climb rate with jitter
    alt += v
    temp = 15.0 - 0.0065 * alt + rng.normal(0, 0.3)
    press = 1013.25 * (1 - 2.25577e-5 * alt) ** 5.25588
    log.append((t, alt, temp, press, v))
    print(f"{t:>5} {alt:>9.1f} {temp:>8.2f} {press:>11.2f} {v:>7.2f}", flush=True)
    time.sleep(max(0.0, t0 + t - time.time()))  # one line per real second

a = np.array(log)
climb = a[:, 4]
print()
print(f"samples: {len(a)}  final altitude: {a[-1, 1]:.0f} m")
print(f"mean climb rate: {climb.mean():.2f} m/s  (std {climb.std():.2f})")
print(f"temperature range: {a[:, 2].min():.1f} to {a[:, 2].max():.1f} C")
print(f"pressure at top: {a[-1, 3]:.1f} hPa")
print("stderr demo: burst altitude not reached", file=sys.stderr)
