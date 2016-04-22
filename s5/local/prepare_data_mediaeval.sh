#!/bin/bash
#this script prepares the data by splitting it into two sets (train and test) and creating the necessary lists
#list of locations where to find the .wav and .info files for each of the databases
#usage: $0 <data_directory>

# we input the directory where to find the training data
if [ ! -d "$1" ]; then
  echo "[ERROR]: data directory $1 not found"
fi
databases=($1);

#percentage of files used for training (the rest goes for test) written as how many for every 10 files
trainPerten=9

#path prefix for the output files
pathPrefix=./data

##############################################

#if not present, create the output directories
mkdir -p ${pathPrefix}/train
mkdir -p ${pathPrefix}/test
mkdir -p ${pathPrefix}/local/dict
mkdir -p ${pathPrefix}/local/lm

#create the wav.scp file for training and for testing, taking into account the percentage split we defined before
rm -f ${pathPrefix}/train/wav.scp
rm -f ${pathPrefix}/train/text
rm -f ${pathPrefix}/train/utt2spk
rm -f ${pathPrefix}/test/wav.scp
rm -f ${pathPrefix}/test/text
rm -f ${pathPrefix}/test/utt2spk
rm -f ${pathPrefix}/local/dict/lexicon.txt
rm -f ${pathPrefix}/local/lm/text
rm -f ${pathPrefix}/local/dict/extra_questions.txt
rm -f ${pathPrefix}/local/dict/nonsilence_phones.txt
rm -f ${pathPrefix}/local/dict/optional_silence.txt
rm -f ${pathPrefix}/local/dict/silence_phones.txt

# Using system clock to create unique tmp files among differences instances of this script
tmp_dict=/tmp/`date +%s%N | cut -b1-13`
sleep 1
tmp_lmtext=/tmp/`date +%s%N | cut -b1-13`

#the beginning of the lexicon is always the same
echo "!SIL SIL" > ${pathPrefix}/local/dict/lexicon.txt
echo "<UNK> SPN" >> ${pathPrefix}/local/dict/lexicon.txt
echo "<SPOKEN_NOISE> SPN" >> ${pathPrefix}/local/dict/lexicon.txt

#the silence phone is the sil phone (more to come if in other datasets we have extra markings)
echo "SIL" >> ${pathPrefix}/local/dict/silence_phones.txt
echo "SPN" >> ${pathPrefix}/local/dict/silence_phones.txt
echo "SIL" >> ${pathPrefix}/local/dict/optional_silence.txt

#for now we do not have any extra questions
touch ${pathPrefix}/local/dict/extra_questions.txt

#collect the training materials
for database in "${databases[@]}"
do
  counter=0
  #in the case of ELSA data the input directory has a set of links to directories with the info, we need to recursively search for them
  for file in $(find -L ${database} -name '*.wav'); do
	  let counter+=1
		
	  baseFileName=$(basename $file)
	  echo "Processing file $baseFileName"
	
	  uttID=$( basename ${file} .wav )

		# we expect the files all to have the following format: spkXXX_uttYYY
	  speakerID=$( echo ${uttID} | sed 's/_[^_]*$//' )

	  #Accompanying every audio file I have a txt file with the text and phonetic transcription, in two columns
	  # Format: word {{tab}} transcript
		#In the ELSA setup I have a single line with a whole sentence merged into a single word and its transcription
	  infoFile=$( echo ${file} | sed 's/.wav/.txt/' )
	  	
  	#create the lexicon by parsing the information file line by line
  	#NOTE that we add lexicon entries both for training and testing data, which is not strictly fair
    fileText=""
	  oldIFS=${IFS}
	  IFS=''
	  while read line;
	  do
	    wordTrans=$( echo ${line} | awk -F $'\t' '{print $1}' | sed 's/  */ /g' | sed 's/ *$//')
	    phoneTrans=$( echo ${line} | awk -F $'\t' '{print $2}' | sed 's/  */ /g' | sed 's/ *$//')
	    #echo "Word trans <${wordTrans}> phone trans <${phoneTrans}>"
	    fileText+=" "${wordTrans}
	    echo "${wordTrans} ${phoneTrans}" >> ${tmp_dict}
	  done < ${infoFile}
	  IFS=${oldIFS}
	  fileText=$(echo ${fileText} | sed 's/^ *//') #eliminate the space at the beginning
	  
    #assign each file either for training or testing
    if [ $counter -le $trainPerten ]
    then
		  echo "${uttID} $file" >> ${pathPrefix}/train/wav.scp
		  echo "${uttID} ${fileText}" >> ${pathPrefix}/train/text
		  echo "${uttID} ${speakerID}" >> ${pathPrefix}/train/utt2spk
		  
		  #create the LM training text
			#NOTE: for ELSA we are not interested in the LM, but I leave it here for now...
		  echo ${fileText} >> $tmp_lmtext
	  else
		  echo "${uttID} $file" >> ${pathPrefix}/test/wav.scp
		  echo "${uttID} ${fileText}" >> ${pathPrefix}/test/text
      echo "${uttID} ${speakerID}" >> ${pathPrefix}/test/utt2spk
	  fi

	  #when we get to 10, we start over
	  if [ $counter -eq 10 ]
	  then
		  let counter=0
	  fi
  done
done

#make sure the lists are sorted
export LC_ALL=C #just making sure (TODO:this should be defined in path.sh!!!)
tmpFile=/tmp/tmpFile${RANDOM}
cat ${pathPrefix}/train/wav.scp | sort | uniq > $tmpFile; mv $tmpFile ${pathPrefix}/train/wav.scp
cat ${pathPrefix}/train/text | sort | uniq > $tmpFile; mv $tmpFile ${pathPrefix}/train/text
cat ${pathPrefix}/train/utt2spk | sort | uniq > $tmpFile; mv $tmpFile ${pathPrefix}/train/utt2spk
cat ${pathPrefix}/test/wav.scp | sort | uniq > $tmpFile; mv $tmpFile ${pathPrefix}/test/wav.scp
cat ${pathPrefix}/test/text | sort | uniq > $tmpFile; mv $tmpFile ${pathPrefix}/test/text
cat ${pathPrefix}/test/utt2spk | sort | uniq > $tmpFile; mv $tmpFile ${pathPrefix}/test/utt2spk

#output the dictionary
cat $tmp_dict | sed 's/^!SIL .*//' | sed 's/^\<UNK\> .*//' | sed 's/^\<SPOKEN_NOISE\> .*//' | sed '/^ *$/d' | sort | uniq >> ${pathPrefix}/local/dict/lexicon.txt
rm -f $tmp_dict

#output the LM training text
cat $tmp_lmtext | sed '/^ *$/d' | sort | uniq >> ${pathPrefix}/local/lm/text
rm -f $tmp_lmtext

#list of all phonemes
cat ${pathPrefix}/local/dict/lexicon.txt | cut -d' ' -f2- | tr '\n' ' ' | sed 's/^ //g'  | sed 's/  */ /g' | tr ' ' '\n' | sort | uniq | grep -v "SIL" | grep -v "SPN" > ${pathPrefix}/local/dict/nonsilence_phones.txt
