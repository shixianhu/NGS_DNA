# Preprocessing (aligning --> bam )
### Step 1: Spike in the PhiX reads

To see whether the pipeline ran correctly. The reads will be inserted in each sample. Later on (step 23) of the pipeline there will be a concordance check to see if the SNPs that are put in, will be found.

** Scriptname:** SpikePhiX

**Input:** raw sequence file in the form of a gzipped fastq file

**Output:** FastQ files (${filePrefix}_${lane}_${barcode}.fq.gz)*

### Step 2: Check the Illumina encoding

In this step the encoding of the FastQ files will be checked. Older (2012 and older) sequence data contains the old Phred+64 encoding (this is called Illumina 1.5 encoding), new sequence data is encoded in Illumina 1.8 or 1.9 (Phred+33). If the data is 1.5, it will be converted to 1.9 encoding

**Toolname:** seqTk
**Scriptname:** CheckIlluminaEncoding
**Input:** FastQ files (${filePrefix}_${lane}_${barcode}.fq.gz)
**Output:** If necessary encoded.fq.gz

```
seqtk seq fastq_1.fq.gz -Q 64 -V > fastq_1.encoded.fq.gz
seqtk seq fastq_2.fq.gz -Q 64 -V > fastq_2.encoded.fq.gz
```
### Step 3: Calculate QC metrics on raw data

In this step, Fastqc, quality control (QC) metrics are calculated for the raw sequencing data. This is done using the tool FastQC. This tool will run a series of tests on the input file. The output is a text file containing the output data which is used to create a summary in the form of several HTML pages with graphs for each test. Both the text file and the HTML document provide a flag for each test: pass, warning or fail. This flag is based on criteria set by the makers of this tool. Warnings or even failures do not necessarily mean that there is a problem with the data, only that it is unusual compared to the used criteria. It is possible that the biological nature of the sample means that this particular bias is to be expected.

**Toolname:** FastQC
**Scriptname:** Fastqc
**Input:** fastq_1.fq.gz and fastq_2.fq.gz (${filePrefix}_${lane}_${barcode}.fq.gz)
**Output:** ${filePrefix}.fastqc.zip archive containing amongst others the HTML document and the text file

```
fastqc \
	fastq1.gz \
	fastq2.gz \
	-o outputDirectory
```
### Step 4: Alignment + SortSam

In this step, the Burrows-Wheeler Aligner (BWA) is used to align the (mostly paired end) sequencing data to the reference genome. The method that is used is BWA mem. The output is a FIFO piped SAM file, this way we can do the sorting of the sam/bam file in one go without writing it to disk in between.

**Scriptname:** BwaAlignAndSortBam

####Aligning

**Toolname:** BWA
**Input:** raw sequence file in the form of a gzipped fastq file (${filePrefix}.fq.gz)
**Output:** FIFO piped SAM formatted file (${filePrefix}.sam)


```
bwa mem \
    -M \
    -R $READGROUPLINE \
    -t 8 \
	-human_g1k_v37.fa \
	-fastq1.gz \
	-fastq2.gz \
	> aligned.sam &

#### Sorting Sam/bam file

**Toolname:** Picard SortSam
**Input**: fifo piped sam file
**Output**: sorted bamfile (.sorted.bam)

```
java -Djava.io.tmpdir=${tempDir} -XX:ParallelGCThreads=4
-Xmx29G -jar /folder/to/picard/picard.jar \
SortSam \
INPUT= aligned.sam \
OUTPUT=aligned.sorted.bam  \
SORT_ORDER=coordinate \
CREATE_INDEX=true
```

### Step 5: Merge BAMs and build index

To improve the coverage of sequence alignments, a sample can be sequenced on multiple lanes and/or flowcells. If this is the case for the sample(s) being analyzed, this step merges all BAM files of one sample and indexes this new file. If there is just one BAM file for a sample, nothing happens.

**Toolname:** Sambamba merge
**Scriptname:** SambambaMerge
**Input:** sorted BAM files from (${sample}.sorted.bam)
**Output:** merged BAM file (${sample}.merged.bam)

```
sambamba merge \
	merged.bam \
	${arrayOfSortedBams[@]}
