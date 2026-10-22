"""Same-host API history benchmark, retaining fixtures only on the runner."""
import importlib.util,json,os,pathlib,shutil,statistics,subprocess,sys,time
base=pathlib.Path(sys.argv[1]).resolve();candidate=pathlib.Path(sys.argv[2]).resolve();root=pathlib.Path(sys.argv[3]).resolve();root.mkdir(parents=True,exist_ok=True)
sys.argv=[sys.argv[0],str(base),str(root)]
import windows_idle as probe

def process_cpu(pid):
 return float(subprocess.check_output(['powershell.exe','-NoProfile','-Command',f'(Get-Process -Id {pid}).CPU.ToString([Globalization.CultureInfo]::InvariantCulture)'],text=True).strip())

def calls(peer,sid):
 elapsed=[];before=process_cpu(peer.child.pid);started=time.monotonic()
 for _ in range(30):
  start=time.monotonic();peer.ask('read',session=sid);elapsed.append(time.monotonic()-start)
 return {'calls':30,'wall_seconds':time.monotonic()-started,'process_cpu_seconds':process_cpu(peer.child.pid)-before,'median_call_seconds':statistics.median(elapsed),'p95_call_seconds':sorted(elapsed)[28]}

data=root/'owner';other=None;owner=probe.Peer(data)
try:
 sessions=[probe.pair(owner,i) for i in range(8)];sid=sessions[-1]
 owner.ask('seed',channel='historyprof-'+__import__('uuid').uuid4().hex[:16])
 for i in range(200):owner.ask('send',session=sid,body=f'Fictional history sample {i}')
 assert owner.ask('read',session=sid)=={'dm':8,'groups':2,'channels':1}
 expected=owner.ask('poll',session=sid)['messages'];assert len(expected)>=200
finally:owner.stop()
backup=root/'fixture-backup';shutil.copytree(data,backup)
results={'baseline':[],'candidate':[]}
for round in range(3):
 for variant,app in ([('baseline',base),('candidate',candidate)] if round%2==0 else [('candidate',candidate),('baseline',base)]):
  shutil.rmtree(data);shutil.copytree(backup,data);probe.APP=app
  peer=probe.Peer(data)
  try:
   peer.ask('read',session=sid)
   assert peer.ask('poll',session=sid)['messages']==expected,'History content/status changed'
   result=calls(peer,sid);results[variant].append(result)
   (root/'history-comparison.json').write_text(json.dumps(results,indent=2))
   print(variant,round,json.dumps(result),flush=True)
  finally:peer.stop()
print('COMPLETE same-host history comparison',flush=True)
