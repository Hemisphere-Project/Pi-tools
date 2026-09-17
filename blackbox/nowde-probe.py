#!/usr/bin/env python3
"""nowde-probe.py — one line about the Nowde node on this player's USB, asked from the NODE itself,
not from HPlayer2's memory (HPlayer2 can believe it is linked while the node is silent).

Sends QUERY_RUNNING_STATE (0x03) — the very query HPlayer2 sends every 1 s (master) / 2 s (slave),
so it changes nothing on the node and HPlayer2 handles the reply as one more of its own polls:
  master node -> RUNNING_STATE chunks: the receiver table (who is heard, each slave's lock, age)
  slave node  -> HELLO: its own lock quality (0 none / 1 coarse / 2 locked), uptime, LR
  nothing in 3 s -> node=dead   (USB/MIDI link gone or node hung — what a freewheel looks like)
Runs with HPlayer2's venv (has mido):  /opt/HPlayer2/.venv/bin/python nowde-probe.py
Output, one line of key=value:
  node=master slaves=5 locked=5 coarse=0 age=1200ms rx=99E008:2,996CD4:2,99B52C:2,98A91C:2,00099C:2
  node=slave sq=2 up=812m boot=POWERON lr=0 v=2.0.3
  node=dead | node=noport | node=nomido
Wire format copied from HPlayer2 core/interfaces/nowde.py (2.0.x), kept here so the probe does not
import HPlayer2 and keeps working across its versions."""
import sys, time
try:
    import mido
except ImportError:
    print("node=nomido"); sys.exit(0)

RESET = {1: 'POWERON', 3: 'SW', 4: 'PANIC', 5: 'INT_WDT', 6: 'TASK_WDT', 7: 'WDT', 8: 'DEEPSLEEP',
         9: 'BROWNOUT', 10: 'SDIO', 11: 'USB', 12: 'JTAG', 13: 'EFUSE', 14: 'PWR_GLITCH', 15: 'CPU_LOCKUP'}
ROLE = {0: 'slave', 1: 'master', 2: 'legacy'}


def decode7(d):
    """7-bit -> 8-bit: every run of 8 bytes (MSB byte first) gives back up to 7 raw bytes."""
    out = []
    i = 0
    while i < len(d):
        msb = d[i]
        chunk = d[i + 1:i + 8]
        for j, b in enumerate(chunk):
            out.append(b | (0x80 if msb & (1 << j) else 0))
        i += 8
    return out


def parse_hello(d):
    if len(d) < 16:
        return None
    version = bytes(decode7(d[0:10])[:8]).decode('ascii', errors='ignore').rstrip('\x00')
    up = decode7(d[10:15])
    info = {'version': version, 'uptime': (up[0] << 24) | (up[1] << 16) | (up[2] << 8) | up[3],
            'boot': RESET.get(d[15], 'UNKNOWN_%d' % d[15])}
    if len(d) >= 18:
        info['role'] = ROLE.get(d[16], 'unknown')
    if len(d) >= 19:
        info['sq'] = d[18]
    if len(d) >= 20:
        info['lr'] = int(bool(d[19]))
    return info


def parse_running_state(d):
    if len(d) < 10:
        return None, []
    up = decode7(d[0:5])
    meta = {'uptime': (up[0] << 24) | (up[1] << 16) | (up[2] << 8) | up[3],
            'synced': int(bool(d[5])), 'total': d[6], 'chunk': d[7], 'chunks': d[8]}
    n = d[9]
    rx = []
    idx = 10
    for _ in range(n):
        if idx + 43 > len(d):
            break
        r = decode7(d[idx:idx + 43])
        idx += 43
        if len(r) < 36:
            break
        rx.append({'mac': ''.join('%02X' % b for b in r[0:6]),
                   'last_seen': (r[30] << 24) | (r[31] << 16) | (r[32] << 8) | r[33],
                   'sq': r[36] if len(r) >= 37 else 255})
    return meta, rx


def main():
    ins = [x for x in mido.get_input_names() if 'Nowde' in x]
    outs = [x for x in mido.get_output_names() if 'Nowde' in x]
    if not ins or not outs:
        print("node=noport"); return
    hello, meta, rx, done = None, None, {}, False
    with mido.open_input(ins[0]) as inp, mido.open_output(outs[0]) as out:
        out.send(mido.Message('sysex', data=[0x7D, 0x03]))
        t0 = time.time()
        while time.time() - t0 < 3.0 and not done:
            for m in inp.iter_pending():
                if m.type != 'sysex':          # a slave's node also emits CC/clock messages: no .data
                    continue
                d = list(m.data)
                if len(d) < 2 or d[0] != 0x7D:
                    continue
                if d[1] == 0x20:
                    hello = parse_hello(d[2:])
                    if hello and hello.get('role') != 'master':
                        done = True          # a slave answers with its HELLO only
                elif d[1] == 0x22:
                    meta, part = parse_running_state(d[2:])
                    for r in part:
                        rx[r['mac']] = r
                    if meta and meta['chunk'] >= meta['chunks'] - 1:
                        done = True
            time.sleep(0.03)
    if meta is not None:
        locked = sum(1 for r in rx.values() if r['sq'] == 2)
        coarse = sum(1 for r in rx.values() if r['sq'] == 1)
        age = max([r['last_seen'] for r in rx.values()] or [0])
        tab = ','.join('%s:%s' % (mac[-6:], r['sq']) for mac, r in sorted(rx.items()))
        print("node=master slaves=%d locked=%d coarse=%d age=%dms rx=%s" % (len(rx), locked, coarse, age, tab or '-'))
    elif hello is not None:
        print("node=%s sq=%s up=%dm boot=%s lr=%s v=%s" % (hello.get('role', '?'), hello.get('sq', '?'),
              hello['uptime'] // 60000, hello['boot'], hello.get('lr', '?'), hello['version']))
    else:
        print("node=dead")


if __name__ == '__main__':
    main()
