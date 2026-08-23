#!/usr/bin/env python3
"""Assemble docs/fathom-app.html — the Instrument Panel prototype.

Ports the content model out of the design handoff's .dc.html verbatim, swaps the
Design-Component runtime for plain DOM rendering, inlines the fonts and icons so
the file stays self-contained the way the locked prototype was, and applies the
contrast decisions that are already shipped in Swift.
"""
import base64
import json
import re
import urllib.parse
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
REPO = SCRIPTS.parent

# Everything this needs is in the repository. Fonts and icons are derived from
# the same files the app bundles, so the prototype and the app cannot drift
# apart, and the content model is committed beside this script rather than
# living in someone's working directory.
FONTS = REPO / "Fathom/Resources/Fonts"
ICONS = REPO / "Fathom/Resources/NavIcons"

# family, css weight, filename, css format
FACES = [
    ("Archivo", 400, "Archivo-Regular.ttf", "ttf", "truetype"),
    ("Archivo", 500, "Archivo-Medium.ttf", "ttf", "truetype"),
    ("Archivo", 600, "Archivo-SemiBold.ttf", "ttf", "truetype"),
    ("ArchivoSX", 600, "Archivo_SemiExpanded-SemiBold.ttf", "ttf", "truetype"),
    ("JB", 400, "JB-400.woff2", "woff2", "woff2"),
    ("JB", 500, "JB-500.woff2", "woff2", "woff2"),
]


def embedded_faces() -> str:
    blocks = []
    for family, weight, filename, mime, fmt in FACES:
        data = base64.b64encode((FONTS / filename).read_bytes()).decode()
        blocks.append(
            f"@font-face{{font-family:'{family}';font-style:normal;"
            f"font-display:block;font-weight:{weight};"
            f"src:url(data:font/{mime};base64,{data}) format('{fmt}')}}"
        )
    return "\n".join(blocks)


def embedded_icons() -> dict[str, str]:
    out = {}
    for path in sorted(ICONS.glob("*.svg")):
        svg = re.sub(r"\s+", " ", path.read_text().strip())
        out[path.stem] = "data:image/svg+xml," + urllib.parse.quote(svg, safe="")
    return out


fonts = embedded_faces()
icons = embedded_icons()
dc = (SCRIPTS / "prototype-content.js").read_text()

# ---------------------------------------------------------------- content model
# Lift sec() out of the design file and rewrite the Design-Component idioms as
# plain calls. Every string, number and colour stays exactly as designed.
body = dc[dc.index("  sec(k) {"): dc.index("  renderVals() {")]
body = body[body.index("{") + 1: body.rindex("}")]
subs = [
    (r"\bthis\.tbl\(", "tbl("), (r"\bthis\.sp\(", "sp("), (r"\bthis\.note\(", "note("),
    (r"\bthis\.go\(", "go("), (r"\bthis\.E\b", "E"), (r"\bthis\.sim\b", "SIM"),
    (r"\bthis\.hist\b", "HIST"), (r"\bthis\.props\.firstRun\b", "FIRSTRUN"),
    (r"\bthis\.state\.rsel\b", "RSEL"),
]
for pat, rep in subs:
    body = re.sub(pat, rep, body)

# Two semantic colours could not carry text on a data row: blocked #FFAFAF read
# 3.88:1 and informational #A9CBFF 4.10:1. Lightened until each clears 4.5:1
# with the same margin as the rest of the system. Hue is unchanged; these are
# the same four meanings, just legible on the surface they actually land on.
body = body.replace("R = '#FFAFAF'", "R = '#FFCACA'")
body = body.replace("I = '#A9CBFF'", "I = '#BFD9FF'")
body = body.replace("rgba(255,175,175,.11)", "rgba(255,202,202,.11)")
assert "'#FFAFAF'" not in body and "'#A9CBFF'" not in body
# the one setState in the model is Reclaim's rule toggle
body = body.replace(
    "() => this.setState(st => ({ rsel: { ...st.rsel, [r[0]]: !st.rsel[r[0]] } }))",
    "() => { RSEL[r[0]] = !RSEL[r[0]]; render(); }",
)
# `this.` also occurs in prose ("carrying most of this."), so match the members
# rather than the token.
leftover = re.findall(r"this\.(setState|props|state|sim|hist|tbl|sp|note|go|E)\b", body)
assert not leftover, f"unported Design-Component idioms remain: {set(leftover)}"

