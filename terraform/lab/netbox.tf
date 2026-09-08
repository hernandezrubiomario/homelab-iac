# ============================================================
# POOL DE DIRECCIONES IP
# ============================================================
# Localiza en NetBox el rango de IPs reservado para Terraform
# (buscado por su descripción, no por ID, para no depender de
# un valor concreto en NetBox).
data "netbox_ip_range" "terraform_pool" {
  description = "Pool Terraform laboratorio"
}

# ============================================================
# CLÚSTER DE VIRTUALIZACIÓN
# ============================================================

# Define el tipo de plataforma de virtualización utilizada.
resource "netbox_cluster_type" "kvm" {
  name = "KVM"
  slug = "kvm"
}

# Define el entorno KVM del laboratorio donde se alojan las VMs.
resource "netbox_cluster" "lab_kvm" {
  name            = "lab-kvm"
  cluster_type_id = netbox_cluster_type.kvm.id
}

# ============================================================
# MÁQUINAS VIRTUALES EN NETBOX
# ============================================================

# Registra cada máquina virtual en NetBox.
resource "netbox_virtual_machine" "vm" {
  for_each = var.vms

  name       = each.key
  cluster_id = netbox_cluster.lab_kvm.id
  status     = "active"
}

# Registra la interfaz principal de cada VM.
resource "netbox_interface" "vm_interface" {
  for_each = var.vms

  name               = "enp1s0"
  virtual_machine_id = netbox_virtual_machine.vm[each.key].id
}

# Reserva automáticamente una IP disponible del pool de Terraform
# y la asigna a la interfaz de cada VM.
resource "netbox_available_ip_address" "vm_ip" {
  for_each = var.vms

  ip_range_id                  = data.netbox_ip_range.terraform_pool.id
  status                       = "active"
  description                  = "Asignada por Terraform a ${each.key}"
  virtual_machine_interface_id = netbox_interface.vm_interface[each.key].id
}

# Define la IPv4 principal de cada VM (primary_ip4 en NetBox),
# necesaria para que el inventario dinámico de Ansible pueda
# usarla como ansible_host.
resource "netbox_primary_ip" "vm_primary_ip" {
  for_each = var.vms

  ip_address_id      = netbox_available_ip_address.vm_ip[each.key].id
  virtual_machine_id = netbox_virtual_machine.vm[each.key].id
  ip_address_version = 4
}
