# Aprovisionamiento con Terraform + Cloud-Init

## Qué hace este código

Crea y mantiene las máquinas virtuales del laboratorio sobre KVM/libvirt.
Por cada nombre incluido en `var.vms`, Terraform:

1. Crea un disco QCOW2 a partir de la plantilla `rocky9-template` (`main.tf`).
2. Reserva una IP en NetBox y registra la VM, su interfaz y su IP
   primaria (`netbox.tf`).
3. Genera el ISO de Cloud-Init con el hostname, el usuario `mario`,
   las claves SSH autorizadas y la configuración de red
   (`cloud-init/*.tftpl`).
4. Crea el dominio `libvirt_domain` con ese disco y ese ISO conectados.

Cloud-Init se encarga de la configuración del primer arranque; Ansible
(ver `docs/ansible.md`) entra después para enrolar la VM en FreeIPA y
dejarla lista para administración centralizada.

## Estructura

```
terraform/lab/
├── providers.tf              # providers libvirt + netbox
├── variables.tf               # variables (vms, red, claves SSH)
├── main.tf                    # discos, cloud-init, dominios libvirt
├── netbox.tf                  # cluster, VM, interfaz, IP en NetBox
├── vms.auto.tfvars.json       # lista de VMs gestionadas (la actualiza deploy_vm.sh)
├── terraform.tfvars.example   # plantilla de valores reales (NO subir terraform.tfvars)
├── deploy_vm.sh                # script de despliegue de extremo a extremo
└── cloud-init/
    ├── user-data.yml.tftpl
    └── network-config.yml.tftpl
```

## Por qué `for_each` y no una VM por `terraform apply`

La primera versión de este código usaba una única variable `vm_name`
(string) y creaba una VM por ejecución. Se sustituyó por `var.vms`
(`set(string)`) + `for_each` para que Terraform pueda gestionar todas
las VMs del laboratorio como un solo estado, sin destruir las
existentes al crear una nueva. `vms.auto.tfvars.json` es la lista
persistente de esa variable; `deploy_vm.sh` la actualiza automáticamente
en cada despliegue.

## Requisitos previos

- Terraform instalado en el host KVM (repositorio oficial de HashiCorp).
- Un storage pool de libvirt llamado `terraform-vms`, separado del pool
  donde viven las VMs creadas manualmente.
- Plantilla base disponible en `/home/mario/labs/templates/rocky9-template.qcow2`.
- Variable de entorno `NETBOX_API_TOKEN` exportada (el provider de
  NetBox la usa vía `terraform.tfvars` / entorno, nunca hardcodeada).
- `terraform.tfvars` creado a partir de `terraform.tfvars.example`, con
  las claves públicas SSH reales del nodo `automation` y del host KVM.

## Uso

```bash
cd terraform/lab
terraform init
cp terraform.tfvars.example terraform.tfvars   # y rellena tus valores
./deploy_vm.sh nombre-de-la-vm
```

`deploy_vm.sh` no solo llama a `terraform apply`: también espera a que
la VM aparezca en el inventario dinámico de Ansible (vía NetBox), limpia
claves SSH antiguas, espera conectividad y lanza el playbook de
enrolamiento en FreeIPA. El flujo completo es:

```
Terraform → KVM → NetBox → Cloud-Init → Ansible → FreeIPA → DNS
```

## Notas de seguridad

- `terraform.tfstate` puede contener datos sensibles en texto plano.
  Nunca se versiona (ver `.gitignore`).
- El token de NetBox y las claves SSH se pasan como variables, nunca
  se escriben directamente en los `.tf`.
- `deploy_vm.sh` asume un alias SSH `automation` (y `automation.lab.local`)
  resuelto vía `~/.ssh/config` o DNS; documenta ese requisito si lo
  añades al README general del repositorio.
