#!/bin/bash

set -e

CLI=/usr/local/bin/entrypoint.sh

SERVICES=$(ls /proto)

gen_go() {
  $CLI \
    -l go \
    -d "/proto/$srv" \
    -o "/defs/gosdk/$srv"
}

gen_grpc_gateway() {
  cfg_file=gateway.http.yaml;
  dst="/defs/gosdk/$srv";

  if [[ -e $cfg_file ]]; then
    proto_files=`ls -- *.proto`;

    protoc -I. -I/opt/include \
        --grpc-gateway_out=logtostderr=true,grpc_api_configuration=$cfg_file:$dst \
        $proto_files
  fi
}

gen_node() {
  $CLI \
    -l node \
    -d "/proto/$srv" \
    -o "/defs/nodesdk/$srv" \
    --with-typescript
}

gen_java() {
  $CLI \
    -l java \
    -d "/proto/$srv" \
    -o "/defs/javasdk"
}

gen_python() {
  $CLI \
    -l python \
    -d "/proto/$srv" \
    -o "/defs/pythonsdk/$srv"
}

for srv in $SERVICES; do
  cd "/proto/$srv";
  gen_go "$srv";
  gen_grpc_gateway "$srv";
  gen_node "$srv";
  gen_java "$srv";
  gen_python "$srv";
done

for sdk in gosdk nodesdk javasdk pythonsdk
do
  chown -R 1000:1000 "/defs/$sdk"
done
