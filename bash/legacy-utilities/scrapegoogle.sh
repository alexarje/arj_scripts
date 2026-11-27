#!/bin/sh
xmlgetnext () {
   local IFS='>'
   read -d '<' TAG VALUE
}

cat $1 | while xmlgetnext ; do
   echo "<$TAG>{$VALUE}"
done

