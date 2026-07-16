## **Server Infrastructure Specifications**

### **1\. Hardware Allocation (Proxmox LXC)**

| Component | Specification |
| ----- | ----- |
| **Container Type** | Unprivileged LXC (Nesting Enabled) |
| **Operating System** | Debian 12 (Bookworm) |
| **CPU Resources** | 2 vCPU Cores (Host Passthrough) |
| **Memory (RAM)** | 6144 MB (6 GB) Total |
| **Swap Space** | 512 MB |
| **Storage** | 20 GB SSD (Ext4) |

---

### **2\. Software Runtime & Environment**

* **Java Runtime:** OpenJDK 25 (Adoptium Temurin LTS)  
* **Process Management:** systemd with tmux (Session: `mc-session`)  
* **Shell Environment:** Zsh/Bash with `curl`, `wget`, and `jq` utilities  
* **JVM Flags:** Aikar’s Optimized G1GC (Tuned for 3GB Heap)

---

### **3\. Minecraft Engine & Architecture**

* **Core Engine:** Purpur 26.1.2 (Paper/Spigot Fork)  
* **Edition Support:**  
  * **Java Edition:** Native support (1.21.x \- 26.x)  
  * **Bedrock Edition:** Cross-play via GeyserMC \+ Floodgate  
  * **Offline Mode:** TLauncher / Cracked support via `online-mode=false`  
* **Protocol Support:** Multi-versioning via packet translation

---

### **4\. Networking & Connectivity**

* **Tunneling Service:** playit.gg (Global Anycast Network)  
* **Port Mapping:**  
  * **TCP 25565:** Java / TLauncher Traffic  
  * **UDP 19132:** Bedrock / Mobile Traffic  
* **Network Strategy:** WISP Mode isolation (via OpenWrt) to protect homelab resources from local network residents.

---

### **5\. Security & Management Plugins**

* **Authentication:** AuthMeReloaded (v6.0.0+) \- Session-based login  
* **Identity:** SkinsRestorer \- Offline skin synchronization  
* **Performance:**  
  * **Chunky:** Asynchronous world pre-generation (Radius: 5000\)  
  * **Spark:** Real-time CPU/Heap profiling and TPS monitoring  
* **Integrity:** `enforce-secure-profile=false` for non-Mojang signed packets

