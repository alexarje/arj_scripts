#!/usr/bin/env python
# coding: utf-8

import sys
import os
import datetime
import shutil

datetime = datetime.datetime.now()
prefix = datetime.strftime('%y_%m_%d_')

if len(sys.argv) == 1:
    command = os.path.split(sys.argv[0])[-1]
    print("usage: {0} file...".format(command))

else:
    for _file in sys.argv[1:]:
        newfile = prefix+_file
        print("New file: {0}".format(newfile))
        shutil.move(_file, newfile)
