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
$GITHUB_TOKEN = $env:GITHUB_TOKEN
$WHATSAPP_PHONE = $env:WHATSAPP_PHONE
$WHATSAPP_APIKEY = $env:WHATSAPP_APIKEY

# Soporte para GitHub Actions
if ($env:GITHUB_REPOSITORY) {
    $parts = $env:GITHUB_REPOSITORY -split "/"
    $GITHUB_USERNAME = $parts[0]
    $GITHUB_REPO = $parts[1]
} else {
    $GITHUB_USERNAME = $env:GITHUB_USERNAME
    $GITHUB_REPO = $env:GITHUB_REPO
}

if (-not $GEMINI_API_KEY -or -not $GITHUB_TOKEN -or -not $GITHUB_USERNAME -or -not $GITHUB_REPO -or -not $WHATSAPP_PHONE -or -not $WHATSAPP_APIKEY) {
    Write-Host "Error: Faltan variables de entorno. Asegurese de configurar los Secrets."
    exit 1
}

$SearchTerms = @("Google Gemini when:1d", "OpenAI when:1d", "Anthropic Claude when:1d", "Inteligencia Artificial when:1d")
$AllNews = @()

Write-Host "Buscando noticias..."
foreach ($term in $SearchTerms) {
    $encodedTerm = [uri]::EscapeDataString($term)
    $url = "https://news.google.com/rss/search?q=$encodedTerm&hl=es-419&gl=US&ceid=US:es-419"
    try {
        $xml = Invoke-RestMethod -Uri $url
        if ($null -ne $xml) {
            $items = $xml | Select-Object -First 3
            foreach ($item in $items) {
                if ($item.title -and $item.link) {
                    $AllNews += "- $($item.title)`n  Enlace: $($item.link)"
                }
            }
        }
    } catch {
        Write-Host "Error buscando $term"
    }
}

$NewsText = $AllNews -join "`n`n"
if ([string]::IsNullOrWhiteSpace($NewsText)) {
    Write-Host "No se encontraron noticias."
    exit 0
}

Write-Host "Generando resumen con Gemini..."
$prompt = "Eres un experto analista en Inteligencia Artificial. A continuacion, te proporciono una lista de noticias recientes sobre IA. Por favor, lee los titulares y redacta un boletin diario o resumen ejecutivo. 

INSTRUCCIONES IMPORTANTES DE FORMATO:
Debes responder ÃšNICAMENTE con cÃ³digo HTML (etiquetas <h2>, <h3>, <p>, <ul>, <li>, <a>).
NO uses etiquetas <html>, <head> ni <body>.
NO pongas tu respuesta dentro de un bloque de cÃ³digo markdown (```html). Solo devuelve el texto crudo.
AsegÃºrate de incluir los enlaces a las noticias originales en etiquetas <a>.

Noticias del dia:`n$NewsText"

$bodyObj = @{
    contents = @(
        @{
            parts = @(
                @{ text = $prompt }
            )
        }
    )
}
$bodyJson = $bodyObj | ConvertTo-Json -Depth 10
$bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyJson)

$geminiUrl = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$GEMINI_API_KEY"

try {
    $response = Invoke-RestMethod -Uri $geminiUrl -Method Post -ContentType "application/json; charset=utf-8" -Body $bodyBytes
    $summaryHtml = $response.candidates[0].content.parts[0].text
    # Limpiar si Gemini por error incluyÃ³ bloques markdown
    $summaryHtml = $summaryHtml -replace "^```html`n", "" -replace "`n```$", "" -replace "^````n", ""
} catch {
    Write-Host "Error al llamar a Gemini: $_"
    exit 1
}

