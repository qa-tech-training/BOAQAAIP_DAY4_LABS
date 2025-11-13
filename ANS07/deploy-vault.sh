#!/bin/bash
sudo apt-get update
which docker || sudo apt-get install -y docker.io
docker run -d -p 8200:8200 -e 'VAULT_DEV_ROOT_TOKEN_ID=example-vault-token-1234' hashicorp/vault