#!/usr/bin/python
# -*- coding: utf-8 -*-
# It parses the output of ali-to-phones --write-lengths=true to convert it to ctm format

import argparse, re, io, codecs, os, sys

parser = argparse.ArgumentParser(usage='Conversion of ali-to-phones output to ctm.')
parser.add_argument('dict', help='Dictionary assigning phonemes to symbols')
parser.add_argument('--do_ctm', action='store_true', help='Flag to tell the program to output CTM format instead of the default LAB format')
parser.add_argument('--noContext', action='store_true', help='Flag to tell the program to eliminate the phone context and join (if necessary) equal adjacent phones')
parser.add_argument('--fr', help='Frame rate')
args = parser.parse_args()

if args.fr is None:
    frameRate = 0.01
else:
    frameRate = float(args.fr)


#read the dictionary file into memory
dict={}
if not os.path.isfile(args.dict):
    print "[ERROR]: Dictionary file does not exist"
    exit(-1)
else:
    with open(args.dict) as f:
        for line in f:
            dict[line.split()[1]] = line.split()[0]
            #print "Reading symbol <%s> with content <%s>" % (line.split()[1], line.split()[0])

#read the stdin and process it. We only expect one single line
#inputList = sys.stdin.readlines()
#for line in inputList:
#    print "==============> Read: <%s>" % line

inputLine = sys.stdin.readline()

#eliminate the beginning text, until the first space. This text just identifies the command we juts ran
#also eliminate the \n at the end
testID = re.match("^\S* ", inputLine).group(0).rstrip()
inputLine = re.sub("^\S* ", "", inputLine.rstrip());

#parse the line and write the output

if False:
    prevTime = 0 #time of the previous element
    ## CTM output
    if args.do_ctm == True:
        for elem in inputLine.split(';'):
            duration = frameRate * int(elem.split()[1])
            print "%s 1 %.2f %.2f %s" % (testID , prevTime, duration, dict[elem.split()[0]])
            prevTime += duration
    else: # we output lab format
        for elem in inputLine.split(';'):
            endTime = prevTime + frameRate * int(elem.split()[1])
            print "%.2f %.2f %s" % (prevTime, endTime, dict[elem.split()[0]])
            prevTime = endTime
else:
    ##version taking care of eliminating the context##
    startTime = 0
    duration = 0
    outPhone=""
    for elem in inputLine.split(';'):
        phone =  dict[elem.split()[0]]
        #if requested, we eliminate the context
        if args.noContext == True:
            phone = re.sub("_.*$", "", phone)

        if not outPhone: #first line
            outPhone = phone
            duration = frameRate * int(elem.split()[1])
        else: #other lines
            if outPhone == phone:
                duration += frameRate * int(elem.split()[1])
            else:
                #we print what we have until now, and start over
                if args.do_ctm == True:
                    print "%s 1 %.2f %.2f %s" % (testID , startTime, duration, outPhone)
                else:
                    print "%.2f %.2f %s" % (startTime, startTime+duration, outPhone)
                startTime += duration
                duration = frameRate * int(elem.split()[1])
                outPhone = phone
    #at the end, if I still have content, I output it
    if duration > 0:
        if args.do_ctm == True:
            print "%s 1 %.2f %.2f %s" % (testID , startTime, duration, outPhone)
        else:
            print "%.2f %.2f %s" % (startTime, startTime+duration, outPhone)



