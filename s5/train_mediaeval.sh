#!/bin/bash

# This recipe is based on the egs/swbd/s5b recipe, by Arnab Ghoshal.
# The swbd recipe was downscaled by Karel Vesely (iveselyk@fit.vutbr.cz).
# Then it was reshuffled by Xavier Anguera - ELSA Corp (xavier@elsanow.io)
#
# This is a shell script, but it's recommended that you run the commands one by
# one by copying and pasting into the shell.
# Usage: $0 <training_data_directory>

. cmd.sh
. path.sh

JOBS=4 #how many jobs we split into

##########################################################################
### DATA PREPARATION
##########################################################################
#false && \
{
  #check that an input directory is provided
  if [ "$#" -ne 1 ]; then
    echo "[ERROR] Illegal number of parameters, usage is: $0 training_dir"
    exit -1
  fi

	echo "Preparing the data..."
	#
	local/prepare_data_mediaeval.sh $1 || exit 1
	echo "Preparing the language directory..."
	utils/prepare_lang.sh data/local/dict "<SPOKEN_NOISE>" data/local/lang data/lang || exit 1
}

#false && \
{
	echo "Training the language model..."	
	# We use MITLM, distributed under MIT license
	#NOTE: automatic package download and compilation might not work on OSX
	lm_corpus=data/local/lm/text
	local/train_lm_mitlm.sh $lm_corpus data/local/dict/lexicon.txt data/local/lm || exit 1
	LM=data/local/lm/trn.o3g.kn.gz
	utils/format_lm.sh data/lang $LM data/local/dict/lexicon.txt data/lang_test || exit 1
}


##########################################################################
### FEATURE EXTRACTION
##########################################################################

#false && \
{
	echo "Performing feature extraction on the data"
	
	# Convert the spk2utt mapping
	utils/utt2spk_to_spk2utt.pl data/train/utt2spk > data/train/spk2utt
	utils/utt2spk_to_spk2utt.pl data/test/utt2spk > data/test/spk2utt
 
	# Create MFCCs for the train set
	data=data/train
	steps/make_mfcc.sh --nj ${JOBS} --cmd "$train_cmd" $data $data/log $data/data || exit 1;
	steps/compute_cmvn_stats.sh $data $data/log $data/data || exit 1;
	# Remove the small number of utterances that couldn't be extracted for some 
	# reason (e.g. too short; no such file).
	utils/fix_data_dir.sh $data || exit 1;
	
	# Create MFCCs for the test set
	data=data/test
	steps/make_mfcc.sh --cmd "$train_cmd" --nj ${JOBS} $data $data/log $data/data || exit 1;
	steps/compute_cmvn_stats.sh $data $data/log  $data/data || exit 1;
	utils/fix_data_dir.sh $data || exit 1 # remove segments with problems
}

##########################################################################
### MAKING SUBSETS
##########################################################################
 
#false && \
{
	echo "Making training and testing subsets"
	# Split the MFCCs to dev/nodev set:
  # usually we take 10% of the data for train & dev
  numFiles=$(cat data/train/feats.scp | wc -l)
  numFilesDev=$(echo "$numFiles/10" | bc)
  numFilesTrain=$[${numFiles} - ${numFilesDev}]

	utils/subset_data_dir.sh --first data/train ${numFilesDev} data/train_dev
	utils/subset_data_dir.sh --last data/train ${numFilesTrain} data/train_nodev

	#we want to start with approx. 40% of the shortest utterances, easier on the system
  numFilesInit=$(echo "scale=0; ${numFiles}*4/10" | bc) #40% of the total data
	utils/subset_data_dir.sh --shortest data/train_nodev ${numFilesInit} data/train_4kshort

	# Show the size of training sets in hours:
	hours_train=$(feat-to-len scp:data/train/feats.scp ark,t:- | awk '{sum_frames += $2;} END{print sum_frames/100.0/3600;}')
	hours_train_dev=$(feat-to-len scp:data/train_dev/feats.scp ark,t:- | awk '{sum_frames += $2;} END{print sum_frames/100.0/3600;}')
	hours_train_nodev=$(feat-to-len scp:data/train_nodev/feats.scp ark,t:- | awk '{sum_frames += $2;} END{print sum_frames/100.0/3600;}')
	hours_train_4kshort=$(feat-to-len scp:data/train_4kshort/feats.scp ark,t:- | awk '{sum_frames += $2;} END{print sum_frames/100.0/3600;}')
	echo "
	Set-size in hours:
	 data/train $hours_train
	 data/train_dev $hours_train_dev
	 data/train_nodev $hours_train_nodev
	 data/train_4kshort $hours_train_4kshort
	"
}
 
##########################################################################
### TRAINING GMM SYSTEMS
##########################################################################
 
