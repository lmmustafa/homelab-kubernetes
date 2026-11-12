# Kubernetes Cluster – Proxmox

Automação, configuração e documentação de um cluster Kubernetes implantado sobre infraestrutura virtualizada com Proxmox VE.

## 1. Objetivo do projeto

Este repositório centraliza os arquivos necessários para preparar os servidores, instalar e configurar os componentes do Kubernetes e validar o funcionamento do cluster.

O projeto tem como foco:

- Preparação dos nós Ubuntu Server.
- Configuração do Container Runtime (containerd).
- Instalação do Kubernetes com kubeadm.
- Inicialização do Control Plane.
- Integração dos Worker Nodes.
- Configuração de rede com Flannel.
- Disponibilização de serviços externos com MetalLB.
- Validação da infraestrutura e dos componentes do cluster.

A configuração é centralizada para facilitar a manutenção, a padronização e futuras expansões.

## 2. Arquitetura da infraestrutura

O ambiente utiliza máquinas virtuais hospedadas no Proxmox VE, com um nó Control Plane e um nó Worker.

### Topologia do cluster

| Componente | Hostname | Endereço IP | CPU | Memória |
|---|---|---|---:|---:|
| Control Plane | s0076-kubernetes-master-prd | 192.168.250.76 | 2 vCPU | 4 GB |
| Worker | s0077-kubernetes-worker-prd | 192.168.250.77 | 2 vCPU | 8 GB |

**Características da arquitetura:**

- Virtualização: Proxmox VE.
- Sistema operacional: Ubuntu Server 24.04.5 LTS.
- Arquitetura: 1 Control Plane + 1 Worker.
- Comunicação entre os nós pela rede local.
- Gerenciamento do cluster por kubeadm.
- Container Runtime: containerd.

> Esta arquitetura possui um único Control Plane e não oferece alta disponibilidade do plano de controle.

## 3. Configuração de rede

| Parâmetro | Configuração |
|---|---|
| Rede | 192.168.250.0/24 |
| Gateway | 192.168.250.1 |
| Control Plane | 192.168.250.76 |
| Worker | 192.168.250.77 |
| Pod CIDR | 10.244.0.0/16 |
| Service CIDR | 10.96.0.0/12 |

### Componentes de rede

**Flannel**

Responsável pela comunicação de rede entre os Pods distribuídos nos nós do cluster.

- CNI: Flannel.
- Pod CIDR: `10.244.0.0/16`.
- Modo de operação: VXLAN.

Observação: Flannel, por si só, não implementa a aplicação de NetworkPolicies.

**MetalLB**

Responsável por disponibilizar endereços IP externos para Services do tipo LoadBalancer.

Configuração planejada:

| Parâmetro | Valor |
|---|---|
| Namespace | metallb-system |
| IP inicial | 192.168.250.83 |
| IP final | 192.168.250.85 |
| Pool | production-ip-pool |
| L2 Advertisement | production-l2-advertisement |
| Modo | Layer 2 |

Os endereços `.83`, `.84` e `.85` estão reservados para utilização pelo MetalLB.

## 4. Versões dos componentes

| Componente | Versão |
|---|---|
| Ubuntu Server | 24.04.5 LTS |
| Kubernetes | 1.37.1 |
| containerd | 2.2.1 |
| runc | 1.3.4 |
| Flannel | v0.28.10 |
| MetalLB | v0.15.3 |

As versões dos componentes são definidas para manter a padronização do ambiente e reduzir diferenças entre os nós.

## 5. Estrutura do repositório

```text
homelab-kubernetes/
│
├── README.md
│
├── config/
│   └── kubernetes.env
│
├── scripts/
   ├── 01-prepare-node.sh
   ├── 02-install-containerd.sh
   ├── 03-install-kubernetes.sh
   ├── 04-init-control-plane.sh
   ├── 05-join-worker.sh
   ├── 06-install-flannel.sh
   ├── 07-install-metallb.sh
   └── 08-validate-cluster.sh


```

**Observação:** O NFS não faz parte da implantação inicial do cluster.
A integração com armazenamento persistente será avaliada em uma etapa futura.

## 6. Configuração centralizada

As principais configurações do ambiente ficam armazenadas em:

```text
config/kubernetes.env
```

Exemplo:

```bash
KUBERNETES_VERSION="1.37.1"

CONTROL_PLANE_IP="192.168.250.76"
CONTROL_PLANE_HOSTNAME="s0076-kubernetes-master-prd"

WORKER_IP="192.168.250.77"
WORKER_HOSTNAME="s0077-kubernetes-worker-prd"

POD_NETWORK_CIDR="10.244.0.0/16"
SERVICE_CIDR="10.96.0.0/12"

METALLB_NAMESPACE="metallb-system"
METALLB_IP_START="192.168.250.83"
METALLB_IP_END="192.168.250.85"
METALLB_NETWORK_CIDR="192.168.250.0/24"

IP_POOL_NAME="production-ip-pool"
L2_ADVERTISEMENT_NAME="production-l2-advertisement"
```

Os scripts utilizam esse arquivo como referência para evitar configurações duplicadas e divergentes.

## 7. Processo de instalação

A instalação deve respeitar a sequência abaixo.

### Etapa 1 — Preparação dos nós

Executar nos dois servidores:

```bash
sudo bash scripts/01-prepare-node.sh
```

Atividades:

