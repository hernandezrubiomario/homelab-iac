# NetBox como IPAM / fuente de verdad

## Qué es y qué papel juega

NetBox es una aplicación web de código abierto que actúa como fuente
de verdad (Source of Truth) de la infraestructura de red: redes, IPs,
VMs, interfaces, VLANs, sitios, racks, etc. Se describe habitualmente
como DCIM + IPAM. En este laboratorio, NetBox es el IPAM del que
Terraform obtiene/reserva las IPs de las nuevas VMs.

Requisitos de la versión actual: Python 3.12+, PostgreSQL 15+ (14
está entrando en fin de soporte) y Redis.

## Arquitectura de publicación

```
Cliente → HAProxy (VIP web, Keepalived) → Nginx (nodo netbox) → Gunicorn → NetBox/Django
```

- **Keepalived** mantiene la VIP web disponible (failover entre
  HAProxy-1 y HAProxy-2).
- **HAProxy** recibe el tráfico y lo distribuye hacia el nodo NetBox
  (ver `haproxy/netbox.cfg.snippet`).
- **Nginx** sirve `/static/` y hace de proxy local hacia Gunicorn
  (ver `netbox/nginx-netbox.conf`).
- **Gunicorn** ejecuta la aplicación Django y solo escucha en
  `127.0.0.1:8001` — nunca expuesto directamente a la red.

## Base de datos: PostgreSQL HA reutilizado

NetBox no tiene su propio PostgreSQL: reutiliza el clúster Patroni +
HAProxy + Keepalived ya existente en el laboratorio, conectándose
siempre a través de la VIP (`postgres-vip.lab.local:5432`). Si el
Leader de Patroni cambia, HAProxy redirige el tráfico automáticamente
sin tocar la configuración de NetBox.

Alta de base de datos y usuario (desde cualquier nodo con `psql`):

```sql
CREATE USER netbox WITH PASSWORD '...';
CREATE DATABASE netbox OWNER netbox;
```

Como `pg_hba.conf` está gestionado por Patroni, las reglas de acceso
se añaden vía `patronictl edit-config`, no editando el fichero a
mano, y se restringen a las IPs de los nodos HAProxy (que es por
donde realmente llegará el tráfico de NetBox):

```yaml
pg_hba:
  - host netbox netbox 192.168.10.30/32 scram-sha-256
  - host netbox netbox 192.168.10.31/32 scram-sha-256
```

```bash
patronictl -c /etc/patroni/patroni.yml reload postgres-ha
```

## Instalación (resumen)

```bash
useradd --system --shell /sbin/nologin netbox
mkdir -p /opt/netbox && chown netbox:netbox /opt/netbox

cd /opt
git clone --branch v4.6.7 --depth 1 \
  https://github.com/netbox-community/netbox.git netbox-4.6.7
ln -s /opt/netbox-4.6.7 /opt/netbox
chown -R netbox:netbox /opt/netbox-4.6.7
```

El enlace simbólico `/opt/netbox -> /opt/netbox-X.Y.Z` permite que
servicios y configuraciones siempre apunten a `/opt/netbox`; una
actualización futura solo cambia el destino del symlink
(`ln -sfn /opt/netbox-4.7.0 /opt/netbox`).

Configuración principal en `netbox/netbox/configuration.py` (ver
plantilla consolidada en `netbox/configuration.py.example` de este
repo): base de datos, Redis, `SECRET_KEY`, `ALLOWED_HOSTS` y
`API_TOKEN_PEPPERS`.

```bash
cd /opt/netbox
./upgrade.sh   # crea el venv, instala dependencias, migra la BD, recopila estáticos
```

Gunicorn y los servicios systemd (`netbox.service`, `netbox-rq.service`)
se copian de las plantillas oficiales del propio repositorio de
NetBox (`contrib/gunicorn.py`, `contrib/netbox.service`,
`contrib/netbox-rq.service`).

## API y tokens

NetBox 4.6 recomienda tokens API v2 (v1 está deprecado), protegidos
mediante `API_TOKEN_PEPPERS`. El token se crea desde la interfaz web
(usuario → API Tokens) con permiso de escritura, ya que Terraform
necesita reservar IPs.

**Importante**: si NetBox se accede a través de HAProxy, las
peticiones le llegan con la IP de los nodos HAProxy, no la del
cliente original. El campo *Allowed IPs* del token debe incluir
ambos HAProxy (`192.168.10.30/32,192.168.10.31/32`) para que siga
funcionando tras un failover de Keepalived.

## Cargar el estado inicial de IPs

Antes de dejar que Terraform reserve IPs automáticamente, hay que
decirle a NetBox qué direcciones ya están en uso. El prefijo de red
se crea desde la interfaz (`IPAM → Prefixes → Add`), y las IPs
existentes se cargan por API con
`netbox/scripts/import_netbox_ips.sh` (ver
`netbox/scripts/netbox_ips.txt.example` para el formato de entrada).

Convención de numeración usada en este laboratorio:

- `.1 – .50` → infraestructura fija.
- `.51 – .199` → pool dinámico para Terraform.
- `.200 – .254` → reserva.

El rango de Terraform se crea como *IP Range* en NetBox
(`IPAM → IP Ranges → Add`) y Terraform lo localiza por su
`description` (ver `terraform/lab/netbox.tf`), no por ID, para no
depender de un valor concreto en NetBox.

## Integración con Terraform y Ansible

- `terraform/lab/netbox.tf` reserva una IP del pool, registra la VM,
  su interfaz y su IP primaria (`docs/terraform.md`).
- El inventario dinámico de Ansible (`ansible/inventories/lab/netbox.yml`)
  usa la misma API para descubrir automáticamente las VMs nuevas,
  usando su IP primaria como `ansible_host`.
