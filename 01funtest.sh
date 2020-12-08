#!/bin/bash

demoFun(){
  echo "函数测试"
}

case $1 in
  "one")
      echo "one"
  ;;
  *)
    echo "USAGE:$0 {one|two}"
esac