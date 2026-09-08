# Ansible: administración centralizada del laboratorio

## Rol de Ansible en la arquitectura

- **Terraform + Cloud-Init** aprovisionan la VM (disco, red, usuario,
  claves SSH iniciales).
- **Ansible** se conecta a ella una vez creada para terminar su
  configuración: enrolamiento en FreeIPA, registro DNS, y cualquier
  otra tarea de administración recurrente.

Todo el código (playbooks, inventarios, ficheros de Terraform) se
versiona con Git desde un único servidor de automatización,
`automation`, para mantener historial de cambios y una configuración
homogénea entre nodos.

## Estructura

```
ansible/
├── ansible.cfg
├── inventories/lab/
│   ├── hosts.yml     # máquinas existentes del laboratorio
│   └── netbox.yml    # VMs nuevas descubiertas automáticamente desde NetBox
├── group_vars/all/
│   └── vault.yml.example   # plantilla; el vault.yml real se cifra y no se sube
├── playbooks/
│   ├── validacion.yml       # comprueba que Ansible administra todo el inventario
│   ├── freeipa_client.yml   # enrola una VM en FreeIPA y registra su DNS
│   └── cleanup_hosts.yml    # retira entradas manuales de /etc/hosts
├── roles/
├── files/
└── templates/
```

## Acceso SSH

Ansible administra los nodos como usuario `mario` (con `sudo`), nunca
como `root` directamente. El acceso se configura con clave SSH
(`ssh-keygen -t ed25519` + `ssh-copy-id`), sin contraseña, requisito
para automatizar tareas de forma desatendida.

## Inventario dinámico con NetBox

Las VMs creadas por Terraform no se añaden a mano a `hosts.yml`:
Ansible las descubre automáticamente vía el plugin
`netbox.netbox.nb_inventory` (`inventories/lab/netbox.yml`), usando
la IP primaria que NetBox tiene registrada para cada VM.

Requisitos en el nodo `automation`:

```bash
ansible-galaxy collection install netbox.netbox:==3.16.0
python3 -m pip install --user pynetbox
sudo dnf install python3-pytz   # si está disponible por dnf
export NETBOX_API_TOKEN='...'   # el mismo token que usa Terraform
```

Comprobación:

```bash
ansible-inventory -i inventories/lab/netbox.yml --graph
ansible-inventory -i inventories/lab/netbox.yml --host <vm>
```

## Enrolamiento en FreeIPA

El playbook `playbooks/freeipa_client.yml` usa la collection
`ansible-freeipa` (`freeipa.ansible_freeipa.ipaclient`) para:

1. Enrolar la VM como cliente FreeIPA.
2. Registrar sus registros DNS A y PTR en FreeIPA.

Es idempotente: ejecutarlo sobre una VM ya enrolada no repite el
enrolamiento ni produce cambios.

La contraseña de administrador de FreeIPA nunca se escribe en claro
en el playbook: se cifra con Ansible Vault
(`group_vars/all/vault.yml`, ver plantilla `.example` en este repo) y
se referencia como `{{ vault_ipa_admin_password }}`.

```bash
ansible-vault create group_vars/all/vault.yml
# contenido: vault_ipa_admin_password: "..."

ansible-playbook \
  -i inventories/lab/netbox.yml \
  playbooks/freeipa_client.yml \
  --limit <vm> \
  --ask-vault-pass
```

Para automatizar despliegues sin introducir la contraseña de Vault a
mano cada vez, se guarda en un fichero local protegido en
`automation` (fuera de Git):

```bash
mkdir -p ~/.ansible && chmod 700 ~/.ansible
vi ~/.ansible/vault_pass    # solo la contraseña de Vault
chmod 600 ~/.ansible/vault_pass
```

## Despliegue de extremo a extremo

`terraform/lab/deploy_vm.sh` (ver `docs/terraform.md`) orquesta todo
el flujo: crea la VM con Terraform, espera a que aparezca en el
inventario dinámico, limpia claves SSH antiguas del `known_hosts`,
espera conectividad, y finalmente ejecuta `freeipa_client.yml` para
enrolarla y publicar su DNS. El resultado:

```
Terraform → KVM → NetBox → Cloud-Init → Ansible → FreeIPA → DNS
```

## Mantenimiento: limpiar `/etc/hosts`

Una vez el DNS de FreeIPA funciona para todo el laboratorio, las
entradas manuales en `/etc/hosts` quedan redundantes y pueden
desincronizarse. `playbooks/cleanup_hosts.yml` hace backup, las
retira y verifica que la resolución sigue funcionando (ver
`docs/freeipa-dns.md` para el detalle).