- Desabilitar Swap.
- Configurar módulos do kernel.
- Habilitar encaminhamento IPv4.
- Configurar parâmetros necessários para o Kubernetes.
- Verificar conectividade e resolução de nomes.
- Validar a sincronização de horário.

### Etapa 2 — Instalação do containerd

Executar nos dois servidores:

```bash
sudo bash scripts/02-install-containerd.sh
```

Atividades:

- Instalar containerd.
- Configurar o SystemdCgroup.
- Habilitar e iniciar o serviço.
- Validar a integração com a interface CRI.

### Etapa 3 — Instalação do Kubernetes

Executar nos dois servidores:

```bash
sudo bash scripts/03-install-kubernetes.sh
```

Componentes instalados:

- kubeadm
- kubelet
- kubectl

As versões devem corresponder à versão definida no arquivo central de configuração.

### Etapa 4 — Inicialização do Control Plane

Executar somente no Control Plane:

```bash
sudo bash scripts/04-init-control-plane.sh
```

Atividades:

- Preparar a configuração do kubeadm.
- Validar os parâmetros do cluster.
- Baixar as imagens necessárias.
- Inicializar o Control Plane.
- Configurar o kubeconfig para administração.

### Etapa 5 — Integração do Worker

No Control Plane, gerar o comando de integração:

```bash
sudo kubeadm token create --print-join-command
```

Copiar o comando apresentado.

No Worker, executar:

```bash
sudo bash scripts/05-join-worker.sh
```

O script solicitará o comando gerado no Control Plane para realizar a integração do nó.

### Etapa 6 — Instalação do Flannel

Executar no Control Plane:

```bash
sudo bash scripts/06-install-flannel.sh
```

Atividades:

- Aplicar o manifesto do Flannel.
- Configurar a rede de Pods.
- Aguardar a inicialização dos componentes.
- Verificar a disponibilidade dos nós e do CoreDNS.

### Etapa 7 — Instalação do MetalLB

Executar no Control Plane:

```bash
sudo bash scripts/07-install-metallb.sh
```

Atividades:

- Instalar os componentes do MetalLB.
- Configurar o IPAddressPool.
- Configurar o L2Advertisement.
- Validar Controller e Speakers.

## 8. Validação do cluster

Após a instalação dos componentes, realizar as verificações abaixo no Control Plane.

**Nós:**

```bash
kubectl get nodes -o wide
```

**Pods de todos os namespaces:**

```bash
kubectl get pods -A -o wide
```

**Componentes do sistema:**

```bash
kubectl get pods -n kube-system
```

**Flannel:**

```bash
kubectl get pods -n kube-flannel -o wide
```

**MetalLB:**

```bash
kubectl get pods -n metallb-system -o wide
kubectl get ipaddresspools -n metallb-system
kubectl get l2advertisements -n metallb-system
```

**Serviços:**

```bash
kubectl get services -A
```

### Critérios de validação

A implantação será considerada validada quando:

- Control Plane estiver Ready.
- Worker estiver Ready.
- containerd estiver ativo nos dois nós.
- kubelet estiver ativo nos dois nós.
- Flannel estiver operacional.
- CoreDNS estiver disponível.
- MetalLB Controller estiver disponível.
- MetalLB Speakers estiverem ativos nos nós.
- O pool de endereços estiver configurado e aceito.

A validação deve ser registrada somente após a execução dos testes no ambiente.

## 9. Armazenamento

O NFS não está incluído na implantação inicial.

A integração com armazenamento persistente será avaliada posteriormente, considerando:

- Servidor NFS.
- Provisionamento dinâmico de volumes.
- StorageClass.
- PersistentVolume.
- PersistentVolumeClaim.

A documentação de armazenamento será atualizada quando essa etapa fizer parte do ambiente.

## 10. Segurança e boas práticas

- Manter as versões dos componentes padronizadas.
- Centralizar as configurações do cluster.
- Não armazenar tokens de integração ou credenciais no repositório.
- Não versionar arquivos kubeconfig com credenciais.
- Validar os scripts antes da execução.
- Registrar alterações relevantes no Git.
- Manter os endereços reservados do MetalLB fora do pool DHCP.
- Realizar alterações de infraestrutura de forma controlada.

## 11. Status do projeto

| Atividade | Status |
|---|---|
| Provisionamento das VMs | Realizado |
| Preparação dos nós | Realizada |
| Instalação do containerd | Realizada |
| Scripts de instalação Kubernetes | Preparados |
| Inicialização do Control Plane | Pendente |
| Integração do Worker | Pendente |
| Instalação do Flannel | Pendente |
| Instalação do MetalLB | Pendente |
| Validação geral do cluster | Pendente |
| Integração NFS | Fora do escopo inicial |

Os status devem ser atualizados conforme as etapas forem efetivamente executadas e verificadas.

## 12. Próximas etapas

1. Finalizar a revisão dos scripts de instalação.
2. Instalar o Kubernetes nos dois nós.
3. Inicializar o Control Plane.
4. Integrar o Worker.
5. Instalar e validar o Flannel.
6. Instalar e validar o MetalLB.
7. Executar o script `08-validate-cluster.sh`.
8. Atualizar a documentação com os resultados reais da implantação.

---

**Projeto:** Kubernetes Cluster – Proxmox
**Sistema operacional:** Ubuntu Server 24.04.5 LTS
**Orquestrador:** Kubernetes 1.37.1
**Container Runtime:** containerd 2.2.1
**CNI:** Flannel
**LoadBalancer:** MetalLB
**Gerenciamento:** kubeadm