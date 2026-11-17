# Lab: HTTPS - Creating, Installing & Renewing Certificates (Linux)

**Goal:** Understand how SSL/TLS and HTTPS work, then get hands-on practice creating a private key and CSR, issuing a certificate (both self-signed/self-CA and Let's Encrypt), installing it on a web server (Nginx and Apache), and setting up renewal/expiry monitoring so certificates never silently expire.

**Duration:** ~60-90 minutes

**What you'll learn / do:**
1. SSL/TLS and HTTPS fundamentals (hands-on inspection of a live handshake)
2. Creating certificates and certificate signing requests (CSRs) on Linux
3. Installing certificates on a web server
4. Certificate renewal and expiry handling (manual + automated)

---

## 0. Prerequisites & Setup

### Option A: Docker Compose (Recommended - no VM needed)

Everything is pre-built. Just run:

```powershell
cd labs\https-certificates-linux
docker compose up -d --build
docker compose ps
```

Open a shell inside the container (you'll run commands from here):

```powershell
docker exec -it https-lab bash
```

Sanity-check the toolchain:

```bash
openssl version
nginx -v
apache2 -v
certbot --version
```

Expected output looks like:
```
OpenSSL 3.0.2 15 Mar 2022 (Library: OpenSSL 3.0.2 15 Mar 2022)
nginx version: nginx/1.18.0 (Ubuntu)
Server version: Apache/2.4.52 (Ubuntu)
certbot 1.21.0
```

> **Key difference:** You're root in the container, so **omit `sudo`** from every command below. If you're following on a real VM instead (Option B), prefix each command with `sudo`.

### Option B: Bare Linux VM / Container

If you don't want to use Docker, prepare a fresh Ubuntu/Debian VM/container:

```bash
sudo apt update
sudo apt install -y openssl nginx curl apache2 certbot python3-certbot-nginx
```

Verify your toolchain:

```bash
openssl version
nginx -v
apache2 -v
certbot --version
```

> All commands below use `sudo`. If you're inside a container where you're already root, omit `sudo`.

---

## Part 1 - SSL/TLS and HTTPS Fundamentals

### 1.1 Concepts (read before you run commands)

| Term | What it means |
|---|---|
| **TLS** | Transport Layer Security - the protocol that encrypts traffic between client and server. "SSL" is the old name (SSL 2.0/3.0 are deprecated/insecure); modern deployments use TLS 1.2 or 1.3. |
| **HTTPS** | HTTP running inside a TLS tunnel (default port 443 instead of 80). |
| **Asymmetric (public/private key) crypto** | A key *pair*: the **private key** stays secret on the server; the **public key** is embedded in the certificate and shared with everyone. Data encrypted with the public key can only be decrypted with the private key (and vice versa for signatures). |
| **Symmetric crypto** | Fast encryption using one shared "session key". TLS uses asymmetric crypto only to securely *negotiate* a symmetric session key, then switches to symmetric encryption for the actual data (because it's much faster). |
| **Certificate (cert)** | A signed document binding a public key to an identity (a domain name), issued and digitally signed by a Certificate Authority (CA). |
| **CSR (Certificate Signing Request)** | A request file containing your public key + identity info, which you send to a CA to get a signed certificate. Generated from your private key; the private key itself is never sent anywhere. |
| **CA (Certificate Authority)** | A trusted entity (e.g., Let's Encrypt, DigiCert) that verifies you control a domain and signs a certificate for it. Your OS/browser ships a list of trusted "root CAs". |
| **Chain of trust** | Leaf certificate → Intermediate CA certificate(s) → Root CA certificate. Browsers trust the root; the chain proves the leaf cert was signed (directly or transitively) by that root. |
| **CN / SAN** | Common Name (legacy, single hostname) and Subject Alternative Name (modern, list of hostnames/IPs a cert is valid for). Browsers today **require** SAN - CN alone is ignored. |
| **TLS handshake (simplified)** | 1) Client says hello with supported TLS versions/ciphers. 2) Server replies with its certificate + chosen cipher. 3) Client validates the cert chain against trusted roots, checks hostname/SAN and expiry. 4) Client & server derive a shared symmetric session key (via the key exchange algorithm). 5) Encrypted application data (HTTP) flows. |