Write-Host "Construyendo pagina web..."
$currentDate = Get-Date -Format "dd/MM/yyyy"
$htmlTemplate = @"
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Resumen Diario de IA</title>
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
        .container {
            max-width: 800px;
            margin: 0 auto;
        }
        header {
            text-align: center;
            margin-bottom: 3rem;
            animation: fadeInDown 1s ease-out;
        }
        h1 {
            font-size: 2.5rem;
            font-weight: 800;
            background: linear-gradient(to right, #38bdf8, #8b5cf6);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            margin-bottom: 0.5rem;
        }
        .date {
            color: #94a3b8;
            font-size: 1.1rem;
        }
        .content-card {
            background: var(--card-bg);
            backdrop-filter: blur(16px);
            -webkit-backdrop-filter: blur(16px);
            border: 1px solid rgba(255, 255, 255, 0.1);
            border-radius: 1.5rem;
            padding: 2.5rem;
            box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.5);
            animation: fadeInUp 1s ease-out;
        }
        h2 { color: #f1f5f9; font-size: 1.5rem; margin-top: 2rem; border-bottom: 1px solid rgba(255,255,255,0.1); padding-bottom: 0.5rem;}
        h2:first-of-type { margin-top: 0; }
        h3 { color: var(--accent); font-size: 1.25rem; margin-top: 1.5rem; }
        a {
            color: var(--accent);
            text-decoration: none;
            transition: all 0.3s ease;
            font-weight: 600;
        }
        a:hover {
            color: #bae6fd;
            text-shadow: 0 0 8px var(--accent-glow);
        }
        ul { padding-left: 1.5rem; }
        li { margin-bottom: 1rem; color: #cbd5e1; }
        p { color: #cbd5e1; }
        @keyframes fadeInDown {
            from { opacity: 0; transform: translateY(-20px); }
            to { opacity: 1; transform: translateY(0); }
        }
        @keyframes fadeInUp {
            from { opacity: 0; transform: translateY(20px); }
            to { opacity: 1; transform: translateY(0); }
        }
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
    </div>
</body>
</html>
"@

Write-Host "Subiendo a GitHub Pages..."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$githubUrl = "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPO/contents/index.html"
$headers = @{
    "Authorization" = "Bearer $GITHUB_TOKEN"
    "Accept" = "application/vnd.github.v3+json"
}

$sha = $null
try {
    $fileInfo = Invoke-RestMethod -Uri $githubUrl -Headers $headers -Method Get
    $sha = $fileInfo.sha
} catch { }

$base64Content = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($htmlTemplate))
$body = @{
    message = "Actualizacion automatica de noticias: $currentDate"
    content = $base64Content
}
if ($sha) { $body.sha = $sha }
$jsonBody = $body | ConvertTo-Json

try {
    Invoke-RestMethod -Uri $githubUrl -Headers $headers -Method Put -Body $jsonBody | Out-Null
    Write-Host "Subido exitosamente."
} catch {
    Write-Host "Error subiendo a GitHub: $_"
    exit 1
}

Write-Host "Enviando notificacion por WhatsApp..."
$pageUrl = "https://$GITHUB_USERNAME.github.io/$GITHUB_REPO/"
$msgBase64 = "8J+kliDCoVR1IHJlc3VtZW4gZGlhcmlvIGRlIElBIGVzdMOhIGxpc3RvISDwn5qADQpWaXNpdGEgZWwgc2lndWllbnRlIGVubGFjZSBwYXJhIGxlZXJsbyBjb24gZGlzZcOxbyBwcmVtaXVtOg0K"
$message = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($msgBase64)) + $pageUrl
$encodedMessage = [uri]::EscapeDataString($message)
$encodedPhone = [uri]::EscapeDataString($WHATSAPP_PHONE)
$whatsappUrl = "https://api.callmebot.com/whatsapp.php?phone=$encodedPhone&text=$encodedMessage&apikey=$WHATSAPP_APIKEY"

try {
    Invoke-RestMethod -Uri $whatsappUrl -Method Get | Out-Null
    Write-Host "WhatsApp enviado!"
} catch {
    Write-Host "Error al enviar WhatsApp: $_"
}
Write-Host "Proceso finalizado."