## Starting basic training on MFCC features

#false && \
{
	echo "Training basic GMM models"
	# mono (this is on short utterances)
	steps/train_mono.sh --nj ${JOBS} --cmd "$train_cmd" \
	  data/train_4kshort data/lang exp/mono || exit 1;

	$train_cmd exp/mono/graph/mkgraph.log \
	  utils/mkgraph.sh --mono data/lang_test exp/mono exp/mono/graph || exit 1;
	steps/decode_si.sh --nj ${JOBS} --cmd "$decode_cmd" --config conf/decode.conf --acwt 0.1 \
	  exp/mono/graph data/test exp/mono/decode_test || exit 1;
	steps/decode_si.sh --nj ${JOBS} --cmd "$decode_cmd" --config conf/decode.conf --acwt 0.1 \
	  exp/mono/graph data/train_dev exp/mono/decode_dev || exit 1;

	# aligning all the data
	#WARNING!! for higher than 1 I do not get a good alignment
	steps/align_si.sh --nj 1 --cmd "$train_cmd" \
	  data/train data/lang exp/mono exp/mono_ali_all || exit 1;
}

#false && \
{
	# tri1 
	steps/train_deltas.sh --cmd "$train_cmd" \
	  2000 20000 data/train_nodev data/lang exp/mono_ali_all exp/tri1 || exit 1;

	$train_cmd exp/tri1/graph/mkgraph.log \
	  utils/mkgraph.sh data/lang_test exp/tri1 exp/tri1/graph || exit 1
	steps/decode_si.sh --nj ${JOBS} --cmd "$decode_cmd" --config conf/decode.conf \
	  exp/tri1/graph data/test exp/tri1/decode_test || exit 1
	steps/decode_si.sh --nj ${JOBS} --cmd "$decode_cmd" --config conf/decode.conf \
	  exp/tri1/graph data/train_dev exp/tri1/decode_dev || exit 1
	
	#WARNING!! for higher than 1 I do not have a good alignment
	steps/align_si.sh --nj 1 --cmd "$train_cmd" \
	  data/train_nodev data/lang exp/tri1 exp/tri1_ali || exit 1;
}

#Compute phoneme graphs for tri1, repeat in others if you want to perform phonetic decoding there.
#false && \
{
	# Create phone-bigram grammar (unsmoothed) estimated from alignments
	utils/make_phone_bigram_lang.sh data/lang exp/tri1_ali data/lang_phn || exit 1;
	# Create phone recognition graph
	utils/mkgraph.sh data/lang_phn exp/tri1 exp/tri1/graph_phn || exit 1
}

#false && \
{
	# tri2 
	# - here we rebuild the triphone tree,
	# - the optimal number of pdf-states/Gaussians depends on amount of data, 
	#   it is good to try several values
	steps/train_deltas.sh --cmd "$train_cmd" \
	  3200 30000 data/train_nodev data/lang exp/tri1_ali exp/tri2 || exit 1;

	$train_cmd exp/tri2/graph/mkgraph.log \
	  utils/mkgraph.sh data/lang_test exp/tri2 exp/tri2/graph || exit 1
	steps/decode_si.sh --nj ${JOBS} --cmd "$decode_cmd" --config conf/decode.conf \
	  exp/tri2/graph data/test exp/tri2/decode_test || exit 1
	steps/decode_si.sh --nj ${JOBS} --cmd "$decode_cmd" --config conf/decode.conf \
	  exp/tri2/graph data/train_dev exp/tri2/decode_dev || exit 1

	# aligning all the data,
	#WARNING!! for higher than 1 I do not have a good alignment
	steps/align_si.sh --nj 1 --cmd "$train_cmd" \
	  data/train data/lang exp/tri2 exp/tri2_ali_all || exit 1;
}	

#false && \
{
	# tri3 
	# Here we perform LDA + MLLT + SAT
	steps/train_sat.sh --cmd "$train_cmd" 2500 15000 \
	  data/train_nodev data/lang exp/tri2_ali_all exp/tri3b || exit 1;
	
	$train_cmd exp/tri3b/graph/mkgraph.log \
		utils/mkgraph.sh data/lang_test exp/tri3b exp/tri3b/graph || exit 1;
	steps/decode_fmllr.sh --nj ${JOBS} --cmd "$decode_cmd" --config conf/decode.conf \
	  exp/tri3b/graph data/test exp/tri3b/decode_test || exit 1;
	steps/decode_fmllr.sh --nj ${JOBS} --cmd "$decode_cmd" --config conf/decode.conf \
	  exp/tri3b/graph data/train_dev exp/tri3b/decode_dev || exit 1;
}	

#NOTE: here we would usually start training DNN models, but the amount of data is not too big, therefore
# we opted against it.

#print the results of the different steps
bash RESULTS

