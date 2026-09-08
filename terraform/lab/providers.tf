terraform {
  required_providers {
    # Provider para gestionar las máquinas virtuales de KVM/libvirt.
    libvirt = {
      source = "dmacvicar/libvirt"
    }

    # Provider para consultar y gestionar recursos del IPAM NetBox.
    netbox = {
      source = "e-breuninger/netbox"
    }
  }
}

# Conexión de Terraform con libvirt en el propio host KVM.
# Terraform se ejecuta localmente en el hipervisor (uri qemu:///system)
# para evitar los problemas encontrados con el acceso remoto qemu+ssh.
provider "libvirt" {
  uri = "qemu:///system"
}

# Conexión de Terraform con el servidor NetBox del laboratorio.
# El token de autenticación NO se define aquí: se toma de la variable
# de entorno NETBOX_API_TOKEN (ver README / terraform.tfvars.example).
provider "netbox" {
  server_url = "https://netbox.lab.local"
}