```
### Step 6: Base recalibration
Calculate more accurate base quality scores, the output of this step can be used as an argument in HaplotypeCaller (see step XX VariantCalling )

**Toolname:** GATK BaseRecalibrator
**Scriptname:** BaseRecalibrator
**Input:** merged.bam
**Output:** merged.bam.recalibrated.table

```java -XX:ParallelGCThreads=2 -Djava.io.tmpdir=${tempDir} -Xmx9g -jar ${EBROOTGATK}/GenomeAnalysisTK.jar \
-T BaseRecalibrator \
-R human_g1k_v37.fa \
-I merged.bam \
```
### Step 7: Marking duplicates 

In this step, the BAM file is examined to locate duplicate reads, using Sambamba markdup. A mapped read is considered to be duplicate if the start and end base of two or more reads are located at the same chromosomal position in comparison to the reference genome. For paired-end data the start and end locations for both ends need to be the same to be called duplicate. One read pair of these duplicates is kept, the remaining ones are flagged as being duplicate.

**Toolname:** Sambamba markdup
**Scriptname:** MarkDuplicates
**Input:** Merged BAM file (${sample}.merged.bam)

**Output:**
- BAM file with duplicates flagged (${sample}.dedup.bam)
- BAM index file (${sample}.dedup.bam.bai)

Mark duplicates:
```
sambamba markdup \
	--nthreads=4 \
	--overflow-list-size 1000000 \
	--hash-table-size 1000000 \
	-p \
	merged.bam \
	merged.dedup.bam
```

### Step 8: Flagstat (dedup metrics)
Calculating dedup metrics

**Toolname:** Sambamba flagstat
**Scriptname:** FlagstatMetrics
**Input:** dedup BAM file (${sample}.dedup.bam)
**Output:** .flagstat file (${sample}.dedup.bam.flagstat)

```
sambamba flagstat \
	--nthreads=4 \
	merged.dedup.bam \
	> dedup.bam.flagstat
```

# Indel calling with Manta, Convading & XHMM
### Step 9a: Calling big deletions with Manta

In this step, the progam Manta calls all types (DEL,DUP,INV,TRA,INS) from the merged BAM file. The calls are written to 3 different gzipped VCF files. These files are candidateSmallIndels, candidateSV and diploidSV along with information such as difference in length between REF and ALT alleles, type of structural variant end information about allele depth.

**Toolname:** Manta
**Scriptname:** Manta
**Input:** dedup BAM file (${sample}.dedup.bam)
**Output:** ${sample}.candidateSmallIndels.vcf.gz
		${sample}.candidateSV.vcf.gz
		${sample}.diploidSV.vcf.gz


Prepare workflow
```
python configManta.py \
        --bam merged.dedup.bam \
        --referenceFasta human_g1k_v37.fa \
        --exome \
        --runDir /run/dir/manta
```

run workflow
```
        python /run/dir/manta/runWorkflow.py \ 
		-m local \
		-j 20
```

### Step 9b: CoNVaDING
CoNVaDING (Copy Number Variation Detection In Next-generation sequencing Gene panels) was designed for small (single-exon) copy number variation (CNV) detection in high coverage next-generation sequencing (NGS) data, such as obtained by analysis of smaller targeted gene panels.
This step includes the 4 Convading steps in one protocol. It is gender specific for the sex chromosomes. For more detail about this step: http://molgenis.github.io/software/CoNVaDING
Note: This step needs an already defined controlsgroup!

**Toolname:** Convading
**Scriptname:** Convading
**Input:** dedup BAM file (${sample}.dedup.bam)
**Output:** file containing regions that contain a CNV ${sample}.finallist

**Step 1:StartWithBam**
```
perl CoNVaDING.pl \
	-mode StartWithBam \
	-inputDir Convading/InputBamsDir/ \
	-outputDir Convading/StartWithBam/ \
	-controlsDir Convading/ControlsDir/ \
	-bed mypanel.bed \
	-rmdup
```

**Step 2:StartWithMatchScore**
```
perl ${EBROOTCONVADING}/CoNVaDING.pl \
	-mode StartWithMatchScore \
    -inputDir Convading/StartWithBam/ \
    -outputDir Convading/StartWithMatchScore/ \
    -controlsDir Convading/ControlsDir/
