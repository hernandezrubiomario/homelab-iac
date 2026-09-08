# ============================================================
# DISCO DE LAS MÁQUINAS VIRTUALES
# ============================================================
# Crea un disco QCOW2 independiente para cada VM definida
# en la variable var.vms.
resource "libvirt_volume" "vm_disk" {
  # Terraform crea una instancia de este recurso por cada
  # nombre incluido en var.vms.
  for_each = var.vms

  # Nombre del disco de la VM. each.key representa el nombre
  # de la máquina actual.
  name = "${each.key}.qcow2"

  # Pool donde Terraform almacena los discos de las VMs.
  pool = "terraform-vms"

  # Capacidad virtual máxima: 50 GiB (copy-on-write, no ocupa
  # 50 GiB físicamente desde el principio).
  capacity = 53687091200

  target = {
    format = {
      type = "qcow2"
    }
  }

  # Utiliza rocky9-template como disco base. La plantilla
  # permanece intacta y cada VM almacena sus propios cambios
  # en su disco QCOW2.
  backing_store = {
    path = "/home/mario/labs/templates/rocky9-template.qcow2"
    format = {
      type = "qcow2"
    }
  }
}

# ============================================================
# CLOUD-INIT
# ============================================================
# Genera un disco Cloud-Init independiente para cada VM.
# Cloud-Init configura hostname, usuario, claves SSH y red
# durante el primer arranque.
resource "libvirt_cloudinit_disk" "vm_init" {
  for_each = var.vms

  # Nombre del disco Cloud-Init correspondiente a cada VM.
  name = "${each.key}-cloudinit.iso"

  # Configura hostname, usuario y claves SSH.
  user_data = templatefile(
    "${path.module}/cloud-init/user-data.yml.tftpl",
    {
      # Nombre de la VM actual.
      vm_name = each.key
      # Clave pública utilizada por el nodo automation.
      ssh_public_key = var.ssh_public_key
      # Clave pública del host KVM.
      host_ssh_public_key = var.host_ssh_public_key
    }
  )

  # Configura la red utilizando la IP que NetBox ha reservado
  # específicamente para esta VM.
  network_config = templatefile(
    "${path.module}/cloud-init/network-config.yml.tftpl",
    {
      vm_ip      = netbox_available_ip_address.vm_ip[each.key].ip_address
      vm_gateway = var.vm_gateway
      vm_dns     = var.vm_dns
    }
  )

  # Identifica de forma única la instancia ante Cloud-Init.
  meta_data = yamlencode({
    instance-id    = each.key
    local-hostname = each.key
  })
}

# ============================================================
# VOLUMEN CLOUD-INIT
# ============================================================
# Importa en el pool de libvirt el ISO generado previamente
# por libvirt_cloudinit_disk para cada VM.
resource "libvirt_volume" "vm_cloudinit" {
  for_each = var.vms

  name = "${each.key}-cloudinit.iso"
  pool = "terraform-vms"

  # Utiliza como contenido el disco Cloud-Init generado
  # específicamente para esta VM.
  create = {
    content = {
      url = libvirt_cloudinit_disk.vm_init[each.key].path
    }
  }
}

# ============================================================
# MÁQUINAS VIRTUALES
# ============================================================
# Crea una máquina virtual KVM por cada elemento definido
# en var.vms.
resource "libvirt_domain" "vm" {
  for_each = var.vms

  name = each.key
  type = "kvm"

  # Recursos asignados a cada VM (4 GiB expresados en KiB).
  memory = 4194304
  vcpu   = 2

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
  }

  # Expone directamente las características de la CPU del host
  # KVM a la máquina virtual.
  cpu = {
    mode = "host-passthrough"
  }

  devices = {
    # --------------------------------------------------------
    # DISCOS
    # --------------------------------------------------------
    disks = [
      {
        # Disco principal de la VM.
        driver = {
          name = "qemu"
          type = "qcow2"
        }
        # Referencia el volumen correspondiente a esta VM.
        source = {
          volume = {
            pool   = "terraform-vms"
            volume = libvirt_volume.vm_disk[each.key].name
          }
        }
        # El sistema operativo verá el disco como /dev/vda.
        target = {
          dev = "vda"
          bus = "virtio"
        }
      },
      {
        # ISO con la configuración de Cloud-Init.
        source = {
          volume = {
            pool   = "terraform-vms"
            volume = libvirt_volume.vm_cloudinit[each.key].name
          }
        }
        # Se conecta como unidad CD-ROM.
        target = {
          dev = "sda"
          bus = "sata"
        }
        device = "cdrom"
      }
    ]

    # --------------------------------------------------------
    # RED
    # --------------------------------------------------------
    interfaces = [
      {
        # Interfaz conectada a una red gestionada por libvirt.
        type = "network"
        # Todas las VMs utilizan la red del laboratorio.
        source = {
          network = {
            network = "hadoop-net"
          }
        }
        # Adaptador de red optimizado para KVM.
        model = {
          type = "virtio"
        }
      }
    ]

    # --------------------------------------------------------
    # CONSOLA SERIE
    # --------------------------------------------------------
    # Permite acceder a cada VM desde el host mediante:
    # virsh console <nombre-vm>
    consoles = [
      {
        type = "pty"
        target = {
          type = "serial"
        }
      }
    ]

    # Dispositivo serie utilizado por la consola anterior.
    serials = [
      {
        type = "pty"
        target = {
          type = "isa-serial"
        }
      }
    ]

    # --------------------------------------------------------
    # CONSOLA GRÁFICA
    # --------------------------------------------------------
    # Permite acceder a la consola gráfica desde virt-manager.
    # El puerto VNC se asigna automáticamente y solo escucha
    # en localhost.
    graphics = [
      {
        vnc = {
          auto_port = true
          listen    = "127.0.0.1"
        }
      }
    ]
  }
}
