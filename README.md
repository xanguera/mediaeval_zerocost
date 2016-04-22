# mediaeval_zerocost
Baseline system for Mediaeval 2016 Zero Cost evaluation in Vietnamese language

##Introduction

##Installation

Requirements: We have tested the following models in a Mac and an Ubuntu 14.04 boxes. We can not guarantee that it should work on other systems.
To get the system ready, do:

1) Download Kaldi into your system. Go to www.kaldi-asr.org and follow the instructions (usually git clone https://github.com/kaldi-asr/kaldi.git wherever you want it)
2) Move to the egs directory inside kaldi and clone this repo: git clone https://github.com/xanguera/mediaeval_zerocost.git

##Working with the baseline

###Vietnamese models
We have trained very basic Vietnamese models by pulling data from several sources (namely Forvo.com, Rhinospike.com and ELSA). After cleaning the data a bit we have trained a simple triphone-based model with max 20K Gaussians using standard MFCC features. The transcription is obtained by obtaining the graphemes in each word, keeping any tone they might have. This results in a grapheme inventory of XX graphemes as shown below (the number is how many examples we have of each grapheme in the training set). Total side of the training set is XX hours.

###Decoding Mediaeval's datasets
You first need to download the data from the Mediaeval sftp directory (available to you if you signed up for Mediaeval 2016 ZeroCost evaluation and signed the license agreements).
You can run the decoding by executing s5/decode_mediaeval.sh --inputDir <path_to_your_wav_files>
Results will be stored by default in the ./output directory (decoding_phones and phoneme/grapheme results and decoding_words for word results, output.ctm file in both)

###Decoding "any" dataset
It is possible to use the trained models on other arbitrary data. To do so you need to call the above script with the directory where your audio files are (wav format, 16KHz, 16bit/sample) in the following way: s5/decode_mediaeval.sh --inputDir <path_to_your_wav_files>

###Training new models
With the package we also added the script to allow for users with more/different data to train new acoustic models and to experiment with different models. You can do that by calling s5/run_mediaeval.sh <input_training_data>
Inside the directory <input_training_data> you need to place the audio files together with the text/trancription files.
Some important tips on how to prepare the data:
* Each audio file (.wav) needs to have its counterpart .txt file
* Name convention for the files is <spkrID>_<utteranceID> which allows for one speaker to contribute multiple independent utterances to the training.
* Inside the .txt file you need to place, in two columns, the text and transcription of each word in the utterance, separated by <tab>, for example:
	là      l à
	nai     n a i
	cái     c á i
	cây     c â y

Note when running the training script: it requires the MITLM package to be downloaded and compiled under ./tools
By default the LM training script will try to install it, but we have had issues under OSX and had to install it manually (Linux should work ok).