### 1.2 Hands-on: Inspect a live HTTPS handshake

Connect to a real site and dump the certificate it presents:

```bash
openssl s_client -connect example.com:443 -servername example.com </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer -dates
```

Expected output (values will vary):
```
subject=CN = example.com
issuer=C = US, O = DigiCert Inc, CN = DigiCert Global G3 TLS ECC SHA384 2020 CA1
notBefore=Jan 15 00:00:00 2025 GMT
notAfter=Feb 15 23:59:59 2026 GMT
```

Look at protocol version, negotiated cipher, and chain depth:

```bash
openssl s_client -connect example.com:443 -servername example.com </dev/null 2>/dev/null | grep -E "Protocol|Cipher|depth|verify"
```

Dump the **entire** certificate (subject, issuer, validity, SANs, public key, signature algorithm):

```bash
openssl s_client -connect example.com:443 -servername example.com </dev/null 2>/dev/null \
  | openssl x509 -noout -text
```

Look specifically for `X509v3 Subject Alternative Name` and `X509v3 Basic Constraints` (`CA:FALSE` on a leaf cert).

**Questions to answer (write down your answers):**
- Who issued this certificate, and is it a root or intermediate CA?
- When does it expire? How many days from today?
- What TLS version and cipher suite were negotiated?
- What hostnames (SANs) is this certificate valid for?

---

## Part 2 - Creating Certificates and CSRs on Linux

### 2.1 Set up a working directory

```bash
mkdir -p /etc/ssl/lab
cd /etc/ssl/lab
```

*(Docker users: omit `sudo`. VM users: `sudo mkdir -p /etc/ssl/lab` then `cd`)*

### 2.2 Generate a private key

RSA 2048-bit (widely compatible):

```bash
openssl genrsa -out lab.key 2048
chmod 600 lab.key
```

> **Modern alternative:** Elliptic-curve keys are smaller and faster:
> ```bash
> openssl ecparam -name prime256v1 -genkey -noout -out lab.key
> ```

Inspect the key you just created:

```bash
openssl rsa -in lab.key -noout -text | head -5
```

### 2.3 Create a CSR config file (recommended over `-subj` for multi-SAN certs)

```bash
cat <<'EOF' > lab-csr.cnf
[req]
default_bits       = 2048
prompt             = no
default_md         = sha256
distinguished_name = dn
req_extensions     = req_ext

[dn]
C  = IN
ST = State
L  = City
O  = Lab
CN = lab.local

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = lab.local
DNS.2 = www.lab.local
EOF
```

### 2.4 Generate the CSR from the key + config

```bash
openssl req -new -key lab.key -out lab.csr -config lab-csr.cnf
```

### 2.5 Verify the CSR

```bash
openssl req -in lab.csr -noout -text
```

Confirm you can see:
- `Subject: ... CN=lab.local`
- `Requested Extensions: X509v3 Subject Alternative Name: DNS:lab.local, DNS:www.lab.local`
- `Signature Algorithm: sha256WithRSAEncryption`

Verify the CSR's public key matches your private key (their hashes must match):

```bash
openssl req -in lab.csr -noout -pubkey | openssl md5
openssl rsa -in lab.key -pubout | openssl md5
```

Both commands should print the **same** hash - proof the CSR was generated from this exact key.

> **Key takeaway:** The CSR (public key + identity) is what you send to a CA. The private key **never leaves the server**.

---

## Part 3 - Issuing a Certificate

You have two realistic paths. Do Option A first (it works fully offline and teaches you how a CA signs things), then read Option B for the real-world production path.

### Option A - Act as your own mini Certificate Authority (recommended for this lab)

This is more realistic than a plain self-signed cert because it mirrors how a real CA signs your CSR.

