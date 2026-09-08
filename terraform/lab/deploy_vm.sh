#!/bin/bash
set -euo pipefail

# ============================================================
# PARÁMETROS
# ============================================================
VM_NAME="${1:-}"

if [[ -z "$VM_NAME" ]]; then
  echo "Uso: $0 <nombre-vm>"
  exit 1
fi

# Fichero persistente con las VMs gestionadas por Terraform.
VMS_FILE="vms.auto.tfvars.json"

# ============================================================
# REGISTRAR VM EN LA LISTA DE TERRAFORM
# ============================================================
echo "=== Registrando $VM_NAME en Terraform ==="

python3 - "$VMS_FILE" "$VM_NAME" <<'PY'
import json
import os
import sys

path = sys.argv[1]
vm_name = sys.argv[2]

# Si el fichero todavía no existe, comienza con una lista vacía.
data = {"vms": []}
if os.path.exists(path):
    with open(path, "r") as f:
        data = json.load(f)

vms = data.get("vms", [])

# Evita introducir la misma VM varias veces.
if vm_name not in vms:
    vms.append(vm_name)

# Mantiene la lista ordenada.
data["vms"] = sorted(vms)

# Escritura temporal para evitar dejar el fichero incompleto.
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
os.replace(tmp, path)
PY

# ============================================================
# TERRAFORM
# ============================================================
echo "=== Creando VM: $VM_NAME ==="

terraform apply \
  -auto-approve

# ============================================================
# ARRANCAR VM
# ============================================================
echo "=== Comprobando estado de $VM_NAME ==="

if [[ "$(virsh domstate "$VM_NAME" | xargs)" != "running" ]]; then
  echo "=== Arrancando $VM_NAME ==="
  virsh start "$VM_NAME"
fi

# ============================================================
# ESPERAR INVENTARIO DINÁMICO
# ============================================================
echo "=== Esperando a que $VM_NAME aparezca en NetBox/Ansible ==="

until ssh automation \
  "cd ~/automation/ansible && \
   ansible-inventory \
     -i inventories/lab/netbox.yml \
     --host '$VM_NAME' \
     --vault-password-file ~/.ansible/vault_pass \
     >/dev/null 2>&1"
do
  sleep 5
done

# ============================================================
# OBTENER IP Y LIMPIAR CLAVES SSH ANTIGUAS
# ============================================================
VM_IP=$(ssh automation.lab.local \
  "cd ~/automation/ansible && \
   ansible-inventory \
     -i inventories/lab/netbox.yml \
     --host '$VM_NAME' \
     --vault-password-file ~/.ansible/vault_pass" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["ansible_host"])')

echo "=== Limpiando claves SSH antiguas de $VM_NAME ==="

# Host KVM.
ssh-keygen -R "$VM_NAME.lab.local" >/dev/null 2>&1 || true
ssh-keygen -R "$VM_IP" >/dev/null 2>&1 || true

# Nodo automation.
ssh automation.lab.local \
  "ssh-keygen -R '$VM_NAME.lab.local' >/dev/null 2>&1 || true; \
   ssh-keygen -R '$VM_IP' >/dev/null 2>&1 || true"

# ============================================================
# REGISTRAR NUEVA CLAVE SSH
# ============================================================
echo "=== Esperando SSH y registrando nueva clave de $VM_IP ==="

until ssh automation \
  "ssh-keyscan -T 2 -H '$VM_IP' >> ~/.ssh/known_hosts 2>/dev/null"
do
  sleep 5
done

# ============================================================
# ESPERAR CONECTIVIDAD SSH
# ============================================================
echo "=== Esperando conectividad SSH con $VM_NAME ==="

until ssh automation \
  "cd ~/automation/ansible && \
   ansible '$VM_NAME' \
     -i inventories/lab/netbox.yml \
     -m ping \
     --vault-password-file ~/.ansible/vault_pass \
     >/dev/null 2>&1"
do
  sleep 5
done

# ============================================================
# FREEIPA + DNS
# ============================================================
echo "=== Enrolando $VM_NAME en FreeIPA y registrando DNS ==="

ssh automation \
  "cd ~/automation/ansible && \
   ansible-playbook \
     -i inventories/lab/netbox.yml \
     -i inventories/lab/hosts.yml \
     playbooks/freeipa_client.yml \
     --limit '$VM_NAME,ipa' \
     --extra-vars 'vm_name=$VM_NAME vm_ip=$VM_IP' \
     --vault-password-file ~/.ansible/vault_pass"

echo "=== Despliegue completado: $VM_NAME ==="