# maps + simulation, verbatim from the design file
def grab(name):
    m = re.search(rf"^  {name} = (\{{.*?\}});$", dc, re.M | re.S)
    return m.group(1)

W, TT, SUB, E = grab("W"), grab("TT"), grab("SUB"), grab("E")
NAV = ("[['', ['menubar', 'digest']], ['OVERVIEW', ['home', 'scan']], "
       "['SYSTEM', ['cpu', 'gpu', 'mem', 'sensors', 'network', 'bt']], "
       "['STORAGE', ['storage', 'timeline', 'explore', 'reclaim', 'endurance', "
       "'attrib', 'apps', 'cloud', 'maint', 'ssd']]]")

# ---------------------------------------------------------------------- styles
# Values below that differ from the handoff are the shipped contrast decisions:
#   plate .45 under content and rail; cell .16, row .07, hover .13 ON the plate,
#   black rather than white; no text below 82%.
CSS = """
*{margin:0;padding:0;box-sizing:border-box}
:root{
 /* Archivo, per the handoff. SemiExpanded is width class 6 -- 112.5% of
    normal -- against the specified wdth 112. The UI face is normal width:
    wdth 104 needs the variable font, which Archivo does not ship here. */
 --disp:'ArchivoSX','Archivo',-apple-system,sans-serif;
 --ui:'Archivo',-apple-system,BlinkMacSystemFont,sans-serif;
 --num:'Archivo',-apple-system,sans-serif;--mono:'JB',ui-monospace,monospace;
 --b1:#04203A;--b2:#0B5296;--b3:#2E8BE0;
 --plate:rgba(0,0,0,.45);--cell:rgba(0,0,0,.16);
 --row:rgba(0,0,0,.07);--rowh:rgba(0,0,0,.13);
 --tx:rgba(255,255,255,.82);
 --hair:rgba(255,255,255,.16);--grid:rgba(255,255,255,.14);
 --G:#8DF3C4;--A:#FCD98A;--R:#FFCACA;--I:#BFD9FF;--L:#5CE6A8;
 --ease:cubic-bezier(.16,1,.3,1)}
html,body{height:100%;background:#EFEFF2;overflow:hidden;-webkit-font-smoothing:antialiased;
 text-rendering:optimizeLegibility;font-family:var(--ui);font-variant-numeric:tabular-nums;
 letter-spacing:-.008em;color:#fff}
*{cursor:default;-webkit-tap-highlight-color:transparent}
:focus-visible{outline:2px solid rgba(255,255,255,.6);outline-offset:3px;border-radius:8px}
a{color:var(--I);text-decoration:none}a:hover{color:#fff}
@keyframes pul{0%,100%{opacity:1}50%{opacity:.3}}
@keyframes ein{from{opacity:0;transform:translateY(12px)}to{opacity:1;transform:none}}
::-webkit-scrollbar{display:none}

#win{position:fixed;inset:14px;border-radius:15px;overflow:hidden;display:flex;isolation:isolate;
 box-shadow:0 50px 130px rgba(0,0,0,.45),0 0 0 .5px rgba(0,0,0,.25)}
#bg{position:absolute;inset:0;z-index:0;transition:background .55s var(--ease);
 background:linear-gradient(177deg,var(--b1) 0%,var(--b2) 60%,var(--b3) 100%)}
#grain{position:absolute;inset:0;z-index:1;pointer-events:none;opacity:.3;mix-blend-mode:overlay;
 background-image:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='180' height='180'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='.85' numOctaves='4'/%3E%3C/filter%3E%3Crect width='180' height='180' filter='url(%23n)' opacity='.5'/%3E%3C/svg%3E")}
#halo{position:absolute;left:20%;right:0;top:-8%;height:88%;z-index:1;pointer-events:none;
 background:radial-gradient(52% 58% at 50% 42%,rgba(255,255,255,.30) 0%,rgba(255,255,255,.10) 42%,transparent 72%)}

/* The plate. Everything that carries text sits on it — see FATHOM-DESIGN.md. */
#rail{width:64px;flex:none;position:relative;z-index:6;display:flex;flex-direction:column;
 align-items:center;padding:14px 0 12px;background:var(--plate);
 backdrop-filter:blur(46px) saturate(135%);border-right:.5px solid rgba(255,255,255,.09)}
#lights{display:flex;flex-direction:column;gap:6px;padding:0 0 16px}
#lights i{width:9px;height:9px;border-radius:50%;display:block}
#navs{display:flex;flex-direction:column;align-items:center;gap:3px;flex:1 1 0;min-height:0;overflow-y:auto}
.nb{width:42px;height:42px;flex:none;display:grid;place-items:center;border-radius:10px;cursor:pointer;
 border:0;background:transparent;padding:0;transition:background .22s var(--ease),transform .18s var(--ease)}
.nb:hover{background:rgba(255,255,255,.11)}
.nb:active{transform:scale(.94)}
.nb.on{background:linear-gradient(180deg,rgba(255,255,255,.26),rgba(255,255,255,.13));
 box-shadow:inset 0 1px 0 rgba(255,255,255,.3)}
.nb i{width:19px;height:19px;display:block;background:var(--tx);
 filter:drop-shadow(0 1px 2px rgba(0,0,0,.28))}
.nb.on i{background:#fff}
.ndv{width:22px;height:1px;background:rgba(255,255,255,.22);margin:9px 0 8px;flex:none}
#foot{border-top:.5px solid rgba(255,255,255,.1);margin-top:8px;padding:12px 0 2px;display:grid;place-items:center}
#foot i{width:7px;height:7px;border-radius:50%;background:var(--L);box-shadow:0 0 9px var(--L);
 animation:pul 2.2s ease-in-out infinite}

#main{flex:1;position:relative;min-width:0;z-index:5;display:flex;flex-direction:column;background:var(--plate)}
#strip{height:32px;flex:none;display:flex;align-items:center;justify-content:space-between;padding:0 16px;
 font-size:10px;font-weight:700;letter-spacing:.1em;color:var(--tx);background:rgba(0,0,0,.25);
 backdrop-filter:blur(20px);border-bottom:.5px solid rgba(255,255,255,.08)}
#col{flex:1;min-height:0;overflow-y:auto;padding:22px 28px 40px}
#col.anim{animation:ein .45s var(--ease)}
@media (prefers-reduced-motion:reduce){
 #col.anim{animation:none}
 #foot i,.lp i{animation:none}
 #bg{transition:none}}

.hd{display:flex;align-items:baseline;justify-content:space-between;gap:20px;flex-wrap:wrap;
 padding-bottom:16px;border-bottom:.5px solid var(--hair);margin-bottom:20px}
.hd .l{display:flex;align-items:baseline;gap:18px;flex-wrap:wrap}
.hd h1{font-family:var(--disp);font-size:clamp(28px,2.8vw,40px);font-weight:600;letter-spacing:-.028em;
 line-height:1;color:#fff;text-wrap:balance}
.hd .m{font-size:12.5px;color:var(--tx)}
.lp{display:inline-flex;align-items:center;gap:9px;font-size:11.5px;color:var(--tx);white-space:nowrap}
.lp i{width:5px;height:5px;border-radius:50%;background:var(--L);box-shadow:0 0 9px var(--L);
 animation:pul 2.2s ease-in-out infinite;flex:none}

/* the gap IS the hairline */
.rg{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:1px;
 margin-bottom:4px}
.rc{background:var(--cell);padding:16px 18px 18px;box-shadow:0 0 0 .5px var(--grid);
 transition:background .25s var(--ease)}
.rc:hover{background:var(--rowh)}
.rl{font-size:9px;font-weight:600;letter-spacing:.16em;text-transform:uppercase;color:var(--tx);
 margin-bottom:12px}
.rv{font-family:var(--disp);font-size:clamp(30px,2.7vw,38px);font-weight:600;letter-spacing:-.03em;
 line-height:1;color:#fff}
.rv u{font-size:13px;color:var(--tx);margin-left:5px;text-decoration:none;font-family:var(--ui);
 letter-spacing:-.008em}
.rn{font-size:11.5px;color:var(--tx);line-height:1.45;max-width:32ch;margin-top:10px}

.pn{padding:22px 0 26px;border-top:.5px solid var(--hair)}
.pl{font-size:9px;font-weight:600;letter-spacing:.16em;text-transform:uppercase;color:var(--tx);
 margin-bottom:14px}
.rw{display:grid;grid-template-columns:minmax(0,1fr) 110px 150px;gap:10px;align-items:center;
 padding:11px 13px;border-radius:12px;background:var(--row);margin-bottom:3px;font-size:13px;
 transition:background .2s var(--ease)}
.rw:hover{background:var(--rowh)}
.rw .n{min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:#fff}
.rw .a,.rw .b{text-align:right;font-variant-numeric:tabular-nums}
.rw .b em{display:block;font-style:normal;font-size:10.5px;color:var(--tx)}
.hint{font-size:11.5px;color:var(--tx);margin-top:10px;max-width:66ch}

.sk{width:100%;height:52px;display:block}
.cores{display:flex;align-items:flex-end;gap:8px;height:110px}
.cores div{flex:1;display:flex;flex-direction:column;justify-content:flex-end;align-items:center;gap:6px;height:100%}
.cores b{display:block;width:100%;background:rgba(255,255,255,.92);border-radius:2px;
 transition:height .6s var(--ease)}
.cores b.e{background:rgba(255,255,255,.5)}
.cores span{font-size:9px;color:var(--tx);letter-spacing:.08em}

.seg{display:flex;height:34px;border-radius:8px;overflow:hidden;margin-bottom:12px}
.leg{display:flex;flex-wrap:wrap;gap:8px 18px;font-size:11.5px;color:var(--tx)}
.leg span{display:inline-flex;align-items:center;gap:7px}
.leg i{width:9px;height:9px;border-radius:2px;flex:none}

/* grid rather than flex: `1fr` rows resolve to a definite height, so the bars'
   percentage heights actually apply. Growth rises from the baseline, deletion
   falls from it. */
.days{display:flex;gap:8px;align-items:stretch;height:170px}
.days>div{flex:1;display:grid;grid-template-rows:1fr 1px 1fr auto auto;gap:4px;
 justify-items:center;height:100%}
.days .hu,.days .hd{display:block;position:relative;width:100%;height:100%}
.days .up,.days .dn{display:block;position:absolute;left:0;right:0;
 background:rgba(255,255,255,.78);border-radius:2px}
.days .up{bottom:0}
.days .dn{top:0;background:rgba(255,255,255,.34)}
.days .base{width:100%;height:1px;background:var(--hair);align-self:center}
.days .v{font-size:10.5px;color:#fff;font-variant-numeric:tabular-nums}
.days .b{font-size:10px;color:var(--tx)}

.dev{display:grid;grid-template-columns:minmax(0,1fr) 120px 110px;gap:12px;align-items:center;
 padding:11px 13px;border-radius:12px;background:var(--row);margin-bottom:3px;font-size:13px}
.dev .mt{height:6px;border-radius:3px;background:rgba(255,255,255,.16);overflow:hidden}
.dev .mt i{display:block;height:100%;background:rgba(255,255,255,.85)}
.dev .v{text-align:right}

.feed{display:flex;flex-direction:column;gap:3px}
.fi{display:grid;grid-template-columns:10px minmax(0,1fr) 110px;gap:12px;align-items:start;
 padding:13px;border-radius:12px;background:var(--row);transition:background .2s var(--ease)}
.fi:hover{background:var(--rowh)}
.fi i{width:8px;height:8px;border-radius:50%;margin-top:5px}
.fi b{display:block;font-size:13.5px;font-weight:600;color:#fff}
.fi p{font-size:11.5px;color:var(--tx);margin-top:3px;max-width:66ch}
.fi .v{text-align:right;font-weight:600;font-family:var(--num)}

.g3{display:grid;grid-template-columns:repeat(auto-fit,minmax(178px,1fr));gap:1px}
.g3 button{background:var(--cell);border:0;padding:13px 15px;text-align:left;cursor:pointer;
 font:inherit;color:inherit;box-shadow:0 0 0 .5px var(--grid);
 transition:background .2s var(--ease)}
.g3 button:hover{background:var(--rowh)}
.g3 b{display:block;font-size:9px;font-weight:600;letter-spacing:.14em;text-transform:uppercase;
 color:var(--tx)}
.g3 strong{display:block;font-family:var(--disp);font-size:21px;font-weight:600;letter-spacing:-.02em;
 margin:7px 0 3px;color:#fff}
.g3 span{display:block;font-size:11px;color:var(--tx)}

.map{position:relative;height:230px;border:.5px solid var(--grid)}
.map div{position:absolute;padding:9px 11px;border:.5px solid var(--grid);overflow:hidden}
.map b{display:block;font-size:11.5px;font-weight:600;color:#fff}
.map span{display:block;font-size:10px;color:var(--tx);margin-top:2px}

.chain{display:flex;flex-wrap:wrap;align-items:center;gap:10px}
.chain .it{background:var(--cell);border:.5px solid var(--grid);padding:12px 15px;min-width:132px}
.chain b{display:block;font-size:9px;font-weight:600;letter-spacing:.14em;text-transform:uppercase;color:var(--tx)}
.chain strong{display:block;font-family:var(--disp);font-size:23px;font-weight:600;letter-spacing:-.02em;
 margin:6px 0 2px;color:#fff}
.chain span{display:block;font-size:10.5px;color:var(--tx)}
.chain .ar{color:var(--tx);font-size:15px}

.dig{background:#F4F3F1;color:#1A1A1A;border-radius:14px;padding:22px 24px;max-width:520px}
.dig h4{font-family:var(--disp);font-size:19px;font-weight:600;letter-spacing:-.02em;margin-bottom:3px}
.dig .dt{font-size:11px;color:#6B6B6B;margin-bottom:14px}
.dig .dr{display:flex;justify-content:space-between;gap:14px;font-size:12.5px;padding:6px 0;
 border-top:1px solid #E2E0DD}
.dig p{font-size:12.5px;color:#3A3A3A;margin-top:14px;line-height:1.5}

.tog{display:flex;justify-content:space-between;align-items:center;gap:14px;padding:12px 13px;
 border-radius:12px;background:var(--row);margin-bottom:3px}
.tog b{display:block;font-size:13px;font-weight:600;color:#fff}
.tog span{display:block;font-size:11px;color:var(--tx);margin-top:2px}
.tog .sw{width:36px;height:21px;border-radius:11px;flex:none;position:relative}
.tog .sw i{position:absolute;top:2.5px;width:16px;height:16px;border-radius:50%;background:#fff}

.mbar{background:rgba(0,0,0,.42);backdrop-filter:blur(20px);border-radius:6px;height:26px;
 display:inline-flex;align-items:center;gap:14px;padding:0 12px;font-size:11.5px;color:#fff}
.mbar b{font-weight:600}

.note{max-width:66ch}
.note h3{font-family:var(--disp);font-size:19px;font-weight:600;letter-spacing:-.022em;
 margin-bottom:8px;color:#fff;text-wrap:balance}
.note p{font-size:12.5px;color:var(--tx);line-height:1.55}

.act{margin-top:22px}
.act button{background:rgba(255,255,255,.14);border:.5px solid rgba(255,255,255,.22);
 box-shadow:inset 0 1px 0 rgba(255,255,255,.20);color:#fff;font:inherit;font-size:13px;font-weight:600;
 padding:11px 20px;border-radius:15px;cursor:pointer;transition:transform .16s var(--ease),background .16s var(--ease)}
.act button:hover{background:rgba(255,255,255,.2);transform:scale(1.04)}
.act button:active{transform:scale(.96)}

@media(max-width:760px){#col{padding:18px 16px 32px}.rw,.dev{grid-template-columns:minmax(0,1fr) 92px}
 .rw .b em{display:inline;margin-left:6px}}
"""

