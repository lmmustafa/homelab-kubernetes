# Homelab Kubernetes

Cluster Kubernetes de laboratório desenvolvido sobre **Proxmox VE**, **Ubuntu Server**, **containerd**, **Flannel**, **MetalLB** e **NFS**.

O objetivo deste projeto é construir uma infraestrutura Kubernetes reproduzível para estudos práticos de:

* Kubernetes
* Linux
* Containers
* Networking
* Storage
* Proxmox
* NFS
* MetalLB
* Persistent Volumes
* DevOps
* CKA

---

## 📋 Objetivo

Construir um cluster Kubernetes funcional utilizando:

* 1 Control Plane
* 2 Worker Nodes
* Flannel como CNI
* MetalLB como LoadBalancer
* NFS como armazenamento compartilhado

Arquitetura atual:

```text
                    Kubernetes Cluster
                           |
             +-------------+-------------+
             |             |             |
             v             v             v
        Control Plane   Worker 01     Worker 02
        10.10.1.241     10.10.1.242   10.10.1.243
        2 vCPU / 4 GB    2 vCPU / 2 GB 2 vCPU / 2 GB
             |             |             |
             +-------------+-------------+
                           |
                        Flannel
                    10.244.0.0/16
                           |
                           v
                     Kubernetes Pods
```

---

# 🏗️ Infraestrutura

## Proxmox

O cluster Kubernetes é executado sobre VMs hospedadas no ambiente:

```text
Proxmox VE
    |
    +-- k8s-master-01
    +-- k8s-worker-01
    +-- k8s-worker-02
    +-- nfs-server
```

### Máquinas Virtuais

| VMID | Hostname        | Função        |    CPU |  RAM | IP            |
| ---: | --------------- | ------------- | -----: | ---: | ------------- |
|  191 | `k8s-master-01` | Control Plane | 2 vCPU | 4 GB | `10.10.1.241` |
|  201 | `k8s-worker-01` | Worker        | 2 vCPU | 2 GB | `10.10.1.242` |
|  202 | `k8s-worker-02` | Worker        | 2 vCPU | 2 GB | `10.10.1.243` |
|  210 | `nfs-server`    | NFS Server    | 2 vCPU | 2 GB | `10.10.1.240` |

---

# 🌐 Rede

A infraestrutura utiliza:

```text
Rede:       10.10.1.0/24
Gateway:    10.10.1.1
Proxmox:    10.10.1.254
```

### Endereçamento

| Componente           | IP                          |
| -------------------- | --------------------------- |
| Gateway              | `10.10.1.1`                 |
| MetalLB Pool         | `10.10.1.150 - 10.10.1.170` |
| NFS Server           | `10.10.1.240`               |
| Kubernetes Master    | `10.10.1.241`               |
| Kubernetes Worker 01 | `10.10.1.242`               |
| Kubernetes Worker 02 | `10.10.1.243`               |
| Proxmox              | `10.10.1.254`               |

A faixa:

```text
10.10.1.150 - 10.10.1.170
```

é reservada para serviços `LoadBalancer` do MetalLB.

---

# ☸️ Kubernetes

Versão atual:

```text
Kubernetes v1.36.3
```

Componentes:

```text
kubeadm
kubelet
kubectl
containerd
```

Runtime:

```text
containerd 2.2.2
```

Sistema operacional:

```text
Ubuntu Server 26.04 LTS
```

---

# 🧩 Container Runtime

O cluster utiliza:

```text
containerd 2.2.2
```

Configuração:

```text
SystemdCgroup = true
```

CRI:

```text
habilitado
```

Todos os Nodes utilizam o mesmo runtime:

```text
k8s-master-01   containerd://2.2.2
k8s-worker-01   containerd://2.2.2
k8s-worker-02   containerd://2.2.2
```

---

# 🌐 CNI - Flannel

O cluster utiliza **Flannel** como Container Network Interface.

Pod CIDR:

```text
10.244.0.0/16
```

Distribuição observada:

```text
k8s-master-01
    |
    +-- 10.244.0.0/24

k8s-worker-01
    |
    +-- 10.244.1.0/24

k8s-worker-02
    |
    +-- 10.244.2.0/24
```

O Flannel está configurado em todos os Nodes.

---

# 🧪 Validação da Rede

A infraestrutura foi validada utilizando Pods distribuídos entre os dois Workers.

Exemplo:

