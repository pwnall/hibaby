#!/bin/sh

mkdir -p dms/tufts
cd dms/tufts
PORT=16990 CHROME="/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary" ruby ../../dms.rb Tufts
cd ../..

mkdir -p dms/mit
cd dms/mit
PORT=16990 CHROME="/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary" ruby ../../dms.rb MIT
cd ../..
