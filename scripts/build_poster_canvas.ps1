param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,
    [string]$OutputPath = '',
    [string]$ConceptPath = '',
    [switch]$Serve,
    [int]$Port = 0,
    [int]$TimeoutMinutes = 30,
    [string]$SaveConfigPath = '',
    [switch]$NoBrowser
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

function Write-PosterCanvasResponse(
    [System.Net.HttpListenerResponse]$Response,
    [int]$Status,
    [string]$ContentType,
    [string]$Body
) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Body)
    $Response.StatusCode = $Status
    $Response.ContentType = $ContentType
    $Response.ContentLength64 = $bytes.Length
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.Close()
}

function Receive-PosterCanvasEdit([string]$Html, [int]$Port, [int]$TimeoutMinutes, [bool]$OpenBrowser) {
    if ($Port -le 0) {
        $probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $probe.Start()
        $Port = $probe.LocalEndpoint.Port
        $probe.Stop()
    }

    $url = "http://localhost:$Port/"
    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add($url)
    try {
        $listener.Start()
    }
    catch {
        throw "Could not serve the canvas on $url. Choose a free port with -Port. $($_.Exception.Message)"
    }

    Write-Host "Review canvas is live at $url"
    Write-Host "Waiting up to $TimeoutMinutes minute(s) for the reviewer to press the save button."
    if ($OpenBrowser) { Start-Process $url | Out-Null }

    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $saved = $null
    try {
        while ($true) {
            $remaining = [int][Math]::Ceiling(($deadline - (Get-Date)).TotalMilliseconds)
            if ($remaining -le 0) {
                Write-Warning 'Timed out before the reviewer saved. The config on disk is unchanged.'
                break
            }

            $pending = $listener.GetContextAsync()
            if (-not $pending.Wait($remaining)) {
                Write-Warning 'Timed out before the reviewer saved. The config on disk is unchanged.'
                break
            }

            $context = $pending.Result
            $request = $context.Request
            $path = $request.Url.AbsolutePath

            if ($request.HttpMethod -eq 'POST' -and $path -eq '/save') {
                if ($request.ContentLength64 -gt 4MB) {
                    Write-PosterCanvasResponse $context.Response 413 'text/plain; charset=utf-8' 'Config payload is too large.'
                    continue
                }
                $reader = [IO.StreamReader]::new($request.InputStream, [Text.Encoding]::UTF8)
                try { $body = $reader.ReadToEnd() } finally { $reader.Dispose() }

                # Never write a payload back to disk before it parses and looks like a poster config.
                try { $parsed = $body | ConvertFrom-Json }
                catch {
                    Write-PosterCanvasResponse $context.Response 400 'text/plain; charset=utf-8' 'Payload was not valid JSON.'
                    continue
                }
                if (-not $parsed.canvas -or -not $parsed.texts) {
                    Write-PosterCanvasResponse $context.Response 400 'text/plain; charset=utf-8' 'Payload is missing canvas or texts.'
                    continue
                }

                Write-PosterCanvasResponse $context.Response 200 'application/json; charset=utf-8' '{"ok":true}'
                $saved = $body
                break
            }
            elseif ($request.HttpMethod -eq 'POST' -and $path -eq '/cancel') {
                Write-PosterCanvasResponse $context.Response 200 'application/json; charset=utf-8' '{"ok":true}'
                Write-Host 'Reviewer closed the canvas without saving.'
                break
            }
            elseif ($path -eq '/favicon.ico') {
                Write-PosterCanvasResponse $context.Response 404 'text/plain; charset=utf-8' 'no icon'
            }
            else {
                Write-PosterCanvasResponse $context.Response 200 'text/html; charset=utf-8' $Html
            }
        }
    }
    finally {
        $listener.Stop()
        $listener.Close()
    }
    return $saved
}

