# main.ps1
# Cargar variables de entorno locales (si existe .env)
$envFile = "$PSScriptRoot\.env"
if (Test-Path $envFile) {
    Get-Content $envFile | Where-Object { $_ -match '^([^#=]+)=(.*)$' } | ForEach-Object {
        $name = $Matches[1].Trim()
        $value = $Matches[2].Trim().Trim('"').Trim("'").Replace("`r", "").Replace("`n", "")
        Set-Item -Path Env:\$name -Value $value
    }
}

$GEMINI_API_KEY = $env:GEMINI_API_KEY
$GITHUB_TOKEN   = $env:PAT_TOKEN
if (-not $GITHUB_TOKEN) { $GITHUB_TOKEN = $env:GITHUB_TOKEN }
$WHATSAPP_PHONE = $env:WHATSAPP_PHONE
$WHATSAPP_APIKEY = $env:WHATSAPP_APIKEY

# Soporte para GitHub Actions
if ($env:GITHUB_REPOSITORY) {
    $parts = $env:GITHUB_REPOSITORY -split "/"
    $GITHUB_USERNAME = $parts[0]
    $GITHUB_REPO     = $parts[1]
} else {
    $GITHUB_USERNAME = $env:GITHUB_USERNAME
    $GITHUB_REPO     = $env:GITHUB_REPO
}

if (-not $GEMINI_API_KEY -or -not $GITHUB_TOKEN -or -not $GITHUB_USERNAME -or -not $GITHUB_REPO -or -not $WHATSAPP_PHONE -or -not $WHATSAPP_APIKEY) {
    Write-Host "Error: Faltan variables de entorno."
    exit 1
}

# ---------------------------------------------------------------
# PASO 1: Buscar noticias recientes
# ---------------------------------------------------------------
$todayDate = Get-Date
$currentDate = $todayDate.ToString("dd/MM/yyyy")
$SearchTerms = @("Google Gemini", "OpenAI", "Anthropic Claude", "Inteligencia Artificial novedades")
$AllNews = @()

Write-Host "Buscando noticias recientes..."
foreach ($term in $SearchTerms) {
    $query = "$term when:1d"
    $encodedTerm = [uri]::EscapeDataString($query)
    $url = 'https://news.google.com/rss/search?q=' + $encodedTerm + '&hl=es-419&gl=US&ceid=US:es-419'
    try {
        $items = Invoke-RestMethod -Uri $url
        if ($null -ne $items) {
            $selected = $items | Select-Object -First 3
            foreach ($item in $selected) {
                if ($item.title -and $item.link) {
                    $AllNews += '- ' + $item.title + "`n  Enlace: " + $item.link
                }
            }
        }
    } catch {
        Write-Host "Error buscando '$term': $_"
    }
}

$NewsText = $AllNews -join "`n`n"
if ([string]::IsNullOrWhiteSpace($NewsText)) {
    Write-Host "Sin resultados con when:1d, probando general..."
    foreach ($term in $SearchTerms) {
        $encodedTerm = [uri]::EscapeDataString($term)
        $url = 'https://news.google.com/rss/search?q=' + $encodedTerm + '&hl=es-419&gl=US&ceid=US:es-419'
        try {
            $items = Invoke-RestMethod -Uri $url
            if ($null -ne $items) {
                $selected = $items | Select-Object -First 2
                foreach ($item in $selected) {
                    if ($item.title -and $item.link) {
                        $AllNews += '- ' + $item.title + "`n  Enlace: " + $item.link
                    }
                }
            }
        } catch {}
    }
    $NewsText = $AllNews -join "`n`n"
}

if ([string]::IsNullOrWhiteSpace($NewsText)) {
    Write-Host "No se encontraron noticias. Saliendo."
    exit 0
}

Write-Host "Total noticias recopiladas: $($AllNews.Count)"

# ---------------------------------------------------------------
# PASO 2: Generar resumen con Gemini
# ---------------------------------------------------------------
Write-Host "Generando resumen con Gemini..."

