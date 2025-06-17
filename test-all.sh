#!/usr/bin/env bash

ID="$2"
grade_file="grade/$ID"
testcase="tmp/$ID"

echo -n "" > $grade_file
mkdir -p $testcase

rm -rf "$testcase/testcase"
unzip testcase.zip -d "$testcase" >/dev/null 2>&1

for i in {1..5}; do
    ./test.sh "$1" "$testcase/testcase/$i" >> $grade_file 2>&1
done

rm -rf "$testcase/testcase"
