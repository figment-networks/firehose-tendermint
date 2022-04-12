#!/usr/bin/env bash

fh_bin="firehose-tendermint"

if [[ -z $(which $fh_bin || true) ]]; then
  echo "You must install the firehose-binary first. See README for instructions"
  exit 1
fi

echo "Starting firehose"
pushd tmp
$fh_bin start ingestor # only running node is supported
popd