# ---------------------------------------------------------------------- runtime
JS = """
const IC=%(icons)s, W=%(W)s, TT=%(TT)s, SUB=%(SUB)s, E=%(E)s, NAV=%(NAV)s;
const RSEL={derived:true,caches:true,fcp:true,snap:false,logs:true};
let FIRSTRUN=false, K='cpu';
const SIM={cpu:22,gpu:16,net:1240,up:84,pwr:6.8,hot:41,cores:[34,28,18,12,42,38,9,6]};
const HIST={cpu:Array(60).fill(22),gpu:Array(60).fill(16),net:Array(60).fill(1200),pwr:Array(60).fill(6.8)};

const esc=s=>String(s).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
function sp(key,max,label){const b=HIST[key],n=b.length;
 const pts=b.map((v,i)=>(i*(1000/(n-1))).toFixed(0)+','+(54-Math.min(1,v/max)*48).toFixed(1)).join(' ');
 return{isSpark:true,label,pts,poly:'0,56 '+pts+' 1000,56'};}
function tbl(label,c1,c2,c3,rows,hint){return{isTbl:true,label,c1,c2,c3,hint:hint||'',
 rows:rows.map(r=>({n:r[0],a:r[1],b:r[2]||'',bc:r[3]||'#fff',ff:r[4]?"var(--mono)":'inherit',
 em:r[5]||'',bg:r[6]||'',click:r[7]||null}))};}
function note(h,b,label){return{isNote:true,h,b,label:label||''};}
function sec(k){%(body)s}

function bars(cs){return cs.map((c,i)=>({l:i<4?'E'+(i+1):'P'+(i-3),h:Math.round(c)+'%%',v:Math.round(c)+'%%'}));}

function panel(m){
 const L=m.label?`<div class="pl">${esc(m.label)}</div>`:'';
 if(m.isSpark)return `<div class="pn">${L}<svg class="sk" viewBox="0 0 1000 56" preserveAspectRatio="none" aria-hidden="true"><polygon points="${m.poly}" fill="rgba(255,255,255,.13)"/><polyline points="${m.pts}" fill="none" stroke="rgba(255,255,255,.92)" stroke-width="2.5" stroke-linejoin="round" stroke-linecap="round"/></svg></div>`;
 if(m.isCores)return `<div class="pn">${L}<div class="cores">${m.bars.map((b,i)=>`<div><b class="${i<4?'e':''}" style="height:${b.h}"></b><span>${b.l}</span></div>`).join('')}</div></div>`;
 if(m.isTbl)return `<div class="pn">${L}<div class="rw" style="background:none;font-size:9px;font-weight:600;letter-spacing:.14em;text-transform:uppercase;color:var(--tx);padding-bottom:6px"><span>${esc(m.c1)}</span><span class="a">${esc(m.c2)}</span><span class="b">${esc(m.c3)}</span></div>${m.rows.map((r,i)=>`<div class="rw" data-tbl="${r.click?i:''}" style="${r.bg?'background:'+r.bg:''};${r.click?'cursor:pointer':''}"><span class="n" style="font-family:${r.ff}">${esc(r.n)}</span><span class="a">${esc(r.a)}</span><span class="b" style="color:${r.bc}">${esc(r.b)}${r.em?`<em>${esc(r.em)}</em>`:''}</span></div>`).join('')}${m.hint?`<div class="hint">${esc(m.hint)}</div>`:''}</div>`;
 if(m.isSeg)return `<div class="pn">${L}<div class="seg">${m.segs.map(s=>`<i style="width:${s.w};background:${s.bg};display:block"></i>`).join('')}</div><div class="leg">${m.leg.map(l=>`<span><i style="background:${l.bg}"></i>${esc(l.t)}</span>`).join('')}</div></div>`;
 if(m.isDays)return `<div class="pn">${L}<div class="days">${m.days.map(d=>`<div><span class="hu"><i class="up" style="height:${d.upH}"></i></span><span class="base"></span><span class="hd"><i class="dn" style="height:${d.dnH}"></i></span><span class="v">${esc(d.v)}</span><span class="b">${esc(d.b)}</span></div>`).join('')}</div></div>`;
 if(m.isDevs)return `<div class="pn">${L}${m.rows2.map(r=>`<div class="dev"><span class="n">${esc(r.n)}</span><span class="mt"><i style="width:${r.w}"></i></span><span class="v" style="opacity:${Math.max(r.op,.82)};font-size:${r.fs};font-style:${r.fst};font-weight:${r.fw}">${esc(r.v)}</span></div>`).join('')}</div>`;
 if(m.isFeed)return `<div class="pn">${L}<div class="feed">${m.items2.map(f=>`<div class="fi"><i style="background:${f.c}"></i><span><b>${esc(f.t)}</b><p>${esc(f.p)}</p></span><span class="v" style="color:${f.vc}">${esc(f.v)}</span></div>`).join('')}</div></div>`;
 if(m.isGrid)return `<div class="pn">${L}<div class="g3">${m.items3.map((g,i)=>`<button data-go="${i}"><b>${esc(g.t)}</b><strong>${esc(g.v)}</strong><span>${esc(g.s)}</span></button>`).join('')}</div></div>`;
 if(m.isMap)return `<div class="pn">${L}<div class="map">${m.rects.map(r=>`<div style="left:${r.l};top:${r.t};width:${r.w};height:${r.h};background:${r.bg}"><b>${esc(r.n)}</b><span>${esc(r.v)}</span></div>`).join('')}</div></div>`;
 if(m.isChain)return `<div class="pn">${L}<div class="chain">${m.items.map(c=>`<div class="it"><b>${esc(c.l)}</b><strong>${esc(c.v)}</strong><span>${esc(c.s)}</span></div>${c.arrow?'<span class="ar">&rarr;</span>':''}`).join('')}</div></div>`;
 if(m.isDig)return `<div class="pn">${L}<div class="dig"><h4>${esc(m.l1)}</h4><div class="dt">${esc(m.date)}</div>${m.rows4.map(r=>`<div class="dr"><span>${esc(r.n)}</span><span style="color:${r.c};font-weight:600">${esc(r.v)}</span></div>`).join('')}<p>${esc(m.l2)}</p><p style="font-weight:600;color:#1A1A1A">Nothing needs you. This is the whole message.</p></div></div>`;
 if(m.isTogs)return `<div class="pn">${L}${m.rows3.map(r=>`<div class="tog"><span><b>${esc(r.b)}</b><span>${esc(r.s)}</span></span><span class="sw" style="background:${r.tbg}"><i style="left:${r.tx}"></i></span></div>`).join('')}</div>`;
 if(m.isMbar)return `<div class="pn">${L}<div class="mbar"><span><b>${esc(m.free)}</b> GB</span><span>${esc(m.hot)}</span><span>&darr; <b>${esc(m.net)}</b></span><span><b>${esc(m.cpu)}</b>%%</span><span style="opacity:.82">${esc(m.time)}</span></div></div>`;
 if(m.isNote)return `<div class="pn">${L}<div class="note"><h3>${esc(m.h)}</h3><p>${esc(m.b)}</p></div></div>`;
 return '';
}

let LAST=null;
function render(anim){
 const d=sec(K); LAST=d;
 const w=W[K];
 document.documentElement.style.setProperty('--b1',w[0]);
 document.documentElement.style.setProperty('--b2',w[1]);
 document.documentElement.style.setProperty('--b3',w[2]);
 document.getElementById('navs').querySelectorAll('.nb').forEach(b=>
   b.classList.toggle('on',b.dataset.k===K));
 const col=document.getElementById('col');
 col.innerHTML=
  `<div class="hd"><div class="l"><h1>${esc(TT[K])}</h1>`+
  `<div class="m">MacBook Air M2 &middot; 16 GB &middot; 142 days recorded</div></div>`+
  `<div class="lp"><i></i>${esc(SUB[K])}</div></div>`+
  (d.tiles.length?`<div class="rg">${d.tiles.map(t=>
    `<div class="rc"><div class="rl">${esc(t.k)}</div><div class="rv">${esc(t.v)}`+
    `${t.u?`<u>${esc(t.u)}</u>`:''}</div>${t.s?`<div class="rn">${esc(t.s)}</div>`:''}</div>`).join('')}</div>`:'')+
  d.mods.map(panel).join('')+
  (d.act?`<div class="act"><button data-act="1">${esc(d.act.t)}</button></div>`:'');
 col.scrollTop=0;
 if(anim){col.classList.remove('anim');void col.offsetWidth;col.classList.add('anim');}
}

function go(k){if(k===K)return;K=k;render(true);}
const ORDER=Object.keys(TT);
function stepNav(d){const i=ORDER.indexOf(K);go(ORDER[(i+d+ORDER.length)%%ORDER.length]);}

function step(){
 const w=(v,lo,hi,j)=>Math.min(hi,Math.max(lo,v+(Math.random()-.5)*j));
 SIM.cpu=w(SIM.cpu,6,88,9);SIM.gpu=w(SIM.gpu,3,70,7);SIM.net=w(SIM.net,40,4800,620);SIM.up=w(SIM.up,10,400,60);
 SIM.pwr=+(3.4+SIM.cpu*.07+SIM.gpu*.04).toFixed(1);SIM.hot=+(38+SIM.cpu*.1).toFixed(1);
 SIM.cores=SIM.cores.map((c,i)=>w(c,1,96,i<4?14:18));
 ['cpu','gpu','net','pwr'].forEach(k=>{const b=HIST[k];b.push(SIM[k]);if(b.length>60)b.shift();});
 render(false);
}

// nav
const navs=document.getElementById('navs');
NAV.forEach(([head,keys],gi)=>{
 if(gi)navs.insertAdjacentHTML('beforeend',`<div class="ndv" role="separator"></div>`);
 keys.forEach(k=>navs.insertAdjacentHTML('beforeend',
  `<button class="nb" data-k="${k}" title="${esc(TT[k])}" aria-label="${esc(TT[k])}"><i style="-webkit-mask:url(&quot;${IC[k]}&quot;) center/contain no-repeat;mask:url(&quot;${IC[k]}&quot;) center/contain no-repeat"></i></button>`));
});
navs.addEventListener('click',e=>{const b=e.target.closest('.nb');if(b)go(b.dataset.k);});
document.getElementById('col').addEventListener('click',e=>{
 const g=e.target.closest('[data-go]');
 if(g&&LAST){for(const m of LAST.mods)if(m.isGrid){const it=m.items3[+g.dataset.go];if(it&&it.go)it.go();return;}}
 const t=e.target.closest('[data-tbl]');
 if(t&&t.dataset.tbl!==''&&LAST){for(const m of LAST.mods)if(m.isTbl){const r=m.rows[+t.dataset.tbl];if(r&&r.click){r.click();return;}}}
 const a=e.target.closest('[data-act]');
 if(a&&LAST&&LAST.act&&LAST.act.go)LAST.act.go();
});
addEventListener('keydown',e=>{
 if(e.metaKey||e.ctrlKey||e.altKey)return;
 if(e.key==='ArrowDown'||e.key==='ArrowRight'){e.preventDefault();stepNav(1);}
 if(e.key==='ArrowUp'||e.key==='ArrowLeft'){e.preventDefault();stepNav(-1);}
});
window.go=go;
render(false);
setInterval(step,1000);
"""