```						

**Step 3:StartWithBestScore**
```
perl ${EBROOTCONVADING}/CoNVaDING.pl \
	-mode StartWithBestScore \
	-inputDir Convading/StartWithMatchScore/ \
	-outputDir Convading/StartWithBestScore/ \
	-controlsDir Convading/ControlsDir/ \
	-sexChr	##only selected when there are sexChromosomes	
```

**Step 4: CreateFinalList**
```
perl ${EBROOTCONVADING}/CoNVaDING.pl \
	-mode CreateFinalList \
	-inputDir Convading/StartWithBestScore/ \
	-outputDir Convading/CreateFinalList/ \
	-targetQcList targetQcList.txt
```	
### Step 9c: XHMM
The XHMM software suite was written to call copy number variation (CNV) from next-generation sequencing projects, where exome capture was used (or targeted sequencing, more generally)
This protocol contains all the steps described here http://atgu.mgh.harvard.edu/xhmm/tutorial.shtml

**Toolname:** XHMM

**Scriptname:** XHMM 

**Input:** dedup BAM file (${sample}.dedup.bam)

**Output:** file containing regions that contain a CNV ${sample}.xcnv

# Determine gender
### Step 10: GenderCalculate

Due to the fact a male has only one X chromosome it is important to know if the sample is male or female. Calculating the coverage on the non pseudo autosomal region and compare this to the average coverage on the complete genome predicts male or female well.

**Toolname:** Picard CalculateHSMetrics
**Scriptname:** GenderCalculate
**Input:** dedup BAM file (${sample}.dedup.bam)
**Output:** ${dedupBam}.nonAutosomalRegionChrX_hs_metrics

```
java -jar -Xmx4g picard.jar CalculateHsMetrics \
	INPUT=merged.dedup.bam \
	TARGET_INTERVALS=input.nonAutosomalChrX.interval_list \
	BAIT_INTERVALS=input.nonAutosomalChrX.interval_list \
	OUTPUT=output.nonAutosomalRegionChrX_hs_metrics
```
# Side steps (Cram conversion and concordance check)
### Step 11: CramConversion

Producing more compressed bam files, decreasing size with 40%

**Toolname:** Scramble
**Scriptname:**CramConversion
**Input:** dedup BAM file (${sample}.dedup.bam)
**Output:** dedup CRAM file (${sample}.dedup.bam.cram)

```
scramble \
	-I bam \
	-O cram \
	-r human_g1k_v37.fa \
	-m \
	-t 8 \
	merged.dedup.bam \
	merged.dedup.bam.cram
```

### Step 12: Make md5’s for the bam files

Small step to create md5sums for the bams created in the MarkDuplicates step

**Scriptname:** MakeDedupBamMd5
**Input:** realigned BAM file (.merged.dedup.bam)
**Output:** md5sums (.merged.dedup.bam.md5)

```
md5sum merged.dedup.bam > merged.dedup.bam.md5
```


# Coverage calculations (Diagnostics only)
### Step 13: Calculate coverage per base and per target

Calculates coverage per base and per target, the output will contain chromosomal position, coverage per base and gene annotation

**Toolname:** GATK DepthOfCoverage
**Scriptname:** CoverageCalculations
**Input:** dedup BAM file (.merged.dedup.bam)
**Output:** tab delimeted file containing chromosomal position, coverage per base and Gene annotation name (.coveragePerBase.txt)

Per base:
```
java -Xmx10g -jar /path/to/GATK/GenomeAnalysisTK.jar \
	-R human_g1k_v37.fa \
	-T DepthOfCoverage \
	-o region.coveragePerBase \
	--omitLocusTable \
	-I merged.dedup.bam \
	-L region.bed
```

Per target:
```
java -Xmx10g -jar /path/to/GATK/GenomeAnalysisTK.jar \
	-R human_g1k_v37.fa \
	-T DepthOfCoverage \
	-o region.coveragePerTarget \
	--omitDepthOutputAtEachBase \
	-I merged.dedup.bam \
	-L region.bed