```text
Worker 01
10.10.1.242
    |
    +-- Pod 10.244.1.2
    +-- Pod 10.244.1.3


Worker 02
10.10.1.243
    |
    +-- Pod 10.244.2.2
    +-- Pod 10.244.2.3
```

Foi realizado teste bidirecional:

```text
10.244.2.2 → 10.244.1.2   OK
10.244.1.2 → 10.244.2.2   OK
```

Resultado:

```text
Pod → Pod
Pod → Pod entre Workers
```

**Status: OK**

---

# 🔎 CoreDNS

O CoreDNS está funcionando corretamente.

Foi validado acesso a Services através do DNS interno do Kubernetes.

Exemplo:

```text
nginx-service
```

e:

```text
nginx-service.default.svc.cluster.local
```

Ambos foram utilizados para acessar o serviço Nginx com sucesso.

---

# 🚀 Deployment de Teste

Foi criado um Deployment utilizando Nginx:

```text
nginx
```

Configuração:

```text
Replicas: 2
Image: nginx:alpine
```

Distribuição:

```text
nginx Pod
10.244.1.3
k8s-worker-01
```

```text
nginx Pod
10.244.2.3
k8s-worker-02
```

Os Pods foram distribuídos entre os dois Workers.

---

# 🔌 Kubernetes Service

Foi criado:

```text
nginx-service
```

Inicialmente como:

```text
ClusterIP
```

ClusterIP:

```text
10.106.196.24
```

Endpoints:

```text
10.244.1.3:80
10.244.2.3:80
```

Foi validado acesso ao Nginx através do ClusterIP.

---

# ⚖️ MetalLB

O cluster utiliza **MetalLB** para disponibilizar Services do tipo:

```text
LoadBalancer
```

Modo:

```text
Layer 2
```

Namespace:

```text
metallb-system
```

Pool configurado:

```text
10.10.1.150 - 10.10.1.170
```

Configuração:

```text
IPAddressPool:
    homelab-pool

L2Advertisement:
    homelab-l2
```

---

# 🌐 LoadBalancer

O `nginx-service` foi alterado para:

```text
TYPE: LoadBalancer
```

Configuração atual:

```text
ClusterIP:
10.106.196.24

External IP:
10.10.1.150

Port:
80
```

Resultado:

```text
nginx-service
      |
      v
LoadBalancer
      |
      v
10.10.1.150
      |
      v
MetalLB Layer 2
      |
      +-------------+
      |             |
      v             v
10.244.1.3      10.244.2.3
Worker 01       Worker 02
```

### Teste realizado

O endereço:

```text
http://10.10.1.150
```

foi acessado pela rede LAN e apresentou corretamente a página padrão do Nginx.

**MetalLB: VALIDADO COM SUCESSO**

---

# 💾 NFS

O servidor NFS está disponível em:

```text
Hostname: nfs-server
IP:       10.10.1.240
```

Export:

```text
/srv/nfs/k8s
```

O NFS foi previamente validado a partir dos Nodes.

Testes realizados:

```text
Conectividade   OK
Export          OK
Montagem         OK
Escrita          OK
Leitura          OK
Desmontagem      OK
```

Próxima etapa:

```text
NFS
 |
 +-- StorageClass
 |
 +-- PersistentVolume
 |
 +-- PersistentVolumeClaim
 |
 +-- Pod
```

---

# 📁 Estrutura do Projeto

```text
homelab-kubernetes/
│
├── README.md
│
├── docs/
│   ├── architecture.md
│   ├── networking.md
│   ├── storage.md
│   └── metallb.md
│
├── manifests/
│   ├── metallb/
│   ├── storage/
│   └── applications/
│
├── scripts/
│   ├── prepare-node.sh
│   ├── install-containerd.sh
│   ├── install-kubernetes.sh
│   ├── init-control-plane.sh
│   ├── install-metallb.sh
│   └── ...
│
└── .gitignore
```

---

# 🔧 Scripts

Os scripts do projeto são utilizados para automatizar a preparação e configuração dos Nodes.

Principais etapas:

```text
prepare-node.sh
       |
       v
install-containerd.sh
       |
       v
install-kubernetes.sh
       |
       v
init-control-plane.sh
       |
       v
Flannel
       |
       v
Worker Join
       |
       v
install-metallb.sh
```

---

# 🧪 Validações Realizadas

## Nodes

```bash
kubectl get nodes -o wide
```

Resultado:

```text
k8s-master-01   Ready
k8s-worker-01   Ready
k8s-worker-02   Ready
```

