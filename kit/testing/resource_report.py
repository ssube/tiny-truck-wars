#!/usr/bin/env python3
"""Linux process telemetry, independent of the Godot render loop; stdlib only."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

INTERVAL = 0.05


def parse_stat(text, ticks=None, page_size=None):
    # comm can contain spaces and ')'; fields after it start at stat field 3.
    fields = text[text.rfind(')') + 2:].split()
    ticks = ticks or os.sysconf('SC_CLK_TCK')
    page_size = page_size or os.sysconf('SC_PAGE_SIZE')
    return {'cpu_seconds': (int(fields[11]) + int(fields[12])) / ticks,
            'rss_bytes': int(fields[21]) * page_size, 'start_ticks': int(fields[19])}


def parse_fdinfo(text):
    values = {}
    for line in text.splitlines():
        if ':' in line:
            key, value = line.split(':', 1)
            values[key] = value.strip()
    if 'drm-client-id' not in values:
        return None
    engines, memory = {}, {}
    for key, value in values.items():
        parts = value.split()
        if key.startswith('drm-engine-') and len(parts) == 2 and parts[1] == 'ns':
            engines[key.removeprefix('drm-engine-')] = int(parts[0]) / 1e9
        if key.startswith('drm-memory-') and len(parts) == 2 and parts[1] in ('KiB', 'kB', 'bytes'):
            memory[key.removeprefix('drm-memory-')] = int(parts[0]) * (1 if parts[1] == 'bytes' else 1024)
    return {'client': values['drm-client-id'], 'device': values.get('drm-pdev', 'unknown'),
            'engine_seconds': engines or None, 'memory_bytes': memory or None}


def sample_process(pid, proc=Path('/proc'), sysfs=Path('/sys/class/drm')):
    result = {'pid': pid, 'cpu_seconds': None, 'rss_bytes': None, 'gpu_clients': None,
              'device_wide_not_attributable': [], 'missing': []}
    try:
        result.update(parse_stat((proc / str(pid) / 'stat').read_text()))
    except (OSError, ValueError, IndexError) as exc:
        result['missing'].append('process stat: ' + str(exc))
    clients = {}
    try:
        paths = list((proc / str(pid) / 'fdinfo').iterdir())
        for path in paths:
            try:
                client = parse_fdinfo(path.read_text())
                if client:
                    clients[(client['device'], client['client'])] = client
            except (OSError, ValueError) as exc:
                result['missing'].append('fdinfo: ' + str(exc))
    except OSError as exc:
        result['missing'].append('fdinfo directory: ' + str(exc))
    result['gpu_clients'] = list(clients.values()) or None
    if not clients:
        result['missing'].append('No readable DRM client counters (headless/software/unsupported/permission)')
    devices = (path for path in sysfs.glob('card[0-9]*/device') if path.parent.name[4:].isdigit())
    for device in sorted(devices):
        readings = {'device': str(device.resolve()), 'scope': 'device-wide NOT attributable to tests'}
        for sensor in ('gpu_busy_percent', 'mem_info_vram_used', 'mem_info_gtt_used'):
            try:
                readings[sensor] = int((device / sensor).read_text())
            except (OSError, ValueError):
                readings[sensor] = None
        result['device_wide_not_attributable'].append(readings)
    return result


def metrics(samples, start, end):
    rows = [r for r in samples if start <= r['unix_seconds'] <= end]
    rss = [r['rss_bytes'] for r in rows if r.get('rss_bytes') is not None]
    valid = [r for r in rows if r.get('cpu_seconds') is not None]
    result = {'sample_count': len(rows), 'rss_last_bytes': rss[-1] if rss else None,
              'rss_sampled_peak_bytes': max(rss) if rss else None,
              'cpu_seconds': None, 'cpu_core_percent': None, 'cpu_coverage_seconds': None,
              'gpu_engine_seconds': None, 'gpu_coverage_seconds': None, 'gpu_memory_sampled_peak_bytes': None}
    if len(valid) >= 2 and valid[-1].get('start_ticks') == valid[0].get('start_ticks'):
        elapsed = valid[-1]['monotonic_seconds'] - valid[0]['monotonic_seconds']
        cpu = valid[-1]['cpu_seconds'] - valid[0]['cpu_seconds']
        if elapsed > 0 and cpu >= 0:
            result.update(cpu_seconds=cpu, cpu_core_percent=100 * cpu / elapsed, cpu_coverage_seconds=elapsed)
    gpu_memory = {}
    for row in rows:
        totals = {}
        for client in row.get('gpu_clients') or []:
            for region, value in (client['memory_bytes'] or {}).items():
                key = client['device'] + '/' + region
                totals[key] = totals.get(key, 0) + value
        for key, value in totals.items():
            gpu_memory[key] = max(gpu_memory.get(key, 0), value)
    result['gpu_memory_sampled_peak_bytes'] = gpu_memory or None
    # Match persistent clients; do not mistake closed/new DRM clients for zero use.
    if len(rows) >= 2:
        first = {(c['device'], c['client']): c for c in rows[0].get('gpu_clients') or []}
        last = {(c['device'], c['client']): c for c in rows[-1].get('gpu_clients') or []}
        deltas = {}
        if first and first.keys() == last.keys():
            for key, before in first.items():
                for engine, value in (before['engine_seconds'] or {}).items():
                    after = (last[key]['engine_seconds'] or {}).get(engine)
                    if after is not None and after >= value:
                        name = key[0] + '/' + engine
                        deltas[name] = deltas.get(name, 0) + after - value
            result['gpu_engine_seconds'] = deltas or None
            if deltas:
                result['gpu_coverage_seconds'] = rows[-1]['monotonic_seconds'] - rows[0]['monotonic_seconds']
    return result


def read_jsonl(path):
    rows = []
    if path.exists():
        for line in path.read_text(errors='replace').splitlines():
            try:
                rows.append(json.loads(line))
            except ValueError:
                pass  # Interrupted final write is retained verbatim in raw evidence.
    return rows


def build_report(events, samples, start, end, exit_code, errors):
    suites, phases, active_phases = [], [], {}
    current = None
    for event in events:
        kind = event['kind']
        if kind == 'phase_start':
            key = (event['source'], event['phase'], event.get('guid'))
            active_phases[key] = event
        elif kind == 'phase_end':
            key = (event['source'], event['phase'], event.get('guid'))
            before = active_phases.pop(key, None)
            if before:
                phases.append(dict(before, seconds=(event['ticks_us'] - before['ticks_us']) / 1e6,
                                   end_ticks_us=event['ticks_us'], end_unix_seconds=event['unix_seconds'], complete=True))
        elif kind == 'gdunit' and event['type'] == 2:
            current = {'source': event['resource_path'], 'suite': event['suite_name'], 'start': event,
                       'end': None, 'executed_cases': []}
            suites.append(current)
        elif kind == 'gdunit' and event['type'] in (4, 5) and current:
            current['executed_cases'].append(event)
        elif kind == 'gdunit' and event['type'] == 3 and current:
            current['end'] = event
            current = None
    phases.extend(dict(p, seconds=None, complete=False) for p in active_phases.values())
    # A crash inside suite setup can precede TESTSUITE_BEFORE.
    for phase in phases:
        if not any(s['source'] == phase['source'] for s in suites):
            suites.append({'source': phase['source'], 'suite': None, 'start': phase,
                           'end': None, 'executed_cases': []})
    discovered = {e['guid']: e for e in events if e['kind'] == 'discovered'}
    for suite in suites:
        for case in suite['executed_cases']:
            case['case_identity'] = discovered.get(case.get('guid'))
        relevant = [p for p in phases if p['source'] == suite['source']]
        first = min([suite['start']] + relevant, key=lambda p: p['ticks_us'])
        last = suite['end']
        complete = last is not None and all(p['complete'] for p in relevant)
        finish = max([last['unix_seconds']] + [p.get('end_unix_seconds', end) for p in relevant]) if complete else end
        finish_ticks = max([last['ticks_us']] + [p['end_ticks_us'] for p in relevant]) if complete else None
        suite.update(complete=complete, statistics=last.get('statistics') if last else None,
                     wall_seconds=(finish_ticks - first['ticks_us']) / 1e6 if complete else None,
                     observed_seconds=finish - first['unix_seconds'], phases=relevant,
                     resources=metrics(samples, first['unix_seconds'], finish))
        statistics = suite['statistics'] or {}
        suite['result'] = ('incomplete' if not complete else 'failed' if statistics.get('failed') or statistics.get('errors')
                           else 'skipped' if statistics.get('skipped') else 'passed')
        suite['phase_timing_available'] = bool(relevant) or bool((suite['statistics'] or {}).get('skipped'))
        suite['phase_seconds'] = {}
        for name in ('suite_setup', 'suite_teardown', 'case_setup', 'test_body', 'case_teardown'):
            matching = [p for p in relevant if p['phase'] == name]
            suite['phase_seconds'][name] = (sum(p['seconds'] for p in matching)
                                            if suite['phase_timing_available'] and all(p['complete'] for p in matching) else None)
        suite['framework_other_seconds'] = (max(0, suite['wall_seconds'] - sum(suite['phase_seconds'].values()))
                                            if suite['wall_seconds'] is not None and suite['phase_timing_available'] else None)
    boundaries = [p['unix_seconds'] for p in phases] + [s['start']['unix_seconds'] for s in suites]
    identity = next((e for e in events if e['kind'] == 'identity'), None)
    session_closed = any(e['kind'] == 'gdunit' and e['type'] == 9 for e in events)
    session_closed = session_closed and all(s['complete'] for s in suites)
    return {'schema': 1, 'identity': identity, 'engine_exit': exit_code,
            'status': 'complete' if session_closed else 'incomplete', 'sampler_errors': errors,
            'started_unix_seconds': start, 'finished_unix_seconds': end,
            'invocation_observed_seconds': end - start,
            'startup_discovery_seconds': min(boundaries) - start if boundaries else None,
            'outside_suite_seconds': max(0, end - start - sum(s['observed_seconds'] for s in suites)),
            'selection': [e for e in events if e['kind'] in ('discovered', 'selection_error')],
            'suites': suites, 'process_resources': metrics(samples, start, end),
            'measurement': {'interval_seconds': INTERVAL, 'scope': 'Godot PID only, all threads; no children/Xvfb/launcher',
                            'cpu': 'Actual /proc stat user+system deltas between interior samples; core-percent may exceed 100. Coverage excludes boundary gaps; <2 samples => null.',
                            'memory': 'RSS sampled peak, not true high-water; GPU regions may overlap, never sum regions.',
                            'gpu': 'Per-client fdinfo deduplicated by device/client ID; unavailable => null. sysfs is device-wide NOT attributable.',
                            'clock': 'Phase durations use engine monotonic ticks. Sample attribution uses UNIX timestamps; wall-clock adjustments can affect attribution.',
                            'overhead': 'Sampling external; event writes synchronous. No overhead subtraction or speedup claim. Launcher CPU separately measured; uninstrumented baseline not measured.'}}


def write_report(run, report):
    (run / 'resources.json').write_text(json.dumps(report, indent=2) + '\n')
    lines = [f"Resource report: {run.name}", f"Status: {report['status']}; engine exit: {report['engine_exit']}; runner verdict: {report.get('runner_exit', 'pending')}",
             f"Device/renderer: {report['identity']}",
             f"Invocation observed: {report['invocation_observed_seconds']}s; startup/discovery: {report['startup_discovery_seconds']}s; outside suites: {report['outside_suite_seconds']}s",
             f"Launcher CPU (before report finalization): {report.get('launcher_cpu_seconds')}s",
             'Process resources: ' + json.dumps(report['process_resources']),
             'CPU = process core-percent; memory = sampled RSS; null = unavailable/too few samples.',
             'GPU sysfs readings are device-wide NOT attributable. See raw timeline and JSON measurement caveats.']
    for suite in report['suites']:
        lines += [f"\n{suite['source']} complete={suite['complete']} wall={suite['wall_seconds']}s",
                  '  phases: ' + json.dumps(suite['phase_seconds']),
                  '  resources: ' + json.dumps(suite['resources']),
                  '  result: ' + json.dumps(suite['statistics'])]
    lines += ['\nSampler errors: ' + json.dumps(report['sampler_errors'])]
    (run / 'resources.txt').write_text('\n'.join(lines) + '\n')


def launch(run, command):
    start, cpu_start, monotonic_start = time.time(), time.process_time(), time.monotonic()
    errors = []
    interrupted = None
    child = None
    def stop(signum, _frame):
        nonlocal interrupted
        interrupted = signum
        if child and child.poll() is None:
            try:
                os.killpg(child.pid, signum)
            except ProcessLookupError:
                pass
    previous = {sig: signal.signal(sig, stop) for sig in (signal.SIGINT, signal.SIGTERM)}
    (run / 'launcher.pid').write_text(str(os.getpid()))
    events_path = run / 'events.jsonl'
    env = dict(os.environ, KIT_TEST_EVENTS=str(events_path))
    code = 127
    pid = None
    sampler_failed = False
    termination_time = None
    try:
        child = subprocess.Popen(command, env=env, start_new_session=True)
        if (run / 'signal.request').exists():
            stop(getattr(signal, 'SIG' + (run / 'signal.request').read_text().strip()), None)
        with (run / 'samples.jsonl').open('w') as timeline:
            while child.poll() is None:
                if interrupted:
                    termination_time = termination_time or time.monotonic()
                    if time.monotonic() - termination_time > 2:
                        try:
                            os.killpg(child.pid, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                if pid is None:
                    identity = next((e for e in read_jsonl(events_path) if e['kind'] == 'identity'), None)
                    if identity:
                        pid = identity['pid']
                if pid is not None and not sampler_failed:
                    try:
                        row = sample_process(pid)
                        row.update(kind='sample', unix_seconds=time.time(), monotonic_seconds=time.monotonic())
                        timeline.write(json.dumps(row) + '\n')
                        timeline.flush()
                    except Exception as exc:
                        errors.append(repr(exc))
                        sampler_failed = True
                time.sleep(INTERVAL)
        code = child.wait()
        if code < 0:
            code = 128 - code
        if interrupted:
            code = 128 + interrupted
    except Exception as exc:
        errors.append(repr(exc))
        print('Resource launcher failure: ' + str(exc), file=sys.stderr)
    finally:
        if child:
            # Only our new session/process group, never the caller's lock or other engines.
            try:
                os.killpg(child.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            child.wait()
        (run / 'launcher.pid').unlink(missing_ok=True)
        for sig, handler in previous.items():
            signal.signal(sig, handler)
        end, monotonic_end = time.time(), time.monotonic()
        events = read_jsonl(events_path)
        samples = read_jsonl(run / 'samples.jsonl')
        report = build_report(events, samples, start, end, code, errors)
        report.update(run_directory=str(run), command=command, source_revision=os.environ.get('KIT_TEST_REVISION'),
                      invocation_monotonic_seconds=monotonic_end - monotonic_start,
                      source_dirty=os.environ.get('KIT_TEST_SOURCE_DIRTY') == '1',
                      requested_display=os.environ.get('KIT_TEST_DISPLAY'),
                      requested_wayland_display=os.environ.get('KIT_TEST_WAYLAND_DISPLAY'), display_mode=os.environ.get('KIT_TEST_DISPLAY_MODE'),
                      interrupted_signal=interrupted, launcher_cpu_seconds=time.process_time() - cpu_start)
        write_report(run, report)
        with (run / 'timeline.jsonl').open('w') as timeline:
            for row in sorted(events + samples, key=lambda row: row['unix_seconds']):
                timeline.write(json.dumps(row) + '\n')
    return code


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--finalize', type=int)
    parser.add_argument('run', type=Path)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.finalize is not None:
        path = args.run / 'resources.json'
        if path.exists():
            report = json.loads(path.read_text())
            report['runner_exit'] = args.finalize
            write_report(args.run, report)
        return 0
    return launch(args.run, args.command)


if __name__ == '__main__':
    sys.exit(main())