js = JS % dict(icons=json.dumps(icons), W=W, TT=TT, SUB=SUB, E=E, NAV=NAV, body=body)

html = (
    '<!doctype html><html lang="en"><head><meta charset="utf-8">\n'
    '<meta name="viewport" content="width=device-width,initial-scale=1">\n'
    "<title>FATHOM</title>\n"
    "<!-- FATHOM — Instrument Panel. The visual spec. Self-contained: fonts and\n"
    "     icons are inlined, nothing is fetched. Materials and text alphas match\n"
    "     FathomSurface in Swift; see FATHOM-DESIGN.md for why they are what they\n"
    "     are. Numbers simulate a MacBook Air M2; the app reads them for real. -->\n"
    "<style>\n" + fonts + "\n" + CSS.strip() + "\n</style></head>\n"
    "<body>\n"
    '<div id="win">\n'
    ' <div id="bg"></div>\n <div id="grain"></div>\n <div id="halo"></div>\n'
    ' <aside id="rail">\n'
    '  <div id="lights"><i style="background:#FF5F57"></i>'
    '<i style="background:#FEBC2E"></i><i style="background:#28C840"></i></div>\n'
    '  <nav id="navs" aria-label="Sections"></nav>\n'
    '  <div id="foot" title="0.2% CPU · energy 2.1"><i></i></div>\n'
    " </aside>\n"
    ' <main id="main">\n'
    '  <div id="strip"><span>INSTRUMENT PANEL</span><span>1 HZ &middot; LIVE</span></div>\n'
    '  <div id="col"></div>\n'
    " </main>\n"
    "</div>\n"
    "<script>\n" + js.strip() + "\n</script>\n</body></html>\n"
)

out = REPO / "docs/fathom-app.html"
out.write_text(html)
print(f"wrote {out} — {len(html):,} bytes")
