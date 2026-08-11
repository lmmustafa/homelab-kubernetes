#!/bin/bash

set -euo pipefail

# ============================================================
# Instalação e Configuração do containerd
# Homelab Kubernetes
# ============================================================

CONTAINERD_CONFIG="/etc/containerd/config.toml"

echo
echo "============================================================"
echo " Instalação e Configuração do containerd"
echo "============================================================"
echo

# ============================================================
# Verificar root
# ============================================================

if [ "$EUID" -ne 0 ]; then
    echo "ERRO: execute este script como root."
    echo
    echo "Exemplo:"
    echo "  sudo ./install-containerd.sh"
    exit 1
fi

# ============================================================
# Informações do sistema
# ============================================================

echo "Hostname : $(hostname)"
echo "OS       : $(grep PRETTY_NAME /etc/os-release | cut -d '"' -f2)"
echo "Kernel   : $(uname -r)"
echo

# ============================================================
# Atualizar repositórios
# ============================================================

echo "[1/8] Atualizando repositórios..."

apt update

echo

# ============================================================
# Instalar dependências
# ============================================================

echo "[2/8] Instalando dependências..."

apt install -y \
    ca-certificates \
    curl \
    gnupg \
    containerd

echo

# ============================================================
# Verificar instalação
# ============================================================

echo "[3/8] Verificando instalação..."

if ! command -v containerd >/dev/null 2>&1; then
    echo "ERRO: containerd não foi instalado corretamente."
    exit 1
fi

echo "containerd:"
containerd --version

echo

# ============================================================
# Criar diretório de configuração
# ============================================================

echo "[4/8] Criando configuração do containerd..."

mkdir -p /etc/containerd

# Backup da configuração existente
if [ -f "$CONTAINERD_CONFIG" ]; then

    BACKUP="${CONTAINERD_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"

    cp "$CONTAINERD_CONFIG" "$BACKUP"

    echo "Backup criado:"
    echo "$BACKUP"

fi

echo

# ============================================================
# Gerar configuração padrão
# ============================================================

echo "Gerando configuração padrão..."

containerd config default > "$CONTAINERD_CONFIG"

# ============================================================
# Configurar SystemdCgroup
# ============================================================

echo "Configurando SystemdCgroup..."

sed -i \
    's/SystemdCgroup = false/SystemdCgroup = true/' \
    "$CONTAINERD_CONFIG"

# ============================================================
# Garantir CRI habilitado
# ============================================================

echo "Validando configuração CRI..."

# Remover configuração antiga de plugins CRI desabilitados
sed -i \
    '/disabled_plugins.*cri/d' \
    "$CONTAINERD_CONFIG"

echo

# ============================================================
# Validar configuração
# ============================================================

echo "[5/8] Validando configuração..."

if ! containerd config dump >/dev/null 2>&1; then
    echo "ERRO: configuração do containerd inválida."
    exit 1
fi

echo "Configuração válida."

echo

# ============================================================
# Habilitar e iniciar serviço
# ============================================================

echo "[6/8] Habilitando containerd..."

systemctl daemon-reload

systemctl enable --now containerd

echo

# ============================================================
# Verificar serviço
# ============================================================

echo "[7/8] Verificando serviço..."

if systemctl is-active --quiet containerd; then
    echo "containerd: ACTIVE"
else
    echo "ERRO: containerd não está ativo."
    systemctl status containerd --no-pager
    exit 1
fi

echo

# ============================================================
# Validar SystemdCgroup
# ============================================================

echo "[8/8] Validando configuração Kubernetes..."

SYSTEMD_CGROUP=$(grep -E '^[[:space:]]*SystemdCgroup[[:space:]]*=' \
    "$CONTAINERD_CONFIG" | head -n 1 || true)

echo "SystemdCgroup:"
echo "${SYSTEMD_CGROUP:-não encontrado}"

echo

# ============================================================
# Validação final
# ============================================================

echo "============================================================"
echo " Validação Final"
echo "============================================================"
echo

echo "Hostname:"
hostnamectl --static

echo

echo "containerd:"
containerd --version

echo

echo "Serviço:"
systemctl is-active containerd

echo

echo "Boot:"
systemctl is-enabled containerd

echo

echo "SystemdCgroup:"
grep -E '^[[:space:]]*SystemdCgroup[[:space:]]*=' \
    "$CONTAINERD_CONFIG" || true

echo

echo "CRI:"
if containerd config dump 2>/dev/null | grep -q 'io.containerd.grpc.v1.cri'; then
    echo "CRI: habilitado"
else
    echo "AVISO: não foi possível confirmar o plugin CRI."
fi

echo

echo "============================================================"
echo " CONTAINERD CONFIGURADO COM SUCESSO"
echo "============================================================"
echo

echo "Próxima etapa:"
echo "  Instalação do kubeadm, kubelet e kubectl"
echo