function Get-PosterCanvasChanges($Before, $After) {
    $beforeTexts = @($Before.texts)
    $afterTexts = @($After.texts)
    $rows = [System.Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $afterTexts.Count; $index++) {
        $new = $afterTexts[$index]
        $old = if ($index -lt $beforeTexts.Count) { $beforeTexts[$index] } else { $null }
        $changes = [System.Collections.Generic.List[string]]::new()
        foreach ($key in 'id', 'text', 'fontFamily', 'style', 'lineHeight', 'size', 'color', 'x', 'y', 'width', 'height', 'align', 'valign') {
            $oldValue = if ($old) { [string]$old.$key } else { '(new block)' }
            $newValue = [string]$new.$key
            if ($oldValue -eq $newValue) { continue }
            if ($key -eq 'text') {
                # Windows PowerShell writes redirected stdout in the system codepage, so echoing
                # the copy here would reach the agent as mojibake. The saved config is UTF-8.
                $changes.Add('text edited (read the saved config for the wording)')
            }
            else {
                $changes.Add("$key $oldValue -> $newValue")
            }
        }
        if ($changes.Count -gt 0) {
            $rows.Add([pscustomobject]@{
                Block = if ([string]::IsNullOrWhiteSpace([string]$new.id)) { "#$index" } else { [string]$new.id }
                Changed = ($changes -join '; ')
            })
        }
    }
    if ($afterTexts.Count -lt $beforeTexts.Count) {
        $rows.Add([pscustomobject]@{ Block = '(removed)'; Changed = "$($beforeTexts.Count - $afterTexts.Count) block(s) deleted in the canvas" })
    }
    return $rows
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

if ([string]::IsNullOrWhiteSpace($SaveConfigPath)) {
    $SaveConfigPath = $configFullPath
}
else {
    $SaveConfigPath = Resolve-ConfigPath $SaveConfigPath $baseDirectory
}

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
.stage{display:flex;align-items:flex-start;justify-content:center;overflow:auto}.poster{position:relative;width:min(88vh,100%);container-type:inline-size;flex:none;background:#fff;box-shadow:0 16px 50px #17203326;background-size:100% 100%;background-repeat:no-repeat;touch-action:none}
.shape,.text{position:absolute}.text{display:flex;white-space:pre;overflow:visible;outline:1px dashed #1d6ee899;outline-offset:-1px;cursor:move;user-select:none}.text.overflow{outline:4px solid #d62f2f;background:#d62f2f12}.selected{outline:3px solid #1d6ee8;outline-offset:2px}.selected.overflow{outline:4px solid #d62f2f}
.text::after{content:attr(data-label);position:absolute;left:0;top:-18px;font:700 11px/1.4 "Microsoft JhengHei",sans-serif;color:#fff;background:#1d6ee8;padding:3px 6px;border-radius:4px;white-space:nowrap;opacity:0;pointer-events:none;transition:opacity .1s}
.text:hover::after,.text.selected::after{opacity:1}
.handle{position:absolute;right:-8px;bottom:-8px;width:16px;height:16px;background:#1d6ee8;border:2px solid #fff;border-radius:4px;cursor:nwse-resize}
.concept{position:absolute;inset:0;background-size:100% 100%;background-repeat:no-repeat;pointer-events:none}.concept.diff{mix-blend-mode:difference}
.measure{position:absolute;border:2px solid #f08c00;background:#f08c0022;pointer-events:none}
.poster.measuring{cursor:crosshair}.poster.measuring .text{pointer-events:none}
.panel{position:sticky;top:20px;align-self:start;background:#fff;border-radius:16px;padding:18px;box-shadow:0 10px 30px #1720331a;max-height:calc(100vh - 40px);overflow:auto}
h1{font-size:20px;margin:0 0 8px}.hint{font-size:13px;color:#647087;margin:0 0 16px;line-height:1.6}.field{margin:12px 0}.field label{display:block;font-size:12px;font-weight:700;margin-bottom:5px}.field input,.field select,.field textarea{width:100%;padding:8px;border:1px solid #cbd2dc;border-radius:7px;background:#fff}.field input[type=checkbox]{width:auto;padding:0;margin-right:6px}.field input[readonly]{background:#f2f5f9;color:#647087}.row{display:grid;grid-template-columns:1fr 1fr;gap:8px}.actions{display:flex;gap:8px;margin-top:14px}.actions button{flex:1;border:0;border-radius:8px;padding:10px 12px;background:#172033;color:#fff;cursor:pointer;font-size:13px}.actions button.secondary{background:#e7ebf1;color:#172033}
.onion{background:#f5f8fc;border:1px solid #dbe3ec;border-radius:10px;padding:2px 12px 10px;margin-bottom:6px}
@media(max-width:900px){.app{grid-template-columns:1fr}.panel{position:relative;top:auto}.poster{width:min(88vw,720px)}}
</style>
</head>
<body>
<main class="app"><section class="stage"><div id="poster" class="poster"></div></section><aside class="panel">
<h1>A4 海報排版畫布</h1><p class="hint">點選方框即選取；拖曳可移動，拉右下角藍點可改尺寸，方向鍵微調 1px、Shift+方向鍵 10px。紅框＝瀏覽器預覽已溢出。量測模式可直接在海報上框出面板內緣，再一鍵套用成文字方框。改完按<b>複製 JSON</b>貼回設定檔，仍須以正式 renderer 驗證。</p>
<div id="onionRow" class="onion" hidden><div class="field"><label for="onion">概念圖疊圖 <span id="onionValue">0</span>%</label><input id="onion" type="range" min="0" max="100" value="0"></div><div class="field"><label for="onionDiff"><input id="onionDiff" type="checkbox">差異模式（重疊處變黑即為對齊）</label></div></div>
<div class="onion"><div class="field"><label for="measure"><input id="measure" type="checkbox">量測模式（在海報上拖曳框選）</label></div>
<div class="row"><div class="field"><label for="mx">量測 X</label><input id="mx" type="number" readonly></div><div class="field"><label for="my">量測 Y</label><input id="my" type="number" readonly></div></div>
<div class="row"><div class="field"><label for="mw">量測寬</label><input id="mw" type="number" readonly></div><div class="field"><label for="mh">量測高</label><input id="mh" type="number" readonly></div></div>
<div class="actions"><button id="applyMeasure">套用到選取方框</button><button id="clearMeasure" class="secondary">清除</button></div></div>
<div class="field"><label for="block">文字區塊</label><select id="block"></select></div>
<div class="field"><label for="text">文字</label><textarea id="text" rows="4"></textarea></div>
<div class="field"><label for="font">本機字型</label><select id="font"></select></div>
<div class="row"><div class="field"><label for="style">字型樣式</label><select id="style"><option>Regular</option><option>Bold</option><option>Italic</option><option>Bold, Italic</option></select></div><div class="field"><label for="lineHeight">行高倍數</label><input id="lineHeight" type="number" min="0.5" step="0.01"></div></div>
<div class="row"><div class="field"><label for="size">字級 px</label><input id="size" type="number"></div><div class="field"><label for="color">顏色</label><input id="color" type="color"></div></div>
<div class="row"><div class="field"><label for="x">X</label><input id="x" type="number"></div><div class="field"><label for="y">Y</label><input id="y" type="number"></div></div>
<div class="row"><div class="field"><label for="width">寬度</label><input id="width" type="number"></div><div class="field"><label for="height">高度</label><input id="height" type="number"></div></div>
<div class="row"><div class="field"><label for="align">水平</label><select id="align"><option>near</option><option>center</option><option>far</option></select></div><div class="field"><label for="valign">垂直</label><select id="valign"><option>near</option><option>center</option><option>far</option></select></div></div>
<div class="actions" id="serveRow" hidden><button id="save">儲存並回傳 agent</button><button id="cancel" class="secondary">不存離開</button></div>
<p id="serveStatus" class="hint" hidden></p>
<div class="actions"><button id="copy">複製 JSON</button><button id="download" class="secondary">下載</button><button id="reset" class="secondary">還原</button></div>
</aside></main>
<script>
const decode=b64=>JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(b64),c=>c.charCodeAt(0))));
const original=decode('__CONFIG_BASE64__');let config=structuredClone(original);const fonts=decode('__FONTS_BASE64__');const bg='__BACKGROUND_DATA_URI__';const concept='__CONCEPT_DATA_URI__';
const poster=document.querySelector('#poster'),blockSelect=document.querySelector('#block');
const onionRow=document.querySelector('#onionRow'),onion=document.querySelector('#onion'),onionDiff=document.querySelector('#onionDiff'),onionValue=document.querySelector('#onionValue');
const measureMode=document.querySelector('#measure'),mx=document.querySelector('#mx'),my=document.querySelector('#my'),mw=document.querySelector('#mw'),mh=document.querySelector('#mh');
const fields=['text','font','style','lineHeight','size','color','x','y','width','height','align','valign'];const el=Object.fromEntries(fields.map(id=>[id,document.querySelector('#'+id)]));
const pct=(n,total)=>`${100*n/total}%`;const cqw=(n,total)=>`${100*n/total}cqw`;const cssColor=v=>v&&v.length===9?`#${v.slice(3,9)}${v.slice(1,3)}`:v;const hAlign={near:'flex-start',center:'center',far:'flex-end'};const vAlign={near:'flex-start',center:'center',far:'flex-end'};
const canvasWidth=()=>config.canvas?.width||2480;const canvasHeight=()=>config.canvas?.height||3508;
const selected=()=>config.texts?.[Number(blockSelect.value)||0];
let measured=null;
function render(){const w=canvasWidth(),h=canvasHeight();poster.style.aspectRatio=`${w}/${h}`;poster.style.backgroundImage=`url(${JSON.stringify(bg)})`;poster.classList.toggle('measuring',measureMode.checked);poster.innerHTML='';
 (config.roundedRectangles||[]).forEach(s=>{const d=document.createElement('div');d.className='shape';Object.assign(d.style,{left:pct(s.x,w),top:pct(s.y,h),width:pct(s.width,w),height:pct(s.height,h),borderRadius:pct(s.radius,s.width),background:cssColor(s.fill)});poster.appendChild(d)});
 (config.texts||[]).forEach((t,i)=>{const isSelected=i===blockSelect.selectedIndex;const d=document.createElement('div');d.className='text'+(isSelected?' selected':'');d.dataset.index=i;d.dataset.label=t.id||t.text.slice(0,10)||`文字 ${i+1}`;d.textContent=t.text;Object.assign(d.style,{left:pct(t.x,w),top:pct(t.y,h),width:pct(t.width,w),height:pct(t.height,h),fontFamily:`${JSON.stringify(t.fontFamily||config.fontFamily)},sans-serif`,fontSize:cqw(t.size,w),lineHeight:String(t.lineHeight||1.15),color:cssColor(t.color),fontWeight:(t.style||'').toLowerCase().includes('bold')?'700':'400',fontStyle:(t.style||'').toLowerCase().includes('italic')?'italic':'normal',textAlign:t.align==='center'?'center':t.align==='far'?'right':'left',justifyContent:hAlign[t.align||'near'],alignItems:vAlign[t.valign||'near']});
  if(isSelected){const g=document.createElement('div');g.className='handle';d.appendChild(g)}
  poster.appendChild(d);requestAnimationFrame(()=>d.classList.toggle('overflow',d.scrollWidth>d.clientWidth+1||d.scrollHeight>d.clientHeight+1))});
 if(measured){const m=document.createElement('div');m.className='measure';Object.assign(m.style,{left:pct(measured.x,w),top:pct(measured.y,h),width:pct(measured.width,w),height:pct(measured.height,h)});poster.appendChild(m)}
 if(concept){const c=document.createElement('div');c.className='concept'+(onionDiff.checked?' diff':'');c.style.backgroundImage=`url(${JSON.stringify(concept)})`;c.style.opacity=onionDiff.checked?'1':String(onion.value/100);poster.appendChild(c)}
}
function fillSelects(){blockSelect.innerHTML='';(config.texts||[]).forEach((t,i)=>blockSelect.add(new Option(t.id||t.text.slice(0,20)||`文字 ${i+1}`,i)));el.font.innerHTML='';fonts.forEach(f=>el.font.add(new Option(f,f)))}
function loadBlock(){const t=selected();if(!t)return;el.text.value=t.text;el.font.value=t.fontFamily||config.fontFamily;el.style.value=t.style||'Regular';el.lineHeight.value=t.lineHeight||1.15;['size','x','y','width','height','align','valign'].forEach(k=>el[k].value=t[k]);el.color.value=cssColor(t.color).slice(0,7)}
function update(){const t=selected();if(!t)return;t.text=el.text.value;t.fontFamily=el.font.value;t.style=el.style.value;['lineHeight','size','x','y','width','height'].forEach(k=>t[k]=Number(el[k].value));['color','align','valign'].forEach(k=>t[k]=el[k].value);render()}
function moveSelected(dx,dy){const t=selected();if(!t)return;t.x=Math.round(t.x+dx);t.y=Math.round(t.y+dy);el.x.value=t.x;el.y.value=t.y;render()}
function showMeasure(){[mx,my,mw,mh].forEach((f,i)=>f.value=measured?[measured.x,measured.y,measured.width,measured.height][i]:'')}
const toCanvas=e=>{const r=poster.getBoundingClientRect(),k=canvasWidth()/r.width;return{x:Math.round((e.clientX-r.left)*k),y:Math.round((e.clientY-r.top)*k)}};
let drag=null;
poster.addEventListener('pointerdown',e=>{
 if(measureMode.checked){const p=toCanvas(e);drag={mode:'measure',ox:p.x,oy:p.y};measured={x:p.x,y:p.y,width:0,height:0};showMeasure();render();poster.setPointerCapture(e.pointerId);e.preventDefault();return}
 const d=e.target.closest('.text');if(!d)return;const i=Number(d.dataset.index);
 blockSelect.selectedIndex=i;loadBlock();
 const t=config.texts[i];drag={mode:e.target.closest('.handle')?'resize':'move',i,k:canvasWidth()/poster.getBoundingClientRect().width,sx:e.clientX,sy:e.clientY,ox:t.x,oy:t.y,ow:t.width,oh:t.height};
 render();poster.setPointerCapture(e.pointerId);e.preventDefault()});
poster.addEventListener('pointermove',e=>{if(!drag)return;
 if(drag.mode==='measure'){const p=toCanvas(e);measured={x:Math.min(p.x,drag.ox),y:Math.min(p.y,drag.oy),width:Math.abs(p.x-drag.ox),height:Math.abs(p.y-drag.oy)};showMeasure();render();return}
 const t=config.texts[drag.i];const dx=(e.clientX-drag.sx)*drag.k,dy=(e.clientY-drag.sy)*drag.k;
 if(drag.mode==='resize'){t.width=Math.max(1,Math.round(drag.ow+dx));t.height=Math.max(1,Math.round(drag.oh+dy));el.width.value=t.width;el.height.value=t.height}
 else{t.x=Math.round(drag.ox+dx);t.y=Math.round(drag.oy+dy);el.x.value=t.x;el.y.value=t.y}
 render()});
poster.addEventListener('pointerup',()=>{drag=null});poster.addEventListener('pointercancel',()=>{drag=null});
document.addEventListener('keydown',e=>{if(!e.key.startsWith('Arrow'))return;if(/^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement.tagName))return;
 const s=e.shiftKey?10:1;const map={ArrowLeft:[-s,0],ArrowRight:[s,0],ArrowUp:[0,-s],ArrowDown:[0,s]}[e.key];
 if(!map)return;moveSelected(map[0],map[1]);e.preventDefault()});
blockSelect.onchange=()=>{loadBlock();render()};fields.forEach(k=>el[k].oninput=update);
onion.oninput=()=>{onionValue.textContent=onion.value;render()};onionDiff.onchange=render;measureMode.onchange=render;
document.querySelector('#applyMeasure').onclick=()=>{const t=selected();if(!t||!measured||!measured.width||!measured.height)return;Object.assign(t,{x:measured.x,y:measured.y,width:measured.width,height:measured.height});loadBlock();render()};
document.querySelector('#clearMeasure').onclick=()=>{measured=null;showMeasure();render()};
document.querySelector('#reset').onclick=()=>{config=structuredClone(original);measured=null;showMeasure();fillSelects();loadBlock();render()};
const jsonText=()=>JSON.stringify(config,null,2);
document.querySelector('#copy').onclick=async ev=>{const s=jsonText(),b=ev.currentTarget;
 try{await navigator.clipboard.writeText(s)}catch{const ta=document.createElement('textarea');ta.value=s;document.body.appendChild(ta);ta.select();document.execCommand('copy');ta.remove()}
 b.textContent='已複製到剪貼簿';setTimeout(()=>b.textContent='複製 JSON',1200)};
document.querySelector('#download').onclick=()=>{const blob=new Blob([jsonText()],{type:'application/json'});const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download='poster-config-reviewed.json';a.click();setTimeout(()=>URL.revokeObjectURL(a.href),1000)};
if(concept)onionRow.hidden=false;
if(__SERVE__){
 const status=document.querySelector('#serveStatus'),saveBtn=document.querySelector('#save');
 const say=(m,ok)=>{status.hidden=false;status.textContent=m;status.style.color=ok?'#1a7f37':'#d62f2f'};
 document.querySelector('.hint').insertAdjacentHTML('beforeend','<br><b>改完按「儲存並回傳 agent」</b>，設定會寫回檔案並交還 agent 繼續。');
 document.querySelector('#serveRow').hidden=false;
 saveBtn.onclick=async()=>{saveBtn.disabled=true;saveBtn.textContent='回傳中…';
  try{const r=await fetch('/save',{method:'POST',headers:{'Content-Type':'application/json'},body:jsonText()});
   if(!r.ok)throw new Error(await r.text());
   saveBtn.textContent='已回傳';say('已回傳 agent，可以關閉這個分頁。',true)}
  catch(err){saveBtn.disabled=false;saveBtn.textContent='儲存並回傳 agent';say('回傳失敗：'+err.message,false)}};
 document.querySelector('#cancel').onclick=async()=>{
  try{await fetch('/cancel',{method:'POST'})}catch(err){}
  saveBtn.disabled=true;say('已結束，未儲存。可以關閉這個分頁。',true)};
}
fillSelects();loadBlock();render();
</script>
</body></html>
'@

$html = $htmlTemplate.Replace('__CONFIG_BASE64__', $configBase64).Replace('__FONTS_BASE64__', $fontsBase64).Replace('__BACKGROUND_DATA_URI__', $backgroundDataUri).Replace('__CONCEPT_DATA_URI__', $conceptDataUri)
$outputDirectory = Split-Path -Parent $OutputPath
if ($outputDirectory) { New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null }
# The saved file has no server to post to, so only the served copy gets the save button.
[IO.File]::WriteAllText($OutputPath, $html.Replace('__SERVE__', 'false'), [Text.UTF8Encoding]::new($false))

$savedConfig = $null
if ($Serve) {
    $savedConfig = Receive-PosterCanvasEdit $html.Replace('__SERVE__', 'true') $Port $TimeoutMinutes (-not $NoBrowser)
}

[pscustomobject]@{
    Path = $OutputPath
    Background = $backgroundPath
    Concept = if ($conceptFullPath) { $conceptFullPath } else { '(none)' }
    TextBlocks = @($config.texts).Count
    InstalledFonts = $fontNames.Count
    Bytes = (Get-Item -LiteralPath $OutputPath).Length
    Saved = if ($savedConfig) { $SaveConfigPath } elseif ($Serve) { '(reviewer did not save)' } else { '(not served)' }
} | Format-List

if ($savedConfig) {
    # Write the reviewed payload verbatim: a ConvertTo-Json round trip would reorder keys
    # and rewrite every number the reviewer just tuned.
    [IO.File]::WriteAllText($SaveConfigPath, $savedConfig, [Text.UTF8Encoding]::new($false))
    $changes = @(Get-PosterCanvasChanges $config ($savedConfig | ConvertFrom-Json))
    if ($changes.Count -eq 0) {
        Write-Host 'Reviewer saved without changing any text block.'
    }
    else {
        Write-Host "Reviewer changed $($changes.Count) text block(s):"
        $changes | Format-Table -AutoSize -Wrap
    }
    Write-Host 'Re-render and re-verify before treating this layout as final.'
}