```

# Metrics calculations
### Step 14 (a,b,c,d): Calculate alignment QC metrics

In this step, QC metrics are calculated for the alignment created in the previous steps. This is done using several QC related Picard tools:

● CollectAlignmentSummaryMetrics
● CollectGcBiasMetrics
● CollectInsertSizeMetrics
● MeanQualityByCycle (machine cycle)
● QualityScoreDistribution
● CalculateHsMetrics (hybrid selection)
● BamIndexStats

These metrics are later used to create tables and graphs (step 24). The Picard tools also output a PDF version of the data themselves, containing graphs.

**Toolname:** several Picard QC tools
**Scriptname:** Collect metrics
**Input:** dedup BAM file (.merged.dedup.bam)
**Output:** alignmentmetrics, gcbiasmetrics, insertsizemetrics, meanqualitybycycle, qualityscoredistribution, hsmetrics, bamindexstats (text files and matching PDF files)

# Determine Gender
### Step 15: Gender check

Due to the fact a male has only one X chromosome it is important to know if the sample is male or female. Calculating the coverage on the non pseudo autosomal region and compare this to the average coverage on the complete genome predicts male or female well.

**Scriptname:** GenderCheck
**Input:** ${dedupBam}.hs\_metrics (CalculateHsMetrics step) (${dedupBam}.nonAutosomalRegionChrX_hs_metrics (GenderCalculate step)

**Output:** ${sample}.chosenSex.txt

# Variant discovery
### Step 16a: Call variants (VariantCalling)

The GATK HaplotypeCaller estimates the most likely genotypes and allele frequencies in an alignment using a Bayesian likelihood model for every position of the genome regardless of whether a variant was detected at that site or not. This information can later be used in the project based genotyping step.

**Scriptname::** GATK HaplotypeCaller
**Scriptname:** VariantGVCFCalling
**Input:** merged BAM files
**Output:** gVCF file (${sample}.${batchBed}.variant.calls.g.vcf)

```
java -Xmx12g -jar /path/to/GATK/GenomeAnalysisTK.jar \
    -T HaplotypeCaller \
    -R human_g1k_v37.fa \
    -I merged.dedup.bam \
	--BQSR merged.bam.calibrated.table \
	--dbsnp dbsnp_137.b37.vcf \
	--newQuals \
    -o output.g.vcf.gz \
    -L captured.bed \
    --emitRefConfidence GVCF \
	-ploidy 2  ##ploidy 1 in non autosomal chr X region in male##
```
### Step 16b: Combine variants

When there 200 or more samples the gVCF files should be combined into batches of equal size. (NB: These batches are different then the ${batchBed}.) The batches will be calculated and created in this step. If there are less then 200, this step will automatically be skipped.

**Toolname:** GATK CombineGVCFs
**Scriptname:** VariantGVCFCombine
**Input:** gVCF file 
**Output:** Multiple combined gVCF files (${project}.${batchBed}.variant.calls.combined.g.vcf{batch}

```
java -Xmx30g -jar /path/to/GATK/GenomeAnalysisTK.jar \
	-T CombineGVCFs \
	-R human_g1k_v37.fa \
	-o batch_output.g.vcf.gz \
	${ArrayWithgVCF[@]}
```
### Step 16c: Genotype variants

In this step there will be a joint analysis over all the samples in the project. This leads to a posterior probability of a variant allele at a site. SNPs and small Indels are written to a VCF file, along with information such as genotype quality, allele frequency, strand bias and read depth for that SNP/Indel.

**Toolname:** GATK GenotypeGVCFs
**Scriptname:** VariantGVCFGenotype
**Input:** gVCF files from step 16a **or** combined gVCF files from step 16b
**Output:** VCF file for all the samples in the project (${project}.${batchBed}.variant.calls.genotyped.vcf)

```
java -Xmx16g -jar /path/to/GATK/GenomeAnalysisTK.jar \
	-T GenotypeGVCFs \
	-R human_g1k_v37.fa \
	-L captured.bed \
	--dbsnp dbsnp_137.b37.vcf \
	-o genotyped.vcf \
	${ArrayWithgVCFgz[@]} 
