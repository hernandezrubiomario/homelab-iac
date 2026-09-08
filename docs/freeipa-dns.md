# FreeIPA como DNS del laboratorio

## Qué es y qué papel juega

FreeIPA es una plataforma centralizada de identidad para Linux
(similar, a grandes rasgos, a un Active Directory). Integra:

- **LDAP** — usuarios, grupos, equipos.
- **Kerberos** — autenticación centralizada.
- **CA/certificados** — gestión de certificados.
- **DNS** — resolución centralizada de nombres.
- **Políticas de acceso y sudo.**

En este laboratorio, la división de responsabilidades es:

- **NetBox** sabe qué IPs están usadas y a quién pertenecen (IPAM).
- **FreeIPA DNS** permite encontrarlas por nombre.
- **HAProxy** publica servicios de alta disponibilidad detrás de
  nombres como `netbox.lab.local`.

## Zonas gestionadas

- `lab.local` — zona directa (nombre → IP).
- `10.168.192.in-addr.arpa` — zona inversa (IP → nombre).

FreeIPA crea automáticamente los registros de servicio (`_kerberos`,
`_ldap._tcp`, `_kpasswd`, etc.) necesarios para que los clientes
localicen LDAP y Kerberos vía DNS SRV.

## Dos tipos de nombres

- **Hosts reales**: identifican una máquina concreta
  (`automation.lab.local` → `192.168.10.28`).
- **Nombres de servicio**: identifican un servicio de alta
  disponibilidad, no una máquina fija (`postgres-vip.lab.local` →
  `192.168.10.32`, gestionada por Keepalived entre HAProxy-1 y
  HAProxy-2).

La misma VIP puede tener dos nombres con función distinta: por
ejemplo, `192.168.10.33` responde tanto a `netbox.lab.local` (el
servicio publicado) como a `web-vip.lab.local` (el nombre genérico de
la VIP web), mientras que `netbox-backend.lab.local` identifica
únicamente la VM real donde corre NetBox.

## Registrar hosts y VIPs

Los registros A/PTR se gestionan con la CLI de FreeIPA:

```bash
ipa dnsrecord-add lab.local <nombre> --a-rec=<ip>
ipa dnsrecord-add 10.168.192.in-addr.arpa <ultimo-octeto> --ptr-rec=<nombre>.lab.local.
```

Para una VIP con doble nombre (p. ej. `netbox` y `web-vip` apuntando
a la misma IP), basta con un único PTR sobre el nombre más
descriptivo — no hace falta duplicar el PTR.

Verificación:

```bash
dig @192.168.10.10 <nombre>.lab.local +short
dig @192.168.10.10 -x <ip> +short
```

## Hacer que las VMs usen FreeIPA como DNS por defecto

El objetivo es poder hacer `dig netbox.lab.local` sin indicar
`@192.168.10.10` explícitamente. Cada VM necesita:

- DNS principal: `192.168.10.10`
- Dominio de búsqueda: `lab.local`

Comprobación rápida en cualquier host:

```bash
nmcli device show | grep -E 'GENERAL.CONNECTION|IP4.DNS|IP4.DOMAIN'
cat /etc/resolv.conf
dig netbox.lab.local +short
getent hosts netbox.lab.local
```

`dig` consulta DNS directamente; `getent` usa el mecanismo normal de
resolución de Linux (`/etc/nsswitch.conf`, DNS, `/etc/hosts`, etc.),
por lo que es la comprobación más representativa de lo que verá una
aplicación real.

Para comprobar todas las VMs de una vez desde `automation`:

```bash
ansible all -m shell -a \
  'nmcli device show | grep "IP4.DNS" | head -1; echo "resolv.conf:"; grep "^nameserver" /etc/resolv.conf'
```

## Split DNS en el host anfitrión KVM

El host KVM necesita resolver `lab.local` contra FreeIPA sin perder su
DNS normal de Internet. Se configura reenviando solo ese dominio a
FreeIPA mediante `dnsmasq` (gestionado por NetworkManager):

```
# /etc/NetworkManager/dnsmasq.d/lab-local.conf
server=/lab.local/192.168.10.10
```

```bash
sudo systemctl restart NetworkManager
dig netbox.lab.local +short   # resuelve vía FreeIPA
dig google.com +short         # sigue resolviendo vía Internet
```

Así FreeIPA es autoritativo para el laboratorio sin que el
funcionamiento normal de Internet del host dependa de la VM FreeIPA.

## Eliminar dependencias de `/etc/hosts`

Una vez el DNS funciona, las entradas manuales en `/etc/hosts` quedan
duplicadas y pueden desincronizarse. Se retiran con
`ansible/playbooks/cleanup_hosts.yml`, que hace backup, elimina las
líneas `192.168.10.x` y verifica que la resolución sigue funcionando
vía FreeIPA:

```bash
cd ansible
ansible-playbook -K playbooks/cleanup_hosts.yml
```

El playbook es idempotente: ejecutarlo de nuevo sobre un host ya
limpio no produce cambios.