$prompt = "Eres un experto analista en Inteligencia Artificial. Hoy es $currentDate.`n`nNoticias recientes:`n$NewsText`n`nINSTRUCCIONES IMPORTANTES DE FORMATO (OBLIGATORIO):`n- Responde UNICAMENTE con etiquetas HTML validas: <h2>, <h3>, <p>, <ul>, <li>, <a>`n- NO uses <html>, <head>, <body> ni doctype`n- NO uses bloques markdown ni comillas invertidas`n- Enlaza las fuentes usando <a href='...' target='_blank'>`n- Empieza directamente con el contenido HTML."

$bodyObj = @{
    contents = @(@{ parts = @(@{ text = $prompt }) })
}
$bodyJson  = $bodyObj | ConvertTo-Json -Depth 10
$bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyJson)
$geminiUrl = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=' + $GEMINI_API_KEY

$maxRetries  = 5
$retryCount  = 0
$success     = $false
$summaryHtml = ""

while (-not $success -and $retryCount -lt $maxRetries) {
    try {
        $response    = Invoke-RestMethod -Uri $geminiUrl -Method Post -ContentType "application/json; charset=utf-8" -Body $bodyBytes -TimeoutSec 60
        $summaryHtml = $response.candidates[0].content.parts[0].text
        $summaryHtml = $summaryHtml -replace '(?s)^```html\s*', '' -replace '(?s)\s*```\s*$', ''
        $success     = $true
        Write-Host "Resumen generado con exito por Gemini."
    } catch {
        $retryCount++
        Write-Host "Error Gemini (Intento $retryCount/$maxRetries): $_"
        if ($retryCount -lt $maxRetries) {
            Write-Host "Esperando 20 segundos y reintentando..."
            Start-Sleep -Seconds 20
        } else {
            Write-Host "Fallo critico: se agotaron los reintentos de Gemini."
            exit 1
        }
    }
}