## Pods

```bash
kubectl get pods -A -o wide
```

Todos os componentes principais estão `Running`.

## Flannel

```bash
kubectl get pods -n kube-flannel -o wide
```

Flannel presente nos três Nodes.

## Services

```bash
kubectl get svc
```

Services funcionando corretamente.

## EndpointSlice

O Kubernetes v1.36 utiliza `EndpointSlice` como mecanismo recomendado para descoberta dos endpoints.

Exemplo:

```bash
kubectl get endpointslices \
  -l kubernetes.io/service-name=nginx-service
```

---

# 🗺️ Roadmap

## Infraestrutura

* [x] Proxmox VE
* [x] Ubuntu Server
* [x] Rede `10.10.1.0/24`
* [x] VMs
* [x] NFS Server
* [x] Testes NFS
* [x] containerd
* [x] Kubernetes
* [x] Control Plane
* [x] Worker 01
* [x] Worker 02

## Kubernetes

* [x] kubeadm
* [x] kubelet
* [x] kubectl
* [x] containerd
* [x] Flannel
* [x] CoreDNS
* [x] Pod → Pod
* [x] Service ClusterIP
* [x] Service DNS
* [x] Deployment
* [x] MetalLB
* [x] IPAddressPool
* [x] L2Advertisement
* [x] LoadBalancer
* [x] Acesso externo via LAN

## Storage

* [ ] Integração NFS com Kubernetes
* [ ] StorageClass
* [ ] PersistentVolume
* [ ] PersistentVolumeClaim
* [ ] Teste de persistência
* [ ] Dynamic Provisioning

## Networking

* [x] Flannel
* [x] CoreDNS
* [x] ClusterIP
* [x] Service Discovery
* [x] MetalLB Layer 2
* [x] LoadBalancer
* [ ] Ingress Controller
* [ ] TLS
* [ ] DNS externo

## Aplicações

* [x] Nginx de teste
* [ ] Aplicação com persistência NFS
* [ ] Ingress
* [ ] Aplicação multi-replica
* [ ] Monitoramento
* [ ] Observabilidade

---

# 🎯 Objetivos de Aprendizado

Este laboratório tem como objetivo desenvolver conhecimentos práticos em:

* Linux
* Kubernetes
* Proxmox VE
* Virtualização
* Container Runtime
* containerd
* kubeadm
* Networking
* Flannel
* CoreDNS
* Kubernetes Services
* MetalLB
* LoadBalancer
* NFS
* Persistent Volumes
* StorageClass
* Ingress
* DevOps
* Git
* Infrastructure as Code
* CKA

---

# 📊 Status Atual

```text
============================================================
 KUBERNETES HOMELAB
============================================================

Nodes:
  Control Plane : READY
  Worker 01     : READY
  Worker 02     : READY

Kubernetes:
  Version       : v1.36.3

Container Runtime:
  containerd    : 2.2.2

CNI:
  Flannel       : OK
  Pod CIDR      : 10.244.0.0/16

DNS:
  CoreDNS       : OK

Networking:
  Pod → Pod      : OK
  Service        : OK
  Service DNS    : OK

MetalLB:
  Mode           : Layer 2
  Pool           : 10.10.1.150-10.10.1.170
  LoadBalancer   : 10.10.1.150
  Status         : OK

NFS:
  Server         : 10.10.1.240
  Export         : /srv/nfs/k8s
  Status         : VALIDATED

============================================================
 STATUS: INFRAESTRUTURA KUBERNETES FUNCIONAL
============================================================
```

---

# 🚀 Próxima Etapa

A próxima etapa do projeto será integrar o **NFS ao Kubernetes** para fornecer armazenamento persistente.

Arquitetura planejada:

```text
                    Kubernetes
                         |
                    NFS Storage
                         |
                  10.10.1.240
                         |
                   /srv/nfs/k8s
                         |
                +--------+--------+
                |        |        |
                v        v        v
               PV       PVC   StorageClass
                         |
                         v
                        Pod
```

Após a implementação do armazenamento persistente, o laboratório poderá evoluir para:

```text
NFS
 |
StorageClass
 |
PersistentVolume
 |
PersistentVolumeClaim
 |
Applications
 |
Ingress
 |
MetalLB
 |
LAN
```

---

# 📄 Licença

Este projeto foi desenvolvido para fins de estudo, laboratório e aprendizado prático de infraestrutura, Linux, virtualização, Kubernetes e DevOps.

```
```