```
# Annotation
### Step 17a: Annotating with SnpEff 
Data will be annotated with SnpEff
Genetic variant annotation and effect prediction toolbox. It annotates and predicts the effects of variants on genes (such as amino acid changes). 

**Toolname:** SnpEff
**ScriptName:** SnpEff
**Input:** genotyped vcf (.genotyped.vcf)
**Output:** snpeff annotated vcf (.snpeff.vcf)

```
java -XX:ParallelGCThreads=4 -Xmx4g -jar \
        /path/to/snpEff/snpEff.jar \
        -v hg19 \
        -noStats \
        -noLog \
        -lof \
		-canon \
        -ud 0 \
        -c snpEff.config \
        genotyped.vcf \
        > genotyped.snpeff.vcf
```
### Step 17b: Annotating with VEP
Data will be annotated with VEP.
VEP determines the effect of your variants (SNPs, insertions, deletions, CNVs or structural variants) on genes, transcripts, and protein sequence, as well as regulatory regions

**Toolname:** VEP
**ScriptName:** VEP
**Input:** genotyped vcf (.genotyped.vcf)
**Output:** VEP annotated vcf (.variant.calls.VEP.vcf)

```
variant_effect_predictor.pl \
	-i genotyped.vcf \
    --offline \
    --cache \
    --dir ${vepDataDir} \
    --db_version=${vepDBVersion} \
    --buffer 1000 \
    --most_severe \
    --species homo_sapiens \
    --vcf \
    -o genotyped.vep.vcf
```

### Step 18: Annotating with CADD, GoNL, ExAC (CmdLineAnnotator) 
Data will be annotated with CADD, GoNL and ExAC

**Toolname:** CmdLineAnnotator
**Scriptname:** CmdLineAnnotator
**Input:** snpeff annotated vcf (.snpeff.vcf)
**Output:** cadd, gonl and exac annotated vcf (.exac.gonl.cadd.vcf)

```
java -Xmx10g -jar /path/to/CmdLineAnnotator/molgenisAnnotator.jar \
        -a exac ## gonl or cadd ## \
        -s exacAnnotation ##gonlAnnotation ##caddAnnotation  \
        -i genotyped.snpeff.vcf #genotyped.snpeff.exac.vcf #genotyped.snpeff.exac.gonl.vcf \
        -o genotyped.snpeff.exac.vcf #genotyped.snpeff.exac.gonl.vcf #genotyped.snpeff.exac.gonl.cadd.vcf
