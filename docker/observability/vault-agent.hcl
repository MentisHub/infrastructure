pid_file = "/tmp/pidfile"

vault {
  address = "http://vault:8200"
}

auto_auth {
  method {
    type = "approle"
    
    config = {
      role_id_file_path = "/etc/otel/creds/otel-role-id"
      secret_id_file_path = "/etc/otel/creds/otel-secret-id"
      remove_secret_id_file_after_reading = false
    }
  }

  sink {
    type = "file"
    config = {
      path = "/tmp/vault-token"
    }
  }
}

template {
  source = "/vault/templates/cert.tpl"
  destination = "/etc/otel/certs/otel-server.crt"
}

template {
  source = "/vault/templates/key.tpl"
  destination = "/etc/otel/certs/otel-server.key"
  perms = "0600"
}

template {
  source = "/vault/templates/ca.tpl"
  destination = "/etc/otel/certs/ca.crt"
}