**1. Create a root CA key and self-signed CA certificate:**

```bash
cd /etc/ssl/lab
openssl genrsa -out ca.key 4096
openssl req -x509 -new -nodes -key ca.key -sha256 -days 3650 -out ca.crt \
  -subj "/C=IN/ST=State/L=City/O=Lab-Root-CA/CN=Lab Root CA"
```

**2. Use the CA to sign your CSR (this issues `lab.crt`):**

```bash
cat <<'EOF' > lab-ext.cnf
subjectAltName = DNS:lab.local,DNS:www.lab.local
basicConstraints = CA:FALSE
keyUsage = digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
EOF

openssl x509 -req -in lab.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out lab.crt -days 397 -sha256 -extfile lab-ext.cnf
```

> `-days 397` matches the current max lifetime browsers enforce for publicly-trusted certs.

**3. Verify the issued certificate and the chain:**

```bash
openssl x509 -in lab.crt -noout -text | grep -A1 "Subject:\|Issuer:\|Subject Alternative Name"
openssl verify -CAfile ca.crt lab.crt
```

Expected: `lab.crt: OK`.

**4. Trust your lab CA locally (optional - so `curl`/browser stop warning):**

```bash
cp ca.crt /usr/local/share/ca-certificates/lab-root-ca.crt
update-ca-certificates
```

### Option B - Real-world production path: Let's Encrypt (free, publicly trusted)

For a real internet-facing domain use ACME via Certbot:

```bash
certbot --nginx -d your.domain -d www.your.domain
```

This needs a publicly resolvable domain pointed at a public IP, so it **won't succeed inside this lab environment** - the command is here so you can read/discuss the flow and try it later against a real domain.

Certbot automatically obtains the cert, edits the Nginx config, and reloads it. Part 4.5 shows how its auto-renewal works.

---

## Part 4 - Installing the Certificate on a Web Server

### 4.1 Nginx

Lock down the key's permissions (private keys should never be world-readable):

```bash
chmod 600 /etc/ssl/lab/lab.key
chown root:root /etc/ssl/lab/lab.key /etc/ssl/lab/lab.crt
```

Create a site config:

```bash
cat <<'EOF' > /etc/nginx/sites-available/lab.local
server {
    listen 443 ssl;
    server_name lab.local www.lab.local;

    ssl_certificate     /etc/ssl/lab/lab.crt;
    ssl_certificate_key /etc/ssl/lab/lab.key;

    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    add_header          Strict-Transport-Security "max-age=63072000" always;

    root /var/www/html;
    index index.html;
}

server {
    listen 80;
    server_name lab.local www.lab.local;
    return 301 https://$host$request_uri;
}
EOF

ln -sf /etc/nginx/sites-available/lab.local /etc/nginx/sites-enabled/lab.local
rm -f /etc/nginx/sites-enabled/default
```

**Always test the config before reloading:**

```bash
nginx -t
```

Expected: `nginx: configuration file /etc/nginx/nginx.conf test is successful`

Start/reload Nginx:

```bash
# Docker users (no systemd):
service nginx start   # or: nginx

# VM users:
sudo systemctl reload nginx
```

Test the HTTP→HTTPS redirect and TLS handshake:

```bash
curl -vk --resolve lab.local:443:127.0.0.1 --resolve lab.local:80:127.0.0.1 http://lab.local
curl -vk --resolve lab.local:443:127.0.0.1 https://lab.local
```

`-k` skips cert trust validation. You should see the `301` redirect on port 80 and, on port 443, the HTML response plus the negotiated protocol/cipher.

Now test **with** validation, using your CA (should succeed without `-k`):

```bash
curl -v --resolve lab.local:443:127.0.0.1 --cacert /etc/ssl/lab/ca.crt https://lab.local
```

Expected: no certificate error, and the page loads.

**From your host machine / browser (optional):**