```


### Step s19: Merge batches

Running GATK CatVariants to merge all the files created in the previous into one.

**Toolname:** GATK CatVariants
**Scriptname:** MergeChrAndSplitVariants
**Input:** CmdLineAnnotator vcf file (.genotyped.snpeff.exac.gonl.cadd.vcf)
**Output:** merged (batches) vcf per project (${project}.variant.calls.vcf)

```
java -Xmx12g -Djava.io.tmpdir=${tempDir} -cp /path/to/GATK/GenomeAnalysisTK.jar \
org.broadinstitute.gatk.tools.CatVariants \
-R human_g1k_v37.fa \
${arrayWithVcfs[@]} \
-out merged.variant.calls.vcf
```

### Step s20a: Gavin split samples
To run Gavin per sample the data needs to be splitted first.

**Toolname:** GATK
**Scriptname:** GavinSplitSamples
**Input:** merged vcf per project (${project}.variant.calls.vcf)
**Output:** merged vcf per sample ${sample}.variant.calls.vcf

```
java -Xmx4g -jar /path/to/GATK/GenomeAnalysisTK.jar \
-R human_g1k_v37.fa \
-T SelectVariants \
--variant input.vcf \
-o output.vcf \
-L .interval_list \
-sn sampleID
```

### Step s20b: Gavin
Tool that predict the impact of the SNP with the help of different databases (CADD etc). 


#### Gavin first round

**Scriptname:** Gavin
**Toolname:** Gavin_toolpack
**Input:** merged vcf per sample ${sample}.variant.calls.GATK.vcf
**Output:** 
- First draft (.GAVIN.RVCF.firstpass.vcf)
- Tab seperated file to be send to CADD (.toCadd.tsv)

```
java -Xmx4g -jar /path/to/Gavin_toolpack/GAVIN-APP.jar \
-i input.vcf \
-o output.vcf \
-m CREATEFILEFORCADD \
-a gavinToCADD \
-c gavinClinVar.vcf.gz \
-d gavinCGD.txt.gz \
-f gavinFDR.tsv \
-g gavinCalibrations.tsv
```

#### Get CADD annotations locally

**Toolname:** CADD
**Input:** tab seperated file to be send to CADD (.toCadd.tsv)
**Output:** tab seperated file to be send from CADD (.fromCadd.tsv.gz)

```
score.sh gavinToCADDgz gavinFromCADDgz
```

#### Gavin second round
**Toolname:** Gavin_toolpack
**Input:** 	
- merged vcf per sample ${sample}.variant.calls.GATK.vcf
- tab seperated file to be send from CADD (.fromCadd.tsv.gz)	
**Output:** Gavin final output (.GAVIN.RVCF.final.vcf)

```
java -Xmx4g -jar /path/to/Gavin_toolpack/GAVIN-APP.jar \
-i input.vcf \
-o output.vcf \
-m ANALYSIS \
-a gavinFromCADDgz \
-c gavinClinVar.vcf.gz \
-d gavinCGD.txt.gz \
-f gavinFDR.tsv \
-g gavinCalibrations.tsv
```

#### Merging Gavin output with original
**Toolname:** Gavin_toolpack
**Input:** 	
- merged vcf per sample ${sample}.variant.calls.GATK.vcf
- Gavin final output (.GAVIN.RVCF.final.vcf)
**Output:** Gavin final output merged with original (.GAVIN.rlv.vcf)

```
java -jar -Xmx4g /path/to/Gavin_toolpack/MergeBackTool.jar \
-i input.vcf \
-v output.GAVIN.RVCF.final.vcf \
-o output.GAVIN.rlv.vcf
```

### Step 21: Split indels and SNPs

This step is necessary because the filtering of the vcf needs to be done seperately.

**Toolname:** GATK SelectVariants
**Scriptname:** SplitIndelsAndSNPs
**Input:** merged (batches) vcf per project (${project}.variant.calls.GATK.vcf) (from step 22)
**Output:** 
- .annotated.indels.vcf 
- .annotated.snps.vcf

```
java -XX:ParallelGCThreads=2 -Xmx4g -jar /path/to/GATK/GenomeAnalysisTK.jar \
-R human_g1k_v37 \
-T SelectVariants \
--variant merged.variant.calls.vcf \
-o .annotated.snps.vcf #.annotated.indels.vcf \
-L captured.bed \
--selectTypeToExclude INDEL ##--selectTypeToInclude INDEL  \
-sn ${externalSampleID}
```

### Step 22: (a) SNP and (b) Indel filtration

Based on certain quality thresholds (based on GATK best practices) the SNPs and indels are filtered or marked as Pass.

**Toolname:** GATK VariantFiltration
**Scriptname:** VariantFiltration
**Input:**
-annotated.snps.vcf
-.annotated.indels.vcf
**Output:**
- Filtered snp vcf file (.annotated.filtered.snps.vcf)
- Filtered indel vcf file (.annotated.filtered.indels.vcf)

SNP:
```
java-Xmx8g -Xms6g -jar /path/to/GATK/GenomeAnalysisTK.jar \
-T VariantFiltration \
-R human_g1k_v37.fa \
-o .annotated.filtered.snps.vcf \
--variant inputSNP.vcf \
--filterExpression "QD < 2.0" \
--filterName "filterQD" \
--filterExpression "MQ < 25.0" \
--filterName "filterMQ" \
--filterExpression "FS > 60.0" \
--filterName "filterFS" \
--filterExpression "MQRankSum < -12.5" \
--filterName "filterMQRankSum" \
--filterExpression "ReadPosRankSum < -8.0" \
--filterName "filterReadPosRankSum"
```

Indel:
```
java-Xmx8g -Xms6g -jar /path/to/GATK/GenomeAnalysisTK.jar \
-T VariantFiltration \
-R human_g1k_v37.fa \
-o .annotated.filtered.indels.vcf\
--variant inputIndel.vcf \
--filterExpression "QD < 2.0" \
--filterName "filterQD" \
--filterExpression "FS > 200.0" \
--filterName "filterFS" \
--filterExpression "ReadPosRankSum < -20.0" \
--filterName "filterReadPosRankSum"
```

### Step 23: Merge indels and SNPs

Merge all the SNPs and indels into one file (per project) and merge SNPs and indels per sample.

**Toolname:** GATK CombineVariants
**Scriptname:** MergeIndelsAndSnps
**Input:** .annotated.filtered.indels.vcf and .annotated.snps.vcf

**Output:**
- sample.final.vcf
- project.final.vcf

Per sample:
```
java -Xmx2g -jar /path/to/GATK/GenomeAnalysisTK.jar \
	-R human_g1k_v37.fa \
	-T CombineVariants \
	--variant sample.annotated.filtered.indels.vcf \
	--variant sample.annotated.filtered.snps.vcf \
	--genotypemergeoption UNSORTED \
	-o sample.final.vcf
