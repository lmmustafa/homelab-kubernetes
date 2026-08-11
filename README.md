# Homelab Kubernetes

Cluster Kubernetes desenvolvido em laboratório utilizando **Ubuntu Server**, **containerd**, **kubeadm**, **kubelet** e **kubectl**.

Este projeto faz parte de um Homelab construído sobre **Proxmox VE**, com o objetivo de criar um ambiente prático e reproduzível para estudar **Kubernetes, Linux, networking, storage, containers e infraestrutura**.

A infraestrutura das máquinas virtuais é mantida no projeto:

```text
homelab-proxmox-vms
```

---

## 🎯 Objetivo

Construir um cluster Kubernetes funcional utilizando três máquinas virtuais:

* 1 Control Plane
* 2 Worker Nodes

O ambiente será configurado de forma automatizada através de scripts e documentado no GitHub.

A proposta é entender cada etapa da construção do cluster, desde a preparação do sistema operacional até a execução das aplicações.

---

## 🏗️ Arquitetura

```text
                         Internet / LAN
                              |
                         10.10.1.1
                           Gateway
                              |
                    ┌───────────────────┐
                    │    Proxmox VE     │
                    │    10.10.1.254    │
                    │                   │
                    │      vmbr0        │
                    └─────────┬─────────┘
                              |
                 ┌────────────┼────────────┐
                 |            |            |
                 ▼            ▼            ▼
          ┌────────────┐ ┌────────────┐ ┌────────────┐
          │  Control   │ │  Worker 01 │ │  Worker 02 │
          │   Plane    │ │            │ │            │
          │            │ │            │ │            │
          │ .241       │ │ .242       │ │ .243       │
          │ 2 vCPU     │ │ 2 vCPU     │ │ 2 vCPU     │
          │ 4 GB RAM   │ │ 2 GB RAM   │ │ 2 GB RAM   │
          └─────┬──────┘ └─────┬──────┘ └─────┬──────┘
                │               │               │
                └───────────────┼───────────────┘
                                |
                         Kubernetes Cluster
                                |
                         ┌──────┴──────┐
                         │             │
                         ▼             ▼
                      MetalLB        NFS
                                   10.10.1.240
```

---

## 🖥️ Infraestrutura

O cluster será executado sobre o seguinte ambiente:

| Recurso             | Configuração   |
| ------------------- | -------------- |
| Hypervisor          | Proxmox VE 9.1 |
| Sistema operacional | Ubuntu Server  |
| Container Runtime   | containerd     |
| Kubernetes          | kubeadm        |
| Control Plane       | 1              |
| Workers             | 2              |
| NFS Server          | `10.10.1.240`  |
| Rede                | `10.10.1.0/24` |
| Gateway             | `10.10.1.1`    |

### Nós Kubernetes

| Hostname        | Função        | IP            |    CPU |  RAM |
| --------------- | ------------- | ------------- | -----: | ---: |
| `k8s-master-01` | Control Plane | `10.10.1.241` | 2 vCPU | 4 GB |
| `k8s-worker-01` | Worker        | `10.10.1.242` | 2 vCPU | 2 GB |
| `k8s-worker-02` | Worker        | `10.10.1.243` | 2 vCPU | 2 GB |

### Storage

Servidor NFS:

```text
Hostname: nfs-server
IP:       10.10.1.240
Export:   /srv/nfs/k8s
```

O NFS já foi validado pelos três nós Kubernetes, incluindo:

* Conectividade
* Export
* Montagem
* Escrita
* Leitura
* Desmontagem

---

## 🧱 Componentes

O ambiente será construído utilizando:

```text
Kubernetes
├── kubeadm
├── kubelet
├── kubectl
├── containerd
├── CNI
├── MetalLB
├── NFS
├── PersistentVolume
├── PersistentVolumeClaim
├── StorageClass
├── Ingress Controller
└── Aplicações
```

---

## ⚙️ Preparação dos Nós

Antes da instalação do Kubernetes, os nós serão preparados com:

* Configuração de hostname
* Configuração de `/etc/hosts`
* IP estático
* Atualização do sistema
* Instalação de pacotes básicos
* Configuração de `chrony`
* Desabilitação do Swap
* Configuração dos módulos do kernel
* Configuração do `sysctl`
* Instalação do containerd
* Configuração do containerd
* Instalação do kubeadm
* Instalação do kubelet
* Instalação do kubectl

---

## 📁 Estrutura do Projeto

```text
homelab-kubernetes/
│
├── README.md
├── .gitignore
│
├── docs/
│   ├── architecture.md
│   ├── installation.md
│   └── networking.md
│
├── scripts/
│   ├── prepare-node.sh
│   ├── install-containerd.sh
│   ├── install-kubernetes.sh
│   └── validate-cluster.sh
│
└── manifests/
```

---

## 🔧 Scripts

### `prepare-node.sh`

Responsável pela preparação inicial dos nós Kubernetes.

Será utilizado nos:

```text
k8s-master-01
k8s-worker-01
k8s-worker-02
```

Principais configurações:

```text
Swap
Kernel Modules
Sysctl
Hostname
Hosts
Pacotes básicos
Chrony
```

### `install-containerd.sh`

Responsável pela instalação e configuração do **containerd**, utilizado como Container Runtime do Kubernetes.

### `install-kubernetes.sh`

Responsável pela instalação dos componentes:

```text
kubeadm
kubelet
kubectl
```

### `validate-cluster.sh`

Será utilizado posteriormente para validar:

