# Same-host Rust edge real-IP trust

This configuration targets `L4_Proxy/deploy/rust.compose.yml` and
`L4_Proxy/configs/edge.toml`: the host-network Rust edge terminates TLS,
replaces client-supplied `X-Real-IP` with the TCP peer IP, and forwards to
`127.0.0.1:8081` (web) or `127.0.0.1:8082` (app).

L7 publishes these ports on loopback only. Its dedicated Docker bridge has
gateway `172.30.79.1`; only that exact address may supply `X-Real-IP`.
The restored `$remote_addr` is used by Swagger access control, logs and rate
limits. Arbitrary `X-Forwarded-For` is not trusted. All local host processes
remain within the trust boundary. Keep host firewall/security groups closed
for direct external access to L7 ports and bridge/container addresses.

Before deployment, ensure `172.30.79.0/24` does not overlap existing Docker,
VPN or VPC routes. Change Compose and `real_ip.conf` together if necessary.
Existing Compose networks must be recreated for the IPAM change; a container
restart alone does not update the network. Plan downtime for network recreation.

Verify on the Linux deployment host that a request through the Rust edge logs
the client's actual IP. The original gateway peer is available through
`$realip_remote_addr` for diagnostics. Do not broaden trust if the observed
address differs: inspect the deployed Docker networking first.

Swagger requests from `34.127.98.202` must pass IP filtering; another source
must receive 403 even if it supplies `X-Real-IP: 34.127.98.202` to the public
edge. PingCha or application authentication may still apply after IP filtering.

The legacy HAProxy TLS-passthrough/PROXY-v2 configuration in L4_Proxy is a
different deployment path and is not covered by this X-Real-IP setup. It needs
PROXY-protocol listeners and exact peer trust configured together, not blind
trust in HTTP headers.
