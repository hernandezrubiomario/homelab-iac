#!/bin/bash
# Carga en bloque, vía API, las IPs ya utilizadas en el laboratorio
# para que NetBox deje de considerarlas disponibles.
#
# Uso:
#   export NETBOX_TOKEN='tu-token-v2'
#   ./import_netbox_ips.sh netbox_ips.txt.example
#
# Formato del fichero de entrada (uno por línea):
#   direccion/prefijo|nombre_dns|descripcion

set -euo pipefail

INPUT_FILE="${1:?Uso: $0 <fichero-de-ips>}"

while IFS='|' read -r address dns_name description
do
  echo "Registrando $address - $dns_name"
  curl -s -X POST \
    -H "Authorization: Bearer $NETBOX_TOKEN" \
    -H "Content-Type: application/json" \
    http://netbox.lab.local/api/ipam/ip-addresses/ \
    -d "{
      \"address\": \"$address\",
      \"status\": \"active\",
      \"dns_name\": \"$dns_name\",
      \"description\": \"$description\"
    }" | jq '{id,address,dns_name,description}'
done < "$INPUT_FILE"
