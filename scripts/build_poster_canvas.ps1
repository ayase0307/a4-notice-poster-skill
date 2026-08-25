param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,
    [string]$OutputPath = '',
    [string]$ConceptPath = ''
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

function Resolve-ConfigPath([string]$Value, [string]$BaseDirectory) {
    if ([System.IO.Path]::IsPathRooted($Value)) {
        return [System.IO.Path]::GetFullPath($Value)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $BaseDirectory $Value))
}

function Get-PosterDataUri([string]$Path) {
    $mime = switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        '.jpg' { 'image/jpeg' }
        '.jpeg' { 'image/jpeg' }
        '.webp' { 'image/webp' }
        default { 'image/png' }
    }
    return "data:$mime;base64,$([Convert]::ToBase64String([IO.File]::ReadAllBytes($Path)))"
}

$configFullPath = (Resolve-Path -LiteralPath $ConfigPath).Path
$baseDirectory = Split-Path -Parent $configFullPath
$config = Get-Content -Raw -Encoding UTF8 -LiteralPath $configFullPath | ConvertFrom-Json
$backgroundPath = Resolve-ConfigPath ([string]$config.background) $baseDirectory
if (-not (Test-Path -LiteralPath $backgroundPath)) {
    throw "Background not found: $backgroundPath"
}

$conceptFullPath = ''
if (-not [string]::IsNullOrWhiteSpace($ConceptPath)) {
    $conceptFullPath = Resolve-ConfigPath $ConceptPath $baseDirectory
    if (-not (Test-Path -LiteralPath $conceptFullPath)) {
        throw "Concept image not found: $conceptFullPath"
    }
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $baseDirectory 'poster-canvas.html'
}
elseif (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path $baseDirectory $OutputPath
}
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)

$backgroundDataUri = Get-PosterDataUri $backgroundPath
$conceptDataUri = if ($conceptFullPath) { Get-PosterDataUri $conceptFullPath } else { '' }
$configuredFontNames = @(
    [string]$config.fontFamily
    @($config.texts | ForEach-Object { [string]$_.fontFamily })
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
$fontNames = @(
    [System.Drawing.FontFamily]::Families.Name
    $configuredFontNames
) | Sort-Object -Unique
$configJson = $config | ConvertTo-Json -Depth 20 -Compress
$configBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($configJson))
$fontsBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($fontNames | ConvertTo-Json -Compress)))

