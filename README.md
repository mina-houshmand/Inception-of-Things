# Inception-of-Things (IoT): Step-by-Step Guide

A plain-language guide to the project: what to build, in what order, and how to check that it works.

---

## 0. Words you need to know

| Word | What it means |
|---|---|
| **Vagrant** | A tool that creates VMs from a text file called a `Vagrantfile`, so you don't click through VirtualBox by hand. |
| **Provider** | The program Vagrant uses to actually run the VMs (usually **VirtualBox**). |
| **Kubernetes (K8s)** | A system that runs and manages apps packaged as containers. |
| **K3s** | A small, lightweight version of Kubernetes that installs with one command. |
| **K3d** | Runs K3s *inside Docker containers*. You get a cluster in seconds with no VMs. |
| **kubectl** | The command-line tool you use to talk to Kubernetes (`kubectl get pods`, etc.). |
| **Node** | One machine in the cluster. The **server** is the boss and the **agent** is a worker. |
| **Pod** | The smallest running unit in Kubernetes: one or more containers. |
| **Deployment** | Tells Kubernetes "keep N copies (replicas) of this pod running." |
| **Service** | A stable address that sends traffic to a group of pods. |
| **Ingress** | A traffic router. It looks at the requested hostname (e.g. `app1.com`) and sends the request to the right Service. |
| **Namespace** | A folder inside the cluster that keeps resources separate. |
| **Argo CD** | Watches a Git repo and automatically applies whatever YAML is in it to the cluster. This is called **GitOps**. |
| **Docker image tag** | A version label on an image, e.g. `wil42/playground:v1`. |

---

## 1. Before you start (do this together)

1. **Create the host VM.** The whole project must run inside a VM.
   - Give it plenty of resources: 4+ CPUs and 8 GB+ RAM (more for the bonus).
   - **Turn on nested virtualization.** Part 1 and Part 2 start VMs *inside* this VM, and they will not start without it. In VirtualBox: VM Settings → System → Processor → *Enable Nested VT-x/AMD-V*.
2. **Install the tools** inside the host VM: `git`, `vagrant`, `virtualbox`, `curl`.
3. **Pick a distro** for the Vagrant VMs, e.g. the latest stable Debian, and use the same box everywhere.
4. **Pick a login** to use in names. The examples below use `wil`, so replace it with yours.
5. **Create the repo** with this layout:

```
.
├── p1/      Vagrantfile, scripts/, confs/
├── p2/      Vagrantfile, scripts/, confs/
├── p3/      scripts/, confs/
└── bonus/   (optional) Vagrantfile, scripts/, confs/
```

> Rule: scripts go in `scripts/`, config files (YAML etc.) go in `confs/`.

---

## 2. Part 1: K3s and Vagrant (2 VMs)

**Goal:** two VMs that together form one Kubernetes cluster.

| Machine | Hostname | IP | K3s role |
|---|---|---|---|
| 1 | `wilS` | 192.168.56.110 | server (controller) |
| 2 | `wilSW` | 192.168.56.111 | agent (worker) |

Each VM gets **1 CPU** and **512 MB or 1024 MB RAM**.

### Steps

1. **Write `p1/Vagrantfile`** that defines both machines. For each one, set:
   - `vm.box` (your distro)
   - `vm.hostname` (`wilS` / `wilSW`)
   - `vm.network "private_network", ip: "192.168.56.110"` (or `.111`)
   - provider settings: 1 CPU, 1024 MB RAM, VM name
   - a `provision "shell", path: "scripts/..."` line that runs your install script
2. **Write `p1/scripts/server.sh`** to install K3s in server mode:
   ```bash
   curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
     --node-ip=192.168.56.110 --flannel-iface=eth1 \
     --write-kubeconfig-mode=644" sh -
   # Share the join token with the worker through the synced folder
   cp /var/lib/rancher/k3s/server/node-token /vagrant/confs/node-token
   ```
3. **Write `p1/scripts/worker.sh`** to install K3s in agent mode and join the server:
   ```bash
   curl -sfL https://get.k3s.io | \
     K3S_URL=https://192.168.56.110:6443 \
     K3S_TOKEN=$(cat /vagrant/confs/node-token) \
     INSTALL_K3S_EXEC="agent --node-ip=192.168.56.111 --flannel-iface=eth1" sh -
   ```
   > Check the real interface name with `ip a`. It may be `enp0s8` instead of `eth1`. Using the wrong one is the #1 reason the worker shows the wrong IP.
4. **kubectl** comes with K3s. Use `kubectl` or `sudo k3s kubectl` on the server.
5. **Passwordless SSH** works out of the box with `vagrant ssh wilS`.

### Check that it works

```bash
cd p1 && vagrant up
vagrant ssh wilS
kubectl get nodes -o wide     # both wilS and wilSW must be "Ready" with the .110/.111 IPs
ip a show eth1                # shows 192.168.56.110
```

---

## 3. Part 2: K3s and three web apps (1 VM)

**Goal:** one VM (`wilS`, 192.168.56.110) running 3 web apps. Which app you see depends on the hostname you ask for:

