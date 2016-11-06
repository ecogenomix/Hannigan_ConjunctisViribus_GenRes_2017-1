#! /bin/bash
# CreateContigRelAbundTable.sh
# Geoffrey Hannigan
# Pat Schloss Lab
# University of Michigan

#PBS -N RunPhageBacteriaModel
#PBS -q first
#PBS -l nodes=1:ppn=1,mem=40gb
#PBS -l walltime=600:00:00
#PBS -j oe
#PBS -V
#PBS -A schloss_lab

#######################
# Set the Environment #
#######################

export BinPath=/mnt/EXT/Schloss-data/ghannig/Hannigan-2016-ConjunctisViribus/bin/
export GitBin=/mnt/EXT/Schloss-data/ghannig/OpenMetagenomeToolkit/pakbin/
export ProjectBin=/mnt/EXT/Schloss-data/ghannig/Hannigan-2016-ConjunctisViribus/bin/

export ContigsFile=$1
# Directory for fasta sequences to align to contigs
export FastaSequences=$2
export MasterOutput=$3
export Output='data/tmpbowtie'

mkdir ./${Output}
mkdir ./${Output}/bowtieReference

###################
# Set Subroutines #
###################
GetHits () {
	# 1 = Input Orfs
	# 2 = Bowtie Reference

	bowtie2 \
		-x ${2} \
		-q ${1} \
		-S ${1}-bowtie.sam \
		-p 8 \
		-L 25 \
		-N 1

	# Quantify alignment hits
	perl \
		${ProjectBin}calculate_abundance_from_sam.pl \
			${1}-bowtie.sam \
			${1}-bowtie.tsv
}

BowtieRun () {
	sampleid=$(echo ${1} | sed 's/_2.fastq//')
	GetHits \
		${FastaSequences}/${1} \
		./${Output}/bowtieReference/bowtieReference

	# Remove the header
	sed -e "1d" ${FastaSequences}/${1}-bowtie.tsv > ${FastaSequences}/${1}-noheader

	awk -v name=${sampleid} '{ print $0"\t"name }' ${FastaSequences}/${1}-noheader \
	| grep -v '\*' > ${FastaSequences}/${1}-noheader-forcat
	# rm ${FastaSequences}/${1}-noheader
}

# Export the subroutines
export -f GetHits
export -f BowtieRun

#############################
# Contig Relative Abundance #
#############################

echo Getting contig relative abundance table...

# Clear the file to prepare for appending to new file below
rm ${MasterOutput}

# Build bowtie reference
bowtie2-build \
	-q ${ContigsFile} \
	./${Output}/bowtieReference/bowtieReference

ls ${FastaSequences}/*_2.fastq | sed "s/.*\///g" | xargs -I {} --max-procs=32 bash -c 'BowtieRun "$@"' _ {}

echo Catting files...

cat ${FastaSequences}/*-noheader-forcat > ${MasterOutput}
