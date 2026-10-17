# Kubernetes Storage — Homelab

## Infraestrutura NFS

- Servidor: nfs-server
- IP: 10.10.1.240
- Export: /srv/nfs/k8s
- Control plane: k8s-master-01
- Workers: k8s-worker-01 e k8s-worker-02

## Provisionamento dinâmico

- Projeto: nfs-subdir-external-provisioner
- Helm chart: 4.0.18
- Namespace: nfs-provisioner
- StorageClass: nfs-server-k8s
- Provisioner ID: homelab.local/nfs-server-k8s
- Política de retenção: Retain

O provisionador deve executar somente nos workers.
A StorageClass não será definida como padrão do cluster.

## Arquivos do projeto

- manifests/storage/nfs-subdir-external-provisioner/values-homelab.yaml
- manifests/storage/nfs-subdir-external-provisioner/pvc-smoke-test.yaml

## Segurança e backup

A política Retain não substitui backups.
Antes de armazenar dados reais de clientes, revisar as permissões do NFS,
restringir o acesso à rede necessária e testar a restauração dos backups.

## Próxima etapa

Validar e instalar o provisionador NFS, testar a criação de PVCs
e depois implantar o Snipe-IT com MariaDB.
