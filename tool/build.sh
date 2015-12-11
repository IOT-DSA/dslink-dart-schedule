#!/usr/bin/env bash
set -e

if [ -d build ]
then
  rm -rf build
fi

mkdir build

pub get
cp -R -L packages/ build/
cp -R bin lib dslink.json build/
dart tool/package_map.dart
cd build
zip -r ../../../files/dslink-dart-schedule.zip .