# ---------------------------------------------------------------
# PASO 3: Construir pagina HTML
# ---------------------------------------------------------------
Write-Host "Construyendo pagina web..."
$htmlTemplate = @"
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Resumen Diario de IA - $currentDate</title>
    <style>
        :root {
            --bg-color: #0f172a;
            --text-color: #f8fafc;
            --card-bg: rgba(30, 41, 59, 0.7);
            --accent: #38bdf8;
            --accent-glow: rgba(56, 189, 248, 0.4);
        }
        body {
            background-color: var(--bg-color);
            color: var(--text-color);
            font-family: 'Inter', system-ui, -apple-system, sans-serif;
            margin: 0;
            padding: 2rem 1rem;
            line-height: 1.6;
            min-height: 100vh;
            background-image:
                radial-gradient(at 0% 0%, rgba(15, 23, 42, 1) 0, transparent 50%),
                radial-gradient(at 50% 0%, rgba(56, 189, 248, 0.15) 0, transparent 50%),
                radial-gradient(at 100% 0%, rgba(139, 92, 246, 0.15) 0, transparent 50%);
        }
        .container { max-width: 800px; margin: 0 auto; }
        header { text-align: center; margin-bottom: 3rem; }
        h1 {
            font-size: 2.5rem; font-weight: 800;
            background: linear-gradient(to right, #38bdf8, #8b5cf6);
            -webkit-background-clip: text; -webkit-text-fill-color: transparent;
            margin-bottom: 0.5rem;
        }
        .date { color: #94a3b8; font-size: 1.1rem; }
        .content-card {
            background: var(--card-bg); backdrop-filter: blur(16px);
            -webkit-backdrop-filter: blur(16px);
            border: 1px solid rgba(255, 255, 255, 0.1);
            border-radius: 1.5rem; padding: 2.5rem;
            box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.5);
        }
        h2 { color: #f1f5f9; font-size: 1.5rem; margin-top: 2rem; border-bottom: 1px solid rgba(255,255,255,0.1); padding-bottom: 0.5rem; }
        h2:first-of-type { margin-top: 0; }
        h3 { color: var(--accent); font-size: 1.25rem; margin-top: 1.5rem; }
        a { color: var(--accent); text-decoration: none; transition: all 0.3s ease; font-weight: 600; }
        a:hover { color: #bae6fd; text-shadow: 0 0 8px var(--accent-glow); }
        ul { padding-left: 1.5rem; }
        li { margin-bottom: 1rem; color: #cbd5e1; }
        p { color: #cbd5e1; }
        footer { text-align: center; margin-top: 2rem; color: #475569; font-size: 0.85rem; }
    </style>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;800&display=swap" rel="stylesheet">
</head>
<body>
    <div class="container">
        <header>
            <h1>Resumen de IA</h1>
            <div class="date">$currentDate</div>
        </header>
        <div class="content-card">
            $summaryHtml
        </div>
        <footer>Generado el $currentDate</footer>
    </div>
</body>
</html>
"@

# ---------------------------------------------------------------
# PASO 4: Subir a GitHub Pages
# ---------------------------------------------------------------
Write-Host "Subiendo a GitHub Pages..."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$githubUrl = 'https://api.github.com/repos/' + $GITHUB_USERNAME + '/' + $GITHUB_REPO + '/contents/index.html'
$headers   = @{
    'Authorization' = 'Bearer ' + $GITHUB_TOKEN
    'Accept'        = 'application/vnd.github.v3+json'
}

$sha = $null
try {
    $fileInfo = Invoke-RestMethod -Uri $githubUrl -Headers $headers -Method Get
    $sha = $fileInfo.sha
} catch { }

$base64Content = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($htmlTemplate))
$body = @{
    message = 'Resumen diario IA: ' + $currentDate
    content = $base64Content
}
if ($sha) { $body.sha = $sha }
$jsonBody = $body | ConvertTo-Json

try {
    Invoke-RestMethod -Uri $githubUrl -Headers $headers -Method Put -Body $jsonBody | Out-Null
    Write-Host "Subido exitosamente a GitHub Pages."
} catch {
    Write-Host "Error subiendo a GitHub: $_"
    exit 1
}

# ---------------------------------------------------------------
# PASO 5: Enviar notificacion WhatsApp
# ---------------------------------------------------------------
Write-Host "Enviando notificacion por WhatsApp..."
$pageUrl = 'https://' + $GITHUB_USERNAME + '.github.io/' + $GITHUB_REPO + '/'
$prefixBytes = [Convert]::FromBase64String("8J+kliDCoVR1IHJlc3VtZW4gZGlhcmlvIGRlIElBIGRlbCA=")
$suffixBytes = [Convert]::FromBase64String("IGVzdMOhIGxpc3RvISDwn5qADQpWaXNpdGEgZWwgc2lndWllbnRlIGVubGFjZSBwYXJhIGxlZXJsbyBjb24gZGlzZcOxbyBwcmVtaXVtOg0K")
$prefix = [System.Text.Encoding]::UTF8.GetString($prefixBytes)
$suffix = [System.Text.Encoding]::UTF8.GetString($suffixBytes)
$message = $prefix + $currentDate + $suffix + $pageUrl

$encodedMessage = [uri]::EscapeDataString($message)
$encodedPhone   = [uri]::EscapeDataString($WHATSAPP_PHONE)
$whatsappUrl    = 'https://api.callmebot.com/whatsapp.php?phone=' + $encodedPhone + '&text=' + $encodedMessage + '&apikey=' + $WHATSAPP_APIKEY

try {
    $respWa = Invoke-RestMethod -Uri $whatsappUrl -Method Get
    Write-Host "Respuesta CallMeBot: $respWa"
    Write-Host "WhatsApp enviado exitosamente!"
} catch {
    Write-Host "Error al enviar WhatsApp: $_"
}

Write-Host "Proceso finalizado correctamente. Fecha: $currentDate"