```

Per project:
```
java -Xmx2g -jar ${EBROOTGATK}/${gatkJar} \
-R human_g1k_v37.fa \
-T CombineVariants \
${arrayWithAllSampleFinalVcf[@]} \
-o ${projectPrefix}.final.vcf
```
### Step 24: Convert structural variants VCF to table

In this step the indels in VCF format are converted into a tabular format using Perlscript vcf2tab by F. Van Dijk.

**Toolname:** vcf2tab.pl
**Scriptname:** IndelVcfToTable
**Input:** (${sample}.final.vcf)
**Output:** (${sample}.final.vcf.table)

# QC-ing
### Step 25: In silico concordance check

The reads that are inserted contain SNPs that are handmade. To see whether the pipeline ran correctly at least these SNPs should be found.

**Input:** InSilicoData.chrNC_001422.1.variant.calls.vcf and ${sample}.variant.calls.sorted.vcf
**Output:** inSilicoConcordance.txt

### Step 26a: Prepare QC Report, collecting metrics

Combining all the statistics which are used in the QC report.

**Scriptname:**QCStats
**Toolname:** pull_DNA_Seq_Stats.py
**Input:** metrics files (flagstat file, *.hsmetrics, *.alignmentmetrics, *.insertsizemetrics and concordance file (*.dedup.metrics.concordance.ngsVSarray.txt)
**Output:** ${sample}.total.qc.metrics.table

### Step 27b: Generate quality control report

The step in the inhouse sequence analysis pipeline is to output the statistics and metrics from each step that produced such data that was collected in the QCStats step before. From these, tables and graphs are produced. Reports are then created and written to a separate quality control (QC) directory, located IN RunNr/Results/qc/statistics. This report will be outputted in html and pdf. Converting html to pdf the tool wkhtmltopdf is used.

**Toolname:** wkhtmltopdf
**Scriptname:** QCReport
**Input:** ${sample}.total.qc.metrics.table
**Output:** A quality control report html(*_QCReport.html) and pdf (*_QCReport.html)

### Step 28: Check if all files are finished

This step is checking if all the steps in the pipeline are actually finished. It sometimes happens that a job is not submitted to the scheduler. If everything is finished than it will write a file called CountAllFinishedFiles_CORRECT, if not it will make CountAllFinishedFiles_INCORRECT. When it is not all finished it will show in the CountAllFinishedFiles_INCORRECT file which files are not finished yet.

**Scriptname:** CountAllFinishedFiles
**Input:** all .sh scripts + all .sh.finished files in the jobs folder
**Output:** CountAllFinishedFiles_CORRECT or CountAllFinishedFiles_INCORRECT

### Step 29: Prepare data to ship to the customer

In this last step the final results of the inhouse sequence analysis pipeline are gathered and prepared to be shipped to the customer. The pipeline tools and scripts write intermediate results to a temporary directory. From these, a selection is copied to a results directory. This directory has five subdirectories:

o alignment: the merged BAM file with index
o coverage: coverage statistics and plots
o coverage_visualization: coverage BEDfiles
o qc: all QC files, from which the QC report is made
o rawdata/ngs: symbolic links to the raw sequence files and their md5 sum
o snps: all SNP calls in VCF format and in tab-delimited format
o structural_variants: all SVs calls in VCF and in tab-delimited format
Additionally, the results directory contains the final QC report, the worksheet which was the basis for this analysis (see 4.2) and a zipped archive with the data that will be shipped to the client (see: GCC_P0006_Datashipment.docx). The archive is accompanied by an md5 sum and README file explaining the contents.

** Scriptname:** CopyToResultsDir