```text
Nodes
Pods
Services
Networking
Storage
```

---

## 🚀 Instalação do Cluster

A instalação seguirá as seguintes etapas:

```text
1. Preparar os nós
        ↓
2. Instalar containerd
        ↓
3. Instalar kubeadm/kubelet/kubectl
        ↓
4. Inicializar Control Plane
        ↓
5. Configurar kubectl
        ↓
6. Instalar CNI
        ↓
7. Adicionar Worker 01
        ↓
8. Adicionar Worker 02
        ↓
9. Validar cluster
        ↓
10. Configurar MetalLB
        ↓
11. Configurar NFS
        ↓
12. Configurar StorageClass
        ↓
13. Deploy de aplicações
```

---

## 🌐 Networking

A rede utilizada pelo laboratório é:

```text
10.10.1.0/24
```

| Componente    | IP            |
| ------------- | ------------- |
| Gateway       | `10.10.1.1`   |
| Proxmox       | `10.10.1.254` |
| NFS           | `10.10.1.240` |
| Control Plane | `10.10.1.241` |
| Worker 01     | `10.10.1.242` |
| Worker 02     | `10.10.1.243` |

A configuração do networking interno do Kubernetes será definida posteriormente através do CNI.

---

## 💾 Storage

O servidor NFS fornecerá armazenamento compartilhado ao cluster.

Export:

```text
10.10.1.240:/srv/nfs/k8s
```

Posteriormente serão configurados:

```text
PersistentVolume
        ↓
PersistentVolumeClaim
        ↓
StorageClass
        ↓
Aplicações Kubernetes
```

O objetivo é trabalhar com armazenamento persistente e compreender o funcionamento de volumes no Kubernetes.

---

## ⚖️ Load Balancing

Será utilizado o **MetalLB** para fornecer endereços IP do tipo `LoadBalancer` dentro da rede do laboratório.

Faixa planejada:

```text
10.10.1.0/24
```

A faixa específica de endereços reservada ao MetalLB será definida durante a configuração do cluster.

---

## 🔍 Validação

Após a instalação, serão realizados testes de:

### Nodes

```bash
kubectl get nodes -o wide
```

### Pods

```bash
kubectl get pods -A
```

### Services

```bash
kubectl get svc -A
```

### Storage

```bash
kubectl get pv
kubectl get pvc
```

### Cluster

```bash
kubectl cluster-info
```

---

## 🗺️ Roadmap

### Preparação

* [ ] Criar estrutura do projeto
* [ ] Documentar arquitetura
* [ ] Validar infraestrutura Proxmox
* [ ] Validar conectividade dos nós
* [ ] Desabilitar Swap
* [ ] Configurar módulos do Kernel
* [ ] Configurar sysctl
* [ ] Preparar sistema operacional

### Container Runtime

* [ ] Instalar containerd
* [ ] Configurar SystemdCgroup
* [ ] Validar containerd

### Kubernetes

* [ ] Instalar kubeadm
* [ ] Instalar kubelet
* [ ] Instalar kubectl
* [ ] Inicializar Control Plane
* [ ] Configurar kubeconfig
* [ ] Instalar CNI
* [ ] Adicionar Worker 01
* [ ] Adicionar Worker 02
* [ ] Validar cluster

### Networking

* [ ] Configurar CNI
* [ ] Validar comunicação entre Pods
* [ ] Instalar MetalLB
* [ ] Configurar IP Pool
* [ ] Testar Service LoadBalancer

### Storage

* [ ] Configurar integração NFS
* [ ] Criar StorageClass
* [ ] Criar PersistentVolume
* [ ] Criar PersistentVolumeClaim
* [ ] Testar armazenamento persistente

### Aplicações

* [ ] Instalar Ingress Controller
* [ ] Deploy de aplicação de teste
* [ ] Configurar Service
* [ ] Configurar Ingress
* [ ] Validar acesso externo

---

## 📊 Status

🟡 **Projeto iniciado**

A infraestrutura base já está pronta:

```text
Proxmox VE                 ✅
Ubuntu Server              ✅
3 nós Kubernetes           ✅
Rede                       ✅
IP estático                ✅
Hostname                   ✅
QEMU Guest Agent           ✅
NFS Server                 ✅
NFS Master                 ✅
NFS Worker 01              ✅
NFS Worker 02              ✅
```

Próxima etapa:

```text
➡️ Preparação dos nós para Kubernetes
```

---

## 🔗 Infraestrutura

A infraestrutura Proxmox utilizada neste projeto está documentada separadamente no projeto:

```text
homelab-proxmox-vms
```

Responsável por:

```text
Proxmox VE
    ↓
Máquinas Virtuais
    ↓
Rede
    ↓
Storage
    ↓
NFS
    ↓
Nós Kubernetes
```

---

## 🎯 Objetivos de Aprendizado

Este laboratório tem como objetivo desenvolver conhecimentos práticos em:

* Kubernetes
* Linux
* Containers
* containerd
* kubeadm
* kubelet
* kubectl
* Kubernetes Networking
* CNI
* MetalLB
* NFS
* Persistent Volumes
* StorageClass
* Ingress
* Services
* DNS
* Troubleshooting
* Git
* GitHub
* DevOps

O objetivo é construir o cluster desde a base, documentar as decisões e entender o funcionamento de cada componente.

---

## 📄 Licença

Este projeto foi desenvolvido para fins de estudo, laboratório e aprendizado prático de Kubernetes, Linux, containers, redes e infraestrutura.