The compose file publishes container port `443` as host port `8443`. Either add `127.0.0.1 lab.local` to your host's `/etc/hosts` and browse to `https://lab.local:8443`, or test with curl:

```powershell
curl.exe -vk --resolve lab.local:8443:127.0.0.1 https://lab.local:8443
```

### 4.2 Apache (alternative/additional practice)

**Docker users only:** Apache conflicts with Nginx (both want port 443 in the same container). This section shows the workaround.

**VM users:** Skip the port binding change; each service runs on its own box.

#### Docker: Reconfigure for port 8444

Apache's default `ports.conf` tries to bind port 443 (already taken by Nginx). Reconfigure:

```bash
cat <<'EOF' > /etc/apache2/ports.conf
Listen 8444
EOF

a2dissite 000-default
```

#### All users: Configure the SSL site

```bash
cat <<'EOF' > /etc/apache2/sites-available/lab-ssl.conf
<VirtualHost *:8444>
    ServerName lab.local
    ServerAlias www.lab.local
    SSLEngine on
    SSLCertificateFile    /etc/ssl/lab/lab.crt
    SSLCertificateKeyFile /etc/ssl/lab/lab.key
    DocumentRoot /var/www/html
</VirtualHost>
EOF

a2enmod ssl
a2ensite lab-ssl
```

Test and start:

```bash
# Docker users:
apachectl configtest && service apache2 start

# VM users:
sudo apachectl configtest && sudo systemctl reload apache2
```

Test locally:

```bash
curl -vk --resolve lab.local:8444:127.0.0.1 https://lab.local:8444
```

### 4.3 Common installation pitfalls to check

- **Permission denied reading the key:** the web server's worker user (`www-data`) must be able to read `lab.key`; `root:root` + `600` works because the master process starts as root and drops privileges after binding - `nginx -t` surfaces read errors early.
- **SAN/hostname mismatch:** if `curl`/browser complains the cert isn't valid for the requested name, confirm `--resolve`/URL hostname is in the cert's SAN list (Part 2.3).
- **Wrong chain order:** for a CA-issued (not self-signed) cert, `ssl_certificate` must contain the **leaf cert followed by any intermediate certs**, in that order: `cat your_domain.crt intermediate.crt > fullchain.crt`.

---

## Part 5 - Certificate Renewal and Expiry Handling

### 5.1 Check current expiry

```bash
openssl x509 -in /etc/ssl/lab/lab.crt -noout -enddate
```

### 5.2 Scripted expiry check (what monitoring tools do under the hood)

`-checkend <seconds>` returns success only if the cert is valid for at least that many more seconds:

```bash
openssl x509 -in /etc/ssl/lab/lab.crt -noout -checkend $((14*86400)) \
  && echo "OK - valid for 14+ more days" \
  || echo "WARNING - expires within 14 days"
```

Wrap it into a reusable monitoring script:

```bash
cat <<'EOF' > /usr/local/bin/check-cert-expiry.sh
#!/usr/bin/env bash
CERT="/etc/ssl/lab/lab.crt"
DAYS=14
if ! openssl x509 -in "$CERT" -noout -checkend $((DAYS*86400)); then
  echo "[$(date)] ALERT: $CERT expires within $DAYS days!" | tee -a /var/log/cert-check.log
  # In production: send an email/Slack/webhook alert here.
  exit 1
fi
echo "[$(date)] OK: $CERT is valid for more than $DAYS days." >> /var/log/cert-check.log
EOF

chmod +x /usr/local/bin/check-cert-expiry.sh
/usr/local/bin/check-cert-expiry.sh
```

### 5.3 Manual renewal (same key/CSR, re-issue with your mini-CA)

```bash
cd /etc/ssl/lab
openssl x509 -req -in lab.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out lab.crt -days 90 -sha256 -extfile lab-ext.cnf

openssl x509 -in lab.crt -noout -dates

# Reload without dropping connections:
# Docker:
service nginx reload
# VM:
# sudo systemctl reload nginx
```

