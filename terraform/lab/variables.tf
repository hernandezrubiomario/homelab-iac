# ============================================================
# MÁQUINAS VIRTUALES GESTIONADAS
# ============================================================

# Conjunto de nombres de VM que Terraform debe crear/mantener.
# Se alimenta automáticamente desde vms.auto.tfvars.json mediante
# deploy_vm.sh; no es necesario editarlo a mano.
variable "vms" {
  description = "Máquinas virtuales gestionadas por Terraform"
  type        = set(string)
}

# ============================================================
# RED
# ============================================================

variable "vm_gateway" {
  description = "Puerta de enlace del laboratorio"
  type        = string
  default     = "192.168.10.1"
}

variable "vm_dns" {
  description = "Servidor DNS del laboratorio (FreeIPA)"
  type        = string
  default     = "192.168.10.10"
}

# ============================================================
# ACCESO SSH
# ============================================================

# Clave pública del nodo automation: permite que Ansible administre
# las nuevas VMs sin contraseña.
variable "ssh_public_key" {
  description = "Clave pública SSH del nodo automation"
  type        = string
}

# Clave pública del host KVM: permite acceso directo por SSH desde
# el host donde se ejecuta Terraform.
variable "host_ssh_public_key" {
  description = "Clave pública SSH del host KVM"
  type        = string
}
