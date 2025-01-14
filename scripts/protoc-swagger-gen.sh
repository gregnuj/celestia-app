#!/usr/bin/env bash

set -eo pipefail

work_dir="$(dirname "$(dirname "$(realpath "$0")")")"

# Create a temporary directory and store its name in a variable.
tmp_dir=$(mktemp -d)

# Exit if the temp directory wasn't created successfully.
if [ ! -e "$tmp_dir" ]; then
    >&2 echo "Failed to create temp directory"
    exit 1
fi

# Make sure the temp directory gets removed on script exit.
trap "exit 1"           HUP INT PIPE QUIT TERM
trap 'rm -rf "$tmp_dir"'  EXIT

# Get the path of the cosmos-sdk repo from go/pkg/mod
gogo_proto_dir=$(go list -f '{{ .Dir }}' -m github.com/gogo/protobuf)
google_api_dir=$(go list -f '{{ .Dir }}' -m github.com/grpc-ecosystem/grpc-gateway)
cosmos_sdk_dir=$(go list -f '{{ .Dir }}' -m github.com/cosmos/cosmos-sdk)
cosmos_proto_dir=$(go list -f '{{ .Dir }}' -m github.com/cosmos/cosmos-proto)
ibc_dir=$(go list -f '{{ .Dir }}' -m github.com/cosmos/ibc-go/v6)

proto_dirs=$(find \
    $cosmos_sdk_dir/proto \
    $cosmos_proto_dir/proto \
    $work_dir/proto \
    -path -prune -o -name '*.proto' -print0 | xargs -0 -n1 dirname | sort | uniq
    #$ibc_dir/proto \
)

cd $google_api_dir
go mod download
go build -o $tmp_dir/protoc-gen-swagger protoc-gen-swagger/main.go
cd $tmp_dir

PATH=./:$PATH

for dir in $proto_dirs; do
  # generate swagger files (filter query files)
  query_file=$(find "${dir}" -maxdepth 1 \( -name 'query.proto' -o -name 'service.proto' \))
  
  if [[ ! -z "$query_file" ]]; then
    #-I "$ibc_dir/proto" \
    protoc  \
    -I "$gogo_proto_dir" \
    -I "$gogo_proto_dir/protobuf" \
    -I "$google_api_dir" \
    -I "$google_api_dir/third_party" \
    -I "$google_api_dir/third_party/googleapis" \
    -I "$cosmos_proto_dir/proto" \
    -I "$cosmos_sdk_dir/proto" \
    -I "$work_dir/proto" \
      "$query_file" \
    --swagger_out $tmp_dir \
    --swagger_opt logtostderr=true \
    --swagger_opt fqn_for_swagger_name=true \
    --swagger_opt simple_operation_ids=true
  fi
done

npm install -g swagger-combine
npx swagger-combine -f yaml \
    $work_dir/docs/swagger-ui/config.json \
    -o $work_dir/docs/swagger-ui/swagger.yaml \
    --continueOnConflictingPaths true \
    --includeDefinitions true
