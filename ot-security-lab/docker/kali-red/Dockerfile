# kali-red — OT/ICS red-team rig
#
# Build:
#   docker build -t kali-red:latest .
#
# Run (use scripts/start-kali-red.sh from repo root for the canonical invocation):
#   docker run -d --name kali-red \
#     --network host \
#     --cap-add=NET_RAW --cap-add=NET_ADMIN \
#     -v "$HOME/engagements:/engagements" \
#     --restart unless-stopped \
#     kali-red:latest sleep infinity

FROM kali:latest

ENV DEBIAN_FRONTEND=noninteractive

# Core network arsenal + ICS-relevant generalist tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    nmap masscan hping3 \
    tcpdump tshark \
    netcat-traditional socat \
    ettercap-text-only bettercap \
    tcpreplay dsniff \
    hydra nikto sqlmap \
    metasploit-framework \
    snmp snmp-mibs-downloader \
    exploitdb \
    git curl wget vim less iputils-ping \
    python3 python3-pip python3-venv \
    build-essential \
    ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Python ICS stack
RUN pip3 install --break-system-packages --no-cache-dir \
    pymodbus \
    pysnmp \
    scapy \
    cpppo \
    opcua \
    python-snap7 \
    boofuzz

# Specialized ICS tools (best-effort clones; upstream repos occasionally rot)
RUN git clone --depth 1 https://github.com/dark-lbp/isf       /opt/isf          || true
RUN git clone --depth 1 https://github.com/meeas/plcscan       /opt/plcscan      || true
RUN git clone --depth 1 https://github.com/tijldeneut/ICSSecurityScripts /opt/ics-scripts || true

# Helpful shell defaults
RUN echo 'export PS1="\[\e[31m\]kali-red\[\e[0m\]:\w# "' >> /root/.bashrc \
 && echo 'cd /engagements 2>/dev/null || cd /root' >> /root/.bashrc

WORKDIR /engagements

CMD ["bash"]
