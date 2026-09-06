# Isolation test results

Test container: `curlimages/curl`, run on `agent-sandbox-net` (internal, no default
route to the internet), with `http_proxy`/`https_proxy` set to `http://agent-proxy:3128`.
`agent-proxy` runs Squid, attached to both `agent-sandbox-net` and `agent-egress-net`,
configured via `network/squid.conf` to allow `CONNECT` only to `api.anthropic.com:443`
and deny everything else.

## Test 1: curl https://api.anthropic.com (allowed destination)

Proves that a sandboxed container with no direct internet access can still reach the
one allowlisted destination by routing through the proxy, and that the full TLS
handshake and HTTP request/response complete end-to-end.

```
* Uses proxy env variable https_proxy == 'http://agent-proxy:3128'
* Host agent-proxy:3128 was resolved.
* IPv6: (none)
* IPv4: 172.18.0.2
*   Trying 172.18.0.2:3128...
* CONNECT: no ALPN negotiated
* Establishing HTTP proxy tunnel to api.anthropic.com:443
> CONNECT api.anthropic.com:443 HTTP/1.1
> Host: api.anthropic.com:443
> User-Agent: curl/8.22.0
> Proxy-Connection: Keep-Alive
> 
< HTTP/1.1 200 Connection established
< 
* CONNECT phase completed for HTTP proxy
* CONNECT tunnel established, response 200
* ALPN: curl offers h2,http/1.1
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
* SSL Trust Anchors:
*   CAfile: /cacert.pem
* TLSv1.3 (IN), TLS handshake, Server hello (2):
* TLSv1.3 (IN), TLS change cipher, Change cipher spec (1):
* TLSv1.3 (IN), TLS handshake, Encrypted Extensions (8):
* TLSv1.3 (IN), TLS handshake, Certificate (11):
* TLSv1.3 (IN), TLS handshake, CERT verify (15):
* TLSv1.3 (IN), TLS handshake, Finished (20):
* TLSv1.3 (OUT), TLS change cipher, Change cipher spec (1):
* TLSv1.3 (OUT), TLS handshake, Finished (20):
* SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384 / X25519MLKEM768 / id-ecPublicKey
* ALPN: server accepted h2
* Server certificate:
*   subject: CN=api.anthropic.com
*   start date: Jul 24 18:00:59 2026 GMT
*   expire date: Oct 22 19:00:52 2026 GMT
*   issuer: C=US; O=Google Trust Services; CN=WE1
*   Certificate level 0: Public key type EC/prime256v1 (256/128 Bits/secBits), signed using ecdsa-with-SHA256
*   Certificate level 1: Public key type EC/prime256v1 (256/128 Bits/secBits), signed using ecdsa-with-SHA384
*   Certificate level 2: Public key type EC/secp384r1 (384/192 Bits/secBits), signed using ecdsa-with-SHA384
*   subjectAltName: "api.anthropic.com" matches cert's "api.anthropic.com"
* OpenSSL verify result: 0
* SSL certificate verified via OpenSSL.
* Established connection to agent-proxy (172.18.0.2 port 3128) from 172.18.0.3 port 37784 
* using HTTP/2
* [HTTP/2] [1] OPENED stream for https://api.anthropic.com/
* [HTTP/2] [1] [:method: GET]
* [HTTP/2] [1] [:scheme: https]
* [HTTP/2] [1] [:authority: api.anthropic.com]
* [HTTP/2] [1] [:path: /]
* [HTTP/2] [1] [user-agent: curl/8.22.0]
* [HTTP/2] [1] [accept: */*]
> GET / HTTP/2
> Host: api.anthropic.com
> User-Agent: curl/8.22.0
> Accept: */*
> 
* Request completely sent off
* TLSv1.3 (IN), TLS handshake, Newsession Ticket (4):
* TLSv1.3 (IN), TLS handshake, Newsession Ticket (4):
 ▐▛███▜▌   Anthropic API
▝▜█████▛▘  POST /v1/messages
  ▘▘ ▝▝    https://docs.anthropic.com
< HTTP/2 404 
< date: Sun, 06 Sep 2026 13:33:26 GMT
< content-type: text/plain
< content-length: 132
< cache-control: private, max-age=0, no-store, no-cache, must-revalidate, post-check=0, pre-check=0
< expires: Thu, 01 Jan 1970 00:00:01 GMT
< referrer-policy: same-origin
< x-frame-options: SAMEORIGIN
< content-security-policy: default-src 'none'; frame-ancestors 'none'
< x-robots-tag: none
< server: cloudflare
< cf-ray: a36dd871aa23863c-DFW
< 
* Connection #0 to host api.anthropic.com:443 left intact
```

The `HTTP/2 404` here is expected — it's Anthropic's API responding to a bare `GET /`
(the API expects `POST /v1/messages`), which confirms the request actually reached
the real service rather than failing before then.

## Test 2: curl https://google.com (disallowed destination)

Proves that the same sandboxed container, using the same proxy, cannot reach any
destination outside the allowlist — Squid rejects the `CONNECT` before a tunnel is
ever established.

```
* Uses proxy env variable https_proxy == 'http://agent-proxy:3128'
* Host agent-proxy:3128 was resolved.
* IPv6: (none)
* IPv4: 172.18.0.2
*   Trying 172.18.0.2:3128...
* CONNECT: no ALPN negotiated
* Establishing HTTP proxy tunnel to google.com:443
> CONNECT google.com:443 HTTP/1.1
> Host: google.com:443
> User-Agent: curl/8.22.0
> Proxy-Connection: Keep-Alive
> 
< HTTP/1.1 403 Forbidden
< Server: squid/6.13
< Mime-Version: 1.0
< Date: Sun, 06 Sep 2026 13:34:10 GMT
< Content-Type: text/html;charset=utf-8
< Content-Length: 3060
< X-Squid-Error: ERR_ACCESS_DENIED 0
< Vary: Accept-Language
< Content-Language: en
< Cache-Status: e07e0ada48c0
< Via: 1.1 e07e0ada48c0 (squid/6.13)
< Connection: keep-alive
< 
* CONNECT tunnel failed, response 403
* closing connection #0
curl: (7) CONNECT tunnel failed, response 403
```