| Request | Shows |
|---|---|
| `Host: app1.com` | app1 |
| `Host: app2.com` | app2 (**3 replicas**) |
| anything else | app3 (the default) |

### Steps

1. **`p2/Vagrantfile`**: one VM, same idea as Part 1, with K3s in server mode. You can give it more RAM (e.g. 2048 MB).
2. **Write the app YAML** in `p2/confs/`. For each app you need:
   - a **Deployment** (app2 gets `replicas: 3`)
   - a **Service** pointing to it
   - Any simple web image works, e.g. `paulbouwer/hello-kubernetes`, or `nginx` with a custom message.
3. **Write one Ingress** in `p2/confs/ingress.yaml`. K3s already includes **Traefik** as the ingress controller.
   - rule `host: app1.com` → app1 service
   - rule `host: app2.com` → app2 service
   - a rule **with no host** → app3 service (this is the default)
4. In the provision script, apply everything:
   ```bash
   kubectl apply -f /vagrant/confs/
   ```

### Check that it works

```bash
kubectl get all              # app2 shows 3/3 ready
kubectl get ingress          # you must show this in the defense
curl -H "Host: app1.com" 192.168.56.110   # app1
curl -H "Host: app2.com" 192.168.56.110   # app2
curl 192.168.56.110                       # app3
```

---

## 4. Part 3: K3d and Argo CD (no Vagrant)

**Goal:** when you change the app version in GitHub, the cluster updates itself.

```
You push to GitHub ──► Argo CD notices ──► updates the app in namespace "dev"
```

### Steps

1. **Write `p3/scripts/install.sh`.** You must run this during the defense, so it has to install everything:
   - Docker
   - kubectl
   - k3d (`curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash`)
2. **Create the cluster and namespaces** (`p3/scripts/setup.sh`):
   ```bash
   k3d cluster create iot
   kubectl create namespace argocd
   kubectl create namespace dev
   kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
   ```
3. **Create a public GitHub repo** with a team member's login in the name, e.g. `wil-iot-app`. Put a `deployment.yaml` (and a Service) in it that uses:
   ```yaml
   image: wil42/playground:v1    # port 8888
   ```
4. **Write an Argo CD Application** (`p3/confs/application.yaml`) that says: watch this repo and path, deploy into namespace `dev`, and sync automatically:
   ```yaml
   syncPolicy:
     automated:
       prune: true
       selfHeal: true
   ```
   Then run `kubectl apply -f p3/confs/application.yaml`.
5. **Open the Argo CD web UI:**
   ```bash
   kubectl port-forward svc/argocd-server -n argocd 8080:443
   # user: admin   password:
   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
   ```

### Check that it works (this is the defense demo)

```bash
kubectl get ns                       # argocd and dev exist
kubectl get pods -n dev              # playground pod Running
kubectl port-forward svc/<your-service> -n dev 8888:8888
curl http://localhost:8888/          # {"status":"ok", "message": "v1"}

# In the GitHub repo: change v1 → v2, then commit and push
# Wait for Argo CD to sync (or click Refresh)
curl http://localhost:8888/          # {"status":"ok", "message": "v2"}
```

---

## 5. Bonus: GitLab (only if everything above is perfect)

- Install GitLab **inside the cluster** in a namespace called `gitlab`, using Helm and the latest version.
- Create a repo in your local GitLab and point Argo CD at it instead of GitHub.
- The v1 → v2 demo from Part 3 must work with GitLab.
- Put it all in `bonus/`. GitLab is heavy, so give the host VM lots of RAM.

---

## 6. Defense checklist

- [ ] Fresh `git clone` → `vagrant up` works for p1 and p2 without manual fixes
- [ ] p1: both nodes `Ready` with the correct IPs and hostnames
- [ ] p2: the 3 hosts route correctly, app2 has 3 replicas, and you can show and explain the Ingress
- [ ] p3: the install script runs cleanly, both namespaces exist, and v1 → v2 updates through Git
- [ ] Both teammates can explain **every** part
- [ ] You can answer the classic questions:
  - What is the difference between **K3s and K3d**? (K3s runs on a real or virtual machine. K3d runs K3s inside Docker containers.)
  - What does an **Ingress** do?
  - What is a **Deployment** vs a **Service** vs a **Pod**?
  - What is **GitOps** / what does Argo CD do?
  - Server vs agent node?

---

## 7. Common problems

| Problem | Likely fix |
|---|---|
| `vagrant up` fails with a VT-x/virtualization error | Turn on nested virtualization on the host VM |
| Worker node never joins | Wrong token or IP; check that `node-token` was copied and that port 6443 is reachable |
| Node shows a 10.0.2.x IP | Set `--node-ip` and `--flannel-iface` to the private network interface |
| Ingress returns 404 | The hostname in the rule doesn't match, or the Service name or port is wrong |
| Argo CD doesn't update | Repo not public, wrong path, or `automated` sync missing |
| VMs too slow / out of memory | Give the host VM more RAM; keep the Vagrant VMs at 1 CPU / 1024 MB |
