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

systemctl enable containerd

systemctl restart containerd

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

echo "SystemdCgroup:"

if awk '
    /^\[plugins\..*containerd\.runtimes\.runc\.options\]$/ {
        in_runc=1
        next
    }
    /^\[/ {
        in_runc=0
    }
    in_runc && /^[[:space:]]*SystemdCgroup[[:space:]]*=[[:space:]]*true([[:space:]]*(#.*)?)?$/ {
        found=1
    }
    END {
        exit !found
    }
' "$CONTAINERD_CONFIG"; then
    echo "OK: SystemdCgroup habilitado no runtime runc."
else
    echo "ERRO: SystemdCgroup não habilitado no runtime runc."
    exit 1
fi

# ============================================================
# Validação final
# ============================================================

echo "============================================================"
echo " Validação Final"
echo "============================================================"
echo

ERRORS=0

echo "Hostname:"
hostnamectl --static

echo
echo "containerd:"
containerd --version

echo
echo "Serviço:"
if systemctl is-active --quiet containerd; then
    echo "OK: containerd ativo."
else
    echo "ERRO: containerd inativo."
    ERRORS=$((ERRORS + 1))
fi

echo
echo "Boot:"
if systemctl is-enabled --quiet containerd; then
    echo "OK: containerd habilitado no boot."
else
    echo "ERRO: containerd não habilitado no boot."
    ERRORS=$((ERRORS + 1))
fi


echo
echo "SystemdCgroup:"
if containerd config dump 2>/dev/null | awk '
    /^[[:space:]]*\[.*runtimes\.runc\.options\][[:space:]]*$/ {
        in_runc=1
        next
    }
    /^[[:space:]]*\[/ {
        in_runc=0
    }
    in_runc && /^[[:space:]]*SystemdCgroup[[:space:]]*=[[:space:]]*true([[:space:]]*(#.*)?)?$/ {
        found=1
    }
    END {
        exit !found
    }
'; then
    echo "OK: SystemdCgroup habilitado no runtime runc."
else
    echo "ERRO: SystemdCgroup não habilitado no runtime runc."
    ERRORS=$((ERRORS + 1))
fi

echo
echo "CRI:"

if ctr plugins ls | awk '
    $1 == "io.containerd.cri.v1" && $2 == "runtime" && $NF == "ok" {
        runtime=1
    }
    $1 == "io.containerd.cri.v1" && $2 == "images" && $NF == "ok" {
        images=1
    }
    END {
        exit !(runtime && images)
    }
'; then
    echo "OK: plugins CRI runtime e images carregados."
else
    echo "ERRO: plugins CRI não estão funcionando."
    ERRORS=$((ERRORS + 1))
fi

echo
echo "============================================================"

if [[ "$ERRORS" -gt 0 ]]; then
    echo " FALHA: $ERRORS validação(ões) não passaram."
    exit 1
fi

echo " CONTAINERD CONFIGURADO COM SUCESSO"
echo "============================================================"

echo
echo "Próxima etapa:"
echo "  Instalação do kubeadm, kubelet e kubectl"