$htmlTemplate = @'
<!doctype html>
<html lang="zh-Hant">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>A4 公告海報排版畫布</title>
<style>
:root{font-family:"Microsoft JhengHei",sans-serif;color:#172033;background:#eef1f5}
*{box-sizing:border-box}body{margin:0}.app{display:grid;grid-template-columns:minmax(420px,1fr) 340px;gap:20px;padding:20px;min-height:100vh}
.stage{display:flex;align-items:flex-start;justify-content:center;overflow:auto}.poster{position:relative;width:min(72vh,100%);container-type:inline-size;flex:none;background:#fff;box-shadow:0 16px 50px #17203326;background-size:100% 100%;background-repeat:no-repeat;touch-action:none}
.shape,.text{position:absolute}.text{display:flex;white-space:pre;overflow:visible;outline:1px dashed #1d6ee899;outline-offset:-1px;cursor:move;user-select:none}.text.overflow{outline:4px solid #d62f2f;background:#d62f2f12}.selected{outline:3px solid #1d6ee8;outline-offset:2px}.selected.overflow{outline:4px solid #d62f2f}
.concept{position:absolute;inset:0;background-size:100% 100%;background-repeat:no-repeat;pointer-events:none}.concept.diff{mix-blend-mode:difference}
.panel{position:sticky;top:20px;align-self:start;background:#fff;border-radius:16px;padding:18px;box-shadow:0 10px 30px #1720331a;max-height:calc(100vh - 40px);overflow:auto}
h1{font-size:20px;margin:0 0 8px}.hint{font-size:13px;color:#647087;margin:0 0 16px}.field{margin:12px 0}.field label{display:block;font-size:12px;font-weight:700;margin-bottom:5px}.field input,.field select,.field textarea{width:100%;padding:8px;border:1px solid #cbd2dc;border-radius:7px;background:#fff}.field input[type=checkbox]{width:auto;padding:0}.row{display:grid;grid-template-columns:1fr 1fr;gap:8px}.actions{display:flex;gap:8px;margin-top:14px}.actions button{border:0;border-radius:8px;padding:10px 12px;background:#172033;color:#fff;cursor:pointer}.actions button.secondary{background:#e7ebf1;color:#172033}
.onion{background:#f5f8fc;border:1px solid #dbe3ec;border-radius:10px;padding:2px 12px 10px;margin-bottom:6px}
@media(max-width:900px){.app{grid-template-columns:1fr}.panel{position:relative;top:auto}.poster{width:min(88vw,720px)}}
</style>
</head>
<body>
<main class="app"><section class="stage"><div id="poster" class="poster"></div></section><aside class="panel">
<h1>A4 海報排版畫布</h1><p class="hint">拖曳文字方框可直接調整位置，方向鍵微調 1px、Shift+方向鍵 10px。虛線是文字方框；紅框表示瀏覽器預覽已溢出。下載 JSON 後仍須以正式 renderer 驗證。</p>
<div id="onionRow" class="onion" hidden><div class="field"><label for="onion">概念圖疊圖 <span id="onionValue">0</span>%</label><input id="onion" type="range" min="0" max="100" value="0"></div><div class="field"><label for="onionDiff">差異模式（重疊處變黑即為對齊）</label><input id="onionDiff" type="checkbox"></div></div>
<div class="field"><label for="block">文字區塊</label><select id="block"></select></div>
<div class="field"><label for="text">文字</label><textarea id="text" rows="4"></textarea></div>
<div class="field"><label for="font">本機字型</label><select id="font"></select></div>
<div class="row"><div class="field"><label for="style">字型樣式</label><select id="style"><option>Regular</option><option>Bold</option><option>Italic</option><option>Bold, Italic</option></select></div><div class="field"><label for="lineHeight">行高倍數</label><input id="lineHeight" type="number" min="0.5" step="0.01"></div></div>
<div class="row"><div class="field"><label for="size">字級 px</label><input id="size" type="number"></div><div class="field"><label for="color">顏色</label><input id="color" type="color"></div></div>
<div class="row"><div class="field"><label for="x">X</label><input id="x" type="number"></div><div class="field"><label for="y">Y</label><input id="y" type="number"></div></div>
<div class="row"><div class="field"><label for="width">寬度</label><input id="width" type="number"></div><div class="field"><label for="height">高度</label><input id="height" type="number"></div></div>
<div class="row"><div class="field"><label for="align">水平</label><select id="align"><option>near</option><option>center</option><option>far</option></select></div><div class="field"><label for="valign">垂直</label><select id="valign"><option>near</option><option>center</option><option>far</option></select></div></div>
<div class="actions"><button id="download">下載目前 JSON</button><button id="reset" class="secondary">還原</button></div>
</aside></main>
<script>
const decode=b64=>JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(b64),c=>c.charCodeAt(0))));
const original=decode('__CONFIG_BASE64__');let config=structuredClone(original);const fonts=decode('__FONTS_BASE64__');const bg='__BACKGROUND_DATA_URI__';const concept='__CONCEPT_DATA_URI__';
const poster=document.querySelector('#poster'),blockSelect=document.querySelector('#block');
const onionRow=document.querySelector('#onionRow'),onion=document.querySelector('#onion'),onionDiff=document.querySelector('#onionDiff'),onionValue=document.querySelector('#onionValue');
const fields=['text','font','style','lineHeight','size','color','x','y','width','height','align','valign'];const el=Object.fromEntries(fields.map(id=>[id,document.querySelector('#'+id)]));
const pct=(n,total)=>`${100*n/total}%`;const cqw=(n,total)=>`${100*n/total}cqw`;const cssColor=v=>v&&v.length===9?`#${v.slice(3,9)}${v.slice(1,3)}`:v;const hAlign={near:'flex-start',center:'center',far:'flex-end'};const vAlign={near:'flex-start',center:'center',far:'flex-end'};
const canvasWidth=()=>config.canvas?.width||2480;
function render(){const w=canvasWidth(),h=config.canvas?.height||3508;poster.style.aspectRatio=`${w}/${h}`;poster.style.backgroundImage=`url(${JSON.stringify(bg)})`;poster.innerHTML='';
 (config.roundedRectangles||[]).forEach(s=>{const d=document.createElement('div');d.className='shape';Object.assign(d.style,{left:pct(s.x,w),top:pct(s.y,h),width:pct(s.width,w),height:pct(s.height,h),borderRadius:pct(s.radius,s.width),background:cssColor(s.fill)});poster.appendChild(d)});
 (config.texts||[]).forEach((t,i)=>{const d=document.createElement('div');d.className='text'+(i===blockSelect.selectedIndex?' selected':'');d.dataset.index=i;d.textContent=t.text;Object.assign(d.style,{left:pct(t.x,w),top:pct(t.y,h),width:pct(t.width,w),height:pct(t.height,h),fontFamily:`${JSON.stringify(t.fontFamily||config.fontFamily)},sans-serif`,fontSize:cqw(t.size,w),lineHeight:String(t.lineHeight||1.15),color:cssColor(t.color),fontWeight:(t.style||'').toLowerCase().includes('bold')?'700':'400',fontStyle:(t.style||'').toLowerCase().includes('italic')?'italic':'normal',textAlign:t.align==='center'?'center':t.align==='far'?'right':'left',justifyContent:hAlign[t.align||'near'],alignItems:vAlign[t.valign||'near']});poster.appendChild(d);requestAnimationFrame(()=>d.classList.toggle('overflow',d.scrollWidth>d.clientWidth+1||d.scrollHeight>d.clientHeight+1))});
 if(concept){const c=document.createElement('div');c.className='concept'+(onionDiff.checked?' diff':'');c.style.backgroundImage=`url(${JSON.stringify(concept)})`;c.style.opacity=onionDiff.checked?'1':String(onion.value/100);poster.appendChild(c)}
}
function fillSelects(){blockSelect.innerHTML='';(config.texts||[]).forEach((t,i)=>blockSelect.add(new Option(t.id||t.text.slice(0,20)||`文字 ${i+1}`,i)));el.font.innerHTML='';fonts.forEach(f=>el.font.add(new Option(f,f)))}
function loadBlock(){const t=config.texts[Number(blockSelect.value)||0];if(!t)return;el.text.value=t.text;el.font.value=t.fontFamily||config.fontFamily;el.style.value=t.style||'Regular';el.lineHeight.value=t.lineHeight||1.15;['size','x','y','width','height','align','valign'].forEach(k=>el[k].value=t[k]);el.color.value=cssColor(t.color).slice(0,7)}
function update(){const t=config.texts[Number(blockSelect.value)||0];if(!t)return;t.text=el.text.value;t.fontFamily=el.font.value;t.style=el.style.value;['lineHeight','size','x','y','width','height'].forEach(k=>t[k]=Number(el[k].value));['color','align','valign'].forEach(k=>t[k]=el[k].value);render()}
function moveSelected(dx,dy){const t=config.texts[Number(blockSelect.value)||0];if(!t)return;t.x=Math.round(t.x+dx);t.y=Math.round(t.y+dy);el.x.value=t.x;el.y.value=t.y;render()}
let drag=null;
poster.addEventListener('pointerdown',e=>{const d=e.target.closest('.text');if(!d)return;const i=Number(d.dataset.index);
 blockSelect.selectedIndex=i;loadBlock();render();
 const t=config.texts[i];drag={i,k:canvasWidth()/poster.getBoundingClientRect().width,sx:e.clientX,sy:e.clientY,ox:t.x,oy:t.y};
 poster.setPointerCapture(e.pointerId);e.preventDefault()});
poster.addEventListener('pointermove',e=>{if(!drag)return;const t=config.texts[drag.i];
 t.x=Math.round(drag.ox+(e.clientX-drag.sx)*drag.k);t.y=Math.round(drag.oy+(e.clientY-drag.sy)*drag.k);
 el.x.value=t.x;el.y.value=t.y;render()});
poster.addEventListener('pointerup',()=>{drag=null});poster.addEventListener('pointercancel',()=>{drag=null});
document.addEventListener('keydown',e=>{if(!e.key.startsWith('Arrow'))return;if(/^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement.tagName))return;
 const s=e.shiftKey?10:1;const map={ArrowLeft:[-s,0],ArrowRight:[s,0],ArrowUp:[0,-s],ArrowDown:[0,s]}[e.key];
 if(!map)return;moveSelected(map[0],map[1]);e.preventDefault()});
blockSelect.onchange=()=>{loadBlock();render()};fields.forEach(k=>el[k].oninput=update);
onion.oninput=()=>{onionValue.textContent=onion.value;render()};onionDiff.onchange=render;
document.querySelector('#reset').onclick=()=>{config=structuredClone(original);fillSelects();loadBlock();render()};
document.querySelector('#download').onclick=()=>{const blob=new Blob([JSON.stringify(config,null,2)],{type:'application/json'});const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download='poster-config-reviewed.json';a.click();setTimeout(()=>URL.revokeObjectURL(a.href),1000)};
if(concept)onionRow.hidden=false;
fillSelects();loadBlock();render();
</script>
</body></html>
'@

$html = $htmlTemplate.Replace('__CONFIG_BASE64__', $configBase64).Replace('__FONTS_BASE64__', $fontsBase64).Replace('__BACKGROUND_DATA_URI__', $backgroundDataUri).Replace('__CONCEPT_DATA_URI__', $conceptDataUri)
$outputDirectory = Split-Path -Parent $OutputPath
if ($outputDirectory) { New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null }
[IO.File]::WriteAllText($OutputPath, $html, [Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    Path = $OutputPath
    Background = $backgroundPath
    Concept = if ($conceptFullPath) { $conceptFullPath } else { '(none)' }
    TextBlocks = @($config.texts).Count
    InstalledFonts = $fontNames.Count
    Bytes = (Get-Item -LiteralPath $OutputPath).Length
} | Format-List
