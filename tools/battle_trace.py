"""Generate a local interactive movement replay from logs, without controlling the emulator."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parent.parent

def collect(log: Path, state: Path, trace: Path | None=None):
    events=[]
    turn=1
    text=log.read_text(encoding='utf-8',errors='replace')
    if trace is None:
        run=re.search(r'run=(current_\w+)',text)
        if run:
            candidate=ROOT/'logs'/f'{run[1]}_trajectory.jsonl'
            if candidate.exists():trace=candidate
    frames=[]
    if trace and trace.exists():
        for line in trace.read_text(encoding='utf-8').splitlines():
            try:frames.append(json.loads(line))
            except json.JSONDecodeError:continue
    for line in text.splitlines():
        m=re.search(r'\bTURN (\d+) game_turn=',line)
        if m:turn=int(m[1])
        m=re.search(r'ADVANCE U(\d+) (\w+) (\d+),(\d+)->(\d+),(\d+) ok=true',line)
        if m:
            slot,kind,ax,ay,bx,by=m.groups()
            events.append(dict(turn=turn,slot=int(slot),kind=kind,ax=int(ax),ay=int(ay),x=int(bx),y=int(by)))
    last=[]
    for line in state.read_text(encoding='utf-8',errors='replace').splitlines() if state.exists() else []:
        m=re.match(r'([UE])(\d+) id(\d+) (.*?) x(\d+) y(\d+) hp(\d+)/',line)
        if m:
            side,slot,uid,name,x,y,hp=m.groups()
            last.append(dict(side='MY' if side=='U' else 'EN',slot=int(slot),id=int(uid),name=name,x=int(x),y=int(y),hp=int(hp)))
    if frames and last:
        state_turn=re.search(r'^step=\d+ turn=(\d+)',state.read_text(encoding='utf-8',errors='replace')) if state.exists() else None
        if state_turn and int(state_turn[1])>=frames[-1]['turn']:
            frames.append(dict(turn=int(state_turn[1]),phase='last_state',units=last))
    return dict(events=events,frames=frames,last=last,max_turn=max([turn]+[f['turn'] for f in frames]),source=log.name)

PAGE='''<!doctype html><html lang="zh"><meta charset="utf-8"><title>战斗轨迹</title>
<style>body{font:16px system-ui;margin:20px;background:#101827;color:#e2e8f0}header{display:flex;gap:18px;align-items:center;flex-wrap:wrap}select,input{font-size:16px}svg{background:#172338;max-width:100%;height:76vh;border:1px solid #52627b}p{max-width:1000px}#info{white-space:pre-wrap}circle{cursor:pointer}</style>
<h2>战斗轨迹回放</h2><p>蓝色为我方，红色为敌方。轨迹线连接已记录的位置，并非逐格寻路路线。旧日志只有推进记录，可能缺少攻击前移动、敌方移动和阵亡位置；新版每轮保存双方位置和任务。视图不包含地形。</p>
<header><label>回合 <input id="turn" type="range" min="1" max="1" value="1"><b id="label"></b></label><label>部队 <select id="unit"><option value="all">全部</option></select></label><span id="source"></span></header>
<svg id="map" viewBox="0 0 930 830" role="img" aria-label="回合移动轨迹"></svg><p id="info">点击单位查看坐标和任务。虚线表示任务目标。</p>
<script>const D=__DATA__;const map=document.getElementById('map'),slider=document.getElementById('turn'),sel=document.getElementById('unit'),info=document.getElementById('info');
slider.max=D.max_turn;slider.value=D.max_turn;document.getElementById('source').textContent='来源：'+D.source;
const slots=[...new Set([...D.events.map(e=>e.slot),...D.frames.flatMap(f=>f.units.filter(u=>u.side==='MY').map(u=>u.slot)),...D.last.filter(u=>u.side==='MY').map(u=>u.slot)])].sort((a,b)=>a-b);
for(const k of slots){const o=document.createElement('option');o.value=k;o.textContent='U'+k;sel.appendChild(o)}
const xy=(x,y)=>[18*(x+0.5*(y%2))+20,16*y+20];
function node(tag,attrs){const e=document.createElementNS('http://www.w3.org/2000/svg',tag);for(const [k,v] of Object.entries(attrs))e.setAttribute(k,v);map.appendChild(e);return e}
function line(ax,ay,x,y,c,dash=false){const a=xy(ax,ay),b=xy(x,y);node('line',{x1:a[0],y1:a[1],x2:b[0],y2:b[1],stroke:c,'stroke-width':2,'stroke-dasharray':dash?'4 4':''})}
function draw(){map.replaceChildren();const t=+slider.value,k=sel.value;document.getElementById('label').textContent=t;
for(let y=1;y<=46;y+=5)for(let x=1;x<=46;x+=5){const p=xy(x,y);node('circle',{cx:p[0],cy:p[1],r:1,fill:'#64748b'});const a=node('text',{x:p[0]+3,y:p[1]-3,fill:'#94a3b8','font-size':9});a.textContent=x+','+y}
const paths=new Map();for(const e of D.events.filter(e=>e.turn<=t)){if(k!=='all'&&e.slot!==+k)continue;line(e.ax,e.ay,e.x,e.y,'hsl('+e.slot*43%360+' 70% 60%)');paths.set(e.slot,{side:'MY',slot:e.slot,x:e.x,y:e.y,order:e.kind})}
let units=[];const frames=D.frames.filter(f=>f.turn<=t);if(frames.length){units=frames.at(-1).units;const prev=new Map();for(const f of frames)for(const u of f.units){if(k!=='all'&&(u.side!=='MY'||u.slot!==+k))continue;const id=u.side+u.slot,p=prev.get(id);if(p)line(p.x,p.y,u.x,u.y,u.side==='EN'?'#f8717180':'#60a5fa80');prev.set(id,u)}}else{units=[...paths.values()];if(t===D.max_turn)units=D.last.length?D.last:units}
for(const u of units){if(k!=='all'&&u.side==='MY'&&u.slot!==+k)continue;const p=xy(u.x,u.y);const c=node('circle',{cx:p[0],cy:p[1],r:u.side==='EN'?5:6,fill:u.side==='EN'?'#fb7185':'#38bdf8',stroke:'white','stroke-width':1});const text=node('text',{x:p[0]+7,y:p[1]-5,fill:'#e2e8f0','font-size':11});text.textContent=(u.side==='EN'?'E':'U')+u.slot;c.onclick=()=>{info.textContent=JSON.stringify(u,null,2)};if(k!=='all'&&u.side==='MY'&&u.goal_x>=0)line(u.x,u.y,u.goal_x,u.goal_y,'#fde047',true)}
}slider.oninput=draw;sel.onchange=draw;draw();</script></html>'''

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--log',type=Path,default=ROOT/'logs/current_battle.txt')
    ap.add_argument('--state',type=Path,default=ROOT/'shots/current_battle/state.txt')
    ap.add_argument('--trace',type=Path)
    ap.add_argument('--output',type=Path,default=ROOT/'shots/current_battle/trajectory.html')
    args=ap.parse_args()
    data=collect(args.log,args.state,args.trace)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    payload=json.dumps(data,ensure_ascii=False).replace('<','\\u003c')
    args.output.write_text(PAGE.replace('__DATA__',payload),encoding='utf-8')
    print(f'Trajectory: {args.output} ({len(data["events"])} moves, {len(data["frames"])} snapshots)')

if __name__=='__main__':main()
