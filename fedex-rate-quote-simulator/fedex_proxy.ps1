# Tiny local CORS proxy for fedex-rate-quote-simulator.html — no install needed (built-in PowerShell).
# FedEx APIs don't allow browser CORS, so the page calls this proxy and it forwards to FedEx.
# Nothing is logged or stored. Close the window to stop.

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$fedexHosts = @{
    "production" = "https://apis.fedex.com"
    "sandbox"    = "https://apis-sandbox.fedex.com"
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:8765/")
$listener.Start()
Write-Host "FedEx CORS proxy running at http://localhost:8765"
Write-Host "Forwarding to apis.fedex.com / apis-sandbox.fedex.com. Close this window to stop."
Write-Host ""

while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $req = $ctx.Request
    $res = $ctx.Response
    $res.Headers.Add("Access-Control-Allow-Origin", "*")
    $res.Headers.Add("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
    $res.Headers.Add("Access-Control-Allow-Headers", "*")

    if ($req.HttpMethod -eq "OPTIONS") {
        $res.StatusCode = 204
        $res.Close()
        continue
    }

    try {
        $targetEnv = $req.Headers["X-FedEx-Env"]
        if (-not $targetEnv -or -not $fedexHosts.ContainsKey($targetEnv)) { $targetEnv = "production" }
        $target = $fedexHosts[$targetEnv] + $req.Url.PathAndQuery

        $fwd = [System.Net.WebRequest]::Create($target)
        $fwd.Method = $req.HttpMethod
        $fwd.Timeout = 60000
        $fwd.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
        if ($req.ContentType) { $fwd.ContentType = $req.ContentType }
        foreach ($h in @("Authorization", "X-locale")) {
            if ($req.Headers[$h]) { $fwd.Headers.Add($h, $req.Headers[$h]) }
        }
        if ($req.HasEntityBody) {
            $ms = New-Object System.IO.MemoryStream
            $req.InputStream.CopyTo($ms)
            $bytes = $ms.ToArray()
            $fwd.ContentLength = $bytes.Length
            $rs = $fwd.GetRequestStream()
            $rs.Write($bytes, 0, $bytes.Length)
            $rs.Close()
        }

        $fresp = $null
        try {
            $fresp = $fwd.GetResponse()
        } catch {
            $ex = $_.Exception
            while ($ex -and -not ($ex -is [System.Net.WebException])) { $ex = $ex.InnerException }
            if ($ex -and $ex.Response) { $fresp = $ex.Response } else { throw }
        }

        $out = New-Object System.IO.MemoryStream
        $fresp.GetResponseStream().CopyTo($out)
        $data = $out.ToArray()
        $res.StatusCode = [int]$fresp.StatusCode
        if ($fresp.ContentType) { $res.ContentType = $fresp.ContentType }
        $res.ContentLength64 = $data.Length
        $res.OutputStream.Write($data, 0, $data.Length)
        Write-Host ("[proxy] " + $req.HttpMethod + " " + $req.Url.PathAndQuery + " -> " + [int]$fresp.StatusCode)
        $fresp.Close()
    } catch {
        $msg = [System.Text.Encoding]::UTF8.GetBytes("Proxy error: " + $_.Exception.Message)
        $res.StatusCode = 502
        $res.ContentType = "text/plain"
        $res.ContentLength64 = $msg.Length
        $res.OutputStream.Write($msg, 0, $msg.Length)
        Write-Host ("[proxy] error: " + $_.Exception.Message)
    }
    $res.Close()
}
