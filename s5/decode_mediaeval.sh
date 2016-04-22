#!/bin/bash
# Xavier Anguera - ELSA Corp. 2016
# This script runs the decoding of a directory of wav files
# USAGE: $0 input_directory output_directory

# Change directory to the location of this script.
cwd=$PWD
cd $(dirname $0)

#define some paths
. path.sh || exit 1
. cmd.sh || exit 1

#default values
inputDir=
outputDir=$PWD/output #defaults to the output dir
numParallel=1
run_cmd=run.pl

read -d '' help_message << HELPMESSAGE
==> Mediaeval Zero Cost decoding script <==
Usage: $0 [options]
  --inputDir: location where to find 16KHz 16bit .wav files to decode
  --outputDir: location where to write decoding output, defaults to ./output
  --numParallel: number of parallel decoding jobs to run
HELPMESSAGE

#parse input parameters
[ $# -gt 1 ] && echo "$0 $@"  # Print the command line for logging
. parse_options.sh || exit 1;

#check that input and output directories are defined
if [ -z "$inputDir" ] || [ -z "$outputDir" ]; then
	echo "[ERROR]: either input or output directories are not defined"
	printf "$help_message\n"
	exit
fi

#checking existence of directories
if [ ! -d ${inputDir} ]; then
	echo "[ERROR]: input directory <<$inputDir>> does not exist"
	exit
fi	

#false && \
{
	#prepare the data
	rm -Rf $outputDir/data
	mkdir -p $outputDir/data
	#prepare wav.scp, utt2spk and text files
	for aFile in ${inputDir}/*.wav; 
	do
		name=$(basename $aFile .wav) 
		echo "$name $aFile" >> $outputDir/data/wav.scp	
		echo "$name $name" >> $outputDir/data/utt2spk
		echo "$name <unk>" >> $outputDir/data/text
	done
	utils/utt2spk_to_spk2utt.pl $outputDir/data/utt2spk > $outputDir/data/spk2utt
}

#false && \
{
	#compute features
	featsData=$outputDir/data
	steps/make_mfcc.sh --cmd "$run_cmd" --nj $numParallel $featsData $featsData/log $featsData/data || exit 1;
	steps/compute_cmvn_stats.sh $featsData $featsData/log  $featsData/data || exit 1;
	utils/fix_data_dir.sh $featsData || exit 1 # remove segments with problems
}

#false && \
{
	#perform decoding (word level)
	steps/decode_si_mediaeval.sh --nj $numParallel --cmd "$run_cmd" --model exp/tri1/final.mdl --config conf/decode.conf\
		--skip-scoring true --srcDir exp/tri1  \
		exp/tri1/graph $featsData $outputDir/decoding_words || exit 1

	if [ -d $outputDir/decoding_words ]; then
		lattice-align-words --output-error-lats=true data/lang/phones/word_boundary.int exp/tri1/final.mdl "ark:gunzip -c $outputDir/decoding_words/lat.*.gz |" ark:- | \
		lattice-to-ctm-conf --decode-mbr=true ark:- - | \
		 utils/int2sym.pl -f 5 data/lang/words.txt > $outputDir/decoding_words/output.ctm || exit 1;
	fi
}

#false && \
{
	#perform decoding (phone level)
	steps/decode_si_mediaeval.sh --nj $numParallel --cmd "$run_cmd" --model exp/tri1/final.mdl --config conf/decode.conf\
		--skip-scoring true --srcDir exp/tri1  \
		exp/tri1/graph_phn $featsData $outputDir/decoding_phones || exit 1

	if [ -d $outputDir/decoding_phones ]; then
		lattice-align-phones --output-error-lats=true exp/tri1/final.mdl "ark:gunzip -c $outputDir/decoding_phones/lat.*.gz |" ark:- | \
		lattice-to-ctm-conf --decode-mbr=true ark:- - | \
		 utils/int2sym.pl -f 5 data/lang_phn/words.txt > $outputDir/decoding_phones/output.ctm || exit 1;
	fi
}

