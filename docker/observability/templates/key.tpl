{{ with secret "pki_int/issue/otel-collector" "common_name=otel-collector" "ttl=720h" }}
{{ .Data.private_key }}
{{ end }}