Confirm the new `notAfter` date is further out, and that the live server now serves the renewed cert:

```bash
echo | openssl s_client -connect 127.0.0.1:443 -servername lab.local 2>/dev/null | openssl x509 -noout -enddate
```

### 5.4 Automate the check with cron

```bash
service cron start   # Docker users: start cron if not already running

( crontab -l 2>/dev/null; echo "0 6 * * * /usr/local/bin/check-cert-expiry.sh" ) | crontab -
crontab -l
```

This runs the expiry check daily at 06:00 and logs to `/var/log/cert-check.log`.

### 5.5 The production path: Certbot auto-renewal

If you had a real domain and ran Option B in Part 3, Certbot installs a renewal timer for you automatically:

```bash
certbot renew --dry-run
cat /etc/cron.d/certbot 2>/dev/null || systemctl list-timers | grep certbot
```

Certbot renews automatically once a certificate is within 30 days of expiry, and reloads the web server for you via a deploy hook - no manual Part 5.3/5.4 steps needed in production.

### 5.6 What happens when a certificate actually expires (see it yourself)

Issue a cert that's already expired to observe client-side failure behavior:

```bash
cd /etc/ssl/lab
openssl x509 -req -in lab.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out lab-expired.crt -days -1 -sha256 -extfile lab-ext.cnf

openssl verify -CAfile ca.crt lab-expired.crt
```

Expected: `error 10 at 0 depth lookup: certificate has expired` - the same error a browser/client surfaces (e.g. `NET::ERR_CERT_DATE_INVALID`) when a site's cert isn't renewed in time. It **hard-blocks** access rather than degrading gracefully - this is why Parts 5.2-5.5 (automated monitoring/renewal) matter.

---

## Troubleshooting Reference

| Symptom | Likely cause | Fix |
|---|---|---|
| `nginx -t` fails with "cannot load certificate" | Wrong path or permissions on `.crt`/`.key` | Check path, `chmod 600` the key, confirm ownership |
| `curl: (60) SSL certificate problem: self signed certificate` | Expected for self-signed/lab CA certs | Use `-k` for testing, or `--cacert ca.crt` to validate properly |
| `curl: (6) Could not resolve host: lab.local` | DNS doesn't know `lab.local` | Use `--resolve lab.local:443:127.0.0.1` instead of editing `/etc/hosts` |
| Browser: `ERR_CERT_COMMON_NAME_INVALID` | Hostname not in SAN list | Regenerate CSR/cert with correct `DNS.x` entries (Part 2.3) |
| `NET::ERR_CERT_DATE_INVALID` | Certificate expired or clock skew | Renew certificate (Part 5.3) |
| `certbot renew` does nothing / "no certificates found" | Expected in this lab - no real domain is configured | Try it against a real domain + public DNS outside this lab |
| `service nginx start` says "already running" | Nginx auto-started or was left from a previous run | `service nginx status`, `service nginx reload` instead |

---

## Checkpoints (self-check before moving on)

- [ ] Can you explain the difference between a private key, a CSR, a certificate, and a chain?
- [ ] Why does TLS use asymmetric crypto only during the handshake, then switch to symmetric encryption?
- [ ] Why run `nginx -t` before every `reload`?
- [ ] What exact error does a client show when a certificate has expired, and why is it a hard failure rather than a warning?
- [ ] What's the difference between the manual renewal you just did and what Certbot automates for you?

---

## Cleanup

### Docker users:

Exit the container and tear down:

```powershell
exit
cd labs\https-certificates-linux
docker compose down -v
```

### VM users:

```bash
sudo rm -f /etc/nginx/sites-enabled/lab.local
sudo systemctl reload nginx
sudo sed -i '/lab.local/d' /etc/hosts
sudo rm -rf /etc/ssl/lab /usr/local/share/ca-certificates/lab-root-ca.crt /usr/local/bin/check-cert-expiry.sh
sudo update-ca-certificates
crontab -l | grep -v check-cert-expiry.sh | crontab -
```
