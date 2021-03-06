#MOLGENIS walltime=05:59:00 mem=10gb ppn=10

#Parameter mapping
#string tmpName
#string tmpDirectory
#string tempDir
#string project
#string logsDir
#string groupname
#string intermediateDir

#string bedToolsVersion
#string bwaVersion
#string computeVersion
#string caddVersion
#string convadingVersion
#string cutadaptVersion
#string fastqcVersion
#string gatkVersion
#string gavinToolPackVersion
#string iolibVersion
#string javaVersion
#string mantaVersion
#string molgenisAnnotatorVersion
#string ngsUtilsVersion
#string perlPlusVersion
#string plink1Version
#string plink2Version
#string plinkSeqVersion
#string picardVersion
#string pythonVersion
#string rVersion
#string sambambaVersion
#string samtoolsVersion
#string seqTkVersion
#string snpEffVersion
#string htsLibVersion
#string tabixVersion
#string vepVersion
#string verifyBamIDVersion
#string wkHtmlToPdfVersion
#string xhmmVersion
#string hpoVersion

#string ngsversion
#string capturingKit
#string stage
#string checkStage
#string multiQCVersion

set -e
set -u

#Making Header of the MultiQC Report
echo -e "report_header_info:
    - Contact E-mail: 'helpdesk.gcc.groningen@gmail.com'
    - Pipeline Version: '${ngsversion}'
    - Project : '${project}'
    - capturingKit : '${capturingKit}'
    - '' : ''
    - Used toolversions: ' '
    - '' : ''
    - '': '${bedToolsVersion}'
    - '': '${bwaVersion}'
    - '': '${computeVersion}'
    - '': '${caddVersion}'
    - '': '${convadingVersion}'
    - '': '${cutadaptVersion}'
    - '': '${fastqcVersion}'
    - '': '${gatkVersion}'
    - '': '${gavinToolPackVersion}'
    - '': '${iolibVersion}'
    - '': '${javaVersion}'
    - '': '${mantaVersion}'
    - '': '${molgenisAnnotatorVersion}'
    - '': '${ngsUtilsVersion}'
    - '': '${perlPlusVersion}'
    - '': '${plink1Version}'
    - '': '${plink2Version}'
    - '': '${plinkSeqVersion}'
    - '': '${picardVersion}'
    - '': '${pythonVersion}'
    - '': '${rVersion}'
    - '': '${sambambaVersion}'
    - '': '${samtoolsVersion}'
    - '': '${seqTkVersion}'
    - '': '${snpEffVersion}'
    - '': '${htsLibVersion}'
    - '': '${tabixVersion}'
    - '': '${vepVersion}'
    - '': '${verifyBamIDVersion}'
    - '': '${wkHtmlToPdfVersion}'
    - '': '${xhmmVersion}'
    - '': '${hpoVersion}'
    - '': '${multiQCVersion}'
    - '' : ''
    - pipeline description : ''
    - Manual : ''
    - '': 'Find manual on installation and use at https://molgenis.gitbooks.io/ngs_dna'
    - '' : ''
    - Preprocessing : ''
    - '': 'During the first preprocessing steps of the pipeline, PhiX reads are inserted in each sample to create control SNPs in the dataset.'
    - '': 'Subsequently, Illumina encoding is checked and QC metrics are calculated using a FastQC tool Andrews S. (2010) 1)'
    - '' : ''
    - Alignment to a reference genome : ''
    - '' : ''
    - '': 'The bwa-mem command from Burrows-Wheeler Aligner(BWA) (Li & Durbin 3)) is used to align the sequence data to a reference genome resulting in a SAM (Sequence Alignment Map) file.'
    - '': 'The reads in the SAM file are sorted with Sambamba(Tarasov et al. 3)). resulting in a sorted BAM file.'
    - '': 'When multiple lanes were used during sequencing, all lane BAMs were merged into a sample BAM using Sambamba.'
    - '': 'The (merged) BAM file is marked for duplicates of the same read pair using Sambamba.'
    - Variant discovery : ''
    - '' : ''
    - '': 'The GATK (McKenna et al. 4)) HaplotypeCaller estimates the most likely genotypes and allele frequencies in an alignment using a Bayesian likelihood model for every position of the genome regardless of whether a variant was detected at that site or not'
    - '': 'This information can later be used in the project based genotyping step. A joint analysis has been performed of all the samples in the project.'
    - '': 'This leads to a posterior probability of a variant allele at a site. '
    - '': 'SNPs and small Indels are written to a VCF file, along with information such as genotype quality, allele frequency, strand bias and read depth for that SNP/Indel.'
    - '': 'Based on quality thresholds from the GATK "best practices" (Van der Auwera et al. 5)) the SNPs and indels are filtered and marked as Lowqual or Pass resulting in a final VCF file.'
    - References : ''
    - '': '1. Andrews S. (2010). FastQC: a quality control tool for high throughput sequence data. Available online at:http://www.bioinformatics.babraham.ac.uk/projects/fastqc '
    - '': '2. Li Durbin, Fast and accurate short read alignment with Burrows-Wheeler transform.'
    - '': '3. Sambamba: Fast processing of NGS alignment formats'
    - '': '4. The Genome Analysis Toolkit: a MapReduce framework for analyzing next-generation DNA sequencing data'
    - '': '5. From FastQ data to high confidence variant calls: the Genome Analysis Toolkit best practices pipeline'
picard_config:
    general_stats_target_coverage:
        - 2
        - 10
        - 20
        - 30
        - 40
        - 50
        - 100" >> ${intermediateDir}/${project}.multiqc_config.yaml

${stage} "${multiQCVersion}"
${checkStage}

multiqc -c "${intermediateDir}/${project}.multiqc_config.yaml" -f "${intermediateDir}" -o "${intermediateDir}"

mv "${intermediateDir}/multiqc_report.html" "${intermediateDir}/${project}_multiqc_report.html"
echo "moved ${intermediateDir}/multiqc_report.html ${intermediateDir}/${project}_multiqc_report.html"
