#!/bin/bash

pushd `pwd`

cd /var/www/html/

for i in themes/*; do (cd "$i" && npm install && npm run build --if-present); done
for i in plugins/*; do (cd "$i" && npm install && npm run build --if-present); done

popd
