# GetMicrobeOrfs.sh
# Geoffrey Hannigan
# Pat Schloss Lab
# University of Michigan

# Set the variables to be used in this script
export WorkingDirectory=/home/ghannig/git/Hannigan-2016-ConjunctisViribus/data
export Output='OperationalProteinFamilies'

export MothurProg=/share/scratch/schloss/mothur/mothur

export PhageGenomes=\
	/home/ghannig/git/Hannigan-2016-ConjunctisViribus/data/phageSVA.fa
export BacteriaGenomes=\
	/home/ghannig/git/Hannigan-2016-ConjunctisViribus/data/bacteriaSVA.fa
export InteractionReference=\
	/home/ghannig/git/Hannigan-2016-ConjunctisViribus/data/PhageInteractionReference.tsv

export SwissProt=/mnt/EXT/Schloss-data/reference/uniprot/uniprot_sprotNoBlock.fasta
export Trembl=/mnt/EXT/Schloss-data/reference/uniprot/uniprot_tremblNoBlock.fasta

export GitBin=/home/ghannig/git/HanniganNotebook/bin/
export SeqtkPath=/home/ghannig/bin/seqtk/seqtk
export LocalBin=/home/ghannig/bin/

# Make the output directory and move to the working directory
echo Creating output directory...
cd ${WorkingDirectory}
mkdir ./${Output}

PredictOrfs () {
	# 1 = Contig Fasta File for Glimmer
	# 2 = Output File Name

	${LocalBin}glimmer3.02/bin/build-icm ./${Output}/Contigs.icm < ${1}

	${LocalBin}glimmer3.02/bin/glimmer3 \
		--linear \
		-g 100 \
		${1} \
		./${Output}/Contigs.icm \
		./${Output}/GlimmerOut

	cat ./${Output}/GlimmerOut.predict | while read line;
    do if [ "${line:0:1}" == ">" ]
        then seqname=${line#'>'}
        else
        orf="$seqname.${line%%' '*}"
        coords="${line#*' '}"
        echo -e "$orf\t$seqname\t$coords"
        fi
    done > ./${Output}/GlimmerOutFormat.predict

    ${LocalBin}glimmer3.02/bin/multi-extract \
    	-l 100 \
    	--nostop \
    	${1} \
    	./${Output}/GlimmerOutFormat.predict \
    	> ./${Output}/tmp-ContigOrfs.fa

    # Remove the block formatting
	perl \
	${GitBin}remove_block_fasta_format.pl \
		./${Output}/tmp-ContigOrfs.fa \
		./${Output}/${2}

	# Remove the tmp file
	rm ./${Output}/tmp-ContigOrfs.fa
}

SubsetUniprot () {
	# 1 = Interaction Reference File
	# 2 = SwissProt Database No Block
	# 3 = Trembl Database No Block

	# Note that database should cannot be in block format
	# Create a list of the accession numbers
	cut -f 1,2 ${1} \
		| grep -v "interactor" \
		| sed 's/uniprotkb\://g' \
		> ./${Output}/ParsedInteractionRef.tsv

	# Collapse that list to single column of unique IDs
	sed 's/\t/\n/' ./${Output}/ParsedInteractionRef.tsv \
		| sort \
		| uniq \
		> ./${Output}/UniqueInteractionRef.tsv

	# Use this list to subset the Uniprot database
	perl ${GitBin}FilterFasta.pl \
		-i ${2} \
		-l ./${Output}/UniqueInteractionRef.tsv \
		-o ./${Output}/SwissProtSubset.fa
	perl ${GitBin}FilterFasta.pl \
		-i ${3} \
		-l ./${Output}/UniqueInteractionRef.tsv \
		-o ./${Output}/TremblProtSubset.fa

	# Create single file with two datasets
	cat \
		./${Output}/SwissProtSubset.fa \
		./${Output}/TremblProtSubset.fa \
		> ./${Output}/TotalUniprotSubset.fa
}

GetOrfUniprotHits () {
	# 1 = UniprotFasta
	# 2 = Phage Orfs
	# 3 = Bacteria Orfs

	# Create blast database
	makeblastdb \
		-dbtype prot \
		-in ${1} \
		-out ./${Output}/UniprotSubsetDatabase

	# Use blast to get hits of ORFs to Uniprot genes
	blastx \
		-query ${2} \
		-out ./${Output}/${2}.blast \
		-db ./${Output}/UniprotSubsetDatabase \
		-outfmt 6 \
		-evalue 1e-10
	blastx \
		-query ${3} \
		-out ./${Output}/${3}.blast \
		-db ./${Output}/UniprotSubsetDatabase \
		-outfmt 6 \
		-evalue 1e-10
}

OrfInteractionPairs () {
	# 1 = Phage Blast Results
	# 2 = Bacterial Blast Results
	# 3 = Interaction Reference

	# Reverse the interaction reference for awk
	awk \
		'{ print $2"\t"$1 }' \
		${3} \
		> ${3}.inverse

	cat \
		${3} \
		${3}.inverse \
		> ./${Output}/TotalInteractionRef.tsv

	# Get only the ORF IDs and corresponding interactions
	# Column 1 is the ORF ID, two is Uniprot ID
	cut -f 1,2 ${1} > ./${Output}/PhageBlastIdReference.tsv
	cut -f 1,2 ${2} > ./${Output}/BacteriaBlastIdReference.tsv

	# Convert bacterial file to reference
	awk \
		'NR == FNR {a[$1] = $2; next} { print $1"\t"$2"\t"a[$1] }' \
		./${Output}/PhageBlastIdReference.tsv \
		./${Output}/TotalInteractionRef.tsv \
		> ./${Output}/tmpMerge.tsv

	awk \
		'NR == FNR {a[$2] = $1; next} { print $1"\t"$2"\t"$3"\t"a[$3] }' \
		./${Output}/BacteriaBlastIdReference.tsv \
		./${Output}/tmpMerge.tsv \
		| cut -f 1,4 \
		> ./${Output}/InteractiveIds.tsv

	# This output can be used for input into perl script for adding
	# to the graph database.
}

export -f PredictOrfs
export -f SubsetUniprot
export -f GetOrfUniprotHits
export -f OrfInteractionPairs


PredictOrfs \
	${PhageGenomes} \
	"PhageGenomeOrfs.fa"

PredictOrfs \
	${BacteriaGenomes} \
	"BacteriaGenomeOrfs.fa"

SubsetUniprot \
	${InteractionReference} \
	${SwissProt} \
	${Trembl}

GetOrfUniprotHits \
	./${Output}/TotalUniprotSubset.fa \
	./${Output}/PhageGenomeOrfs.fa \
	./${Output}/BacteriaGenomeOrfs.fa

OrfInteractionPairs \
	./${Output}/PhageGenomeOrfs.fa.blast \
	./${Output}/BacteriaGenomeOrfs.fa.blast \
	./${Output}/ParsedInteractionRef.tsv
