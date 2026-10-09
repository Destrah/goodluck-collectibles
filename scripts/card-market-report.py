"""Run the actual Lua pull distributions, grading and buyer valuation against a catalog snapshot."""
from pathlib import Path
import argparse
import json
import math
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'.tmp-mysql-tests'))
from lupa.lua54 import LuaRuntime

def to_lua(lua,value):
    if isinstance(value,dict): return lua.table_from({k:to_lua(lua,v) for k,v in value.items()})
    if isinstance(value,list): return lua.table_from([to_lua(lua,v) for v in value])
    return value

def from_lua(value):
    if hasattr(value,'items'):
        entries=dict(value.items())
        if entries and set(entries)==set(range(1,len(entries)+1)):
            return [from_lua(entries[i]) for i in range(1,len(entries)+1)]
        return {str(k):from_lua(v) for k,v in entries.items()}
    return value

def runtime(catalog=None,sets=None):
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.execute('''
        function vec3(x,y,z) return {x=x,y=y,z=z} end;vector3=vec3
        function vec4(x,y,z,w) return {x=x,y=y,z=z,w=w} end;vector4=vec4
        function GetConvar(_,fallback) return fallback end
        function GetConvarInt(_,fallback) return fallback end
        function GetCurrentResourceName() return 'rush-tradingcards' end
        function RegisterNetEvent() end;function RegisterCommand() end;function CreateThread() end
        function AddEventHandler() end;function Wait() end;function GetGameTimer() return 1000 end
        function GetPlayerIdentifiers() return {} end
        MetaComic={RpcHandlers={},Framework={getJob=function() return job end},CanManage=function() return admin==true end,
            CardBuyerStock={version=0,population=function() return 0 end}}
        admin=true
    ''')
    lua.execute((ROOT/'fivem/config.lua').read_text(encoding='utf-8-sig'))
    lua.execute((ROOT/'fivem/shared/utils.lua').read_text(encoding='utf-8'))
    lua.globals().snapshotCatalog=to_lua(lua,catalog if catalog is not None else json.loads((ROOT/'fivem/data/catalog.json').read_text(encoding='utf-8-sig')))
    lua.globals().snapshotSets=to_lua(lua,sets if sets is not None else json.loads((ROOT/'fivem/data/sets.json').read_text(encoding='utf-8-sig')))
    lua.execute('''
        MetaComic.Persistence={name='mysql',loadCatalog=function() return MetaComic.CopyTable(snapshotCatalog) end}
        MetaComic.Sets={get=function(id) for _,s in ipairs(snapshotSets) do if s.id==id then return s end end end,
            getAll=function() return snapshotSets end,defaultId=function() return snapshotSets[1].id end}
        MetaComic.RpcHandlers.getSets=function() return {ok=true,sets=snapshotSets} end
    ''')
    for file in ('fivem/server/modules/grading.lua','fivem/server/cards.lua','fivem/server/modules/card_buyers.lua','fivem/server/modules/card_market_analysis.lua'):
        lua.execute((ROOT/file).read_text(encoding='utf-8'))
    return lua

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--samples',type=int,default=5000)
    parser.add_argument('--output',default='output/card-market-analysis.md');args=parser.parse_args()
    lua=runtime();reports=[]
    for buyer_index,buyer in lua.globals().Config.CardBuyers.Peds.items():
        for _,card_set in lua.globals().snapshotSets.items():
            result=lua.globals().MetaComic.CardMarketAnalysis.calculate(buyer,card_set.id,args.samples)
            if isinstance(result,tuple): continue
            report=from_lua(result);report.update(buyerName=buyer.label,setName=card_set.name,buyerIndex=buyer_index)
            reports.append(report)
    path=ROOT/args.output;path.parent.mkdir(parents=True,exist_ok=True)
    path.with_suffix('.json').write_text(json.dumps(reports,indent=2),encoding='utf-8')
    lines=['# Pack resale analysis','',
        'Source: checked-in `fivem/data/catalog.json`, `sets.json`, and current `config.lua`. Live MySQL definitions may differ; the in-game Pack pricing tab uses the live server definitions. Observed graded population is zero for this offline snapshot.',
        '',f'Factory simulations use up to {min(5000,args.samples):,} packs per set. Clean averages are exact weighted expectations. All figures are dollars, before pack purchase cost and grading fees. Suggested grading assumes all defects are found; actual grader adjustments can differ.','']
    for report in reports:
        lines += [f"## {report['setName']} — {report['buyerName']}",'',f"| Scenario | Average / pack | Median | 10th–90th percentile | Average / {report['packsPerBox']}-pack box |",'|---|---:|---:|---:|---:|']
        for key,label in [('clean','Clean raw (exact average)'),('fresh','Factory raw (simulation)'),('graded','Factory suggested grades (simulation)')]:
            s=report[key];lines.append(f"| {label} | ${s['mean']:.2f} | ${s['median']:.2f} | ${s['p10']:.2f}–${s['p90']:.2f} | ${s['mean']*report['packsPerBox']:.2f} |")
        lines += ['','For factory raw cards, at a $250 pack price:']
        s=report['fresh'];recover=sum(b['count'] for b in s['histogram'] if b['value']>=250)/s['samples']
        lines += [f"- Customer average net return: ${s['mean']-250:.2f}.",f"- Sampled chance of recovering $250: {recover*100:.2f}%.",
            f"- 95% confidence interval for the simulated mean: ${s['confidence95'][0]:.2f}–${s['confidence95'][1]:.2f}.",
            '- Business buyback margin = sale price after fees − supply cost − average card buyback. Enter real supply costs and fees in the UI before choosing a retail price.',
            '', '| Proposed pack price | Customer average net (fresh raw) | Sampled recovery chance | Business margin after buyback, before supply cost/fees |','|---|---:|---:|---:|']
        for price in [10,15,20,25,30,35,40,50,100,250]:
            chance=sum(b['count'] for b in s['histogram'] if b['value']>=price)/s['samples']
            lines.append(f"| ${price} | ${s['mean']-price:.2f} | {chance*100:.2f}% | ${price-s['mean']:.2f} |")
        lines += ['', 'For example, with $5 supply cost, no fees, and a 20% revenue margin including all fresh-card buyback, the target pack price is `ceil((5 + expected resale) / 0.8)`: '
            + f"**${math.ceil((5+s['mean'])/.8)}**. This is a worked example, not a configured supply cost. Buyer funding and actual demand still matter.",
            '', '| Clean slot contribution | Cards | Expected resale |','|---|---:|---:|']
        for slot in report['slots']:lines.append(f"| {slot['label']} | {slot['count']} | ${slot['mean']:.2f} |")
        lines += ['','| All five cards hypothetically at grade | Expected pack resale |','|---|---:|']
        for g in report['gradeScenarios']:lines.append(f"| {g['grade']} | ${g['mean']:.2f} |")
        lines += ['','These fixed-grade rows are scenarios, not expected grade frequencies. The factory-grade simulation uses the grading model’s actual suggested-grade distribution.','',
            '| Card / print | Tier | Expected copies / pack | Clean offer | Contribution / pack |','|---|---|---:|---:|---:|']
        for p in report['prints']:lines.append(f"| {p['label']} / {p['variant']} | {p['rarity']} | {p['expectedCopies']:.6f} | ${p['cleanPrice']:.2f} | ${p['expectedCopies']*p['cleanPrice']:.2f} |")
        lines.append('')
    path.write_text('\n'.join(lines),encoding='utf-8')
    print(path)
    for report in reports: print(f"{report['setName']}: clean ${report['clean']['mean']:.2f}; fresh ${report['fresh']['mean']:.2f}; suggested grades ${report['graded']['mean']:.2f}")

if __name__=='__main__':main()
