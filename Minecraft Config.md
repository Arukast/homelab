### **1\. Systemd Service Configuration**

**Path:** `/etc/systemd/system/minecraft.service`

Ini, TOML  
\[Unit\]  
Description=Minecraft Purpur 26.x Server  
After=network.target

\[Service\]  
Type=forking  
User=minecraft  
Group=minecraft  
WorkingDirectory=/opt/minecraft

\# Java 25 with Aikar's Optimized Flags  
ExecStart=/usr/bin/tmux new-session \-s mc-session \-d '/usr/bin/java \-Xms3G \-Xmx3G \-XX:+UseG1GC \-XX:+ParallelRefProcEnabled \-XX:MaxGCPauseMillis=200 \-XX:+UnlockExperimentalVMOptions \-XX:+DisableExplicitGC \-XX:+AlwaysPreTouch \-XX:G1NewSizePercent=30 \-XX:G1MaxNewSizePercent=40 \-XX:G1HeapRegionSize=8M \-XX:G1ReservePercent=20 \-XX:G1HeapWastePercent=5 \-XX:G1MixedGCCountTarget=4 \-XX:InitiatingHeapOccupancyPercent=15 \-XX:G1MixedGCLiveThresholdPercent=90 \-XX:G1RSetUpdatingPauseTimePercent=5 \-XX:SurvivorRatio=32 \-XX:+PerfDisableSharedMem \-XX:MaxTenuringThreshold=1 \-Dusing.aikars.flags=https://mcflags.emc.gs \-Daikars.new.flags=true \-jar purpur.jar nogui'

\# Graceful Shutdown  
ExecStop=-/usr/bin/tmux send-keys \-t mc-session "stop" ENTER  
ExecStop=/usr/bin/sleep 20

Restart=on-failure  
RestartSec=10

\[Install\]  
WantedBy=multi-user.target

---

### **2\. Core Server Properties**

**Path:** `/opt/minecraft/server.properties`

Properties  
\# Network & Identity  
online-mode=false  
enforce-secure-profile=false  
enable-query=true  
server-port=25565

\# Performance  
view-distance=8  
simulation-distance=6  
network-compression-threshold=256

---

### **3\. Purpur Performance & Network Tweaks**

**Path:** `/opt/minecraft/purpur.yml`

YAML  
settings:  
  logger:  
    suppress-username-change-warnings: true  
world-settings:  
  default:  
    gameplay-mechanics:  
      entities-can-use-portals: false  
    network:  
      alternative-keepalive: true  
      use-alternate-keepalive: true  
    culling:  
      entities: true

---

### **4\. Paper Optimization**

**Path:** `/opt/minecraft/config/paper-world-defaults.yml`

YAML  
chunks:  
  auto-save-interval: 6000  
  max-auto-save-chunks-per-tick: 4  
entities:  
  armor-stands:  
    tick: false  
  mob-spawner-tick-rate: 2

---

### **5\. GeyserMC Cross-Play Bridge**

**Path:** `/opt/minecraft/plugins/Geyser-Spigot/config.yml`

YAML  
bedrock:  
  address: 0.0.0.0  
  port: 19132  
  clone-remote-port: false  
remote:  
  address: 127.0.0.1  
  port: 25565  
  auth-type: floodgate

---

### **6\. AuthMe Authentication**

**Path:** `/opt/minecraft/plugins/AuthMe/config.yml`

YAML  
settings:  
  sessions:  
    enabled: true  
    timeout: 180  
  restrictions:  
    \# Allows Bedrock players (Floodgate prefix) and TLauncher users  
    allowedNicknameCharacters: '\[a-zA-Z0-9\_\\.\]\*'  
    timeout: 90  
    allowChat: false  
    maxRegPerIp: 1

---

### **7\. Playit.gg Tunnel Configuration**

The agent runs as a systemd service. Ensure the following tunnels are active in the [playit.gg](https://playit.gg) dashboard:

* **Tunnel 1:** Java Edition (TCP) \-\> Local Port 25565  
* **Tunnel 2:** Bedrock Edition (UDP) \-\> Local Port 19132

---

### **8\. Plugin Checklist**

Ensure the `/opt/minecraft/plugins` directory contains:

* `purpur.jar` (Engine)  
* `Geyser-Spigot.jar`  
* `floodgate-spigot.jar`  
* `AuthMe.jar` (v6.0.0+)  
* `SkinsRestorer.jar`  
* `Chunky.jar`  
* `spark.jar`

